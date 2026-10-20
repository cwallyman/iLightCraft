//! Native photo export and uncropped previews, using the same engine renderer and encoders.

use std::io::Write;
use std::path::Path;

use lightcraft_engine::export::{ExportFormat, ExportOptions, OutputDepth, encode_rendered, export_photo};
use lightcraft_engine::{Session, catalog::PhotoId};
use serde_json::{Value, json};

use crate::status::{Failure, UVStatus};

fn io(error: impl ToString) -> Failure {
    Failure::new(UVStatus::UV_ERR_IO, error.to_string())
}

pub fn run(session: &mut Session, command: &str, params: &Value) -> Result<Value, Failure> {
    let path = params
        .get("path")
        .and_then(Value::as_str)
        .ok_or_else(|| Failure::invalid("missing output path"))?;
    session.check_write_target(path).map_err(io)?;
    let id = params
        .get("id")
        .and_then(Value::as_u64)
        .map(PhotoId)
        .or_else(|| session.active())
        .ok_or_else(|| Failure::invalid("no photo selected"))?;
    let (bytes, width, height) = if command == "unveil.hdrExport" {
        let settings = session
            .develop_of(id)
            .ok_or_else(|| Failure::invalid("photo not found"))?;
        if !settings.hdr.enabled {
            return Err(Failure::invalid("Enable HDR editing before HDR export"));
        }
        let mut options = ExportOptions::from_params(params).map_err(Failure::engine)?;
        options.format = ExportFormat::Tiff;
        options.bit_depth = Some(32);
        let photo = session
            .catalog
            .photo(id)
            .ok_or_else(|| Failure::invalid("photo not found"))?;
        let (width, height) = lightcraft_engine::export::output_size(photo, &options);
        if width.saturating_mul(height) > 80_000_000 {
            return Err(Failure::invalid("HDR output exceeds the 80 megapixel limit"));
        }
        let metadata = lightcraft_engine::export::export_metadata(photo, &options);
        let job = session
            .export_job(id, width, height, options.effective_space(), OutputDepth::F32Hdr)
            .map_err(io)?;
        let rendered = job.run().rendered.map_err(io)?;
        let bytes = encode_rendered(&rendered, &options, metadata.as_ref()).map_err(io)?;
        (bytes, width, height)
    } else if command == "unveil.cropPreview" {
        let mut settings = (*session
            .develop_of(id)
            .ok_or_else(|| Failure::invalid("photo not found"))?)
        .clone();
        if let Some(orientation) = params.get("orientation") {
            settings.orientation = serde_json::from_value(orientation.clone())
                .map_err(|error| Failure::invalid(error.to_string()))?;
        }
        settings.crop = Default::default();
        settings.crop.flip_h = params.get("flipH").and_then(Value::as_bool).unwrap_or(false);
        settings.crop.flip_v = params.get("flipV").and_then(Value::as_bool).unwrap_or(false);
        let job = session
            .preview_job(id, 1600, 1600, true, &settings)
            .ok_or_else(|| Failure::invalid("cannot prepare crop preview"))?;
        let result = job.run();
        let rendered = result.rendered.map_err(io)?;
        let options = ExportOptions {
            format: ExportFormat::Png,
            ..Default::default()
        };
        let bytes = encode_rendered(&rendered, &options, None).map_err(io)?;
        (bytes, rendered.image.width, rendered.image.height)
    } else {
        let options = ExportOptions::from_params(params).map_err(Failure::engine)?;
        if !matches!(
            options.format,
            ExportFormat::Jpeg | ExportFormat::Png | ExportFormat::Tiff
        ) {
            return Err(Failure::invalid("native export supports JPEG, PNG and TIFF"));
        }
        let exported = export_photo(session, id, &options, 1).map_err(io)?;
        (exported.bytes, exported.width, exported.height)
    };
    // Never replace an existing file, including one outside the catalog. Failed writes are removed.
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(io)?;
    if let Err(error) = file.write_all(&bytes).and_then(|_| file.sync_all()) {
        drop(file);
        let _ = std::fs::remove_file(path);
        return Err(io(error));
    }
    Ok(json!({"path": Path::new(path), "width": width, "height": height}))
}

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
    if command == "ilightcraft.maskPin" {
        return mask_pin(session, params);
    }
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
    let (bytes, width, height) = if command == "ilightcraft.comparisonPreview" {
        let edge = params
            .get("longEdge")
            .and_then(Value::as_u64)
            .unwrap_or(1400)
            .clamp(256, 1600) as usize;
        let before = params.get("before").and_then(Value::as_bool).unwrap_or(false);
        let job = session
            .render_job(id, edge, edge, before, true)
            .ok_or_else(|| Failure::invalid("Cannot prepare comparison preview"))?;
        let rendered = job.run().rendered.map_err(io)?;
        let options = ExportOptions {
            format: ExportFormat::Png,
            ..Default::default()
        };
        let bytes = encode_rendered(&rendered, &options, None).map_err(io)?;
        (bytes, rendered.image.width, rendered.image.height)
    } else if command == "ilightcraft.hdrExport" {
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
    } else if command == "ilightcraft.versionPreview" {
        let index = params
            .get("index")
            .and_then(Value::as_u64)
            .and_then(|i| usize::try_from(i).ok())
            .ok_or_else(|| Failure::invalid("Choose a saved version"))?;
        let settings = session
            .catalog
            .photo(id)
            .and_then(|p| p.versions.get(index).map(|v| v.settings.clone()))
            .ok_or_else(|| Failure::invalid("Version no longer exists"))?;
        let job = session
            .preview_job(id, 1200, 1200, true, &settings)
            .ok_or_else(|| Failure::invalid("Cannot prepare version preview"))?;
        let rendered = job.run().rendered.map_err(io)?;
        let options = ExportOptions {
            format: ExportFormat::Png,
            ..Default::default()
        };
        let bytes = encode_rendered(&rendered, &options, None).map_err(io)?;
        (bytes, rendered.image.width, rendered.image.height)
    } else if command == "ilightcraft.cropPreview" {
        let mut settings = (*session
            .develop_of(id)
            .ok_or_else(|| Failure::invalid("photo not found"))?)
        .clone();
        if let Some(orientation) = params.get("orientation") {
            settings.orientation = serde_json::from_value(orientation.clone())
                .map_err(|error| Failure::invalid(error.to_string()))?;
        }
        settings.crop = Default::default();
        if params
            .get("neutralPerspective")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            settings.geometry = Default::default();
        }
        settings.crop.flip_h = params.get("flipH").and_then(Value::as_bool).unwrap_or(false);
        settings.crop.flip_v = params.get("flipV").and_then(Value::as_bool).unwrap_or(false);
        let job = session
            .preview_job(id, 1600, 1600, true, &settings)
            .ok_or_else(|| Failure::invalid("cannot prepare crop preview"))?;
        let job = if let Some(mask_id) = params.get("overlayMask").and_then(Value::as_u64) {
            let id =
                u16::try_from(mask_id).map_err(|_| Failure::invalid("Mask ID is too large for overlay"))?;
            if !settings.masks.iter().any(|m| u64::from(m.id) == mask_id) {
                return Err(Failure::invalid("Mask no longer exists"));
            }
            job.with_overlay(lightcraft_pipeline::Overlay::Mask {
                id,
                view: params
                    .get("overlayMode")
                    .and_then(Value::as_str)
                    .and_then(lightcraft_pipeline::MaskView::parse)
                    .unwrap_or_default(),
                color: params
                    .get("overlayColor")
                    .and_then(Value::as_array)
                    .filter(|v| v.len() == 3)
                    .and_then(|v| {
                        Some([
                            u8::try_from(v.first()?.as_u64()?).ok()?,
                            u8::try_from(v.get(1)?.as_u64()?).ok()?,
                            u8::try_from(v.get(2)?.as_u64()?).ok()?,
                        ])
                    })
                    .unwrap_or([242, 165, 22]),
                opacity: params
                    .get("overlayOpacity")
                    .and_then(Value::as_u64)
                    .map(|v| v.min(100) as u8)
                    .unwrap_or(35),
            })
        } else {
            job
        };
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

/// The selected component's anchor, or the centroid of its stored foreground coverage.
fn mask_pin(session: &Session, params: &Value) -> Result<Value, Failure> {
    use lightcraft_develop::MaskShape;
    let id = session
        .active()
        .ok_or_else(|| Failure::invalid("no photo selected"))?;
    let settings = session
        .develop_of(id)
        .ok_or_else(|| Failure::invalid("photo not found"))?;
    let mask_id = params
        .get("maskID")
        .and_then(Value::as_u64)
        .ok_or_else(|| Failure::invalid("missing mask ID"))?;
    let mask = settings
        .masks
        .iter()
        .find(|m| u64::from(m.id) == mask_id)
        .ok_or_else(|| Failure::invalid("mask not found"))?;
    let point = mask
        .components
        .iter()
        .find_map(|component| match &component.shape {
            MaskShape::Linear { start, .. } => Some((start.x, start.y)),
            MaskShape::Radial { center, .. } => Some((center.x, center.y)),
            MaskShape::Brush { strokes } => {
                strokes.first().and_then(|s| s.points.first()).map(|p| (p.x, p.y))
            }
            MaskShape::Object { seg: Some(seg), .. } | MaskShape::Prompt { seg: Some(seg), .. } => {
                let side = usize::try_from(seg.side).ok()?;
                if side == 0 {
                    return None;
                }
                let logits = seg.logits()?;
                let bounds = seg.bounds()?;
                let (mut x, mut y, mut count) = (0.0, 0.0, 0.0);
                for (i, value) in logits.iter().enumerate() {
                    if *value > 0.0 {
                        x += (i % side) as f64 + 0.5;
                        y += (i / side) as f64 + 0.5;
                        count += 1.0;
                    }
                }
                (count > 0.0).then(|| {
                    (
                        bounds[0] + x / count / side as f64 * (bounds[2] - bounds[0]),
                        bounds[1] + y / count / side as f64 * (bounds[3] - bounds[1]),
                    )
                })
            }
            _ => None,
        })
        .filter(|(x, y)| {
            x.is_finite() && y.is_finite() && (0.0..=1.0).contains(x) && (0.0..=1.0).contains(y)
        });
    Ok(json!({"point": point.map(|(x, y)| [x, y])}))
}

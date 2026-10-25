//! Native inference results enter the shared non-destructive engine through bounded commands.

use crate::status::Failure;
use lightcraft_engine::Session;
use serde_json::{Value, json};

pub fn mask_from_alpha(session: &mut Session, params: &Value) -> Result<Value, Failure> {
    let side = params
        .get("side")
        .and_then(Value::as_u64)
        .filter(|n| (16..=512).contains(n))
        .ok_or_else(|| Failure::invalid("Mask side must be between 16 and 512"))? as usize;
    let expected = side
        .checked_mul(side)
        .ok_or_else(|| Failure::invalid("Mask size overflow"))?;
    let values = params
        .get("alpha")
        .and_then(Value::as_array)
        .filter(|a| a.len() == expected)
        .ok_or_else(|| Failure::invalid("Mask samples do not match its dimensions"))?;
    let mut logits = Vec::with_capacity(expected);
    for value in values {
        let alpha = value
            .as_u64()
            .filter(|n| *n <= 255)
            .ok_or_else(|| Failure::invalid("Invalid mask coverage"))?;
        let probability = (alpha as f32 / 255.0).clamp(0.0000001, 0.9999999);
        logits.push((probability / (1.0 - probability)).ln());
    }
    let name = params
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("On-device selection");
    if name.len() > 160 {
        return Err(Failure::invalid("Mask name is too long"));
    }
    let seg = lightcraft_develop::SegMask::from_logits(side, &logits);
    let current = session
        .active()
        .and_then(|id| session.develop_of(id))
        .ok_or_else(|| Failure::invalid("Open a photo first"))?;
    if let Some(id) = params.get("maskID").and_then(Value::as_u64) {
        let mask = current
            .masks
            .iter()
            .find(|m| u64::from(m.id) == id)
            .ok_or_else(|| Failure::invalid("The selected mask no longer exists"))?;
        if mask.components.len() >= 16 {
            return Err(Failure::invalid("This native mask already has 16 components"));
        }
        let op = params.get("op").and_then(Value::as_str).unwrap_or("add");
        if !matches!(op, "add" | "subtract" | "intersect") {
            return Err(Failure::invalid("Unknown mask combination"));
        }
        session
            .execute("mask.select", &json!({"id": id}))
            .map_err(Failure::engine)?;
        session
            .execute(
                "mask.addComponent",
                &json!({"id": id, "op": op, "kind": "object", "seg": seg}),
            )
            .map_err(Failure::engine)
    } else {
        if current.masks.len() >= 64 {
            return Err(Failure::invalid("This photo already has 64 native masks"));
        }
        session
            .execute("mask.add", &json!({"kind": "object", "name": name, "seg": seg}))
            .map_err(Failure::engine)
    }
}

/// Extract only the three pinned model-package files, never arbitrary archive paths.
pub fn unpack_enhancement(session: &Session, params: &Value) -> Result<Value, Failure> {
    use std::path::Path;
    let archive = params
        .get("archive")
        .and_then(Value::as_str)
        .ok_or_else(|| Failure::invalid("Missing model archive"))?;
    let destination = params
        .get("destination")
        .and_then(Value::as_str)
        .ok_or_else(|| Failure::invalid("Missing install directory"))?;
    session
        .check_write_target(destination)
        .map_err(|e| Failure::invalid(e.to_string()))?;
    let (package, size, hash) = match params.get("variant").and_then(Value::as_str) {
        Some("denoise") => (
            "RealESRGAN-x4v3-denoise.mlpackage",
            2_286_246u64,
            "a577c31ccc3025d84807f7e124d71656fb2cbbdc57c4c44d3ac2d9980da9c9c4",
        ),
        Some("superResolution") => (
            "RealESRGAN-x4v3.mlpackage",
            2_286_340u64,
            "5a59e554794371b95fe61274b8a2040f1b3e274479abf15595dcdad0535afad4",
        ),
        _ => return Err(Failure::invalid("Unknown enhancement model")),
    };
    let archive = Path::new(archive);
    if std::fs::metadata(archive)
        .map_err(|e| Failure::invalid(e.to_string()))?
        .len()
        != size
    {
        return Err(Failure::invalid("Model archive size mismatch"));
    }
    if lightcraft_denoise_core::hash::sha256_file(archive).map_err(|e| Failure::invalid(e.to_string()))?
        != hash
    {
        return Err(Failure::invalid("Model archive SHA-256 mismatch"));
    }
    let root = Path::new(destination);
    std::fs::create_dir(root).map_err(|e| Failure::invalid(e.to_string()))?;
    for relative in [
        "Manifest.json",
        "Data/com.apple.CoreML/model.mlmodel",
        "Data/com.apple.CoreML/weights/weight.bin",
    ] {
        let file = root.join(package).join(relative);
        if let Some(parent) = file.parent() {
            std::fs::create_dir_all(parent).map_err(|e| Failure::invalid(e.to_string()))?;
        }
        lightcraft_denoise_core::archive::extract(
            archive,
            &format!("{package}/{relative}"),
            &file,
            3 * 1024 * 1024,
        )
        .map_err(|e| Failure::invalid(e.to_string()))?;
    }
    Ok(json!({"package": root.join(package)}))
}

/// Atomically creates a manual component and applies its optional brush/color sample.
/// A failed follow-up cancels the engine interaction so no empty mask is left behind.
pub fn manual_mask(session: &mut Session, params: &Value) -> Result<Value, Failure> {
    let kind = params.get("kind").and_then(Value::as_str).unwrap_or("");
    if !matches!(
        kind,
        "brush" | "linear" | "radial" | "luminanceRange" | "colorRange"
    ) {
        return Err(Failure::invalid("Unsupported manual mask kind"));
    }
    let op = params.get("operation").and_then(Value::as_str).unwrap_or("new");
    if !matches!(op, "new" | "add" | "subtract" | "intersect") {
        return Err(Failure::invalid("Invalid mask operation"));
    }
    let active = session
        .active()
        .ok_or_else(|| Failure::invalid("Open a photo first"))?;
    let settings = session
        .develop_of(active)
        .ok_or_else(|| Failure::invalid("Photo settings are unavailable"))?;
    if op == "new" && settings.masks.len() >= 64 {
        return Err(Failure::invalid("This photo already has 64 masks"));
    }
    if op != "new" {
        let id = params
            .get("id")
            .and_then(Value::as_u64)
            .ok_or_else(|| Failure::invalid("Choose a mask first"))?;
        let mask = settings
            .masks
            .iter()
            .find(|m| u64::from(m.id) == id)
            .ok_or_else(|| Failure::invalid("Mask no longer exists"))?;
        if mask.components.len() >= 16 {
            return Err(Failure::invalid("The mask already has 16 components"));
        }
    }
    let valid_point = |value: &Value| {
        value.as_array().is_some_and(|p| {
            p.len() == 2
                && p.iter().all(|v| {
                    v.as_f64()
                        .is_some_and(|n| n.is_finite() && (0.0..=1.0).contains(&n))
                })
        })
    };
    if let Some(points) = params.get("points") {
        let points = points
            .as_array()
            .filter(|p| !p.is_empty() && p.len() <= 2048)
            .ok_or_else(|| Failure::invalid("Use 1–2048 brush points"))?;
        if !points.iter().all(valid_point) {
            return Err(Failure::invalid("Invalid brush coordinate"));
        }
    } else if kind == "brush" {
        return Err(Failure::invalid("Draw a brush stroke first"));
    }
    for key in ["start", "end", "center", "colorPoint"] {
        if let Some(point) = params.get(key) {
            if !point.is_null() && !valid_point(point) {
                return Err(Failure::invalid("Invalid selection coordinate"));
            }
        }
    }
    for key in ["rx", "ry", "size", "lo", "hi"] {
        if let Some(value) = params.get(key) {
            if !value.is_null()
                && !value
                    .as_f64()
                    .is_some_and(|n| n.is_finite() && (0.0..=1.0).contains(&n))
            {
                return Err(Failure::invalid("Invalid selection size or range"));
            }
        }
    }
    session
        .execute("develop.beginInteraction", &json!({"label":"Manual Mask"}))
        .map_err(Failure::engine)?;
    let result = (|| {
        let mut shape = params
            .as_object()
            .cloned()
            .ok_or_else(|| Failure::invalid("Invalid mask parameters"))?;
        let command = if op == "new" {
            "mask.add"
        } else {
            "mask.addComponent"
        };
        if op != "new" {
            shape.insert("op".into(), json!(op));
        }
        let created = session
            .execute(command, &Value::Object(shape))
            .map_err(Failure::engine)?;
        let id = created
            .get("activeMask")
            .and_then(Value::as_u64)
            .ok_or_else(|| Failure::invalid("The mask was not created"))?;
        if kind == "brush" {
            let mut stroke = params
                .as_object()
                .cloned()
                .ok_or_else(|| Failure::invalid("Invalid brush parameters"))?;
            stroke.insert("id".into(), json!(id));
            session
                .execute("mask.brushStroke", &Value::Object(stroke))
                .map_err(Failure::engine)?;
        }
        if kind == "colorRange" {
            let point = params
                .get("colorPoint")
                .filter(|p| valid_point(p))
                .and_then(Value::as_array)
                .ok_or_else(|| Failure::invalid("Pick a color on the photo first"))?;
            let x = point
                .first()
                .cloned()
                .ok_or_else(|| Failure::invalid("Missing color coordinate"))?;
            let y = point
                .get(1)
                .cloned()
                .ok_or_else(|| Failure::invalid("Missing color coordinate"))?;
            session
                .execute(
                    "mask.sampleColor",
                    &json!({"id":id,"x":x,"y":y,"space":"uncroppedPreview"}),
                )
                .map_err(Failure::engine)?;
        }
        Ok(json!({"activeMask":id}))
    })();
    match result {
        Ok(value) => {
            session
                .execute("develop.endInteraction", &json!({}))
                .map_err(Failure::engine)?;
            Ok(value)
        }
        Err(error) => {
            let _ = session.execute("develop.cancelInteraction", &json!({}));
            Err(error)
        }
    }
}

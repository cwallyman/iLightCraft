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

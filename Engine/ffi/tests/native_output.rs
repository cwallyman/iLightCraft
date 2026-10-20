mod common;
use common::*;
use serde_json::json;

#[test]
fn cropped_exports_use_the_shared_encoder_for_each_format() {
    for (format, extension) in [("jpeg", "jpg"), ("png", "png"), ("tiff", "tif")] {
        let session = TestSession::new();
        let id = import_fixture(&session);
        exec_ok(&session, "crop.set", r#"{"rect":[0.25,0.25,0.75,0.75]}"#);
        let output = session.dir.path().join(format!("cropped.{extension}"));
        let result = exec_ok(
            &session,
            "unveil.export",
            &json!({
                "id": id, "path": output, "format": format, "longEdge": 0,
                "colorSpace": "displayp3", "metadata": "none", "watermark": "Proof"
            })
            .to_string(),
        );
        assert_eq!(result["width"], 48);
        assert_eq!(result["height"], 32);
        let bytes = std::fs::read(output).unwrap();
        let decoded = lightcraft_codecs::decode(&bytes, Default::default()).unwrap();
        assert_eq!((decoded.image.width, decoded.image.height), (48, 32));
    }
}

#[test]
fn a_crop_preview_is_uncropped_and_does_not_change_saved_settings() {
    let session = TestSession::new();
    import_fixture(&session);
    exec_ok(&session, "crop.set", r#"{"rect":[0.25,0.25,0.75,0.75]}"#);
    let before = exec_ok(&session, "develop.get", "{}");
    let output = session.dir.path().join("crop-preview.png");
    let result = exec_ok(
        &session,
        "unveil.cropPreview",
        &json!({
            "path": output, "orientation": "Rotate90", "flipH": true
        })
        .to_string(),
    );
    assert_eq!(result["width"], 64);
    assert_eq!(result["height"], 96);
    assert_eq!(exec_ok(&session, "develop.get", "{}"), before);
}

#[test]
fn output_never_replaces_an_original_or_existing_file() {
    let session = TestSession::new();
    let original = fixture_png(session.dir.path());
    import_png(&session, &original);
    let bytes = std::fs::read(&original).unwrap();
    let request = json!({"path": original, "format": "png"}).to_string();
    assert!(exec(&session, "unveil.export", &request).is_err());
    assert_eq!(std::fs::read(&original).unwrap(), bytes);

    let existing = session.dir.path().join("existing.png");
    std::fs::write(&existing, b"keep this file").unwrap();
    let request = json!({"path": existing, "format": "png"}).to_string();
    assert!(exec(&session, "unveil.export", &request).is_err());
    assert_eq!(std::fs::read(&existing).unwrap(), b"keep this file");
}

mod common;
use common::*;
use serde_json::json;

#[test]
fn hdr_float_export_preserves_highlights_above_sdr_white() {
    let session = TestSession::new();
    import_fixture(&session);
    exec_ok(
        &session,
        "develop.merge",
        r#"{"settings":{"hdr":{"enabled":true,"max_ev":3},"light":{"exposure":3}}}"#,
    );
    let path = session.dir.path().join("hdr.tiff");
    exec_ok(&session, "unveil.hdrExport", &json!({"path": path}).to_string());
    let bytes = std::fs::read(path).unwrap();
    let image = lightcraft_codecs::decode(&bytes, Default::default()).unwrap();
    assert!(image.float);
    assert!(image.image.data.iter().flatten().any(|v| *v > 1.5));
    assert!(
        image
            .image
            .data
            .iter()
            .flatten()
            .all(|v| v.is_finite() && *v <= 8.01)
    );
}

#[test]
fn hdr_export_requires_an_explicit_hdr_edit() {
    let session = TestSession::new();
    import_fixture(&session);
    let path = session.dir.path().join("not-hdr.tiff");
    let error = exec(&session, "unveil.hdrExport", &json!({"path": path}).to_string()).unwrap_err();
    assert!(error.1.contains("Enable HDR"));
    assert!(!path.exists());
}

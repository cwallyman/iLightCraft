mod common;
use common::*;
use lightcraft_codecs::{DecodeOptions, Error, Format};

#[test]
fn native_app_includes_heic_decoder() {
    assert!(Format::Heif.can_decode(), "Unveil must ship the HEIC decoder");
}

#[test]
fn malformed_heic_is_rejected_and_the_session_still_imports() {
    let header = b"\0\0\0\x18ftypheic\0\0\0\0mif1heic";
    let result = lightcraft_codecs::decode(header, DecodeOptions::default());
    assert!(!matches!(result, Err(Error::Unsupported(_, reason)) if reason.contains("isn't included")));
    assert!(result.is_err());

    let session = TestSession::new();
    let path = session.dir.path().join("broken.heic");
    std::fs::write(&path, header).unwrap();
    let params = serde_json::json!({ "paths": [path], "mode": "add" }).to_string();
    match exec(&session, "library.import", &params) {
        Ok(value) => {
            assert!(photo_ids_from_import(&value).is_empty(), "{value}");
            assert!(!value["failed"][0][1].as_str().unwrap_or_default().is_empty());
        }
        Err((_, message)) => assert!(!message.is_empty()),
    }
    import_fixture(&session);
    exec_ok(
        &session,
        "develop.set",
        r#"{"control":"light.exposure","value":0.5}"#,
    );
}

mod common;
use common::*;
use serde_json::json;

#[test]
fn a_native_selection_is_persisted_and_full_settings_restore_removes_it() {
    let session = TestSession::new();
    import_fixture(&session);
    let before = exec_ok(&session, "develop.get", "{}");
    let alpha: Vec<u8> = (0..256).map(|i| if i % 16 < 8 { 255 } else { 0 }).collect();
    let result = exec_ok(
        &session,
        "unveil.maskFromAlpha",
        &json!({"side":16,"alpha":alpha,"name":"Subject"}).to_string(),
    );
    let id = result["activeMask"].as_u64().unwrap();
    exec_ok(
        &session,
        "mask.adjust",
        &json!({"id":id,"values":{"exposure":1.0}}).to_string(),
    );
    let after = exec_ok(&session, "develop.get", "{}");
    assert_eq!(after["masks"].as_array().unwrap().len(), 1);
    assert_eq!(after["masks"][0]["components"][0]["shape"]["seg"]["side"], 16);
    assert_eq!(after["masks"][0]["adjust"]["exposure"], 1.0);
    exec_ok(
        &session,
        "unveil.restore",
        &json!({"settingsJSON":before.to_string()}).to_string(),
    );
    assert_eq!(exec_ok(&session, "develop.get", "{}"), before);
}

#[test]
fn malformed_native_masks_leave_saved_settings_untouched() {
    let session = TestSession::new();
    import_fixture(&session);
    let before = exec_ok(&session, "develop.get", "{}");
    for params in [
        json!({"side":0,"alpha":[]}),
        json!({"side":1025,"alpha":[]}),
        json!({"side":16,"alpha":[255]}),
    ] {
        assert!(exec(&session, "unveil.maskFromAlpha", &params.to_string()).is_err());
    }
    let mut alpha = vec![json!(255); 256];
    alpha[50] = json!(256);
    assert!(
        exec(
            &session,
            "unveil.maskFromAlpha",
            &json!({"side":16,"alpha":alpha}).to_string()
        )
        .is_err()
    );
    assert_eq!(exec_ok(&session, "develop.get", "{}"), before);
}

#[test]
fn merge_guards_reject_duplicate_sources_and_unavailable_memory() {
    let session = TestSession::new();
    let id = import_fixture(&session);
    assert!(
        exec(
            &session,
            "unveil.mergeStart",
            &json!({"ids":[id,id],"availableBytes":u64::MAX}).to_string()
        )
        .is_err()
    );
    let copy = exec_ok(&session, "photo.virtualCopy", &json!({"ids":[id]}).to_string());
    let second = copy["ids"][0].as_u64().unwrap();
    let error = exec(
        &session,
        "unveil.mergeStart",
        &json!({"ids":[id,second],"availableBytes":0}).to_string(),
    )
    .unwrap_err();
    assert!(error.1.contains("memory allowance"));
    assert_eq!(exec_ok(&session, "unveil.mergeStatus", "{}")["state"], "idle");
}

#[test]
fn an_untrusted_model_archive_never_creates_an_install_directory() {
    let session = TestSession::new();
    let archive = session.dir.path().join("fake.zip");
    std::fs::write(&archive, b"not an approved model").unwrap();
    let destination = session.dir.path().join("model-install");
    assert!(
        exec(
            &session,
            "unveil.unpackEnhancement",
            &json!({"archive":archive,"destination":destination,"variant":"denoise"}).to_string()
        )
        .is_err()
    );
    assert!(!destination.exists());
}

#[test]
fn combining_native_selections_preserves_existing_adjustments_and_rejects_unknown_targets() {
    let session = TestSession::new();
    import_fixture(&session);
    let alpha = vec![255u8; 256];
    let result = exec_ok(
        &session,
        "unveil.maskFromAlpha",
        &json!({"side":16,"alpha":alpha,"name":"Subject"}).to_string(),
    );
    let id = result["activeMask"].as_u64().unwrap();
    exec_ok(
        &session,
        "mask.adjust",
        &json!({"id":id,"values":{"exposure":0.75}}).to_string(),
    );
    exec_ok(
        &session,
        "unveil.maskFromAlpha",
        &json!({"side":16,"alpha":alpha,"maskID":id,"op":"subtract"}).to_string(),
    );
    let before = exec_ok(&session, "develop.get", "{}");
    assert_eq!(before["masks"][0]["components"].as_array().unwrap().len(), 2);
    assert_eq!(before["masks"][0]["components"][1]["op"], "subtract");
    assert_eq!(before["masks"][0]["adjust"]["exposure"], 0.75);
    assert!(
        exec(
            &session,
            "unveil.maskFromAlpha",
            &json!({"side":16,"alpha":alpha,"maskID":u32::MAX,"op":"add"}).to_string()
        )
        .is_err()
    );
    assert_eq!(exec_ok(&session, "develop.get", "{}"), before);
}

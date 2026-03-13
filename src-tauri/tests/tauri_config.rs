use std::fs;
use std::path::PathBuf;

use serde_json::Value;

fn manifest_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn macos_private_api_feature_matches_config() {
    let manifest_dir = manifest_dir();
    let config_path = manifest_dir.join("tauri.conf.json");
    let config_contents = fs::read_to_string(&config_path)
        .unwrap_or_else(|error| panic!("Failed to read {config_path:?}: {error}"));
    let config: Value = serde_json::from_str(&config_contents)
        .unwrap_or_else(|error| panic!("Failed to parse tauri.conf.json: {error}"));
    let macos_private_api = config
        .get("app")
        .and_then(|app| app.get("macOSPrivateApi"))
        .and_then(|value| value.as_bool())
        .unwrap_or(false);

    if macos_private_api {
        let cargo_path = manifest_dir.join("Cargo.toml");
        let cargo_contents = fs::read_to_string(&cargo_path)
            .unwrap_or_else(|error| panic!("Failed to read {cargo_path:?}: {error}"));
        let mut in_dependencies = false;
        let mut has_feature = false;

        for line in cargo_contents.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with('[') {
                in_dependencies = trimmed == "[dependencies]";
                continue;
            }
            if !in_dependencies {
                continue;
            }
            if trimmed.starts_with("tauri") && trimmed.contains("macos-private-api") {
                has_feature = true;
                break;
            }
        }

        assert!(
            has_feature,
            "Cargo.toml [dependencies] must enable macos-private-api when app.macOSPrivateApi is true"
        );
    }
}

#[test]
fn desktop_build_does_not_register_updater_plugin() {
    let lib_path = manifest_dir().join("src/lib.rs");
    let lib_contents = fs::read_to_string(&lib_path)
        .unwrap_or_else(|error| panic!("Failed to read {lib_path:?}: {error}"));

    assert!(
        !lib_contents.contains("tauri_plugin_updater::Builder::new().build()"),
        "src/lib.rs must not register the updater plugin for desktop builds"
    );
}

#[test]
fn desktop_capabilities_do_not_request_updater_permission() {
    let capabilities_path = manifest_dir().join("capabilities/default.json");
    let capabilities_contents = fs::read_to_string(&capabilities_path)
        .unwrap_or_else(|error| panic!("Failed to read {capabilities_path:?}: {error}"));

    assert!(
        !capabilities_contents.contains("updater:default"),
        "capabilities/default.json must not request updater permissions when updater is disabled"
    );
}

#[test]
fn desktop_menu_does_not_expose_check_for_updates() {
    let menu_path = manifest_dir().join("src/menu.rs");
    let menu_contents = fs::read_to_string(&menu_path)
        .unwrap_or_else(|error| panic!("Failed to read {menu_path:?}: {error}"));

    assert!(
        !menu_contents.contains("check_for_updates"),
        "src/menu.rs must not expose a Check for Updates action when updater is disabled"
    );
}

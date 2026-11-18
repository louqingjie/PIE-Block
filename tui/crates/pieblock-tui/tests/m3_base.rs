//! M3 基座：设置持久化、最近项目、工程打开/保存/旧格式升版。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_core::{FORMAT_VERSION, ProjectKind};
use pieblock_toolchain::models::CompilerKind;
use pieblock_tui::project_display_name;
use pieblock_tui::{
    AppSettings, ProjectSession, RecentProject, SaveStatus, SettingsStore, ThemePreference,
};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn unique_dir(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join(format!("m3-base-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");
    dir
}

#[test]
fn creates_saves_and_reopens_project() {
    let dir = unique_dir("session");
    let path = dir.join("robot");
    let mut session = ProjectSession::create(&path, ProjectKind::Engineer, None).expect("create");
    assert_eq!(session.path, dir.join("robot.pieproj"));
    assert_eq!(session.save_status, SaveStatus::Saved);
    assert_eq!(session.display_name(), "robot");
    assert!(session.path.exists());

    let json: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&session.path).expect("read")).expect("json");
    assert_eq!(json["format_version"], FORMAT_VERSION);
    assert_eq!(json["project_kind"], "engineer");

    session.document.guide_progress.current_step_id = "mechanism".to_owned();
    session.save_now().expect("save");
    let reopened = ProjectSession::open(&session.path).expect("reopen");
    assert_eq!(reopened.document.kind, ProjectKind::Engineer);
    assert_eq!(reopened.save_status, SaveStatus::Saved);
    assert!(
        fs::read_dir(&dir)
            .expect("dir")
            .flatten()
            .all(|entry| !entry.file_name().to_string_lossy().contains(".tmp-")),
        "atomic write must not leave temp files"
    );
}

#[test]
fn opening_format22_upgrades_file_to_current() {
    let dir = unique_dir("upgrade");
    let target = dir.join("old.pieproj");
    fs::copy(
        repo_root().join("packages/pieblock_core/test/fixtures/format22_infantry.pieproj"),
        &target,
    )
    .expect("copy fixture");
    let session = ProjectSession::open(&target).expect("open old");
    assert_eq!(session.document.kind, ProjectKind::Infantry);
    assert_eq!(session.save_status, SaveStatus::Saved);
    assert!(session.upgrade_warning.is_none());
    let json: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&target).expect("read")).expect("json");
    assert_eq!(json["format_version"], FORMAT_VERSION);
}

#[test]
fn opening_too_new_format_reports_error() {
    let dir = unique_dir("toonew");
    let target = dir.join("future.pieproj");
    fs::write(
        &target,
        r#"{"format_version": 99, "project_kind": "infantry"}"#,
    )
    .expect("write");
    let error = ProjectSession::open(&target).expect_err("too new");
    assert!(error.to_string().contains("99"), "error: {error}");
}

#[test]
fn project_display_names() {
    assert_eq!(project_display_name("C:/a/robot.pieproj"), "robot");
    assert_eq!(project_display_name("/tmp/无标题.PIEPROJ"), "无标题");
    assert_eq!(project_display_name(""), "未命名项目");
    assert_eq!(project_display_name("C:\\x\\y"), "y");
}

#[test]
fn settings_roundtrip_and_recent_merge() {
    let dir = unique_dir("settings");
    let existing = dir.join("robot.pieproj");
    fs::write(&existing, b"{}").expect("existing");
    let store = SettingsStore::new(dir.join("settings.json"));
    let mut settings = AppSettings {
        theme: ThemePreference::Dark,
        recent: vec![
            RecentProject {
                path: existing.display().to_string(),
                kind: None,
            },
            RecentProject {
                path: dir.join("gone.pieproj").display().to_string(),
                kind: Some(ProjectKind::Music),
            },
        ],
        compiler: CompilerKind::Keil,
        keil_path: Some("C:/Keil".to_owned()),
        suppress_flash_guide: true,
        suppress_template_guide: false,
    };
    store.save(&settings).expect("save");
    let text = fs::read_to_string(dir.join("settings.json")).expect("read");
    assert!(text.contains("\"theme\":\"dark\""));
    assert!(text.contains("\"compiler\":\"keil\""));
    let loaded = store.load_cleaned(|_path| Some(ProjectKind::Infantry));
    assert_eq!(loaded.theme, ThemePreference::Dark);
    assert_eq!(loaded.compiler, CompilerKind::Keil);
    assert_eq!(loaded.keil_path.as_deref(), Some("C:/Keil"));
    assert!(loaded.suppress_flash_guide);
    assert_eq!(loaded.recent.len(), 1, "missing project should be dropped");
    assert_eq!(loaded.recent[0].kind, Some(ProjectKind::Infantry));

    settings.adopt_recent("/a.pieproj", ProjectKind::Debug);
    settings.adopt_recent("/a.pieproj", ProjectKind::Engineer);
    assert_eq!(settings.recent.len(), 3);
    assert_eq!(settings.recent[0].kind, Some(ProjectKind::Engineer));
    let merged = AppSettings::merge_recent(&settings.recent, &loaded.recent);
    assert_eq!(merged[0].path, "/a.pieproj");
}

#[test]
fn theme_cycles() {
    assert_eq!(ThemePreference::System.next(), ThemePreference::Light);
    assert_eq!(ThemePreference::Light.next(), ThemePreference::Dark);
    assert_eq!(ThemePreference::Dark.next(), ThemePreference::System);
}

#[test]
fn workspace_create_edit_autosave_and_theme_persist() {
    use pieblock_tui::{SaveStatus, Workspace};
    use std::time::{Duration, Instant};

    let dir = unique_dir("workspace");
    let mut workspace = Workspace::load(dir.join("data"));
    assert_eq!(workspace.recent().len(), 0);
    {
        let session = workspace
            .create(dir.join("robot"), ProjectKind::Infantry, None)
            .expect("create");
        assert!(session.path.exists());
    }
    assert_eq!(workspace.recent().len(), 1);
    assert!(dir.join("data").join("settings.json").exists());
    let config = workspace
        .session
        .as_ref()
        .expect("session")
        .document
        .config
        .clone();
    workspace.update_config(config);
    assert_eq!(workspace.save_status(), SaveStatus::Saving);
    assert!(!workspace.tick(Instant::now()));
    assert!(workspace.tick(Instant::now() + Duration::from_millis(700)));
    assert_eq!(workspace.save_status(), SaveStatus::Saved);

    workspace.cycle_theme();
    let reloaded = Workspace::load(dir.join("data"));
    assert_eq!(reloaded.settings.theme, ThemePreference::Light);
    assert_eq!(reloaded.recent().len(), 1);

    let mut workspace = reloaded;
    let error = workspace
        .open(dir.join("missing.pieproj"))
        .expect_err("missing project");
    assert!(error.to_string().contains("读取工程失败"));
    assert!(
        workspace
            .last_error
            .as_deref()
            .is_some_and(|message| message.starts_with("打开失败"))
    );
}

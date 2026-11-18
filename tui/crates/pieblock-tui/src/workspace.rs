//! 自动保存调度与工作区状态（设置/最近项目/当前工程）。

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use pieblock_core::ProjectKind;
use pieblock_toolchain::models::CompilerKind;

use crate::session::{ProjectSession, SaveStatus, SessionError, read_project_kind};
use crate::settings::{AppSettings, SettingsStore, ThemePreference, atomic_write};

/// 桌面端自动保存防抖间隔（与 Flutter 版 500ms 一致）。
pub const AUTOSAVE_DELAY: Duration = Duration::from_millis(500);

/// 防抖自动保存调度器。
#[derive(Debug, Clone)]
pub struct Autosave {
    delay: Duration,
    dirty_at: Option<Instant>,
}

impl Default for Autosave {
    fn default() -> Self {
        Self::new(AUTOSAVE_DELAY)
    }
}

impl Autosave {
    #[must_use]
    pub fn new(delay: Duration) -> Self {
        Self {
            delay,
            dirty_at: None,
        }
    }

    /// 记录一次编辑。
    pub fn mark_dirty(&mut self, now: Instant) {
        self.dirty_at = Some(now);
    }

    /// 到点则应保存；没有脏数据或还没到间隔返回 false。
    #[must_use]
    pub fn should_save(&self, now: Instant) -> bool {
        self.dirty_at
            .is_some_and(|dirty_at| now.duration_since(dirty_at) >= self.delay)
    }

    /// 保存完成/放弃后清除脏标记。
    pub fn clear(&mut self) {
        self.dirty_at = None;
    }

    #[must_use]
    pub fn is_dirty(&self) -> bool {
        self.dirty_at.is_some()
    }
}

/// TUI 工作区：设置、最近项目与当前工程。
pub struct Workspace {
    pub data_dir: PathBuf,
    pub settings: AppSettings,
    pub store: SettingsStore,
    pub session: Option<ProjectSession>,
    pub autosave: Autosave,
    pub last_error: Option<String>,
}

impl Workspace {
    /// 加载设置并清理已不存在的最近项目。
    #[must_use]
    pub fn load(data_dir: impl Into<PathBuf>) -> Self {
        let data_dir = data_dir.into();
        let store = SettingsStore::new(data_dir.join("settings.json"));
        let settings = store.load_cleaned(read_project_kind);
        Self {
            data_dir,
            settings,
            store,
            session: None,
            autosave: Autosave::default(),
            last_error: None,
        }
    }

    fn persist_settings(&mut self) {
        if let Err(error) = self.store.save(&self.settings) {
            self.last_error = Some(format!("设置保存失败：{error}"));
        }
    }

    /// 切换主题并立即持久化。
    pub fn cycle_theme(&mut self) {
        self.settings.theme = self.settings.theme.next();
        self.persist_settings();
    }

    /// 新建工程（可选模板）。
    pub fn create(
        &mut self,
        path: impl AsRef<Path>,
        kind: ProjectKind,
        template: Option<pieblock_core::model::ProjectConfig>,
    ) -> Result<&ProjectSession, SessionError> {
        match ProjectSession::create(path, kind, template) {
            Ok(session) => {
                self.adopt(session);
                self.last_error = None;
                Ok(self.session.as_ref().expect("adopted"))
            }
            Err(error) => {
                self.last_error = Some(format!("创建失败：{error}"));
                Err(error)
            }
        }
    }

    /// 打开工程；旧格式自动升版。
    pub fn open(&mut self, path: impl AsRef<Path>) -> Result<&ProjectSession, SessionError> {
        match ProjectSession::open(path) {
            Ok(session) => {
                self.adopt(session);
                self.last_error = None;
                Ok(self.session.as_ref().expect("adopted"))
            }
            Err(error) => {
                self.last_error = Some(format!("打开失败：{error}"));
                Err(error)
            }
        }
    }

    fn adopt(&mut self, session: ProjectSession) {
        self.settings
            .adopt_recent(&session.path.display().to_string(), session.document.kind);
        self.persist_settings();
        self.autosave.clear();
        self.session = Some(session);
    }

    /// 配置编辑：标脏并启动 500ms 防抖。
    pub fn update_config(&mut self, config: pieblock_core::model::ProjectConfig) {
        if let Some(session) = self.session.as_mut() {
            session.update_config(config);
            self.autosave.mark_dirty(Instant::now());
        }
    }

    /// 主循环每帧调用；到点自动保存并返回是否发生保存。
    pub fn tick(&mut self, now: Instant) -> bool {
        if !self.autosave.should_save(now) {
            return false;
        }
        self.autosave.clear();
        self.save_now()
    }

    /// 立即保存当前工程。
    pub fn save_now(&mut self) -> bool {
        let Some(session) = self.session.as_mut() else {
            return false;
        };
        match session.save_now() {
            Ok(()) => {
                self.last_error = None;
                true
            }
            Err(error) => {
                self.last_error = Some(error.to_string());
                false
            }
        }
    }

    #[must_use]
    pub fn save_status(&self) -> SaveStatus {
        self.session
            .as_ref()
            .map_or(SaveStatus::Saved, |session| session.save_status)
    }

    #[must_use]
    pub fn title(&self) -> String {
        self.session
            .as_ref()
            .map_or_else(|| "PIE-Block".to_owned(), ProjectSession::display_name)
    }

    /// 供设置页展示：最近 8 条。
    #[must_use]
    pub fn recent(&self) -> &[crate::settings::RecentProject] {
        &self.settings.recent
    }

    /// 主题文案。
    #[must_use]
    pub fn theme_label(&self) -> &'static str {
        match self.settings.theme {
            ThemePreference::System => "跟随系统",
            ThemePreference::Light => "浅色",
            ThemePreference::Dark => "深色",
        }
    }

    /// 手动保存设置。
    pub fn save_settings(&mut self) {
        self.persist_settings();
    }

    /// 切换编译器（SDCC ↔ Keil）。
    pub fn toggle_compiler(&mut self) {
        self.settings.compiler = match self.settings.compiler {
            CompilerKind::Sdcc => CompilerKind::Keil,
            CompilerKind::Keil => CompilerKind::Sdcc,
        };
        self.persist_settings();
    }

    /// 设置 Keil 安装目录（空字符串表示清除）。
    pub fn set_keil_path(&mut self, path: Option<String>) {
        self.settings.keil_path = path.filter(|value| !value.trim().is_empty());
        self.persist_settings();
    }

    /// 切换烧录引导提示开关。
    pub fn toggle_suppress_flash_guide(&mut self) {
        self.settings.suppress_flash_guide = !self.settings.suppress_flash_guide;
        self.persist_settings();
    }

    /// 切换模板引导提示开关。
    pub fn toggle_suppress_template_guide(&mut self) {
        self.settings.suppress_template_guide = !self.settings.suppress_template_guide;
        self.persist_settings();
    }
}

/// 设置 JSON 的一次性原子写（备用接口，供状态栏/调试导出）。
pub fn write_settings_file(path: &Path, settings: &AppSettings) -> std::io::Result<()> {
    let text = serde_json::to_string(&settings.to_json())
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
    atomic_write(path, text.as_bytes())
}

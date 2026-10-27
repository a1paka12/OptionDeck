mod layout;
mod feature;
use feature::Feature;
use serde::{Deserialize, Serialize};
use std::{ffi::{CStr, CString, c_char}, fs::{self, OpenOptions}, io::Write,
    os::{fd::AsRawFd, unix::fs::OpenOptionsExt}, path::{Path, PathBuf}, sync::{Mutex, atomic::{AtomicU64, Ordering}}};

// One serialization point for all FFI callers. flock also protects multiple processes.
static TRANSACTION: Mutex<()> = Mutex::new(());
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct App { pub id: String, pub name: String, pub path: Option<String> }
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Settings {
    pub apps: Vec<App>, pub devices: Vec<u8>, pub media: Vec<u8>, pub automatic_shortcuts: bool,
    #[serde(default)] pub language: Option<Language>,
    #[serde(default)] pub layouts: Option<layout::Layouts>,
    #[serde(default)] pub music_app: Option<App>,
    #[serde(default)] pub media_features: Option<Vec<Feature>>,
    #[serde(default)] pub launcher_features: Option<Vec<Feature>>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Language { Ko, En }
impl Default for Settings {
    fn default() -> Self {
        let apps = [("com.google.Chrome", "Chrome"), ("com.microsoft.VSCode", "VS Code"),
            ("com.cmuxterm.app", "cmux"), ("com.apple.Safari", "Safari"), ("notion.id", "Notion"),
            ("com.apple.Terminal", "터미널"), ("com.apple.finder", "Finder"),
            ("com.apple.VoiceMemos", "음성 메모"), ("md.obsidian", "Obsidian")]
            .into_iter().map(|(id, name)| App { id: id.into(), name: name.into(), path: None }).collect();
        Self { apps, devices: vec![0, 1], media: (0..6).collect(), automatic_shortcuts: true, language: None, media_features: None, launcher_features: None, music_app: None, layouts: None }
    }
}
impl Settings {
    fn validate(&self) -> Result<(), String> {
        fn permutation(values: &[u8], count: u8) -> bool {
            let mut sorted = values.to_vec(); sorted.sort_unstable(); sorted == (0..count).collect::<Vec<_>>()
        }
        if self.apps.len() != 9 || !permutation(&self.devices, 2) || !permutation(&self.media, 6) {
            return Err("Invalid slot count or layout permutation".into());
        }
        if let Some(layouts) = &self.layouts { layouts.validate(self.media_features.as_ref().map_or(1,Vec::len), self.launcher_features.as_ref().map_or(9,Vec::len))?; }
        for features in [&self.media_features, &self.launcher_features] {
            if let Some(features) = features {
                if features.len() > 24 { return Err("Invalid feature slot count".into()); }
                for feature in features { feature.validate()?; }
            }
        }
        for app in self.apps.iter().chain(self.music_app.iter()) {
            if app.id.trim().is_empty() || app.id.len() > 512 || app.name.trim().is_empty() || app.name.len() > 256
                || app.id.contains('\0') || app.name.contains('\0') {
                return Err("Invalid app identity".into());
            }
            if let Some(path) = &app.path {
                if path.len() > 4096 || path.contains('\0') || !Path::new(path).is_absolute() || !path.ends_with(".app") {
                    return Err("Invalid application path".into());
                }
            }
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Document { schema: u32, revision: u64, settings: Settings }
impl Default for Document {
    fn default() -> Self { Self { schema: 1, revision: 0, settings: Settings::default() } }
}
#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
enum Request { Load, Save { expected_revision: u64, settings: Settings } }

struct FileLock(std::fs::File);
impl FileLock {
    fn acquire(path: &Path) -> Result<Self, String> {
        let file = OpenOptions::new().read(true).write(true).create(true).truncate(false).mode(0o600)
            .open(path.with_extension("lock")).map_err(|e| e.to_string())?;
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } != 0 { return Err(std::io::Error::last_os_error().to_string()); }
        Ok(Self(file))
    }
}
impl Drop for FileLock { fn drop(&mut self) { unsafe { libc::flock(self.0.as_raw_fd(), libc::LOCK_UN); } } }
fn transact(path: &Path, request: Request) -> Result<Document, String> {
    let _guard = TRANSACTION.lock().map_err(|_| "Engine lock poisoned")?;
    let parent = path.parent().ok_or("Invalid settings directory")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let _file_lock = FileLock::acquire(path)?;
    let mut doc = match fs::read(path) {
        Ok(data) => {
            if data.len() > 128 * 1024 { return Err("Settings file is too large".into()); }
            let doc: Document = serde_json::from_slice(&data).map_err(|e| format!("Settings unreadable (original preserved): {e}"))?;
            if doc.schema != 1 { return Err("Unsupported settings version (original preserved)".into()); }
            doc.settings.validate()?; doc
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Document::default(),
        Err(e) => return Err(e.to_string()),
    };
    if let Request::Save { expected_revision, settings } = request {
        if expected_revision != doc.revision { return Err("conflict: settings changed in another window or process; reload before saving".into()); }
        settings.validate()?;
        doc.revision = doc.revision.checked_add(1).ok_or("Revision overflow")?;
        doc.settings = settings;
        let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|e| e.to_string())?.as_nanos();
        let temp = parent.join(format!(".optiondeck-{}-{nonce}.tmp", std::process::id()));
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp).map_err(|e| e.to_string())?;
        // Under both locks: persist first, publish only after the atomic rename succeeds.
        let result = (|| -> Result<(), String> {
            let bytes = serde_json::to_vec_pretty(&doc).map_err(|e| e.to_string())?;
            file.write_all(&bytes).and_then(|_| file.sync_all()).map_err(|e| e.to_string())?;
            fs::rename(&temp, path).map_err(|e| e.to_string())?;
            Ok(())
        })();
        if result.is_err() { let _ = fs::remove_file(&temp); }
        result?;
    }
    Ok(doc)
}

// Generation tickets invalidate asynchronous menu responses after selection/configuration changes.
static SHORTCUT_GENERATION: AtomicU64 = AtomicU64::new(0);
#[no_mangle]
pub extern "C" fn od_shortcut_advance() -> u64 {
    SHORTCUT_GENERATION.try_update(Ordering::SeqCst, Ordering::SeqCst, |value| value.checked_add(1))
        .map(|value| value + 1).unwrap_or(0)
}
#[no_mangle]
pub extern "C" fn od_shortcut_is_current(ticket: u64) -> bool {
    ticket != 0 && SHORTCUT_GENERATION.load(Ordering::SeqCst) == ticket
}

/// Callers provide valid NUL-terminated UTF-8 strings, with lifetime through this call.
/// Returned memory belongs to Rust and must be released exactly once with od_engine_free.
#[no_mangle]
pub unsafe extern "C" fn od_engine_request(path: *const c_char, request: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| -> Result<Document, String> {
        if path.is_null() || request.is_null() { return Err("Null request".into()); }
        let path = CStr::from_ptr(path).to_str().map_err(|e| e.to_string())?;
        let json = CStr::from_ptr(request).to_str().map_err(|e| e.to_string())?;
        if path.len() > 4096 || json.len() > 128 * 1024 { return Err("Request too large".into()); }
        let request = serde_json::from_str(json).map_err(|e| e.to_string())?;
        transact(&PathBuf::from(path), request)
    });
    let value = match result {
        Ok(Ok(doc)) => serde_json::json!({"document": doc}),
        Ok(Err(error)) => serde_json::json!({"error": error}),
        Err(_) => serde_json::json!({"error": "Rust engine failed"}),
    };
    CString::new(value.to_string()).expect("JSON has no literal NUL").into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn od_layout_request(request: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| -> Result<layout::ResultLayout,String> {
        if request.is_null() { return Err("Null layout request".into()); }
        let text=CStr::from_ptr(request).to_str().map_err(|e|e.to_string())?;
        if text.len()>16384 { return Err("Layout request too large".into()); }
        layout::execute(serde_json::from_str(text).map_err(|e|e.to_string())?)
    });
    let value=match result {
        Ok(Ok(layout)) => serde_json::json!({"layout":layout}),
        Ok(Err(error)) => serde_json::json!({"error":error}),
        Err(_) => serde_json::json!({"error":"Layout engine failed"}),
    };
    CString::new(value.to_string()).expect("JSON has no NUL").into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn od_engine_free(response: *mut c_char) {
    if !response.is_null() { drop(CString::from_raw(response)); }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier, atomic::{AtomicU64, Ordering}};
    static SERIAL: AtomicU64 = AtomicU64::new(0);
    fn path() -> PathBuf { std::env::temp_dir().join(format!("optiondeck-test-{}-{}", std::process::id(), SERIAL.fetch_add(1, Ordering::Relaxed))).join("settings.json") }
    #[test] fn persistence_and_conflicts() {
        let path = path(); let mut settings = Settings::default(); settings.devices.swap(0, 1); settings.apps.swap(0, 8);
        let saved = transact(&path, Request::Save { expected_revision: 0, settings: settings.clone() }).unwrap();
        assert_eq!(saved.revision, 1); assert_eq!(transact(&path, Request::Load).unwrap().settings, settings);
        assert!(transact(&path, Request::Save { expected_revision: 0, settings: Settings::default() }).unwrap_err().starts_with("conflict:"));
        assert_eq!(transact(&path, Request::Load).unwrap().settings, settings);
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test] fn invalid_configuration_does_not_overwrite() {
        let path = path(); let mut settings = Settings::default(); settings.media = vec![0; 6];
        assert!(transact(&path, Request::Save { expected_revision: 0, settings }).is_err());
        assert!(!path.exists());
        fs::write(&path, "corrupted user data").unwrap();
        assert!(transact(&path, Request::Save { expected_revision: 0, settings: Settings::default() }).is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), "corrupted user data");
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test] fn concurrent_writers_have_one_winner() {
        let path = path(); let barrier = Arc::new(Barrier::new(8));
        let threads: Vec<_> = (0..8).map(|i| { let path = path.clone(); let barrier = barrier.clone();
            std::thread::spawn(move || { let mut settings = Settings::default(); settings.apps[0].name = format!("App {i}"); barrier.wait();
                transact(&path, Request::Save { expected_revision: 0, settings }).is_ok() }) }).collect();
        assert_eq!(threads.into_iter().filter_map(|t| t.join().ok()).filter(|ok| *ok).count(), 1);
        assert_eq!(transact(&path, Request::Load).unwrap().revision, 1);
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test]
    #[ignore = "subprocess helper, invoked by concurrent_processes"]
    fn process_writer() {
        let path = PathBuf::from(std::env::var("OD_TEST_PATH").unwrap());
        let marker = PathBuf::from(std::env::var("OD_TEST_MARKER").unwrap());
        let won = match transact(&path, Request::Save { expected_revision: 0, settings: Settings::default() }) {
            Ok(_) => true,
            Err(error) => { assert!(error.starts_with("conflict:"), "{error}"); false }
        };
        fs::write(marker, if won { "won" } else { "conflict" }).unwrap();
    }
    #[test] fn concurrent_processes() {
        let path = path(); fs::create_dir_all(path.parent().unwrap()).unwrap();
        let mut children = Vec::new();
        for index in 0..8 {
            let marker = path.parent().unwrap().join(format!("result-{index}"));
            let child = std::process::Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "tests::process_writer", "--ignored"])
                .env("OD_TEST_PATH", &path).env("OD_TEST_MARKER", &marker)
                .stdout(std::process::Stdio::null()).spawn().unwrap();
            children.push((child, marker));
        }
        let mut wins = 0;
        for (mut child, marker) in children {
            assert!(child.wait().unwrap().success());
            if fs::read_to_string(marker).unwrap() == "won" { wins += 1; }
        }
        assert_eq!(wins, 1);
        assert_eq!(transact(&path, Request::Load).unwrap().revision, 1);
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test] fn ffi_roundtrip_and_rejected_request() {
        let path = path();
        let cpath = CString::new(path.to_str().unwrap()).unwrap();
        let request = CString::new(serde_json::json!({"op": "save", "expected_revision": 0, "settings": Settings::default()}).to_string()).unwrap();
        unsafe {
            let response = od_engine_request(cpath.as_ptr(), request.as_ptr());
            let value: serde_json::Value = serde_json::from_str(CStr::from_ptr(response).to_str().unwrap()).unwrap();
            assert_eq!(value["document"]["revision"], 1); od_engine_free(response);
            let invalid = CString::new("{invalid").unwrap();
            let response = od_engine_request(cpath.as_ptr(), invalid.as_ptr());
            assert!(CStr::from_ptr(response).to_str().unwrap().contains("error")); od_engine_free(response);
        }
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test] fn custom_features_roundtrip_and_invalid_actions_are_rejected() {
        use feature::{Feature, FeatureKind};
        let path = path(); let mut settings = Settings::default();
        let action = Feature { kind: FeatureKind::Url, value: "https://example.com".into(), name: "Website".into(), path: None };
        settings.media_features = Some(vec![action; 6]);
        let app = Feature { kind: FeatureKind::App, value: "org.example.app".into(), name: "내 앱".into(), path: Some("/Applications/내 App.app".into()) };
        settings.launcher_features = Some(vec![app; 9]);
        settings.music_app = Some(App { id: "org.example.player".into(), name: "Music Player".into(), path: Some("/Applications/Music Player.app".into()) });
        let resized=layout::execute(layout::Request::Resize { tiles:layout::Layouts::default().actions,id:"app:0".into(),columns:4,rows:2 }).unwrap();
        let system=(0..6).map(|i|layout::Tile {id:format!("media:{i}"),columns:2,rows:1}).collect();
        settings.layouts=Some(layout::Layouts { system, actions:resized.tiles });
        let doc = transact(&path, Request::Save { expected_revision: 0, settings: settings.clone() }).unwrap();
        assert_eq!(transact(&path, Request::Load).unwrap().settings, settings);
        let before = fs::read(&path).unwrap();
        settings.media_features.as_mut().unwrap()[0].value = "javascript:alert(1)".into();
        assert!(transact(&path, Request::Save { expected_revision: doc.revision, settings }).is_err());
        assert_eq!(fs::read(&path).unwrap(), before);
        assert!(Feature { kind: FeatureKind::Builtin, value: "unknown".into(), name: "Unknown".into(), path: None }.validate().is_err());
        assert!(Feature { kind: FeatureKind::Shortcut, value: "My automation".into(), name: "Run".into(), path: None }.validate().is_ok());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test] fn legacy_settings_without_optional_features_remain_readable() {
        let mut value = serde_json::to_value(Settings::default()).unwrap();
        let object = value.as_object_mut().unwrap();
        for key in ["music_app", "media_features", "launcher_features", "layouts", "language"] { object.remove(key); }
        let settings: Settings = serde_json::from_value(value).unwrap();
        settings.validate().unwrap(); assert_eq!(settings, Settings::default());
    }
    #[test] fn language_roundtrips_without_changing_layout_or_names() {
        let path = path();
        let mut settings = Settings::default();
        settings.apps[0].name = "My own app".into();
        settings.language = Some(Language::En);
        transact(&path, Request::Save { expected_revision: 0, settings: settings.clone() }).unwrap();
        let mut loaded = transact(&path, Request::Load).unwrap().settings;
        assert_eq!(loaded, settings);
        loaded.language = Some(Language::Ko);
        transact(&path, Request::Save { expected_revision: 1, settings: loaded.clone() }).unwrap();
        assert_eq!(transact(&path, Request::Load).unwrap().settings, loaded);
        assert!(serde_json::from_value::<Settings>(serde_json::json!({
            "apps": [], "devices": [], "media": [], "automatic_shortcuts": true, "language": "fr"
        })).is_err());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test] fn dynamic_pages_can_add_and_remove_all_slots() {
        use feature::{Feature,FeatureKind};
        let path=path(); let mut settings=Settings::default();
        settings.media_features=Some(vec![]); settings.launcher_features=Some(vec![]);
        settings.layouts=Some(layout::Layouts { system:vec![],actions:vec![] });
        let empty=transact(&path,Request::Save {expected_revision:0,settings:settings.clone()}).unwrap();
        assert!(empty.settings.layouts.as_ref().unwrap().system.is_empty());
        settings.launcher_features.as_mut().unwrap().push(Feature {kind:FeatureKind::Url,value:"https://example.com".into(),name:"Site".into(),path:None});
        settings.layouts.as_mut().unwrap().actions.push(layout::Tile {id:"app:0".into(),columns:2,rows:1});
        let added=transact(&path,Request::Save {expected_revision:1,settings}).unwrap();
        assert_eq!(added.settings.launcher_features.as_ref().unwrap().len(),1);
        assert_eq!(transact(&path,Request::Load).unwrap().settings,added.settings);
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test] fn older_shortcut_response_is_rejected() {
        let older = od_shortcut_advance(); let newer = od_shortcut_advance();
        assert!(!od_shortcut_is_current(older)); assert!(od_shortcut_is_current(newer));
        assert!(!od_shortcut_is_current(0));
    }
    #[test] fn ffi_response_and_null_input() {
        unsafe { let result = od_engine_request(std::ptr::null(), std::ptr::null());
            assert!(CStr::from_ptr(result).to_str().unwrap().contains("Null request")); od_engine_free(result); od_engine_free(std::ptr::null_mut()); }
    }
}

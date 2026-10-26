use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum FeatureKind { Builtin, App, File, Url, Shortcut, Empty }
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Feature { pub kind: FeatureKind, pub value: String, pub name: String, pub path: Option<String> }
impl Feature {
    pub fn validate(&self) -> Result<(), String> {
        if self.name.trim().is_empty() || self.name.len() > 256 || self.value.len() > 4096
            || self.name.contains('\0') || self.value.chars().any(char::is_control) {
            return Err("Invalid feature name or value".into());
        }
        let valid = match self.kind {
            FeatureKind::Builtin => ["mediaWidget", "previous", "playback", "next", "systemMedia", "backwardSkip", "forwardSkip", "mute", "screenshot"].contains(&self.value.as_str()),
            FeatureKind::App => !self.value.trim().is_empty() && self.value.len() <= 512,
            FeatureKind::File => std::path::Path::new(&self.value).is_absolute(),
            FeatureKind::Url => ["https://", "http://"].iter().any(|scheme| self.value.starts_with(scheme) && self.value.len() > scheme.len()) && !self.value.contains(char::is_whitespace),
            FeatureKind::Shortcut => !self.value.trim().is_empty() && self.value.len() <= 256,
            FeatureKind::Empty => self.value.is_empty(),
        };
        if !valid { return Err("Unsupported feature or invalid destination".into()); }
        if let Some(path) = &self.path {
            if self.kind != FeatureKind::App || path.len() > 4096 || path.contains('\0')
                || !std::path::Path::new(path).is_absolute() || !path.ends_with(".app") {
                return Err("Invalid app feature path".into());
            }
        }
        Ok(())
    }
}

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub whisper_model: String,
    pub pause_threshold: f64,
    pub initial_prompt: String,
    pub language: String,
    pub hotkey: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            whisper_model: "medium".to_string(),
            pause_threshold: 1.5,
            initial_prompt: String::new(),
            language: "auto".to_string(),
            hotkey: "Ctrl+Shift+R".to_string(),
        }
    }
}

impl Config {
    pub fn load() -> Self {
        let path = Self::config_path();
        if let Ok(contents) = fs::read_to_string(&path) {
            Self::parse(&contents)
        } else {
            Self::default()
        }
    }

    pub fn config_dir() -> PathBuf {
        if cfg!(windows) {
            dirs::config_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("scriptik")
        } else {
            dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join(".config")
                .join("scriptik")
        }
    }

    pub fn config_path() -> PathBuf {
        Self::config_dir().join("config")
    }

    pub fn data_dir() -> PathBuf {
        if cfg!(windows) {
            dirs::data_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("scriptik")
        } else {
            dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join(".local/share/scriptik")
        }
    }

    fn parse(contents: &str) -> Self {
        let mut map = HashMap::new();
        for line in contents.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((key, value)) = line.split_once('=') {
                let value = value.trim().trim_matches('"');
                map.insert(key.trim().to_uppercase(), value.to_string());
            }
        }

        let defaults = Self::default();
        Self {
            whisper_model: map.get("WHISPER_MODEL").cloned().unwrap_or(defaults.whisper_model),
            pause_threshold: map.get("PAUSE_THRESHOLD")
                .and_then(|v| v.parse().ok())
                .unwrap_or(defaults.pause_threshold),
            initial_prompt: map.get("INITIAL_PROMPT").cloned().unwrap_or(defaults.initial_prompt),
            language: map.get("LANGUAGE").cloned().unwrap_or(defaults.language),
            hotkey: map.get("HOTKEY").cloned().unwrap_or(defaults.hotkey),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_full_config() {
        let input = r#"
WHISPER_MODEL=small
PAUSE_THRESHOLD=2.0
INITIAL_PROMPT=Docker, FastAPI
LANGUAGE=en
HOTKEY=Ctrl+Alt+R
"#;
        let config = Config::parse(input);
        assert_eq!(config.whisper_model, "small");
        assert_eq!(config.pause_threshold, 2.0);
        assert_eq!(config.initial_prompt, "Docker, FastAPI");
        assert_eq!(config.language, "en");
        assert_eq!(config.hotkey, "Ctrl+Alt+R");
    }

    #[test]
    fn test_parse_empty_uses_defaults() {
        let config = Config::parse("");
        assert_eq!(config.whisper_model, "medium");
        assert_eq!(config.pause_threshold, 1.5);
        assert_eq!(config.language, "auto");
    }

    #[test]
    fn test_parse_with_comments_and_quotes() {
        let input = r#"
# This is a comment
WHISPER_MODEL="large"
PAUSE_THRESHOLD=3.0
"#;
        let config = Config::parse(input);
        assert_eq!(config.whisper_model, "large");
        assert_eq!(config.pause_threshold, 3.0);
    }

    #[test]
    fn test_parse_invalid_threshold_uses_default() {
        let input = "PAUSE_THRESHOLD=notanumber";
        let config = Config::parse(input);
        assert_eq!(config.pause_threshold, 1.5);
    }
}

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod config;
mod transcriber;

use audio::Recorder;
use config::Config;
use transcriber::TranscriptionServer;

use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager, hotkey::{Code, HotKey, Modifiers}};
use std::sync::Arc;
use tauri::{
    AppHandle, Emitter, Manager,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
};
use tokio::sync::Mutex;

#[derive(Debug, Clone, serde::Serialize)]
enum AppStatus {
    Idle,
    Recording,
    Transcribing,
}

struct AppState {
    status: Mutex<AppStatus>,
    recorder: Recorder,
    server: TranscriptionServer,
    config: Config,
    last_transcription: Mutex<String>,
}

#[tauri::command]
async fn get_status(state: tauri::State<'_, Arc<AppState>>) -> Result<String, String> {
    let status = state.status.lock().await;
    Ok(serde_json::to_string(&*status).unwrap())
}

#[tauri::command]
async fn get_last_transcription(state: tauri::State<'_, Arc<AppState>>) -> Result<String, String> {
    Ok(state.last_transcription.lock().await.clone())
}

#[tauri::command]
async fn toggle_recording(app: AppHandle, state: tauri::State<'_, Arc<AppState>>) -> Result<(), String> {
    do_toggle(app, &state).await
}

async fn do_toggle(app: AppHandle, state: &Arc<AppState>) -> Result<(), String> {
    let current = state.status.lock().await.clone();
    match current {
        AppStatus::Idle => {
            state.recorder.start()?;
            *state.status.lock().await = AppStatus::Recording;
            let _ = app.emit("status-changed", "Recording");
        }
        AppStatus::Recording => {
            state.recorder.stop();
            *state.status.lock().await = AppStatus::Transcribing;
            let _ = app.emit("status-changed", "Transcribing");

            // Wait for WAV file to be written
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;

            let recording_path = state.recorder.output_path().to_string_lossy().to_string();
            let transcription_path = std::env::temp_dir()
                .join("scriptik")
                .join("transcription.txt")
                .to_string_lossy()
                .to_string();

            let config = &state.config;

            match state.server.transcribe(
                &recording_path,
                &transcription_path,
                config.pause_threshold,
                &config.whisper_model,
                &config.initial_prompt,
                &config.language,
            ).await {
                Ok(text) => {
                    if let Ok(mut clipboard) = arboard::Clipboard::new() {
                        let _ = clipboard.set_text(&text);
                    }
                    *state.last_transcription.lock().await = text.clone();
                    let _ = app.emit("transcription-done", text);
                }
                Err(e) => {
                    let _ = app.emit("transcription-error", e.clone());
                    eprintln!("Transcription error: {e}");
                }
            }

            *state.status.lock().await = AppStatus::Idle;
            let _ = app.emit("status-changed", "Idle");
        }
        AppStatus::Transcribing => {}
    }
    Ok(())
}

fn parse_hotkey(hotkey_str: &str) -> Option<HotKey> {
    let parts: Vec<&str> = hotkey_str.split('+').map(|s| s.trim()).collect();
    let mut modifiers = Modifiers::empty();
    let mut key_code = None;

    for part in &parts {
        match part.to_lowercase().as_str() {
            "ctrl" | "control" => modifiers |= Modifiers::CONTROL,
            "shift" => modifiers |= Modifiers::SHIFT,
            "alt" => modifiers |= Modifiers::ALT,
            "super" | "win" | "meta" => modifiers |= Modifiers::SUPER,
            other => {
                key_code = match other {
                    "a" => Some(Code::KeyA), "b" => Some(Code::KeyB), "c" => Some(Code::KeyC),
                    "d" => Some(Code::KeyD), "e" => Some(Code::KeyE), "f" => Some(Code::KeyF),
                    "g" => Some(Code::KeyG), "h" => Some(Code::KeyH), "i" => Some(Code::KeyI),
                    "j" => Some(Code::KeyJ), "k" => Some(Code::KeyK), "l" => Some(Code::KeyL),
                    "m" => Some(Code::KeyM), "n" => Some(Code::KeyN), "o" => Some(Code::KeyO),
                    "p" => Some(Code::KeyP), "q" => Some(Code::KeyQ), "r" => Some(Code::KeyR),
                    "s" => Some(Code::KeyS), "t" => Some(Code::KeyT), "u" => Some(Code::KeyU),
                    "v" => Some(Code::KeyV), "w" => Some(Code::KeyW), "x" => Some(Code::KeyX),
                    "y" => Some(Code::KeyY), "z" => Some(Code::KeyZ),
                    "space" => Some(Code::Space),
                    "f1" => Some(Code::F1), "f2" => Some(Code::F2), "f3" => Some(Code::F3),
                    "f4" => Some(Code::F4), "f5" => Some(Code::F5), "f6" => Some(Code::F6),
                    _ => None,
                };
            }
        }
    }

    key_code.map(|code| HotKey::new(Some(modifiers), code))
}

fn main() {
    let config = Config::load();
    let recorder = Recorder::new();
    let server = TranscriptionServer::new();

    let app_state = Arc::new(AppState {
        status: Mutex::new(AppStatus::Idle),
        recorder,
        server,
        config: config.clone(),
        last_transcription: Mutex::new(String::new()),
    });

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(app_state.clone())
        .invoke_handler(tauri::generate_handler![
            get_status,
            get_last_transcription,
            toggle_recording,
        ])
        .setup(move |app| {
            let app_handle = app.handle().clone();

            // Build tray menu
            let toggle_item = MenuItem::with_id(app.handle(), "toggle", "Start Recording", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app.handle(), "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app.handle(), &[&toggle_item, &quit_item])?;

            // Build tray icon
            let _tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("Scriptik")
                .on_menu_event(move |app, event| {
                    match event.id().as_ref() {
                        "toggle" => {
                            let app = app.clone();
                            let state = app.state::<Arc<AppState>>().inner().clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = do_toggle(app, &state).await;
                            });
                        }
                        "quit" => {
                            std::process::exit(0);
                        }
                        _ => {}
                    }
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            // Register global hotkey
            let hotkey_manager = GlobalHotKeyManager::new().expect("Failed to init hotkey manager");
            if let Some(hotkey) = parse_hotkey(&config.hotkey) {
                hotkey_manager.register(hotkey).expect("Failed to register hotkey");

                let app_handle_hotkey = app_handle.clone();
                let state_for_hotkey = app_state.clone();
                std::thread::spawn(move || {
                    let _manager = hotkey_manager;
                    loop {
                        if let Ok(_event) = GlobalHotKeyEvent::receiver().recv() {
                            let app = app_handle_hotkey.clone();
                            let state = state_for_hotkey.clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = do_toggle(app, &state).await;
                            });
                        }
                    }
                });
            }

            // Start transcription server in background
            let state_for_server = app_state.clone();
            tauri::async_runtime::spawn(async move {
                let python = TranscriptionServer::find_python();
                let script = TranscriptionServer::find_server_script();

                match (python, script) {
                    (Some(python), Some(script)) => {
                        let script_str = script.to_string_lossy().to_string();
                        if let Err(e) = state_for_server.server.start(
                            &python,
                            &state_for_server.config.whisper_model,
                            &script_str,
                        ).await {
                            eprintln!("Failed to start transcription server: {e}");
                        }
                    }
                    _ => {
                        eprintln!("Python or transcribe_server.py not found. Run setup.ps1 first.");
                    }
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

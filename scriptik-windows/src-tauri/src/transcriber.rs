use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::{mpsc, oneshot, Mutex};
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq)]
pub enum ServerState {
    Stopped,
    Starting,
    Ready,
    Busy,
}

pub struct TranscriptionServer {
    state: Arc<Mutex<ServerState>>,
    request_tx: Arc<Mutex<Option<mpsc::Sender<ServerRequest>>>>,
}

struct ServerRequest {
    payload: Value,
    response_tx: oneshot::Sender<Result<Value, String>>,
}

impl TranscriptionServer {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(ServerState::Stopped)),
            request_tx: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn state(&self) -> ServerState {
        self.state.lock().await.clone()
    }

    pub async fn start(&self, python_path: &str, model: &str, server_script: &str) -> Result<(), String> {
        let mut state = self.state.lock().await;
        if *state != ServerState::Stopped {
            return Err("Server already running".to_string());
        }
        *state = ServerState::Starting;
        drop(state);

        let mut child = Command::new(python_path)
            .arg(server_script)
            .arg(model)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .env("PYTHONUNBUFFERED", "1")
            .env("PYTHONIOENCODING", "utf-8")
            .spawn()
            .map_err(|e| format!("Failed to start Python server: {e}"))?;

        let stdin = child.stdin.take().ok_or("Failed to get stdin")?;
        let stdout = child.stdout.take().ok_or("Failed to get stdout")?;
        let stderr = child.stderr.take().ok_or("Failed to get stderr")?;

        let (request_tx, request_rx) = mpsc::channel::<ServerRequest>(16);
        *self.request_tx.lock().await = Some(request_tx);

        let state_clone = self.state.clone();

        tokio::spawn(async move {
            Self::server_loop(child, stdin, stdout, stderr, request_rx, state_clone).await;
        });

        let start_time = std::time::Instant::now();
        loop {
            let s = self.state.lock().await.clone();
            match s {
                ServerState::Ready => return Ok(()),
                ServerState::Stopped => return Err("Server failed to start".to_string()),
                _ => {}
            }
            if start_time.elapsed().as_secs() > 60 {
                return Err("Server startup timed out".to_string());
            }
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
    }

    async fn server_loop(
        _child: Child,
        mut stdin: tokio::process::ChildStdin,
        stdout: tokio::process::ChildStdout,
        stderr: tokio::process::ChildStderr,
        mut request_rx: mpsc::Receiver<ServerRequest>,
        state: Arc<Mutex<ServerState>>,
    ) {
        let mut stdout_reader = BufReader::new(stdout).lines();
        let mut stderr_reader = BufReader::new(stderr).lines();

        let mut pending_response: Option<oneshot::Sender<Result<Value, String>>> = None;

        tokio::spawn(async move {
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                eprintln!("[whisper-server] {line}");
            }
        });

        loop {
            tokio::select! {
                Some(req) = request_rx.recv() => {
                    let json_str = serde_json::to_string(&req.payload).unwrap() + "\n";
                    if let Err(e) = stdin.write_all(json_str.as_bytes()).await {
                        let _ = req.response_tx.send(Err(format!("Failed to write to server: {e}")));
                        continue;
                    }
                    if let Err(e) = stdin.flush().await {
                        let _ = req.response_tx.send(Err(format!("Failed to flush: {e}")));
                        continue;
                    }
                    pending_response = Some(req.response_tx);
                }
                result = stdout_reader.next_line() => {
                    match result {
                        Ok(Some(line)) => {
                            if let Ok(json) = serde_json::from_str::<Value>(&line) {
                                let msg_type = json.get("type").and_then(|t| t.as_str()).unwrap_or("");
                                match msg_type {
                                    "ready" => {
                                        *state.lock().await = ServerState::Ready;
                                    }
                                    "transcription_done" | "model_reloaded" | "error" | "pong" => {
                                        if let Some(tx) = pending_response.take() {
                                            let _ = tx.send(Ok(json));
                                        }
                                        *state.lock().await = ServerState::Ready;
                                    }
                                    _ => {
                                        eprintln!("Unknown server message type: {msg_type}");
                                    }
                                }
                            }
                        }
                        Ok(None) | Err(_) => {
                            if let Some(tx) = pending_response.take() {
                                let _ = tx.send(Err("Server process terminated".to_string()));
                            }
                            *state.lock().await = ServerState::Stopped;
                            break;
                        }
                    }
                }
            }
        }
    }

    pub async fn transcribe(
        &self,
        recording_path: &str,
        transcription_path: &str,
        pause_threshold: f64,
        model: &str,
        initial_prompt: &str,
        language: &str,
    ) -> Result<String, String> {
        {
            let mut state = self.state.lock().await;
            if *state != ServerState::Ready {
                return Err("Server not ready".to_string());
            }
            *state = ServerState::Busy;
        }

        let payload = json!({
            "type": "transcribe",
            "recording_path": recording_path,
            "transcription_path": transcription_path,
            "pause_threshold": pause_threshold,
            "model": model,
            "initial_prompt": initial_prompt,
            "language": language,
        });

        let (response_tx, response_rx) = oneshot::channel();
        let request = ServerRequest { payload, response_tx };

        let tx = self.request_tx.lock().await;
        let tx = tx.as_ref().ok_or("Server not started")?;
        tx.send(request).await.map_err(|_| "Failed to send request".to_string())?;
        let _ = tx;

        let response = tokio::time::timeout(
            std::time::Duration::from_secs(120),
            response_rx,
        )
        .await
        .map_err(|_| "Transcription timed out".to_string())?
        .map_err(|_| "Response channel closed".to_string())??;

        let msg_type = response.get("type").and_then(|t| t.as_str()).unwrap_or("");
        if msg_type == "error" {
            let msg = response.get("message").and_then(|m| m.as_str()).unwrap_or("Unknown error");
            return Err(msg.to_string());
        }

        let text = std::fs::read_to_string(transcription_path)
            .map_err(|e| format!("Failed to read transcription: {e}"))?
            .trim()
            .to_string();

        if text.is_empty() {
            return Err("Transcription produced no output".to_string());
        }

        Ok(text)
    }

    pub async fn stop(&self) {
        *self.state.lock().await = ServerState::Stopped;
        *self.request_tx.lock().await = None;
    }

    pub fn find_server_script() -> Option<PathBuf> {
        if let Ok(exe) = std::env::current_exe() {
            let dir = exe.parent()?;
            let path = dir.join("python").join("transcribe_server.py");
            if path.exists() {
                return Some(path);
            }
            let path = dir.join("..").join("python").join("transcribe_server.py");
            if path.exists() {
                return Some(path);
            }
        }

        let data_dir = crate::config::Config::data_dir();
        let path = data_dir.join("transcribe_server.py");
        if path.exists() {
            return Some(path);
        }

        None
    }

    pub fn find_python() -> Option<String> {
        let data_dir = crate::config::Config::data_dir();

        let venv_python = if cfg!(windows) {
            data_dir.join("venv").join("Scripts").join("python.exe")
        } else {
            data_dir.join("venv").join("bin").join("python3")
        };
        if venv_python.exists() {
            return Some(venv_python.to_string_lossy().to_string());
        }

        let system = if cfg!(windows) { "python" } else { "python3" };
        if std::process::Command::new(system).arg("--version").output().is_ok() {
            return Some(system.to_string());
        }

        None
    }
}

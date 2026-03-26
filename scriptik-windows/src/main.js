const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const statusEl = document.getElementById("status");
const transcriptionEl = document.getElementById("transcription");

listen("status-changed", (event) => {
  statusEl.textContent = event.payload;
  statusEl.className = event.payload.toLowerCase();
});

listen("transcription-done", (event) => {
  transcriptionEl.textContent = event.payload;
  const copied = document.createElement("div");
  copied.textContent = "Copied to clipboard";
  copied.className = "copied-toast";
  document.body.appendChild(copied);
  setTimeout(() => copied.remove(), 2000);
});

listen("transcription-error", (event) => {
  transcriptionEl.textContent = "Error: " + event.payload;
});

async function init() {
  try {
    const status = await invoke("get_status");
    statusEl.textContent = JSON.parse(status);
    const text = await invoke("get_last_transcription");
    if (text) transcriptionEl.textContent = text;
  } catch (e) {
    console.error("Init error:", e);
  }
}

init();

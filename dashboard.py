#!/usr/bin/env python3
"""Scriptik Dashboard — local web UI for configuration and history."""

import http.server
import json
import os
import socketserver
import subprocess
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path

PORT = 19876
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "scriptik"
CONFIG_FILE = CONFIG_DIR / "config"
DATA_DIR = Path("/tmp/scriptik")
LOG_FILE = DATA_DIR / "scriptik.log"
HISTORY_DIR = CONFIG_DIR / "history"


def read_config():
    defaults = {
        "WHISPER_MODEL": "medium",
        "PAUSE_THRESHOLD": "1.5",
        "INITIAL_PROMPT": "",
        "AUTO_PASTE": "true",
        "LANGUAGE": "auto",
    }
    if CONFIG_FILE.exists():
        for line in CONFIG_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                defaults[key.strip()] = val.strip().strip('"').strip("'")
    return defaults


def write_config(data):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Scriptik Configuration",
        "",
        f'WHISPER_MODEL="{data.get("WHISPER_MODEL", "medium")}"',
        f'PAUSE_THRESHOLD="{data.get("PAUSE_THRESHOLD", "1.5")}"',
        f'INITIAL_PROMPT="{data.get("INITIAL_PROMPT", "")}"',
        f'AUTO_PASTE="{data.get("AUTO_PASTE", "true")}"',
        f'LANGUAGE="{data.get("LANGUAGE", "auto")}"',
        "",
    ]
    CONFIG_FILE.write_text("\n".join(lines))


def get_history():
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    entries = []
    for f in sorted(HISTORY_DIR.glob("*.txt"), reverse=True)[:50]:
        try:
            text = f.read_text(encoding="utf-8").strip()
            ts = datetime.strptime(f.stem, "%Y%m%d_%H%M%S")
            entries.append({
                "id": f.stem,
                "timestamp": ts.isoformat(),
                "display_time": ts.strftime("%b %d, %H:%M"),
                "text": text,
                "words": len(text.split()),
            })
        except (ValueError, OSError):
            continue
    return entries


def get_stats():
    history = get_history()
    now = datetime.now()
    week_ago = now - timedelta(days=7)
    total_words = sum(h["words"] for h in history)
    week_entries = [h for h in history if datetime.fromisoformat(h["timestamp"]) > week_ago]
    week_words = sum(h["words"] for h in week_entries)
    minutes_saved = round(total_words / 40 - total_words / 150) if total_words > 0 else 0
    return {
        "total_recordings": len(history),
        "week_recordings": len(week_entries),
        "total_words": total_words,
        "week_words": week_words,
        "minutes_saved": minutes_saved,
    }


def get_log_tail(n=30):
    if LOG_FILE.exists():
        lines = LOG_FILE.read_text().splitlines()
        return lines[-n:]
    return []


DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Scriptik</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{
  --sidebar-bg:rgba(30,30,30,0.82);
  --main-bg:rgba(40,40,42,0.78);
  --card:rgba(255,255,255,0.06);
  --card-hover:rgba(255,255,255,0.09);
  --border:rgba(255,255,255,0.08);
  --accent:#4a9eff;
  --accent-glow:rgba(74,158,255,0.15);
  --red:#ff453a;
  --green:#32d74b;
  --orange:#ff9f0a;
  --text:#f5f5f7;
  --text2:rgba(245,245,247,0.6);
  --text3:rgba(245,245,247,0.35);
  --r:10px;
}
html,body{height:100%;overflow:hidden}
body{
  font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','SF Pro Display','Helvetica Neue',sans-serif;
  color:var(--text);
  background:linear-gradient(135deg,#1a1a2e 0%,#16213e 30%,#0f3460 70%,#1a1a2e 100%);
  background-size:400% 400%;
  animation:bgShift 20s ease infinite;
  -webkit-font-smoothing:antialiased;
}
@keyframes bgShift{0%,100%{background-position:0% 50%}50%{background-position:100% 50%}}

.app{
  display:flex;
  height:100vh;
  backdrop-filter:blur(80px);
  -webkit-backdrop-filter:blur(80px);
}

/* Sidebar */
.side{
  width:200px;
  background:var(--sidebar-bg);
  backdrop-filter:blur(40px);
  -webkit-backdrop-filter:blur(40px);
  border-right:1px solid var(--border);
  display:flex;
  flex-direction:column;
  padding:16px 8px;
  gap:2px;
  flex-shrink:0;
}
.side-brand{
  padding:4px 12px 16px;
  font-size:13px;
  font-weight:700;
  color:var(--text);
  letter-spacing:-0.2px;
  display:flex;
  align-items:center;
  gap:8px;
}
.side-brand svg{width:20px;height:20px;fill:var(--red)}
.nav{
  display:flex;
  align-items:center;
  gap:10px;
  padding:7px 12px;
  border-radius:8px;
  font-size:13px;
  color:var(--text2);
  cursor:pointer;
  transition:all 0.12s;
  font-weight:500;
}
.nav:hover{background:rgba(255,255,255,0.06);color:var(--text)}
.nav.on{background:rgba(255,255,255,0.1);color:var(--text)}
.nav svg{width:16px;height:16px;opacity:0.5;flex-shrink:0}
.nav.on svg{opacity:0.9}
.side-bottom{margin-top:auto;padding:8px 12px}
.ver{font-size:11px;color:var(--text3)}

/* Main */
.main{
  flex:1;
  background:var(--main-bg);
  backdrop-filter:blur(40px);
  overflow-y:auto;
  padding:24px 28px;
}
.pg{display:none}
.pg.on{display:block}

/* Header bar */
.hdr{
  display:flex;
  justify-content:space-between;
  align-items:center;
  margin-bottom:20px;
}
.hdr h1{font-size:20px;font-weight:700;letter-spacing:-0.3px}
.badge{
  display:flex;
  align-items:center;
  gap:5px;
  font-size:11px;
  font-weight:600;
  padding:4px 10px;
  border-radius:20px;
  background:rgba(255,255,255,0.06);
  color:var(--text3);
}
.badge.rec{background:rgba(255,69,58,0.15);color:var(--red)}
.badge-dot{width:6px;height:6px;border-radius:50%;background:currentColor}
.badge.rec .badge-dot{animation:blink 1.2s infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:0.2}}

/* Stats */
.stats{
  display:grid;
  grid-template-columns:repeat(4,1fr);
  gap:1px;
  background:var(--border);
  border-radius:var(--r);
  overflow:hidden;
  margin-bottom:24px;
}
.st{
  background:rgba(255,255,255,0.04);
  padding:16px;
  text-align:center;
}
.st-val{font-size:24px;font-weight:700;letter-spacing:-0.5px;color:var(--text)}
.st-lbl{font-size:11px;color:var(--text3);margin-top:3px}

/* Cards */
.card{
  background:var(--card);
  border:1px solid var(--border);
  border-radius:var(--r);
  padding:16px;
  margin-bottom:12px;
  transition:background 0.12s;
}
.card:hover{background:var(--card-hover)}
.card-title{font-size:13px;font-weight:600;margin-bottom:4px}
.card-desc{font-size:12px;color:var(--text2)}

/* Inline controls */
.ctrl-row{
  display:flex;
  align-items:center;
  justify-content:space-between;
  padding:12px 0;
  border-bottom:1px solid var(--border);
}
.ctrl-row:last-child{border-bottom:none}
.ctrl-label{font-size:13px;font-weight:500}
.ctrl-hint{font-size:11px;color:var(--text3);margin-top:2px}
.ctrl-right{flex-shrink:0;margin-left:16px}

select.pill{
  appearance:none;
  -webkit-appearance:none;
  background:rgba(255,255,255,0.08);
  border:1px solid rgba(255,255,255,0.12);
  color:var(--text);
  padding:6px 28px 6px 12px;
  border-radius:8px;
  font-size:13px;
  font-family:inherit;
  cursor:pointer;
  outline:none;
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' fill='none'%3E%3Cpath d='M1 1l4 4 4-4' stroke='%23999' stroke-width='1.5' stroke-linecap='round'/%3E%3C/svg%3E");
  background-repeat:no-repeat;
  background-position:right 10px center;
  transition:border-color 0.12s;
}
select.pill:hover{border-color:rgba(255,255,255,0.25)}
select.pill:focus{border-color:var(--accent)}

input.num{
  background:rgba(255,255,255,0.08);
  border:1px solid rgba(255,255,255,0.12);
  color:var(--text);
  padding:6px 12px;
  border-radius:8px;
  font-size:13px;
  font-family:inherit;
  width:70px;
  text-align:center;
  outline:none;
}
input.num:focus{border-color:var(--accent)}

/* Toggle switch */
.toggle{
  position:relative;
  width:42px;
  height:24px;
  cursor:pointer;
}
.toggle input{display:none}
.toggle-track{
  position:absolute;
  inset:0;
  background:rgba(255,255,255,0.15);
  border-radius:12px;
  transition:background 0.2s;
}
.toggle input:checked+.toggle-track{background:var(--green)}
.toggle-knob{
  position:absolute;
  top:2px;left:2px;
  width:20px;height:20px;
  background:#fff;
  border-radius:50%;
  transition:transform 0.2s;
  box-shadow:0 1px 3px rgba(0,0,0,0.3);
}
.toggle input:checked~.toggle-knob{transform:translateX(18px)}

/* Vocabulary */
textarea.vocab{
  width:100%;
  background:rgba(255,255,255,0.05);
  border:1px solid var(--border);
  color:var(--text);
  padding:10px 12px;
  border-radius:8px;
  font-size:13px;
  font-family:inherit;
  resize:vertical;
  min-height:80px;
  outline:none;
  line-height:1.5;
}
textarea.vocab:focus{border-color:var(--accent)}

.btn{
  padding:7px 16px;
  background:var(--accent);
  color:#fff;
  border:none;
  border-radius:8px;
  font-size:13px;
  font-weight:600;
  font-family:inherit;
  cursor:pointer;
  transition:opacity 0.12s;
}
.btn:hover{opacity:0.85}

/* History */
.h-item{
  background:var(--card);
  border:1px solid var(--border);
  border-radius:var(--r);
  padding:12px 14px;
  margin-bottom:6px;
  cursor:pointer;
  transition:background 0.12s;
}
.h-item:hover{background:var(--card-hover)}
.h-meta{display:flex;justify-content:space-between;font-size:11px;color:var(--text3);margin-bottom:6px}
.h-text{
  font-size:12px;color:var(--text2);
  white-space:pre-wrap;
  font-family:'SF Mono',ui-monospace,monospace;
  line-height:1.5;
  max-height:60px;
  overflow:hidden;
  transition:max-height 0.3s;
}
.h-item.open .h-text{max-height:2000px}

/* Logs */
.log-box{
  background:rgba(0,0,0,0.3);
  border-radius:var(--r);
  padding:14px;
  font-family:'SF Mono',ui-monospace,monospace;
  font-size:11px;
  line-height:1.6;
  color:var(--text2);
  white-space:pre-wrap;
  max-height:calc(100vh - 140px);
  overflow-y:auto;
}

/* Toast */
.toast{
  position:fixed;bottom:20px;left:50%;transform:translateX(-50%) translateY(60px);
  background:rgba(50,215,75,0.95);color:#000;
  padding:8px 20px;border-radius:20px;
  font-size:13px;font-weight:600;
  opacity:0;transition:all 0.3s;
  backdrop-filter:blur(10px);
  z-index:100;
}
.toast.show{transform:translateX(-50%) translateY(0);opacity:1}

/* Model cards */
.models{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:8px;margin-top:12px}
.model-card{
  background:var(--card);
  border:2px solid transparent;
  border-radius:var(--r);
  padding:12px;
  text-align:center;
  cursor:pointer;
  transition:all 0.15s;
}
.model-card:hover{background:var(--card-hover)}
.model-card.sel{border-color:var(--accent);background:var(--accent-glow)}
.model-name{font-size:14px;font-weight:700;margin-bottom:2px}
.model-info{font-size:11px;color:var(--text3)}

/* Scrollbar */
::-webkit-scrollbar{width:6px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:rgba(255,255,255,0.12);border-radius:3px}
::-webkit-scrollbar-thumb:hover{background:rgba(255,255,255,0.2)}

.empty{text-align:center;padding:48px 16px;color:var(--text3);font-size:13px}
.section-title{font-size:11px;font-weight:600;color:var(--text3);text-transform:uppercase;letter-spacing:0.5px;margin-bottom:10px;margin-top:20px}
.section-title:first-child{margin-top:0}
</style>
</head>
<body>
<div class="app">
  <nav class="side">
    <div class="side-brand">
      <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>
      Scriptik
    </div>
    <div class="nav on" data-p="home">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 12l9-9 9 9"/><path d="M5 10v10h14V10"/></svg>
      Home
    </div>
    <div class="nav" data-p="models">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
      Models
    </div>
    <div class="nav" data-p="config">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 1v4m0 14v4m-9-9h4m14 0h4m-3.3-6.7l-2.8 2.8m-9.8 9.8l-2.8 2.8m0-15.4l2.8 2.8m9.8 9.8l2.8 2.8"/></svg>
      Configuration
    </div>
    <div class="nav" data-p="vocab">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h10"/></svg>
      Vocabulary
    </div>
    <div class="nav" data-p="history">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>
      History
    </div>
    <div class="nav" data-p="logs">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h8"/></svg>
      Logs
    </div>
    <div class="side-bottom"><span class="ver">v1.0.0</span></div>
  </nav>

  <main class="main">

    <!-- HOME -->
    <div id="p-home" class="pg on">
      <div class="hdr">
        <h1>Home</h1>
        <span id="status" class="badge"><span class="badge-dot"></span>Idle</span>
      </div>
      <div class="stats">
        <div class="st"><div class="st-val" id="s-wr">0</div><div class="st-lbl">Recordings this week</div></div>
        <div class="st"><div class="st-val" id="s-ww">0</div><div class="st-lbl">Words this week</div></div>
        <div class="st"><div class="st-val" id="s-tr">0</div><div class="st-lbl">Total recordings</div></div>
        <div class="st"><div class="st-val" id="s-ts">0 min</div><div class="st-lbl">Time saved</div></div>
      </div>
      <div class="section-title">Get started</div>
      <div class="card" onclick="navigate('models')" style="cursor:pointer">
        <div class="card-title">Choose a model</div>
        <div class="card-desc">Select the Whisper model that fits your speed vs accuracy needs.</div>
      </div>
      <div class="card" onclick="navigate('config')" style="cursor:pointer">
        <div class="card-title">Configure settings</div>
        <div class="card-desc">Set language, auto-paste, pause detection, and more.</div>
      </div>
      <div class="card" onclick="navigate('vocab')" style="cursor:pointer">
        <div class="card-title">Add vocabulary</div>
        <div class="card-desc">Teach Scriptik custom words, names, and technical terms.</div>
      </div>
    </div>

    <!-- MODELS -->
    <div id="p-models" class="pg">
      <div class="hdr"><h1>Models</h1></div>
      <div class="card-desc" style="margin-bottom:12px">Choose a Whisper model. Larger models are slower but significantly more accurate, especially for non-English languages.</div>
      <div class="models" id="model-grid"></div>
    </div>

    <!-- CONFIGURATION -->
    <div id="p-config" class="pg">
      <div class="hdr"><h1>Configuration</h1></div>
      <div style="background:var(--card);border:1px solid var(--border);border-radius:var(--r);padding:4px 16px">
        <div class="ctrl-row">
          <div>
            <div class="ctrl-label">Language</div>
            <div class="ctrl-hint">Auto-detect or force a specific language</div>
          </div>
          <div class="ctrl-right">
            <select class="pill" id="c-lang">
              <option value="auto">Auto-detect</option>
              <option value="en">English</option>
              <option value="he">Hebrew</option>
              <option value="ar">Arabic</option>
              <option value="ru">Russian</option>
              <option value="es">Spanish</option>
              <option value="fr">French</option>
              <option value="de">German</option>
              <option value="zh">Chinese</option>
              <option value="ja">Japanese</option>
              <option value="ko">Korean</option>
              <option value="pt">Portuguese</option>
              <option value="it">Italian</option>
              <option value="nl">Dutch</option>
              <option value="pl">Polish</option>
              <option value="tr">Turkish</option>
              <option value="uk">Ukrainian</option>
              <option value="hi">Hindi</option>
            </select>
          </div>
        </div>
        <div class="ctrl-row">
          <div>
            <div class="ctrl-label">Model</div>
            <div class="ctrl-hint">Current transcription model</div>
          </div>
          <div class="ctrl-right">
            <select class="pill" id="c-model">
              <option value="tiny">tiny</option>
              <option value="base">base</option>
              <option value="small">small</option>
              <option value="medium">medium</option>
              <option value="large">large</option>
            </select>
          </div>
        </div>
        <div class="ctrl-row">
          <div>
            <div class="ctrl-label">Auto-paste</div>
            <div class="ctrl-hint">Paste transcription into the active app automatically</div>
          </div>
          <div class="ctrl-right">
            <label class="toggle">
              <input type="checkbox" id="c-paste">
              <span class="toggle-track"></span>
              <span class="toggle-knob"></span>
            </label>
          </div>
        </div>
        <div class="ctrl-row">
          <div>
            <div class="ctrl-label">Pause threshold</div>
            <div class="ctrl-hint">Seconds of silence to mark as [pause]</div>
          </div>
          <div class="ctrl-right">
            <input type="number" class="num" id="c-pause" step="0.1" min="0.5" max="10">
          </div>
        </div>
      </div>
      <div style="margin-top:12px;text-align:right">
        <button class="btn" onclick="saveConfig()">Save</button>
      </div>
    </div>

    <!-- VOCABULARY -->
    <div id="p-vocab" class="pg">
      <div class="hdr"><h1>Vocabulary</h1></div>
      <div class="card-desc" style="margin-bottom:12px">Add domain-specific terms, names, filler words, or technical jargon. This helps Whisper recognize words it might otherwise miss. Comma-separated.</div>
      <textarea class="vocab" id="c-prompt" placeholder="Docker, FastAPI, PostgreSQL, React, Kubernetes"></textarea>
      <div style="margin-top:12px;text-align:right">
        <button class="btn" onclick="saveVocab()">Save vocabulary</button>
      </div>
    </div>

    <!-- HISTORY -->
    <div id="p-history" class="pg">
      <div class="hdr"><h1>History</h1></div>
      <div id="hist"></div>
    </div>

    <!-- LOGS -->
    <div id="p-logs" class="pg">
      <div class="hdr">
        <h1>Logs</h1>
        <button class="btn" onclick="loadLogs()" style="font-size:12px;padding:5px 12px">Refresh</button>
      </div>
      <pre class="log-box" id="log-out">Loading...</pre>
    </div>

  </main>
</div>

<div id="toast" class="toast"></div>

<script>
var MODELS=[
  {id:'tiny',  label:'Tiny',  size:'75 MB', speed:'~1s',  desc:'Fastest, basic accuracy'},
  {id:'base',  label:'Base',  size:'140 MB',speed:'~2s',  desc:'Good for clear English'},
  {id:'small', label:'Small', size:'500 MB',speed:'~5s',  desc:'Great all-around'},
  {id:'medium',label:'Medium',size:'1.5 GB',speed:'~15s', desc:'Best for non-English'},
  {id:'large', label:'Large', size:'3 GB',  speed:'~30s', desc:'Maximum accuracy'},
];
var currentModel='medium';

function navigate(p){
  document.querySelectorAll('.nav').forEach(function(n){n.classList.remove('on')});
  document.querySelectorAll('.pg').forEach(function(g){g.classList.remove('on')});
  var nav=document.querySelector('[data-p="'+p+'"]');
  if(nav)nav.classList.add('on');
  document.getElementById('p-'+p).classList.add('on');
  if(p==='history')loadHistory();
  if(p==='logs')loadLogs();
  if(p==='models')renderModels();
}
document.querySelectorAll('.nav').forEach(function(n){
  n.addEventListener('click',function(){navigate(n.dataset.p)});
});

function toast(m){
  var t=document.getElementById('toast');
  t.textContent=m;t.classList.add('show');
  setTimeout(function(){t.classList.remove('show')},2200);
}

function api(ep,d){
  var o=d?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)}:{};
  return fetch('/api/'+ep,o).then(function(r){return r.json()});
}

function loadAll(){
  api('config').then(function(c){
    currentModel=c.WHISPER_MODEL||'medium';
    document.getElementById('c-model').value=currentModel;
    document.getElementById('c-lang').value=c.LANGUAGE||'auto';
    document.getElementById('c-pause').value=c.PAUSE_THRESHOLD||'1.5';
    document.getElementById('c-paste').checked=(c.AUTO_PASTE||'true')==='true';
    document.getElementById('c-prompt').value=c.INITIAL_PROMPT||'';
  });
  api('stats').then(function(s){
    document.getElementById('s-wr').textContent=s.week_recordings;
    document.getElementById('s-ww').textContent=s.week_words.toLocaleString();
    document.getElementById('s-tr').textContent=s.total_recordings;
    document.getElementById('s-ts').textContent=s.minutes_saved+' min';
  });
  loadStatus();
}

function saveConfig(){
  var d={
    WHISPER_MODEL:document.getElementById('c-model').value,
    LANGUAGE:document.getElementById('c-lang').value,
    PAUSE_THRESHOLD:document.getElementById('c-pause').value,
    AUTO_PASTE:document.getElementById('c-paste').checked?'true':'false',
    INITIAL_PROMPT:document.getElementById('c-prompt').value,
  };
  currentModel=d.WHISPER_MODEL;
  api('config',d).then(function(){toast('Settings saved')});
}

function saveVocab(){
  api('config').then(function(c){
    c.INITIAL_PROMPT=document.getElementById('c-prompt').value;
    return api('config',c);
  }).then(function(){toast('Vocabulary saved')});
}

function renderModels(){
  var g=document.getElementById('model-grid');
  g.textContent='';
  MODELS.forEach(function(m){
    var d=document.createElement('div');
    d.className='model-card'+(m.id===currentModel?' sel':'');
    d.addEventListener('click',function(){
      currentModel=m.id;
      document.getElementById('c-model').value=m.id;
      renderModels();
      api('config').then(function(c){
        c.WHISPER_MODEL=m.id;
        return api('config',c);
      }).then(function(){toast('Model: '+m.label)});
    });
    var name=document.createElement('div');
    name.className='model-name';name.textContent=m.label;
    var size=document.createElement('div');
    size.className='model-info';size.textContent=m.size+' \u00b7 '+m.speed;
    var desc=document.createElement('div');
    desc.className='model-info';desc.textContent=m.desc;
    desc.style.marginTop='4px';
    d.appendChild(name);d.appendChild(size);d.appendChild(desc);
    g.appendChild(d);
  });
}

function loadHistory(){
  api('history').then(function(entries){
    var c=document.getElementById('hist');
    c.textContent='';
    if(!entries.length){
      var e=document.createElement('div');
      e.className='empty';
      e.textContent='No recordings yet. Press your keyboard shortcut to start.';
      c.appendChild(e);
      return;
    }
    entries.forEach(function(h){
      var d=document.createElement('div');
      d.className='h-item';
      d.addEventListener('click',function(){d.classList.toggle('open')});
      var meta=document.createElement('div');
      meta.className='h-meta';
      var ts=document.createElement('span');ts.textContent=h.display_time;
      var ws=document.createElement('span');ws.textContent=h.words+' words';
      meta.appendChild(ts);meta.appendChild(ws);
      var txt=document.createElement('div');
      txt.className='h-text';txt.textContent=h.text;
      d.appendChild(meta);d.appendChild(txt);
      c.appendChild(d);
    });
  });
}

function loadLogs(){
  api('logs').then(function(l){
    document.getElementById('log-out').textContent=l.join('\n')||'No logs yet';
  });
}

function loadStatus(){
  api('status').then(function(s){
    var b=document.getElementById('status');
    b.className=s.recording?'badge rec':'badge';
    b.textContent='';
    var dot=document.createElement('span');
    dot.className='badge-dot';
    b.appendChild(dot);
    b.appendChild(document.createTextNode(s.recording?' Recording':' Idle'));
  });
}

loadAll();
setInterval(loadStatus,3000);
</script>
</body>
</html>"""


class DashboardHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(DASHBOARD_HTML.encode("utf-8"))
        elif self.path == "/api/config":
            self.json_response(read_config())
        elif self.path == "/api/stats":
            self.json_response(get_stats())
        elif self.path == "/api/history":
            self.json_response(get_history())
        elif self.path == "/api/logs":
            self.json_response(get_log_tail())
        elif self.path == "/api/status":
            self.json_response({"recording": (DATA_DIR / "recording.pid").exists()})
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/api/config":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            write_config(body)
            self.json_response({"ok": True})
        else:
            self.send_error(404)

    def json_response(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))


def kill_existing_dashboard():
    """Kill any existing dashboard process on our port."""
    import signal
    try:
        result = subprocess.run(
            ["lsof", "-ti", f"tcp:{PORT}"],
            capture_output=True, text=True
        )
        if result.stdout.strip():
            for pid in result.stdout.strip().split("\n"):
                pid = pid.strip()
                if pid and pid != str(os.getpid()):
                    os.kill(int(pid), signal.SIGTERM)
            import time
            time.sleep(0.3)
    except Exception:
        pass


def main():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    kill_existing_dashboard()
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), DashboardHandler) as httpd:
        url = f"http://127.0.0.1:{PORT}"
        print(f"Scriptik Dashboard running at {url}")
        webbrowser.open(url)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nDashboard stopped.")


if __name__ == "__main__":
    main()

use serde::{Deserialize, Serialize};
use std::io::Cursor;
use std::net::{SocketAddr, UdpSocket};
use std::sync::{Arc, Condvar, Mutex, RwLock};
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use tiny_http::{Header, Method, Response, Server, StatusCode};

pub const HTTP_PORT: u16 = 43821;
pub const UDP_PORT: u16 = 43822;

#[derive(Clone, Serialize, Deserialize, Default, Debug)]
pub struct RemotePlayerState {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub position: f64,
    pub duration: f64,
    pub playing: bool,
    pub buffering: bool,
    pub accent: String,
    pub liked: bool,
    pub volume: f64,
    pub muted: bool,
    pub has_artwork: bool,
    pub has_lyrics: bool,
    pub seq: u64,
}

#[derive(Deserialize, Debug)]
pub struct StateUpdatePayload {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub position: Option<f64>,
    pub duration: Option<f64>,
    pub playing: Option<bool>,
    pub buffering: Option<bool>,
    pub accent: Option<String>,
    pub liked: Option<bool>,
    pub volume: Option<f64>,
    pub muted: Option<bool>,
    pub has_artwork: Option<bool>,
    pub has_lyrics: Option<bool>,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct CommandPayload {
    pub command: String,
    pub value: Option<f64>,
}

#[derive(Clone)]
pub struct RemoteServerHandle {
    pub state_cond: Arc<(Mutex<RemotePlayerState>, Condvar)>,
    pub artwork: Arc<RwLock<Option<(String, Vec<u8>)>>>,
    pub lyrics: Arc<RwLock<Option<String>>>,
    pub app_handle: AppHandle,
}

impl RemoteServerHandle {
    pub fn update_state(&self, update: StateUpdatePayload) {
        let (lock, cvar) = &*self.state_cond;
        let mut state = lock.lock().unwrap();

        if let Some(t) = update.title {
            state.title = t;
        }
        if let Some(a) = update.artist {
            state.artist = a;
        }
        if let Some(al) = update.album {
            state.album = al;
        }
        if let Some(p) = update.position {
            state.position = p;
        }
        if let Some(d) = update.duration {
            state.duration = d;
        }
        if let Some(pl) = update.playing {
            state.playing = pl;
        }
        if let Some(b) = update.buffering {
            state.buffering = b;
        }
        if let Some(ac) = update.accent {
            state.accent = ac;
        }
        if let Some(l) = update.liked {
            state.liked = l;
        }
        if let Some(v) = update.volume {
            state.volume = v;
        }
        if let Some(m) = update.muted {
            state.muted = m;
        }
        if let Some(ha) = update.has_artwork {
            state.has_artwork = ha;
        }
        if let Some(hl) = update.has_lyrics {
            state.has_lyrics = hl;
        }

        state.seq = state.seq.wrapping_add(1);
        cvar.notify_all();
    }

    pub fn update_artwork(&self, mime: String, data: Vec<u8>) {
        let mut art = self.artwork.write().unwrap();
        *art = Some((mime, data));

        let (lock, cvar) = &*self.state_cond;
        let mut state = lock.lock().unwrap();
        state.has_artwork = true;
        state.seq = state.seq.wrapping_add(1);
        cvar.notify_all();
    }

    pub fn clear_artwork(&self) {
        let mut art = self.artwork.write().unwrap();
        *art = None;

        let (lock, cvar) = &*self.state_cond;
        let mut state = lock.lock().unwrap();
        state.has_artwork = false;
        state.seq = state.seq.wrapping_add(1);
        cvar.notify_all();
    }

    pub fn update_lyrics(&self, lyrics_json: Option<String>) {
        let mut l = self.lyrics.write().unwrap();
        let has = lyrics_json.is_some();
        *l = lyrics_json;

        let (lock, cvar) = &*self.state_cond;
        let mut state = lock.lock().unwrap();
        state.has_lyrics = has;
        state.seq = state.seq.wrapping_add(1);
        cvar.notify_all();
    }
}

pub fn get_local_ip() -> Option<String> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let addr = socket.local_addr().ok()?;
    Some(addr.ip().to_string())
}

pub fn start_server(app_handle: AppHandle) -> Option<RemoteServerHandle> {
    let handle = RemoteServerHandle {
        state_cond: Arc::new((Mutex::new(RemotePlayerState::default()), Condvar::new())),
        artwork: Arc::new(RwLock::new(None)),
        lyrics: Arc::new(RwLock::new(None)),
        app_handle,
    };

    let srv_handle = handle.clone();

    // Spawn HTTP Server
    thread::spawn(move || {
        let bind_addr = format!("0.0.0.0:{}", HTTP_PORT);
        let server = match Server::http(&bind_addr) {
            Ok(s) => {
                println!("[noctra-remote] HTTP server listening on {}", bind_addr);
                s
            }
            Err(e) => {
                eprintln!("[noctra-remote] Failed to bind HTTP server to {}: {}", bind_addr, e);
                return;
            }
        };

        for mut request in server.incoming_requests() {
            let url = request.url().to_string();
            let method = request.method().clone();

            // Handle CORS Preflight
            if method == Method::Options {
                let mut response = Response::empty(204);
                add_cors_headers(&mut response);
                let _ = request.respond(response);
                continue;
            }

            if url == "/api/status" {
                let body = format!(
                    r#"{{"ok":true,"name":"Noctra","version":"1.0.0","port":{}}}"#,
                    HTTP_PORT
                );
                let mut resp = Response::from_string(body);
                resp.add_header(
                    Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap(),
                );
                add_cors_headers(&mut resp);
                let _ = request.respond(resp);
                continue;
            }

            if url == "/api/state" {
                let state = {
                    let (lock, _) = &*srv_handle.state_cond;
                    lock.lock().unwrap().clone()
                };
                let body = serde_json::to_string(&state).unwrap_or_else(|_| "{}".to_string());
                let mut resp = Response::from_string(body);
                resp.add_header(
                    Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap(),
                );
                add_cors_headers(&mut resp);
                let _ = request.respond(resp);
                continue;
            }

            if url.starts_with("/api/wait_state") {
                let client_seq: u64 = url
                    .split('?')
                    .nth(1)
                    .and_then(|query| {
                        query.split('&').find_map(|pair| {
                            let mut parts = pair.split('=');
                            if parts.next() == Some("seq") {
                                parts.next().and_then(|v| v.parse().ok())
                            } else {
                                None
                            }
                        })
                    })
                    .unwrap_or(0);

                let state = {
                    let (lock, cvar) = &*srv_handle.state_cond;
                    let mut state = lock.lock().unwrap();

                    if state.seq <= client_seq {
                        let timeout = Duration::from_secs(12);
                        let result = cvar.wait_timeout(state, timeout).unwrap();
                        state = result.0;
                    }
                    state.clone()
                };

                let body = serde_json::to_string(&state).unwrap_or_else(|_| "{}".to_string());
                let mut resp = Response::from_string(body);
                resp.add_header(
                    Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap(),
                );
                add_cors_headers(&mut resp);
                let _ = request.respond(resp);
                continue;
            }

            if url == "/api/artwork" {
                let art = srv_handle.artwork.read().unwrap().clone();
                match art {
                    Some((mime, bytes)) => {
                        let len = bytes.len();
                        let cursor = Cursor::new(bytes);
                        let mut resp = Response::new(
                            StatusCode(200),
                            vec![
                                Header::from_bytes(&b"Content-Type"[..], mime.as_bytes()).unwrap(),
                                Header::from_bytes(
                                    &b"Cache-Control"[..],
                                    &b"public, max-age=60"[..],
                                )
                                .unwrap(),
                            ],
                            cursor,
                            Some(len),
                            None,
                        );
                        add_cors_headers(&mut resp);
                        let _ = request.respond(resp);
                    }
                    None => {
                        let mut resp = Response::empty(404);
                        add_cors_headers(&mut resp);
                        let _ = request.respond(resp);
                    }
                }
                continue;
            }

            if url == "/api/lyrics" {
                let l = srv_handle.lyrics.read().unwrap().clone();
                match l {
                    Some(json) => {
                        let mut resp = Response::from_string(json);
                        resp.add_header(
                            Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..])
                                .unwrap(),
                        );
                        add_cors_headers(&mut resp);
                        let _ = request.respond(resp);
                    }
                    None => {
                        let mut resp = Response::from_string("null");
                        resp.add_header(
                            Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..])
                                .unwrap(),
                        );
                        add_cors_headers(&mut resp);
                        let _ = request.respond(resp);
                    }
                }
                continue;
            }

            if url == "/api/command" && method == Method::Post {
                let mut body = String::new();
                let _ = request.as_reader().read_to_string(&mut body);

                if let Ok(cmd) = serde_json::from_str::<CommandPayload>(&body) {
                    let _ = srv_handle.app_handle.emit("remote-command", cmd);
                    let mut resp = Response::from_string(r#"{"ok":true}"#);
                    resp.add_header(
                        Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap(),
                    );
                    add_cors_headers(&mut resp);
                    let _ = request.respond(resp);
                } else {
                    let mut resp = Response::from_string(r#"{"error":"invalid JSON"}"#);
                    resp.add_header(
                        Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap(),
                    );
                    add_cors_headers(&mut resp);
                    let _ = request.respond(resp);
                }
                continue;
            }

            // Web App Controller Root
            if url == "/" || url == "/index.html" {
                let html = WEB_REMOTE_HTML;
                let mut resp = Response::from_string(html);
                resp.add_header(
                    Header::from_bytes(&b"Content-Type"[..], &b"text/html; charset=utf-8"[..])
                        .unwrap(),
                );
                add_cors_headers(&mut resp);
                let _ = request.respond(resp);
                continue;
            }

            let mut resp = Response::empty(404);
            add_cors_headers(&mut resp);
            let _ = request.respond(resp);
        }
    });

    // Spawn UDP Discovery Listener
    thread::spawn(move || {
        let addr: SocketAddr = format!("0.0.0.0:{}", UDP_PORT).parse().unwrap();
        let socket = match UdpSocket::bind(addr) {
            Ok(s) => {
                println!("[noctra-remote] UDP discovery listening on {}", addr);
                s
            }
            Err(e) => {
                eprintln!("[noctra-remote] Failed to bind UDP discovery on {}: {}", addr, e);
                return;
            }
        };

        let mut buf = [0u8; 512];
        loop {
            match socket.recv_from(&mut buf) {
                Ok((size, src)) => {
                    let msg = String::from_utf8_lossy(&buf[..size]);
                    if msg.starts_with("NOCTRA_DISCOVER") {
                        let response = format!("NOCTRA_SERVER:{}:Noctra", HTTP_PORT);
                        let _ = socket.send_to(response.as_bytes(), src);
                    }
                }
                Err(e) => {
                    eprintln!("[noctra-remote] UDP recv error: {}", e);
                    break;
                }
            }
        }
    });

    Some(handle)
}

fn add_cors_headers<R: std::io::Read>(resp: &mut Response<R>) {
    resp.add_header(
        Header::from_bytes(&b"Access-Control-Allow-Origin"[..], &b"*"[..]).unwrap(),
    );
    resp.add_header(
        Header::from_bytes(
            &b"Access-Control-Allow-Methods"[..],
            &b"GET, POST, OPTIONS"[..],
        )
        .unwrap(),
    );
    resp.add_header(
        Header::from_bytes(
            &b"Access-Control-Allow-Headers"[..],
            &b"Content-Type, Authorization"[..],
        )
        .unwrap(),
    );
}

const WEB_REMOTE_HTML: &str = r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Noctra Remote</title>
<style>
  :root {
    --accent: #6b8afd;
    --bg: #090a0f;
    --card: rgba(255, 255, 255, 0.05);
    --border: rgba(255, 255, 255, 0.1);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
  body {
    background: var(--bg);
    color: #fff;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 24px 20px;
    overflow-x: hidden;
    position: relative;
  }
  .bg-glow {
    position: fixed;
    top: -20%;
    left: -20%;
    width: 140%;
    height: 140%;
    background: radial-gradient(circle at center, var(--accent) 0%, transparent 65%);
    opacity: 0.15;
    filter: blur(80px);
    z-index: 0;
    pointer-events: none;
    transition: all 0.8s ease;
  }
  .app {
    position: relative;
    z-index: 1;
    width: 100%;
    max-width: 380px;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .header {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;
  }
  .badge {
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1.5px;
    color: var(--accent);
    padding: 4px 10px;
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--border);
    border-radius: 20px;
  }
  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #22c55e;
    box-shadow: 0 0 10px #22c55e;
    display: inline-block;
    margin-right: 6px;
  }
  .art-wrapper {
    width: 260px;
    height: 260px;
    border-radius: 24px;
    overflow: hidden;
    box-shadow: 0 20px 40px rgba(0,0,0,0.6), 0 0 0 1px var(--border);
    background: #14161f;
    margin-bottom: 28px;
    position: relative;
  }
  .art-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .track-meta {
    width: 100%;
    text-align: center;
    margin-bottom: 20px;
  }
  .track-title {
    font-size: 20px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    margin-bottom: 6px;
    letter-spacing: -0.2px;
  }
  .track-artist {
    font-size: 14px;
    color: rgba(255,255,255,0.6);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .progress-section {
    width: 100%;
    margin-bottom: 24px;
  }
  .scrubber {
    -webkit-appearance: none;
    width: 100%;
    height: 6px;
    border-radius: 3px;
    background: rgba(255,255,255,0.15);
    outline: none;
    cursor: pointer;
  }
  .scrubber::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #fff;
    cursor: pointer;
    box-shadow: 0 2px 6px rgba(0,0,0,0.4);
  }
  .time-row {
    display: flex;
    justify-content: space-between;
    font-size: 12px;
    color: rgba(255,255,255,0.45);
    margin-top: 6px;
    font-variant-numeric: tabular-nums;
  }
  .controls-row {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 28px;
  }
  .btn-icon {
    background: none;
    border: none;
    color: #fff;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 10px;
    border-radius: 50%;
    transition: transform 0.1s, opacity 0.2s;
  }
  .btn-icon:active { transform: scale(0.9); }
  .btn-icon svg { width: 22px; height: 22px; fill: currentColor; }
  .btn-play {
    width: 64px;
    height: 64px;
    border-radius: 50%;
    background: #fff;
    color: #000;
    box-shadow: 0 8px 24px rgba(255,255,255,0.25);
  }
  .btn-play svg { width: 28px; height: 28px; fill: currentColor; }
  .btn-heart.liked svg { fill: #ef4444; color: #ef4444; }
  .volume-row {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 18px;
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 16px;
  }
  .vol-slider {
    flex: 1;
    -webkit-appearance: none;
    height: 4px;
    border-radius: 2px;
    background: rgba(255,255,255,0.15);
    outline: none;
  }
  .vol-slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: #fff;
    cursor: pointer;
  }
</style>
</head>
<body>
<div class="bg-glow" id="glow"></div>
<div class="app">
  <div class="header">
    <div class="badge"><span class="status-dot"></span>Noctra Client</div>
    <button class="btn-icon btn-heart" id="btn-fav">
      <svg viewBox="0 0 24 24"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>
    </button>
  </div>

  <div class="art-wrapper">
    <img class="art-img" id="art" src="/api/artwork" alt="Artwork" onerror="this.style.opacity='0.2'">
  </div>

  <div class="track-meta">
    <div class="track-title" id="title">No track playing</div>
    <div class="track-artist" id="artist">Connect to Noctra</div>
  </div>

  <div class="progress-section">
    <input type="range" class="scrubber" id="scrubber" min="0" max="1000" value="0">
    <div class="time-row">
      <span id="cur-time">0:00</span>
      <span id="dur-time">0:00</span>
    </div>
  </div>

  <div class="controls-row">
    <button class="btn-icon" id="btn-prev">
      <svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z"/></svg>
    </button>
    <button class="btn-icon btn-play" id="btn-play">
      <svg viewBox="0 0 24 24" id="play-icon"><path d="M8 5v14l11-7z"/></svg>
    </button>
    <button class="btn-icon" id="btn-next">
      <svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg>
    </button>
  </div>

  <div class="volume-row">
    <button class="btn-icon" id="btn-mute" style="padding:4px">
      <svg viewBox="0 0 24 24" style="width:18px;height:18px"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>
    </button>
    <input type="range" class="vol-slider" id="vol-slider" min="0" max="100" value="80">
  </div>
</div>

<script>
  let state = { seq: 0, position: 0, duration: 0, playing: false };
  let isScrubbing = false;

  function fmt(s) {
    if (!s || isNaN(s)) return '0:00';
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return m + ':' + (sec < 10 ? '0' : '') + sec;
  }

  function sendCmd(command, value = null) {
    fetch('/api/command', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command, value })
    }).catch(console.error);
  }

  document.getElementById('btn-play').onclick = () => sendCmd('toggle');
  document.getElementById('btn-next').onclick = () => sendCmd('next');
  document.getElementById('btn-prev').onclick = () => sendCmd('prev');
  document.getElementById('btn-fav').onclick = () => sendCmd('favorite');
  document.getElementById('btn-mute').onclick = () => sendCmd('mute');

  const scrubber = document.getElementById('scrubber');
  scrubber.onmousedown = scrubber.ontouchstart = () => isScrubbing = true;
  scrubber.onchange = () => {
    isScrubbing = false;
    sendCmd('seek', scrubber.value / 1000);
  };
  scrubber.oninput = () => {
    if (state.duration > 0) {
      document.getElementById('cur-time').textContent = fmt((scrubber.value / 1000) * state.duration);
    }
  };

  const vol = document.getElementById('vol-slider');
  vol.oninput = () => sendCmd('vol', vol.value / 100);

  function applyState(s) {
    state = s;
    document.getElementById('title').textContent = s.title || 'No track playing';
    document.getElementById('artist').textContent = s.artist || 'Connect to Noctra';
    document.getElementById('dur-time').textContent = fmt(s.duration);
    if (!isScrubbing) {
      document.getElementById('cur-time').textContent = fmt(s.position);
      if (s.duration > 0) {
        scrubber.value = Math.floor((s.position / s.duration) * 1000);
      } else {
        scrubber.value = 0;
      }
    }

    if (s.accent) {
      document.documentElement.style.setProperty('--accent', s.accent);
    }

    const heart = document.getElementById('btn-fav');
    if (s.liked) heart.classList.add('liked');
    else heart.classList.remove('liked');

    vol.value = Math.floor((s.volume ?? 1) * 100);

    const playIcon = document.getElementById('play-icon');
    if (s.playing) {
      playIcon.innerHTML = '<path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/>';
    } else {
      playIcon.innerHTML = '<path d="M8 5v14l11-7z"/>';
    }

    const art = document.getElementById('art');
    art.src = '/api/artwork?t=' + (s.seq || 0);
  }

  async function poll() {
    try {
      const res = await fetch('/api/wait_state?seq=' + (state.seq || 0));
      if (res.ok) {
        const data = await res.json();
        applyState(data);
      }
    } catch (e) {
      await new Promise(r => setTimeout(r, 2000));
    }
    poll();
  }

  poll();
</script>
</body>
</html>
"#;

// KSPlayer RemoteLog receiving server.
//
// The iOS demo app POSTs batched logs to {endpoint}/log and crash beacons to
// {endpoint}/crash (see Sources/KSPlayer/Logging/RemoteLog.swift).
// This server:
//   POST /log     -> accepts a "batch" body, appends entries to data/<session>.jsonl
//   POST /crash   -> accepts a "crash" body, stores data/crashes/<session>-<ts>.json
//   GET  /        -> HTML dashboard (auto-refreshing)
//   GET  /api/sessions -> JSON session list
//   GET  /api/logs?session=&level=&q=&limit= -> JSON entries (newest first)
//   GET  /api/crashes  -> JSON crash list (backtrace + lastLogs included)
//   GET  /api/stats    -> counters
//
// Usage: node server.js [port]   (default port 7777, binds 0.0.0.0)
// Data is written under ./data relative to this file's directory.

const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, 'data');
const CRASH_DIR = path.join(DATA_DIR, 'crashes');
fs.mkdirSync(CRASH_DIR, { recursive: true });

const PORT = parseInt(process.argv[2] || process.env.PORT || '7777', 10);
const MAX_BODY = 20 * 1024 * 1024; // 20 MB safety cap

// ---------------------------------------------------------------------------
// Storage helpers
// ---------------------------------------------------------------------------

function sessionFile(sessionId) {
  // Sanitize: session ids are UUIDs, but be defensive.
  const safe = String(sessionId || 'unknown').replace(/[^A-Za-z0-9_-]/g, '_');
  return path.join(DATA_DIR, `${safe}.jsonl`);
}

function appendLine(file, obj) {
  fs.appendFileSync(file, JSON.stringify(obj) + '\n');
}

// ---------------------------------------------------------------------------
// Request handling
// ---------------------------------------------------------------------------

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function sendJson(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function sendText(res, code, text, contentType) {
  res.writeHead(code, {
    'Content-Type': contentType || 'text/plain; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'no-store',
  });
  res.end(text);
}

function handleLog(parsed) {
  const session = parsed.session || 'unknown';
  const file = sessionFile(session);
  const entries = Array.isArray(parsed.entries) ? parsed.entries : [];
  let appended = 0;
  for (const e of entries) {
    appendLine(file, {
      type: 'log',
      session,
      app: parsed.app,
      bundle: parsed.bundle,
      ver: parsed.ver,
      dev: parsed.dev,
      os: parsed.os,
      boot: parsed.boot,
      received: Date.now() / 1000,
      ...e,
    });
    appended++;
  }
  // Compact console line for live tailing.
  const first = entries[0];
  const last = entries[entries.length - 1];
  console.log(
    `[log] ${parsed.dev || '?'} ${parsed.app || '?'} ${parsed.ver || '?'} session=${session} ` +
      `entries=${entries.length} ` +
      `(${first ? first.level + ' ' + (first.file || '') + ':' + (first.line ?? '') : ''} ... ` +
      `${last ? last.level + ' ' + (last.msg || '').slice(0, 80) : ''})`
  );
  return { appended };
}

function handleCrash(parsed) {
  const session = parsed.session || 'unknown';
  const ts = parsed.t ? Math.round(parsed.t) : Date.now();
  const file = path.join(CRASH_DIR, `${session}-${ts}.json`);
  const record = { ...parsed, received: Date.now() / 1000 };
  fs.writeFileSync(file, JSON.stringify(record, null, 2));
  console.log(
    `[crash] ${parsed.dev || '?'} ${parsed.app || '?'} reason=${parsed.reason} signal=${parsed.signal} ` +
      `session=${session} backtraceLines=${Array.isArray(parsed.backtrace) ? parsed.backtrace.length : 0}`
  );
  return { saved: file };
}

// ---------------------------------------------------------------------------
// API: reading stored data
// ---------------------------------------------------------------------------

function listSessions() {
  const out = [];
  if (!fs.existsSync(DATA_DIR)) return out;
  for (const f of fs.readdirSync(DATA_DIR)) {
    if (!f.endsWith('.jsonl')) continue;
    const file = path.join(DATA_DIR, f);
    const stats = fs.statSync(file);
    let count = 0;
    let firstT = Infinity;
    let lastT = 0;
    const levels = {};
    let devices = new Set();
    try {
      const lines = fs.readFileSync(file, 'utf8').split('\n');
      for (const ln of lines) {
        if (!ln.trim()) continue;
        const o = JSON.parse(ln);
        count++;
        if (o.t != null) {
          if (o.t < firstT) firstT = o.t;
          if (o.t > lastT) lastT = o.t;
        }
        if (o.level) levels[o.level] = (levels[o.level] || 0) + 1;
        if (o.dev) devices.add(o.dev);
      }
    } catch (e) {
      // skip unreadable
    }
    const crashDir = CRASH_DIR;
    const crashCount = fs.existsSync(crashDir)
      ? fs.readdirSync(crashDir).filter((c) => c.startsWith(f.replace('.jsonl', ''))).length
      : 0;
    out.push({
      session: f.replace('.jsonl', ''),
      entries: count,
      crashes: crashCount,
      firstT: firstT === Infinity ? null : firstT,
      lastT: lastT === 0 ? null : lastT,
      levels,
      devices: [...devices],
      size: stats.size,
    });
  }
  out.sort((a, b) => (b.lastT || 0) - (a.lastT || 0));
  return out;
}

function readEntries(session, opts) {
  const { level, q, limit } = opts;
  const file = sessionFile(session);
  if (!fs.existsSync(file)) return [];
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const out = [];
  const re = q ? new RegExp(q, 'i') : null;
  for (let i = lines.length - 1; i >= 0; i--) {
    const ln = lines[i];
    if (!ln.trim()) continue;
    let o;
    try {
      o = JSON.parse(ln);
    } catch {
      continue;
    }
    if (level && o.level !== level) continue;
    if (re && !re.test(JSON.stringify(o.msg || '')) && !re.test(JSON.stringify(o.file || ''))) continue;
    out.push(o);
    if (limit && out.length >= limit) break;
  }
  return out;
}

function listCrashes() {
  if (!fs.existsSync(CRASH_DIR)) return [];
  return fs
    .readdirSync(CRASH_DIR)
    .filter((f) => f.endsWith('.json'))
    .map((f) => {
      try {
        return JSON.parse(fs.readFileSync(path.join(CRASH_DIR, f), 'utf8'));
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => (b.t || 0) - (a.t || 0));
}

// ---------------------------------------------------------------------------
// HTML dashboard
// ---------------------------------------------------------------------------

const DASHBOARD = `<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<title>KSPlayer RemoteLog</title>
<style>
  body { font-family: -apple-system, "Segoe UI", monospace; margin: 16px; background: #111; color: #ddd; }
  h1 { font-size: 18px; }
  table { border-collapse: collapse; width: 100%; font-size: 12px; }
  th, td { border: 1px solid #333; padding: 4px 8px; text-align: left; vertical-align: top; }
  th { background: #222; position: sticky; top: 0; }
  tr:nth-child(even) { background: #161616; }
  .warn { color: #ffcc66; } .error { color: #ff6666; } .info { color: #88ccff; }
  .verbose { color: #999; } .debug { color: #777; }
  input, select { background: #222; color: #ddd; border: 1px solid #444; padding: 4px; }
  .mono { font-family: monospace; word-break: break-all; }
  .badge { background:#333; border-radius:8px; padding:1px 6px; font-size:10px; }
</style>
</head>
<body>
<h1>KSPlayer RemoteLog 接收端 <span class="badge" id="st"></span></h1>
<div>
  <input id="q" placeholder="过滤关键字 (正则)" size="24">
  <select id="lv"><option value="">全部级别</option><option>error</option><option>warn</option><option>info</option><option>verbose</option><option>debug</option><option>trace</option></select>
  <select id="sess"></select>
  <button onclick="load()">刷新</button>
  <label><input type="checkbox" id="auto" checked> 自动刷新</label>
</div>
<h2>最近日志</h2>
<table id="logs"><thead><tr><th>时间</th><th>级别</th><th>位置</th><th>消息</th><th>mem</th></tr></thead><tbody></tbody></table>
<h2>崩溃</h2>
<div id="crashes"></div>
<script>
let lastSession = '';
async function load() {
  try {
    const r = await fetch('/api/sessions');
    const sessions = await r.json();
    const sel = document.getElementById('sess');
    const prev = sel.value;
    sel.innerHTML = sessions.map(s => '<option value="'+s.session+'">'+s.session.slice(0,8)+' dev='+(s.devices[0]||'?')+' n='+s.entries+(s.crashes?' CRASH='+s.crashes:'')+'</option>').join('');
    if (prev && [...sel.options].some(o => o.value === prev)) sel.value = prev;
    else if (sessions[0]) sel.value = sessions[0].session;
    document.getElementById('st').textContent = 'sessions=' + sessions.length;
    const sess = sel.value || '';
    const q = document.getElementById('q').value;
    const lv = document.getElementById('lv').value;
    const url = '/api/logs?session=' + encodeURIComponent(sess) + '&level=' + encodeURIComponent(lv) + '&q=' + encodeURIComponent(q) + '&limit=300';
    const lr = await fetch(url);
    const logs = await lr.json();
    const tb = document.querySelector('#logs tbody');
    tb.innerHTML = logs.map(e => {
      const t = e.t ? new Date(e.t * 1000).toLocaleTimeString() : '';
      const cls = e.level || '';
      const mem = e.mem != null ? (e.mem/1048576).toFixed(0)+'M' : '';
      return '<tr><td>'+t+'</td><td class="'+cls+'">'+(e.level||'')+'</td><td class="mono">'+(e.file||'').split('/').pop()+':'+(e.line??'')+'</td><td class="mono">'+(e.msg||'').replace(/</g,'&lt;')+'</td><td>'+mem+'</td></tr>';
    }).join('');
    const cr = await fetch('/api/crashes');
    const crashes = await cr.json();
    document.getElementById('crashes').innerHTML = crashes.map(c =>
      '<details><summary><b>'+new Date((c.t||0)*1000).toLocaleString()+'</b> '+(c.dev||'')+' reason='+(c.reason||'')+' signal='+(c.signal??'')+'</summary><pre>'+
      (c.backtrace||[]).join('\\n') + '\\n\\n--- lastLogs ---\\n' + (c.lastLogs||[]).join('\\n') + '</pre></details>'
    ).join('<hr>') || '<p>无崩溃记录</p>';
  } catch (err) {
    document.getElementById('st').textContent = 'error: ' + err;
  }
}
setInterval(() => { if (document.getElementById('auto').checked) load(); }, 3000);
load();
</script>
</body>
</html>`;

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname;
  try {
    if (req.method === 'POST' && (p === '/log' || p === '/crash')) {
      const raw = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return sendJson(res, 400, { ok: false, error: 'invalid json' });
      }
      if (p === '/log') {
        const r = handleLog(parsed);
        return sendJson(res, 200, { ok: true, ...r });
      }
      const r = handleCrash(parsed);
      return sendJson(res, 200, { ok: true, ...r });
    }

    if (req.method === 'GET') {
      if (p === '/' || p === '/index.html') {
        return sendText(res, 200, DASHBOARD, 'text/html; charset=utf-8');
      }
      if (p === '/api/sessions') {
        return sendJson(res, 200, listSessions());
      }
      if (p === '/api/logs') {
        const session = url.searchParams.get('session') || '';
        const level = url.searchParams.get('level') || '';
        const q = url.searchParams.get('q') || '';
        const limit = parseInt(url.searchParams.get('limit') || '100', 10) || 100;
        return sendJson(res, 200, readEntries(session, { level, q, limit }));
      }
      if (p === '/api/crashes') {
        return sendJson(res, 200, listCrashes());
      }
      if (p === '/api/stats') {
        const sessions = listSessions();
        return sendJson(res, 200, {
          sessions: sessions.length,
          entries: sessions.reduce((a, s) => a + s.entries, 0),
          crashes: listCrashes().length,
          port: PORT,
        });
      }
    }
    return sendText(res, 404, 'not found');
  } catch (err) {
    console.error('[server] error:', err);
    return sendJson(res, 500, { ok: false, error: String(err) });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`KSPlayer RemoteLog server listening on 0.0.0.0:${PORT}`);
  console.log(`  POST /log   <- batched logs`);
  console.log(`  POST /crash <- crash beacons`);
  console.log(`  GET  /      <- dashboard`);
});

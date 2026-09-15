// MolidoVPN subscription link (Cloudflare Worker, free plan).
// Serves the server list from GitHub under your own worker address, with a profile name and
// auto-update interval that Hiddify / Streisand / v2rayNG show. /lite = small list for iPhone.
const FULL = 'https://raw.githubusercontent.com/hidooch980/vpn-sub/sub/sub_base64.txt';
const LITE = 'https://raw.githubusercontent.com/hidooch980/vpn-sub/sub/lite_base64.txt';
const MIRROR = (file) => `https://cdn.jsdelivr.net/gh/hidooch980/vpn-sub@sub/${file}`;

const REPO = 'hidooch980/mobin-vpn';

// App updates through this worker, for networks where github.com / api.github.com are slow or filtered.
// /app/latest.json — same shape as the GitHub "latest release" API, with download URLs pointing back here.
// /app/<asset>      — streams that asset of the latest release.
async function appRoute(url) {
  const name = url.pathname.slice('/app/'.length);
  if (name === 'latest.json') {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { 'user-agent': 'MolidoVPN-worker', accept: 'application/vnd.github+json' },
      cf: { cacheTtl: 300, cacheEverything: true },
    });
    if (!res.ok) return new Response('release info unavailable', { status: 502 });
    const r = await res.json();
    const body = {
      tag_name: r.tag_name,
      published_at: r.published_at,
      assets: r.assets.map((a) => ({ name: a.name, size: a.size, browser_download_url: `${url.origin}/app/${a.name}` })),
    };
    return new Response(JSON.stringify(body), {
      headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=300', 'access-control-allow-origin': '*' },
    });
  }
  if (!/^[A-Za-z0-9._-]+\.(apk|zip|exe)$/.test(name)) return new Response('not found', { status: 404 });
  const res = await fetch(`https://github.com/${REPO}/releases/latest/download/${name}`, { redirect: 'follow' });
  if (!res.ok) return new Response('download unavailable', { status: 502 });
  const headers = new Headers({
    'content-type': name.endsWith('.apk') ? 'application/vnd.android.package-archive' : 'application/octet-stream',
    'content-disposition': `attachment; filename="${name}"`,
    'cache-control': 'no-store',
  });
  const len = res.headers.get('content-length');
  if (len) headers.set('content-length', len);
  return new Response(res.body, { headers });
}

// /remote/<file> — app config files from the android repo, for networks where GitHub is filtered.
const REMOTE_FILES = {
  'policy.json': 'application/json; charset=utf-8',
  'shard-nodes.txt': 'text/plain; charset=utf-8',
  'smart-split.json': 'application/json; charset=utf-8',
};
async function remoteRoute(url) {
  const name = url.pathname.slice('/remote/'.length);
  const type = REMOTE_FILES[name];
  if (!type) return new Response('not found', { status: 404 });
  const sources = [
    `https://raw.githubusercontent.com/hidooch980/molidovpn-android/main/remote/${name}`,
    `https://cdn.jsdelivr.net/gh/hidooch980/molidovpn-android@main/remote/${name}`,
  ];
  for (const source of sources) {
    const res = await fetch(source, { cf: { cacheTtl: 300, cacheEverything: true } }).catch(() => null);
    if (!res || !res.ok) continue;
    return new Response(await res.text(), {
      headers: { 'content-type': type, 'cache-control': 'public, max-age=300', 'access-control-allow-origin': '*' },
    });
  }
  return new Response('file unavailable', { status: 502 });
}

// WARP device registration relay: api.cloudflareclient.com is often reset from Iran. Forwards the app's
// registration POST unchanged (only a public key goes up; the private key never leaves the device).
async function warpRegRoute(request) {
  if (request.method !== 'POST') return new Response('method not allowed', { status: 405 });
  const body = await request.text();
  if (body.length > 2048) return new Response('bad request', { status: 400 });
  const res = await fetch('https://api.cloudflareclient.com/v0a2158/reg', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'user-agent': 'okhttp/3.12.1', 'cf-client-version': 'a-6.10-2158' },
    body,
  });
  return new Response(await res.text(), {
    status: res.status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

// Anonymous opt-in connection reports, aggregated per UTC day in D1. No IPs are stored.
const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
};
const NODE_RE = /^([0-9a-f]{16}|mode:[a-z0-9_-]{1,20})$/;
const NETS = new Set(['wifi', 'cellular', 'other']);
const APPS = new Set(['android', 'windows']);
// Iranian operator bucket, stored inside the net column as "<net>|<op>" so the table keeps its key.
const OPS = new Set(['mci', 'irancell', 'tci', 'rightel', 'shatel', 'other']);
const LIMIT_PER_MIN = 60;
const hits = new Map(); // in-memory only (per isolate): client-ip -> {minute, n}

function limited(ip) {
  const minute = Math.floor(Date.now() / 60000);
  if (hits.size > 5000) hits.clear();
  const h = hits.get(ip);
  if (!h || h.minute !== minute) {
    hits.set(ip, { minute, n: 1 });
    return false;
  }
  return ++h.n > LIMIT_PER_MIN;
}

const bad = () => new Response('bad request', { status: 400, headers: CORS });

async function reportRoute(request, env, ctx) {
  if (request.method !== 'POST') return new Response('method not allowed', { status: 405, headers: CORS });
  const len = Number(request.headers.get('content-length') || 0);
  if (len > 1024) return bad();
  const text = await request.text();
  if (text.length > 1024) return bad();
  let r;
  try {
    r = JSON.parse(text);
  } catch {
    return bad();
  }
  if (!r || typeof r !== 'object' || Array.isArray(r)) return bad();
  if (r.v !== 1 || typeof r.node !== 'string' || !NODE_RE.test(r.node)) return bad();
  if (typeof r.ok !== 'boolean' || !NETS.has(r.net) || !APPS.has(r.app)) return bad();
  if (typeof r.ver !== 'string' || r.ver.length > 32) return bad();
  if (r.op !== undefined && r.op !== null && !OPS.has(r.op)) return bad();
  const netKey = r.op ? `${r.net}|${r.op}` : r.net;
  const ms = r.ms;
  if (!(ms === null || ms === undefined || (Number.isInteger(ms) && ms >= 1 && ms <= 60000))) return bad();

  if (limited(request.headers.get('cf-connecting-ip') || 'unknown')) return new Response(null, { status: 204, headers: CORS });

  // Local Iran tester result for an owner config: kept separately (latest run + consecutive failures) so
  // the reports table for owner configs holds only real app reports from users.
  if (r.owner === true && r.ver === 'local-iran-test') {
    let isOwner = false;
    try {
      isOwner = (await ownerFps(env, ctx)).has(r.node);
    } catch {}
    if (isOwner) {
      const now = Date.now();
      await env.DB.prepare(
        `INSERT INTO owner_tests (fp, ok, ms, tested_at, fail_streak) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(fp) DO UPDATE SET
           fail_streak = CASE WHEN excluded.ok = 1 THEN 0
             WHEN owner_tests.ok = 0 AND owner_tests.tested_at > ?6 THEN owner_tests.fail_streak
             ELSE owner_tests.fail_streak + 1 END,
           ok = excluded.ok, ms = excluded.ms, tested_at = excluded.tested_at`
      )
        .bind(r.node, r.ok ? 1 : 0, r.ok && Number.isInteger(ms) ? ms : null, now, r.ok ? 0 : 1, now - OWNER_RUN_GAP_MS)
        .run();
      return new Response(null, { status: 204, headers: CORS });
    }
  }

  const day = new Date().toISOString().slice(0, 10);
  const hasMs = Number.isInteger(ms) ? 1 : 0;
  await env.DB.prepare(
    `INSERT INTO reports (day, node, app, net, ok, fail, ms_sum, ms_n) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
     ON CONFLICT(day, node, app, net) DO UPDATE SET ok = ok + excluded.ok, fail = fail + excluded.fail,
       ms_sum = ms_sum + excluded.ms_sum, ms_n = ms_n + excluded.ms_n`
  )
    .bind(day, r.node, r.app, netKey, r.ok ? 1 : 0, r.ok ? 0 : 1, hasMs ? ms : 0, hasMs)
    .run();
  return new Response(null, { status: 204, headers: CORS });
}

function summarize(s) {
  return {
    ok: s.ok,
    fail: s.fail,
    ms: s.ms_n ? Math.round(s.ms_sum / s.ms_n) : null,
    score: Math.round(((s.ok + 1) / (s.ok + s.fail + 2)) * 1000) / 1000,
  };
}

async function scoresRoute(request, env, ctx) {
  const cache = caches.default;
  // ?op=mci|irancell|… limits the scores to reports from that operator.
  const opParam = new URL(request.url).searchParams.get('op');
  const op = OPS.has(opParam) ? opParam : '';
  const key = new Request(new URL(`/scores?op=${op}`, request.url).toString());
  const hit = await cache.match(key);
  if (hit) return hit;

  const since = new Date(Date.now() - 6 * 86400000).toISOString().slice(0, 10);
  const { results } = await env.DB.prepare(
    `SELECT node, net, SUM(ok) ok, SUM(fail) fail, SUM(ms_sum) ms_sum, SUM(ms_n) ms_n
     FROM reports WHERE day >= ?1 AND (?2 = '' OR net LIKE '%|' || ?2) GROUP BY node, net`
  )
    .bind(since, op)
    .all();
  const acc = {};
  for (const row of results) {
    const a = (acc[row.node] ||= { all: { ok: 0, fail: 0, ms_sum: 0, ms_n: 0 } });
    const baseNet = String(row.net).split('|')[0];
    for (const k of [baseNet === 'cellular' || baseNet === 'wifi' ? baseNet : null, 'all']) {
      if (!k) continue;
      const s = (a[k] ||= { ok: 0, fail: 0, ms_sum: 0, ms_n: 0 });
      s.ok += row.ok; s.fail += row.fail; s.ms_sum += row.ms_sum; s.ms_n += row.ms_n;
    }
  }
  const out = {};
  for (const [node, a] of Object.entries(acc)) {
    out[node] = summarize(a.all);
    if (a.cellular) out[node].cellular = summarize(a.cellular);
    if (a.wifi) out[node].wifi = summarize(a.wifi);
  }
  const res = new Response(JSON.stringify(out), {
    headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=300', ...CORS },
  });
  ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}

// iPhone list (/lite, /ios; /hiddify also adds WARP). Built for Iranian networks and iOS clients:
// CDN-fronted SHARD nodes first (VLESS/Trojan over WebSocket+TLS behind Cloudflare — what works best
// in Iran), then TLS/Reality/QUIC nodes from the tested list. Plain Shadowsocks and non-TLS VMess are
// dropped: they are the first to be blocked and waste the client's connect attempts.
const IOS_MAX = 80;
const decodeList = (body) => {
  const t = body.trim();
  if (t.includes('://')) return t;
  try {
    return atob(t.replace(/\s/g, ''));
  } catch {
    return '';
  }
};
const iosFriendly = (line) => {
  const scheme = line.slice(0, line.indexOf('://')).toLowerCase();
  if (scheme === 'hysteria2' || scheme === 'hy2' || scheme === 'tuic') return true;
  if (scheme !== 'vless' && scheme !== 'trojan') return false;
  const q = new URLSearchParams(line.split('#')[0].split('?')[1] || '');
  const sec = (q.get('security') || (scheme === 'trojan' ? 'tls' : '')).toLowerCase();
  return sec === 'tls' || sec === 'reality';
};

// /sub/1 … /sub/5: five separate links, 50–100 configs each, different servers per link, so a family
// member can add two or three and still have a working list when one gets filtered.
const SUB_LINKS = 5;
const SUB_MIN = 50;
const SUB_MAX = 100;
const strongTransport = (line) => iosFriendly(line.split('#')[0]);

// Iran-measured quality from the anonymous reports (apps + local Iran tests), last 7 days.
async function reportScores(env) {
  try {
    const since = new Date(Date.now() - 6 * 86400000).toISOString().slice(0, 10);
    const { results } = await env.DB.prepare(
      'SELECT node, SUM(ok) ok, SUM(fail) fail FROM reports WHERE day >= ?1 GROUP BY node'
    )
      .bind(since)
      .all();
    return new Map(results.map((r) => [r.node, r]));
  } catch {
    return new Map();
  }
}

async function nodeFingerprint(line) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(line.split('#')[0].trim()));
  return [...new Uint8Array(digest)].slice(0, 8).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// 0 = worked in Iran, 1 = no data, 2 = only failures in Iran. Stable within a tier.
async function rankByReports(lines, scores) {
  if (!scores.size) return lines;
  const tiers = await Promise.all(
    lines.map(async (line) => {
      const s = scores.get(await nodeFingerprint(line));
      if (!s) return [1, 0];
      if (s.ok > 0) return [0, -(s.ok + 1) / (s.ok + s.fail + 2)];
      return [2, 0];
    })
  );
  return lines
    .map((line, i) => ({ line, t: tiers[i], i }))
    .sort((a, b) => a.t[0] - b.t[0] || a.t[1] - b.t[1] || a.i - b.i)
    .map((x) => x.line);
}

// Drop servers that only ever failed from inside Iran, as long as at least [min] others remain.
async function dropIranFailed(lines, scores, min) {
  if (!scores.size) return lines;
  const failed = await Promise.all(
    lines.map(async (line) => {
      const s = scores.get(await nodeFingerprint(line));
      return !!s && s.ok === 0 && s.fail > 0;
    })
  );
  const kept = lines.filter((_, i) => !failed[i]);
  return kept.length >= min ? kept : lines;
}

// Every config is shown as "<location flag> MolidoVPN NN" (flag taken from the tested name; 🌐 when unknown).
function brand(lines) {
  const counters = new Map();
  return lines.map((line) => {
    const hash = line.indexOf('#');
    const core = hash >= 0 ? line.slice(0, hash) : line;
    if (!core.includes('://') || core.startsWith('warp://')) return line;
    let name = '';
    try {
      name = hash >= 0 ? decodeURIComponent(line.slice(hash + 1)) : '';
    } catch {
      name = line.slice(hash + 1);
    }
    let flag = (name.match(/\p{Regional_Indicator}{2}/u) || [])[0];
    if (!flag && core.startsWith('vmess://')) {
      try {
        flag = (JSON.parse(atob(core.slice(8))).ps || '').match(/\p{Regional_Indicator}{2}/u)?.[0];
      } catch {}
    }
    flag = flag || '🌐';
    const n = (counters.get(flag) || 0) + 1;
    counters.set(flag, n);
    const label = `${flag} MolidoVPN ${String(n).padStart(2, '0')}`;
    if (core.startsWith('vmess://')) {
      try {
        const j = JSON.parse(atob(core.slice(8)));
        j.ps = label;
        const bytes = new TextEncoder().encode(JSON.stringify(j));
        let bin = '';
        for (const b of bytes) bin += String.fromCharCode(b);
        return `vmess://${btoa(bin)}`;
      } catch {
        return `${core}#${encodeURIComponent(label)}`;
      }
    }
    return `${core}#${encodeURIComponent(label)}`;
  });
}

async function subRoute(url, env, ctx) {
  const n = Number(url.pathname.split('/')[2]);
  if (!Number.isInteger(n) || n < 1 || n > SUB_LINKS) return new Response('use /sub/1 … /sub/5', { status: 404 });
  const owner = ownerLines(env, ctx);
  const get = (u) =>
    fetch(u, { cf: { cacheTtl: 300, cacheEverything: true } })
      .then((r) => (r.ok ? r.text() : ''))
      .catch(() => '');
  const [shard, full] = await Promise.all([
    get('https://raw.githubusercontent.com/hidooch980/molidovpn-android/main/remote/shard-nodes.txt').then(
      (t) => t || get('https://cdn.jsdelivr.net/gh/hidooch980/molidovpn-android@main/remote/shard-nodes.txt')
    ),
    get(FULL).then((t) => t || get(MIRROR('sub_base64.txt'))),
  ]);

  // Pool in quality order: CDN nodes, then TLS/Reality/QUIC, then everything else (tested list order).
  const seen = new Set();
  const cdn = [], strong = [], rest = [];
  let c = 0;
  for (const l of shard.split('\n')) {
    const line = l.trim();
    if (!line.includes('://') || line.startsWith('#')) continue;
    const core = line.split('#')[0];
    if (seen.has(core)) continue;
    seen.add(core);
    cdn.push(`${core}#${encodeURIComponent(`MolidoVPN CDN ${++c}`)}`);
  }
  for (const l of decodeList(full).split('\n')) {
    const line = l.trim();
    if (!line.includes('://')) continue;
    const core = line.split('#')[0];
    if (seen.has(core)) continue;
    seen.add(core);
    (strongTransport(line) ? strong : rest).push(line);
  }

  // Deal the non-CDN pool round-robin so every link gets a similar mix, then top each link up with
  // CDN nodes (shared across links — they are the most reliable in Iran) to reach at least SUB_MIN.
  const scores = await reportScores(env);
  const ranked = await rankByReports([...strong, ...rest], scores);
  const cdnRanked = await rankByReports(cdn, scores);
  cdn.splice(0, cdn.length, ...cdnRanked);
  const buckets = Array.from({ length: SUB_LINKS }, () => []);
  ranked.forEach((line, i) => {
    const b = buckets[i % SUB_LINKS];
    if (b.length < SUB_MAX - 20) b.push(line);
  });
  const mine = buckets[n - 1];
  const cdnShare = cdn.filter((_, i) => i % SUB_LINKS === n - 1);
  const cdnOthers = cdn.filter((_, i) => i % SUB_LINKS !== n - 1);
  const lines = [...cdnShare, ...mine];
  while (lines.length < SUB_MIN && cdnOthers.length) lines.push(cdnOthers.shift());
  if (!lines.length) return new Response('server list unavailable, try again shortly', { status: 502 });
  const clean = await dropIranFailed(await rankByReports(lines, scores), scores, SUB_MIN);
  return listResponse(brand(mergeOwner(await owner, clean.slice(0, SUB_MAX))), `MolidoVPN ${n}`);
}

function listResponse(lines, title) {
  const bytes = new TextEncoder().encode(lines.join('\n'));
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return new Response(btoa(bin), {
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'profile-title': 'base64:' + btoa(title),
      'profile-update-interval': '1',
      'profile-web-page-url': 'https://hidooch980.github.io/mobin-vpn/',
      'cache-control': 'public, max-age=300',
      'access-control-allow-origin': '*',
    },
  });
}

async function iosRoute(url, env, ctx) {
  const owner = ownerLines(env, ctx);
  const get = (u) =>
    fetch(u, { cf: { cacheTtl: 300, cacheEverything: true } })
      .then((r) => (r.ok ? r.text() : ''))
      .catch(() => '');
  const [shard, full, lite] = await Promise.all([
    get('https://raw.githubusercontent.com/hidooch980/molidovpn-android/main/remote/shard-nodes.txt').then(
      (t) => t || get('https://cdn.jsdelivr.net/gh/hidooch980/molidovpn-android@main/remote/shard-nodes.txt')
    ),
    get(FULL).then((t) => t || get(MIRROR('sub_base64.txt'))),
    get(LITE).then((t) => t || get(MIRROR('lite_base64.txt'))),
  ]);

  const seen = new Set();
  const out = [];
  const add = (line, name) => {
    line = line.trim();
    if (!line.includes('://') || line.startsWith('#')) return;
    const core = line.split('#')[0];
    if (seen.has(core) || !iosFriendly(core)) return;
    seen.add(core);
    out.push(name ? `${core}#${encodeURIComponent(name)}` : line);
  };
  let cdn = 0;
  for (const l of shard.split('\n')) if (l.includes('://')) add(l, `MolidoVPN CDN ${++cdn}`);
  for (const l of decodeList(lite).split('\n')) add(l);
  for (const l of decodeList(full).split('\n')) add(l);

  // Collect everything iPhone-friendly, put Iran-proven servers first, drop Iran-failed ones when
  // enough others exist, then cap for the iOS memory limit.
  const scores = await reportScores(env);
  const rankedOut = await rankByReports(out, scores);
  const lines = brand(mergeOwner(await owner, (await dropIranFailed(rankedOut, scores, 20)).slice(0, IOS_MAX)));
  if (url.pathname.startsWith('/hiddify')) lines.unshift('warp://auto#MolidoVPN%20WARP', 'warp://p2@auto#MolidoVPN%20WARP%20in%20WARP');
  if (!lines.length) return new Response('server list unavailable, try again shortly', { status: 502 });

  const bytes = new TextEncoder().encode(lines.join('\n'));
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return new Response(btoa(bin), {
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'profile-title': 'base64:' + btoa('MolidoVPN'),
      'profile-update-interval': '1',
      'profile-web-page-url': 'https://hidooch980.github.io/mobin-vpn/',
      'cache-control': 'public, max-age=300',
      'access-control-allow-origin': '*',
    },
  });
}

// ---------------------------------------------------------------------------------------------------
// Owner items: subscription links and single configs the owner adds from /admin. They are placed first
// in every list (/, /lite, /ios, /hiddify, /sub/1..5) and reach all users on their next list refresh.
// ---------------------------------------------------------------------------------------------------
const OWNER_SCHEMES = new Set(['vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic', 'wireguard']);
const OWNER_MAX_ITEMS = 300; // rows in owner_items
const OWNER_MAX_LINES = 150; // owner configs merged into one list
const OWNER_SUB_MAX_LINES = 100; // configs taken from one owner sub link
const OWNER_CONFIG_MAX_LEN = 4096;
const OWNER_URL_MAX_LEN = 2048;
const OWNER_NOTE_MAX_LEN = 200;
const OWNER_SUB_TTL = 600; // seconds
const ADMIN_MAX_FAILS = 5;
const ADMIN_LOCK_MS = 15 * 60000;

let ownerSchemaReady = false;
async function ensureOwnerSchema(env) {
  if (ownerSchemaReady) return;
  await env.DB.batch([
    env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS owner_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL CHECK (kind IN ('sub', 'config')),
        value TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )`
    ),
    env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS admin_fails (ip_hash TEXT PRIMARY KEY, fails INTEGER NOT NULL, locked_until INTEGER NOT NULL, updated INTEGER NOT NULL)'
    ),
    // Latest local Iran test per owner config fingerprint (from iran_node_test.py via /report with owner:true).
    env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS owner_tests (fp TEXT PRIMARY KEY, ok INTEGER NOT NULL, ms INTEGER, tested_at INTEGER NOT NULL, fail_streak INTEGER NOT NULL DEFAULT 0)'
    ),
  ]);
  // Columns added after the first release; ALTER fails harmlessly when they already exist.
  for (const col of ['always_show INTEGER NOT NULL DEFAULT 0', 'due_at INTEGER NOT NULL DEFAULT 0']) {
    await env.DB.prepare(`ALTER TABLE owner_items ADD COLUMN ${col}`).run().catch(() => {});
  }
  ownerSchemaReady = true;
}

const lineCore = (line) => line.split('#')[0].trim();

function validConfig(line) {
  if (typeof line !== 'string') return false;
  const t = line.trim();
  if (!t || t.length > OWNER_CONFIG_MAX_LEN || /\s/.test(t)) return false;
  const i = t.indexOf('://');
  if (i <= 0 || t.length <= i + 3) return false;
  return OWNER_SCHEMES.has(t.slice(0, i).toLowerCase());
}

function validSubUrl(value) {
  if (typeof value !== 'string' || value.length > OWNER_URL_MAX_LEN) return false;
  try {
    const u = new URL(value.trim());
    return u.protocol === 'https:' && !!u.hostname && !u.username && !u.password;
  } catch {
    return false;
  }
}

async function sha256Hex(text) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Configs from one owner sub link, cached ~10 min in caches.default. Never throws.
async function fetchOwnerSub(link, ctx) {
  try {
    const cache = caches.default;
    const key = new Request(`https://owner-sub.molido.internal/${await sha256Hex(link)}`);
    const hit = await cache.match(key);
    if (hit) return (await hit.text()).split('\n').filter(Boolean);
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 8000);
    let body = '';
    try {
      const res = await fetch(link, { signal: ac.signal, redirect: 'follow', headers: { 'user-agent': 'v2rayNG/1.9' } });
      if (res.ok) body = (await res.text()).slice(0, 2_000_000);
    } finally {
      clearTimeout(timer);
    }
    const lines = decodeList(body)
      .split('\n')
      .map((l) => l.trim())
      .filter(validConfig)
      .slice(0, OWNER_SUB_MAX_LINES);
    if (lines.length) {
      const res = new Response(lines.join('\n'), { headers: { 'cache-control': `public, max-age=${OWNER_SUB_TTL}` } });
      ctx.waitUntil(cache.put(key, res));
    }
    return lines;
  } catch {
    return [];
  }
}

// All enabled owner configs (single configs first, then sub-link configs), deduped, as
// { line, fp, item }. Throws on DB errors.
async function ownerEntries(env, ctx) {
  await ensureOwnerSchema(env);
  const { results } = await env.DB.prepare(
    'SELECT id, kind, value, always_show, due_at FROM owner_items WHERE enabled = 1 ORDER BY id'
  ).all();
  const configs = results.filter((r) => r.kind === 'config');
  const subs = results.filter((r) => r.kind === 'sub');
  const subLines = await Promise.all(subs.map((r) => fetchOwnerSub(r.value, ctx)));
  const src = [...configs.map((r) => [r, r.value]), ...subs.flatMap((r, i) => subLines[i].map((l) => [r, l]))];
  const seen = new Set();
  const out = [];
  for (const [item, line] of src) {
    const core = lineCore(line);
    if (!validConfig(line) || seen.has(core)) continue;
    seen.add(core);
    out.push({ line: line.trim(), fp: await nodeFingerprint(line), item });
    if (out.length >= OWNER_MAX_LINES) break;
  }
  return out;
}

const OWNER_FAIL_RUNS = 2; // hide after this many consecutive failed local Iran test runs
const OWNER_RETEST_MS = 3600000; // owner configs are due for the quick local test after 1 h
const OWNER_RUN_GAP_MS = 5 * 60000; // failures closer than this count as the same run

// Local Iran tests (owner_tests) and app reports from Iranian users for owner fingerprints. Never throws.
async function ownerStatus(env) {
  const tests = new Map();
  const users = new Map();
  try {
    const { results } = await env.DB.prepare('SELECT fp, ok, ms, tested_at, fail_streak FROM owner_tests').all();
    for (const r of results) tests.set(r.fp, r);
  } catch {}
  try {
    const day = (d) => new Date(Date.now() - d * 86400000).toISOString().slice(0, 10);
    const { results } = await env.DB.prepare(
      `SELECT node, SUM(ok) ok, SUM(fail) fail, SUM(CASE WHEN day >= ?2 THEN ok ELSE 0 END) recent_ok
       FROM reports WHERE day >= ?1 GROUP BY node`
    )
      .bind(day(6), day(1))
      .all();
    for (const r of results) users.set(r.node, r);
  } catch {}
  return { tests, users };
}

// Hidden from users: failed the latest OWNER_FAIL_RUNS local Iran runs, no user success in ~2 days, no override.
function ownerHidden(entry, st) {
  if (entry.item.always_show) return false;
  const t = st.tests.get(entry.fp);
  if (!t || t.ok || t.fail_streak < OWNER_FAIL_RUNS) return false;
  return !((st.users.get(entry.fp) || {}).recent_ok > 0);
}

function ownerDue(entry, st, now) {
  const t = st.tests.get(entry.fp);
  return !t || t.tested_at < now - OWNER_RETEST_MS || entry.item.due_at > t.tested_at;
}

// Owner configs served to users (Iran-failed ones removed). Never throws.
async function ownerLines(env, ctx) {
  try {
    const entries = await ownerEntries(env, ctx);
    if (!entries.length) return [];
    const st = await ownerStatus(env);
    return entries.filter((e) => !ownerHidden(e, st)).map((e) => e.line);
  } catch {
    return [];
  }
}

// /owner/configs — public list of owner config URIs for the local Iran tester (they are public inside / anyway).
// id is the report fingerprint; due = never tested, older than 1 h, or "test again" pressed in /admin.
async function ownerConfigsRoute(env, ctx) {
  const headers = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
  try {
    const entries = await ownerEntries(env, ctx);
    const st = entries.length ? await ownerStatus(env) : { tests: new Map(), users: new Map() };
    const now = Date.now();
    const configs = entries.map((e) => ({ id: e.fp, uri: e.line, due: ownerDue(e, st, now) }));
    return new Response(JSON.stringify({ configs }), { headers });
  } catch {
    return new Response(JSON.stringify({ error: 'unavailable' }), { status: 500, headers });
  }
}

// Owner fingerprints, cached per isolate for a minute (used to accept owner test results in /report).
let ownerFpCache = { at: 0, set: new Set() };
async function ownerFps(env, ctx) {
  if (Date.now() - ownerFpCache.at > 60000) {
    ownerFpCache = { at: Date.now(), set: new Set((await ownerEntries(env, ctx)).map((e) => e.fp)) };
  }
  return ownerFpCache.set;
}

// Owner configs first, then the normal list without duplicates of them.
function mergeOwner(owner, lines) {
  if (!owner.length) return lines;
  const seen = new Set(owner.map(lineCore));
  return [...owner, ...lines.filter((l) => !seen.has(lineCore(l)))];
}

const ADMIN_HEADERS = {
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'no-referrer',
};
const adminJson = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json; charset=utf-8', ...ADMIN_HEADERS } });

async function timingSafeKeyEqual(a, b) {
  const [x, y] = await Promise.all([a, b].map((s) => crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))));
  const ua = new Uint8Array(x), ub = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < ua.length; i++) diff |= ua[i] ^ ub[i];
  return diff === 0;
}

// Returns null when authorized, otherwise the error response.
async function adminAuth(request, env) {
  if (!env.ADMIN_KEY) return adminJson({ error: 'ADMIN_KEY not set. Run: npx wrangler secret put ADMIN_KEY' }, 503);
  await ensureOwnerSchema(env);
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  // Salted with the admin key so stored hashes cannot be reversed to IPs; rows are removed after a day.
  const ipHash = await sha256Hex(`molido-admin|${env.ADMIN_KEY}|${ip}`);
  const now = Date.now();
  const row = await env.DB.prepare('SELECT fails, locked_until FROM admin_fails WHERE ip_hash = ?1').bind(ipHash).first();
  if (row && row.locked_until > now) {
    return adminJson({ error: 'locked', retry_after_s: Math.ceil((row.locked_until - now) / 1000) }, 429);
  }
  const auth = request.headers.get('authorization') || '';
  const given = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (given && (await timingSafeKeyEqual(given, env.ADMIN_KEY))) {
    if (row) await env.DB.prepare('DELETE FROM admin_fails WHERE ip_hash = ?1').bind(ipHash).run();
    return null;
  }
  const fails = (row ? row.fails : 0) + 1;
  const lockedUntil = fails >= ADMIN_MAX_FAILS ? now + ADMIN_LOCK_MS : 0;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO admin_fails (ip_hash, fails, locked_until, updated) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(ip_hash) DO UPDATE SET fails = excluded.fails, locked_until = excluded.locked_until, updated = excluded.updated`
    ).bind(ipHash, lockedUntil ? 0 : fails, lockedUntil, now),
    env.DB.prepare('DELETE FROM admin_fails WHERE updated < ?1').bind(now - 86400000),
  ]);
  return adminJson({ error: lockedUntil ? 'locked' : 'unauthorized' }, lockedUntil ? 429 : 401);
}

async function adminApi(request, env, url, ctx) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 405, headers: ADMIN_HEADERS });
  const denied = await adminAuth(request, env);
  if (denied) return denied;
  const path = url.pathname.replace(/\/+$/, '');
  const DB = env.DB;

  if (path === '/admin/api/items' && request.method === 'GET') {
    const { results } = await DB.prepare(
      'SELECT id, kind, value, note, enabled, always_show, due_at, created_at FROM owner_items ORDER BY id DESC'
    ).all();
    const st = await ownerStatus(env);
    const now = Date.now();
    // Iran status per config: last local test, consecutive failed runs, 7-day user reports, hidden/due.
    const one = (item, line, fp) => {
      const t = st.tests.get(fp);
      const u = st.users.get(fp) || { ok: 0, fail: 0 };
      const e = { item, fp, line };
      return {
        tested: !!t,
        ok: t ? !!t.ok : null,
        ms: t ? t.ms : null,
        tested_at: t ? t.tested_at : null,
        fail_streak: t ? t.fail_streak : 0,
        user_ok: u.ok || 0,
        user_fail: u.fail || 0,
        hidden: ownerHidden(e, st),
        due: ownerDue(e, st, now),
      };
    };
    const items = await Promise.all(
      results.map(async (it) => {
        if (it.kind === 'config') return { ...it, status: one(it, it.value, await nodeFingerprint(it.value)) };
        const lines = await fetchOwnerSub(it.value, ctx);
        const s = await Promise.all(lines.map(async (l) => one(it, l, await nodeFingerprint(l))));
        return {
          ...it,
          status: {
            total: s.length,
            ok: s.filter((x) => x.ok === true).length,
            failed: s.filter((x) => x.ok === false).length,
            untested: s.filter((x) => !x.tested).length,
            hidden: s.filter((x) => x.hidden).length,
            due: s.some((x) => x.due),
            tested_at: Math.max(0, ...s.map((x) => x.tested_at || 0)) || null,
          },
        };
      })
    );
    return adminJson({ items });
  }

  const readBody = async () => {
    const text = await request.text();
    if (text.length > 200_000) return null;
    try {
      const b = JSON.parse(text);
      return b && typeof b === 'object' && !Array.isArray(b) ? b : null;
    } catch {
      return null;
    }
  };

  if (path === '/admin/api/items' && request.method === 'POST') {
    const b = await readBody();
    if (!b || (b.kind !== 'sub' && b.kind !== 'config') || typeof b.value !== 'string') return adminJson({ error: 'bad request' }, 400);
    const note = typeof b.note === 'string' ? b.note.trim().slice(0, OWNER_NOTE_MAX_LEN) : '';
    const { n } = await DB.prepare('SELECT COUNT(*) n FROM owner_items').first();
    const created = new Date().toISOString();
    if (b.kind === 'sub') {
      const link = b.value.trim();
      if (!validSubUrl(link)) return adminJson({ error: 'invalid link (must be https, max 2048 chars)' }, 400);
      if (n >= OWNER_MAX_ITEMS) return adminJson({ error: 'too many items' }, 400);
      await DB.prepare('INSERT INTO owner_items (kind, value, note, enabled, created_at) VALUES (?1, ?2, ?3, 1, ?4)')
        .bind('sub', link, note, created)
        .run();
      return adminJson({ added: 1, rejected: 0 });
    }
    const lines = b.value.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    const valid = [...new Set(lines.filter(validConfig))];
    const room = Math.max(0, OWNER_MAX_ITEMS - n);
    const toAdd = valid.slice(0, room);
    if (toAdd.length) {
      await DB.batch(
        toAdd.map((line) =>
          DB.prepare('INSERT INTO owner_items (kind, value, note, enabled, created_at) VALUES (?1, ?2, ?3, 1, ?4)').bind('config', line, note, created)
        )
      );
    }
    return adminJson({ added: toAdd.length, rejected: lines.length - toAdd.length }, toAdd.length ? 200 : 400);
  }

  const m = path.match(/^\/admin\/api\/items\/(\d{1,12})$/);
  if (m) {
    const id = Number(m[1]);
    if (request.method === 'DELETE') {
      await DB.prepare('DELETE FROM owner_items WHERE id = ?1').bind(id).run();
      return adminJson({ ok: true });
    }
    if (request.method === 'PATCH') {
      const b = await readBody();
      // { enabled?: bool, always_show?: bool, retest?: true } — retest makes the item due for the quick local Iran test.
      const ups = [];
      if (b && typeof b.enabled === 'boolean') ups.push(DB.prepare('UPDATE owner_items SET enabled = ?1 WHERE id = ?2').bind(b.enabled ? 1 : 0, id));
      if (b && typeof b.always_show === 'boolean')
        ups.push(DB.prepare('UPDATE owner_items SET always_show = ?1 WHERE id = ?2').bind(b.always_show ? 1 : 0, id));
      if (b && b.retest === true) ups.push(DB.prepare('UPDATE owner_items SET due_at = ?1 WHERE id = ?2').bind(Date.now(), id));
      if (!ups.length) return adminJson({ error: 'bad request' }, 400);
      await DB.batch(ups);
      return adminJson({ ok: true });
    }
  }
  return adminJson({ error: 'not found' }, 404);
}

function adminPage(env) {
  const keySet = !!env.ADMIN_KEY;
  const html = `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>پنل مدیریت MolidoVPN</title>
<style>
:root{--bg:#f4f6fb;--card:#fff;--text:#1b2030;--mute:#6b7285;--line:#dde2ee;--accent:#3b5bdb;--danger:#d6336c;--ok:#2b8a3e}
@media (prefers-color-scheme:dark){:root{--bg:#10131b;--card:#191d29;--text:#e8ebf3;--mute:#9aa1b5;--line:#2a3042;--accent:#748ffc;--danger:#f06595;--ok:#69db7c}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 Tahoma,"Segoe UI",system-ui,sans-serif;padding:16px}
main{max-width:720px;margin:0 auto}h1{font-size:20px;margin:0 0 12px}h2{font-size:16px;margin:0 0 8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:14px}
input,textarea,select{width:100%;font:inherit;color:var(--text);background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:9px;margin:4px 0 10px}
textarea{min-height:120px;direction:ltr;text-align:left;font-family:ui-monospace,Consolas,monospace;font-size:13px}
button{font:inherit;border:0;border-radius:8px;padding:8px 14px;background:var(--accent);color:#fff;cursor:pointer}
button.ghost{background:transparent;color:var(--text);border:1px solid var(--line)}button.danger{background:var(--danger)}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.mute{color:var(--mute);font-size:13px}
.item{border-top:1px solid var(--line);padding:10px 0}.item:first-child{border-top:0}
.val{direction:ltr;text-align:left;font-family:ui-monospace,Consolas,monospace;font-size:12px;word-break:break-all;margin:4px 0}
.badge{font-size:12px;border-radius:6px;padding:1px 8px;border:1px solid var(--line)}.on{color:var(--ok)}.off{color:var(--danger)}
#msg{min-height:1.4em}code{direction:ltr;display:inline-block;background:var(--bg);padding:2px 6px;border-radius:6px}
</style></head><body><main>
<h1>پنل مدیریت MolidoVPN</h1>
${
  keySet
    ? ''
    : `<div class="card"><h2>کلید مدیریت تنظیم نشده است</h2><p>برای فعال شدن پنل، در پوشه <code>cloudflare</code> این دستور را اجرا کنید و یک کلید طولانی و محرمانه وارد کنید:</p><p><code>npx wrangler secret put ADMIN_KEY</code></p></div>`
}
<div class="card" id="login"${keySet ? '' : ' hidden'}>
<h2>ورود</h2><label>کلید مدیریت<input id="key" type="password" autocomplete="current-password"></label>
<button id="loginBtn">ورود</button></div>
<div id="panel" hidden>
<div class="card"><h2>افزودن</h2>
<label>نوع<select id="kind"><option value="config">کانفیگ (یک یا چند خط)</option><option value="sub">لینک اشتراک (https)</option></select></label>
<label>مقدار<textarea id="value" placeholder="vless://...&#10;trojan://..."></textarea></label>
<label>یادداشت (اختیاری)<input id="note" maxlength="200"></label>
<div class="row"><button id="addBtn">افزودن</button><button class="ghost" id="logoutBtn">خروج</button></div></div>
<div class="card"><h2>موارد <span class="mute" id="count"></span></h2><div id="list"></div></div>
</div>
<p id="msg" class="mute"></p>
</main>
<script>
(function(){
var $=function(id){return document.getElementById(id)};
var key='';try{key=sessionStorage.getItem('mk')||''}catch(e){}
function msg(t){$('msg').textContent=t||''}
function api(method,path,body){
  var o={method:method,headers:{'Authorization':'Bearer '+key}};
  if(body){o.headers['content-type']='application/json';o.body=JSON.stringify(body)}
  return fetch('/admin/api'+path,o).then(function(r){return r.json().catch(function(){return {}}).then(function(j){j._s=r.status;return j})});
}
function err(j){
  if(j._s===401){logout();return 'کلید اشتباه است'}
  if(j._s===429){logout();return 'تلاش‌های ناموفق زیاد؛ چند دقیقه بعد دوباره امتحان کنید'}
  if(j._s===503)return 'کلید مدیریت روی سرور تنظیم نشده است';
  return j.error||('خطا '+j._s);
}
function logout(){key='';try{sessionStorage.removeItem('mk')}catch(e){}$('panel').hidden=true;$('login').hidden=false}
function load(){
  return api('GET','/items').then(function(j){
    if(j._s!==200){msg(err(j));return}
    $('login').hidden=true;$('panel').hidden=false;
    var list=$('list');list.textContent='';$('count').textContent='('+j.items.length+')';
    j.items.forEach(function(it){
      var d=document.createElement('div');d.className='item';
      var h=document.createElement('div');h.className='row';
      var b1=document.createElement('span');b1.className='badge';b1.textContent=it.kind==='sub'?'لینک اشتراک':'کانفیگ';
      var b2=document.createElement('span');b2.className='badge '+(it.enabled?'on':'off');b2.textContent=it.enabled?'فعال':'غیرفعال';
      var n=document.createElement('span');n.className='mute';n.textContent=(it.note?it.note+' · ':'')+String(it.created_at).slice(0,10);
      var st=it.status||{},b3=document.createElement('span'),b4=document.createElement('span');b4.className='mute';
      var when=function(ms){return ms?new Date(ms).toLocaleString('fa-IR',{dateStyle:'short',timeStyle:'short'}):''};
      if(it.kind==='sub'){
        b3.className='badge '+(st.total&&st.ok===st.total?'on':st.failed?'off':'');
        b3.textContent=st.total?(st.ok+' از '+st.total+' سالم'):'⏳ کانفیگی دریافت نشد';
        b4.textContent=[st.untested?st.untested+' هنوز تست نشده':'',st.hidden?st.hidden+' پنهان از کاربران':'',st.tested_at?'آخرین تست '+when(st.tested_at):''].filter(Boolean).join(' · ');
      }else if(!st.tested){b3.className='badge';b3.textContent='⏳ هنوز تست نشده'}
      else if(st.ok){b3.className='badge on';b3.textContent='✅ ایران OK ('+(st.ms||'?')+' ms، '+when(st.tested_at)+')'}
      else{b3.className='badge off';b3.textContent='❌ از ایران وصل نشد';b4.textContent=when(st.tested_at)+(st.hidden?' · پنهان از کاربران':'')}
      if(it.kind==='config'&&(st.user_ok+st.user_fail))b4.textContent=(b4.textContent?b4.textContent+' · ':'')+'گزارش کاربران ایران: '+Math.round(100*st.user_ok/(st.user_ok+st.user_fail))+'% از '+(st.user_ok+st.user_fail);
      if(st.due&&it.due_at&&(!st.tested_at||it.due_at>st.tested_at))b4.textContent=(b4.textContent?b4.textContent+' · ':'')+'در صف تست';
      h.append(b1,b2,b3,b4,n);
      var v=document.createElement('div');v.className='val';v.textContent=it.value.length>300?it.value.slice(0,300)+'…':it.value;
      var a=document.createElement('div');a.className='row';
      var t=document.createElement('button');t.className='ghost';t.textContent=it.enabled?'غیرفعال کن':'فعال کن';
      t.onclick=function(){api('PATCH','/items/'+it.id,{enabled:!it.enabled}).then(function(r){r._s===200?load():msg(err(r))})};
      var re=document.createElement('button');re.className='ghost';re.textContent='تست دوباره';
      re.onclick=function(){api('PATCH','/items/'+it.id,{retest:true}).then(function(r){if(r._s===200){msg('در صف تست؛ حداکثر ۱۵ دقیقه');load()}else msg(err(r))})};
      var al=document.createElement('label');al.className='row mute';var cb=document.createElement('input');cb.type='checkbox';cb.style.width='auto';cb.style.margin='0';cb.checked=!!it.always_show;
      cb.onchange=function(){api('PATCH','/items/'+it.id,{always_show:cb.checked}).then(function(r){r._s===200?load():msg(err(r))})};
      al.append(cb,document.createTextNode('همیشه نشان بده'));
      var del=document.createElement('button');del.className='danger';del.textContent='حذف';
      del.onclick=function(){if(confirm('حذف شود؟'))api('DELETE','/items/'+it.id).then(function(r){r._s===200?load():msg(err(r))})};
      a.append(t,re,al,del);d.append(h,v,a);list.append(d);
    });
  }).catch(function(){msg('خطای شبکه')});
}
$('loginBtn').onclick=function(){key=$('key').value.trim();if(!key)return;try{sessionStorage.setItem('mk',key)}catch(e){}$('key').value='';msg('');load()};
$('key').onkeydown=function(e){if(e.key==='Enter')$('loginBtn').click()};
$('logoutBtn').onclick=function(){logout();msg('')};
$('addBtn').onclick=function(){
  var body={kind:$('kind').value,value:$('value').value,note:$('note').value};
  if(!body.value.trim())return;
  api('POST','/items',body).then(function(j){
    if(j._s===200){$('value').value='';$('note').value='';msg('افزوده شد: '+j.added+(j.rejected?' · نامعتبر/رد شده: '+j.rejected:''));load()}
    else msg(j.added===0?'هیچ کانفیگ معتبری پیدا نشد (نامعتبر: '+j.rejected+')':err(j));
  }).catch(function(){msg('خطای شبکه')});
};
if(key&&${keySet})load();
})();
</script></body></html>`;
  return new Response(html, {
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'content-security-policy':
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'",
      ...ADMIN_HEADERS,
    },
  });
}

export default {
  async scheduled(event, env, ctx) {
    const cutoff = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
    ctx.waitUntil(env.DB.prepare('DELETE FROM reports WHERE day < ?1').bind(cutoff).run());
    ctx.waitUntil(
      ensureOwnerSchema(env)
        .then(() =>
          env.DB.batch([
            env.DB.prepare('DELETE FROM admin_fails WHERE updated < ?1').bind(Date.now() - 86400000),
            env.DB.prepare('DELETE FROM owner_tests WHERE tested_at < ?1').bind(Date.now() - 30 * 86400000),
          ])
        )
        .catch(() => {})
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS' && (url.pathname === '/report' || url.pathname === '/scores'))
      return new Response(null, { status: 204, headers: CORS });
    if (url.pathname === '/report') return reportRoute(request, env, ctx);
    if (url.pathname === '/owner/configs') return ownerConfigsRoute(env, ctx);
    if (url.pathname === '/scores') return scoresRoute(request, env, ctx);
    if (url.pathname.startsWith('/remote/')) return remoteRoute(url);
    if (url.pathname.startsWith('/app/')) return appRoute(url);
    if (url.pathname === '/warp/reg') return warpRegRoute(request);
    if (url.pathname === '/admin' || url.pathname === '/admin/') return adminPage(env);
    if (url.pathname.startsWith('/admin/api')) {
      try {
        return await adminApi(request, env, url, ctx);
      } catch {
        return adminJson({ error: 'server error' }, 500);
      }
    }
    if (url.pathname.startsWith('/admin')) return adminJson({ error: 'not found' }, 404);
    if (url.pathname.startsWith('/sub/')) return subRoute(url, env, ctx);
    if (url.pathname.startsWith('/lite') || url.pathname.startsWith('/ios') || url.pathname.startsWith('/hiddify'))
      return iosRoute(url, env, ctx);
    const sources = [FULL, MIRROR('sub_base64.txt')];
    const owner = ownerLines(env, ctx);

    for (const source of sources) {
      const res = await fetch(source, { cf: { cacheTtl: 300, cacheEverything: true } }).catch(() => null);
      if (!res || !res.ok) continue;
      const branded = brand(mergeOwner(await owner, decodeList(await res.text()).split('\n').filter((l) => l.includes('://'))));
      const bytes = new TextEncoder().encode(branded.join('\n'));
      let bin = '';
      for (const b of bytes) bin += String.fromCharCode(b);
      return new Response(btoa(bin), {
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          'profile-title': 'base64:' + btoa('MolidoVPN'),
          'profile-update-interval': '1',
          'profile-web-page-url': 'https://hidooch980.github.io/mobin-vpn/',
          'cache-control': 'public, max-age=300',
          'access-control-allow-origin': '*',
        },
      });
    }
    return new Response('server list unavailable, try again shortly', { status: 502 });
  },
};

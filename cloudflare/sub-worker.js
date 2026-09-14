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

async function reportRoute(request, env) {
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

async function subRoute(url, env) {
  const n = Number(url.pathname.split('/')[2]);
  if (!Number.isInteger(n) || n < 1 || n > SUB_LINKS) return new Response('use /sub/1 … /sub/5', { status: 404 });
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
  return listResponse((await rankByReports(lines, scores)).slice(0, SUB_MAX), `MolidoVPN ${n}`);
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

async function iosRoute(url, env) {
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
  const lines = rankedOut.slice(0, IOS_MAX);
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

export default {
  async scheduled(event, env, ctx) {
    const cutoff = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
    ctx.waitUntil(env.DB.prepare('DELETE FROM reports WHERE day < ?1').bind(cutoff).run());
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS' && (url.pathname === '/report' || url.pathname === '/scores'))
      return new Response(null, { status: 204, headers: CORS });
    if (url.pathname === '/report') return reportRoute(request, env);
    if (url.pathname === '/scores') return scoresRoute(request, env, ctx);
    if (url.pathname.startsWith('/remote/')) return remoteRoute(url);
    if (url.pathname.startsWith('/app/')) return appRoute(url);
    if (url.pathname === '/warp/reg') return warpRegRoute(request);
    if (url.pathname.startsWith('/sub/')) return subRoute(url, env);
    if (url.pathname.startsWith('/lite') || url.pathname.startsWith('/ios') || url.pathname.startsWith('/hiddify'))
      return iosRoute(url, env);
    const sources = [FULL, MIRROR('sub_base64.txt')];

    for (const source of sources) {
      const res = await fetch(source, { cf: { cacheTtl: 300, cacheEverything: true } }).catch(() => null);
      if (!res || !res.ok) continue;
      return new Response(await res.text(), {
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

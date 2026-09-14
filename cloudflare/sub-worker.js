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

// Anonymous opt-in connection reports, aggregated per UTC day in D1. No IPs are stored.
const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
};
const NODE_RE = /^([0-9a-f]{16}|mode:[a-z0-9_-]{1,20})$/;
const NETS = new Set(['wifi', 'cellular', 'other']);
const APPS = new Set(['android', 'windows']);
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
    .bind(day, r.node, r.app, r.net, r.ok ? 1 : 0, r.ok ? 0 : 1, hasMs ? ms : 0, hasMs)
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
  const key = new Request(new URL('/scores', request.url).toString());
  const hit = await cache.match(key);
  if (hit) return hit;

  const since = new Date(Date.now() - 6 * 86400000).toISOString().slice(0, 10);
  const { results } = await env.DB.prepare(
    `SELECT node, net, SUM(ok) ok, SUM(fail) fail, SUM(ms_sum) ms_sum, SUM(ms_n) ms_n
     FROM reports WHERE day >= ?1 GROUP BY node, net`
  )
    .bind(since)
    .all();
  const acc = {};
  for (const row of results) {
    const a = (acc[row.node] ||= { all: { ok: 0, fail: 0, ms_sum: 0, ms_n: 0 } });
    for (const k of [row.net === 'cellular' || row.net === 'wifi' ? row.net : null, 'all']) {
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

async function iosRoute(url) {
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
    if (!line.includes('://') || line.startsWith('#') || out.length >= IOS_MAX) return;
    const core = line.split('#')[0];
    if (seen.has(core) || !iosFriendly(core)) return;
    seen.add(core);
    out.push(name ? `${core}#${encodeURIComponent(name)}` : line);
  };
  let cdn = 0;
  for (const l of shard.split('\n')) if (l.includes('://')) add(l, `MolidoVPN CDN ${++cdn}`);
  for (const l of decodeList(lite).split('\n')) add(l);
  for (const l of decodeList(full).split('\n')) add(l);

  const lines = [...out];
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
    if (url.pathname.startsWith('/lite') || url.pathname.startsWith('/ios') || url.pathname.startsWith('/hiddify'))
      return iosRoute(url);
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

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

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/app/')) return appRoute(url);
    const lite = url.pathname.startsWith('/lite');
    const sources = lite ? [LITE, MIRROR('lite_base64.txt')] : [FULL, MIRROR('sub_base64.txt')];

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

// MolidoVPN subscription link (Cloudflare Worker, free plan).
// Serves the server list from GitHub under your own worker address, with a profile name and
// auto-update interval that Hiddify / Streisand / v2rayNG show. /lite = small list for iPhone.
const FULL = 'https://raw.githubusercontent.com/hidooch980/vpn-sub/sub/sub_base64.txt';
const LITE = 'https://raw.githubusercontent.com/hidooch980/vpn-sub/sub/lite_base64.txt';
const MIRROR = (file) => `https://cdn.jsdelivr.net/gh/hidooch980/vpn-sub@sub/${file}`;

export default {
  async fetch(request) {
    const url = new URL(request.url);
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

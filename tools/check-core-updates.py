#!/usr/bin/env python3
"""Checks upstream releases of the bundled cores/tunnels and rewrites the pins.

Stdlib only. Used by .github/workflows/core-updates.yml, but runs locally too:

  python tools/check-core-updates.py                     # dry run, prints what it would do
  python tools/check-core-updates.py --apply \
      --android-dir ../molidovpn-android                 # rewrite pins (+ mirror when a token is set)

Environment:
  GITHUB_TOKEN       token for API calls and issues in mobin-vpn
  CROSS_REPO_TOKEN   optional; contents:write on hidooch980/molidovpn-android. Without it the Android
                     side is not touched and the needed Android updates are reported in an issue.

Safety policy (auto-apply only non-breaking updates, never pre-releases):
  sing-box   same major.minor as the current pin (1.12.x patches); a new minor/major opens an issue
  Xray-core  any newer stable release
  Tor        newest stable Tor Browser version on dist.torproject.org
  Psiphon    newer commit touching windows/psiphon-tunnel-core-i686.exe
  AmneziaWG  newer stable release
  MSN-GUARD  (Rust core / Android mirror upstream) never merged automatically, only reported

Outputs a JSON summary (--summary) consumed by the workflow:
  {"mobin_commit": "...", "android_commit": "...", "applied": [...], "review": [...]}
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile

MOBIN_REPO = "hidooch980/mobin-vpn"
ANDROID_REPO = "hidooch980/molidovpn-android"
RETRY_WINDOW = dt.timedelta(hours=24)
ISSUE_TITLE_REPORT = "Core updates: manual follow-up"


# ---------------------------------------------------------------- versions

def parse_version(tag: str) -> tuple[int, ...] | None:
    """'v1.12.25' -> (1, 12, 25). Pre-release tags ('1.15.0-alpha.4', '15.0a2', 'rc') -> None."""
    t = tag.strip()
    if t[:1] in "vV":
        t = t[1:]
    if not re.fullmatch(r"\d+(\.\d+)*", t):
        return None
    return tuple(int(p) for p in t.split("."))


def is_newer(candidate: str, current: str) -> bool:
    c, o = parse_version(candidate), parse_version(current)
    if c is None or o is None:
        return False
    n = max(len(c), len(o))
    return c + (0,) * (n - len(c)) > o + (0,) * (n - len(o))


def same_minor(a: str, b: str) -> bool:
    x, y = parse_version(a), parse_version(b)
    return x is not None and y is not None and x[:2] == y[:2]


def newest_stable(tags: list[str], prefix_minor: tuple[int, int] | None = None) -> str | None:
    best = None
    for t in tags:
        v = parse_version(t)
        if v is None or (prefix_minor and v[:2] != prefix_minor):
            continue
        if best is None or is_newer(t, best):
            best = t
    return best


# ---------------------------------------------------------------- pin rewriting

# release.yml
RX_XRAY_VER = r"^(\s*XRAY_VERSION:\s*')([^']*)(')"
RX_XRAY_SHA = r"^(\s*XRAY_SHA256:\s*)([0-9a-fA-F]{64})"
RX_PSI_COMMIT = r"^(\s*PSIPHON_COMMIT:\s*)([0-9a-f]{40})"
RX_PSI_SHA = r"^(\s*PSIPHON_SHA256:\s*)([0-9a-fA-F]{64})"
RX_TOR_VER = r"^(\s*TOR_BROWSER_VERSION:\s*')([^']*)(')"
RX_TOR_SHA = r"^(\s*TOR_BUNDLE_SHA256:\s*')([0-9a-fA-F]{64}|)(')"
RX_AWG_VER = r"^(\s*AWG_VERSION:\s*')([^']*)(')"
RX_AWG_SHA = r"^(\s*AWG_MSI_SHA256:\s*)([0-9a-fA-F]{64})"
RX_WIN_SB_MINOR = r'(select\(startswith\("v)(\d+\.\d+)(\."\)\))'
# fetch-binaries.sh
RX_SB_VER = r'^(SINGBOX_VERSION=")([^"]*)(")'
RX_BIN_TAG = r'(\$\{BINARIES_TAG:-)(binaries-\d+)(\})'


def rx_sb_sha(abi: str) -> str:
    return r"^(\s*" + re.escape(abi) + r"\) echo )([0-9a-f]{64})( ;;)"


def pin_group(pattern: str, text: str, what: str) -> str:
    m = list(re.finditer(pattern, text, flags=re.M))
    if len(m) != 1:
        raise ValueError(f"expected exactly one {what} pin, found {len(m)}")
    return m[0].group(2)


def set_pin(pattern: str, value: str, text: str, what: str) -> str:
    def repl(m: re.Match) -> str:
        tail = m.group(3) if m.re.groups >= 3 else ""
        return m.group(1) + value + tail
    new, n = re.subn(pattern, repl, text, flags=re.M)
    if n != 1:
        raise ValueError(f"expected exactly one {what} pin, found {n}")
    return new


# ---------------------------------------------------------------- network

def _token_for(url: str) -> str | None:
    if "api.github.com" in url:
        return os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    return None


def http_get(url: str, accept: str | None = None) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "molido-core-updates"})
    tok = _token_for(url)
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
    if accept:
        req.add_header("Accept", accept)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return r.read()
        except urllib.error.HTTPError:
            raise
        except Exception:
            if attempt == 2:
                raise
    raise AssertionError("unreachable")


def gh_api(path: str):
    return json.loads(http_get("https://api.github.com/" + path.lstrip("/"), "application/vnd.github+json"))


def gh_api_write(method: str, path: str, body: dict):
    req = urllib.request.Request("https://api.github.com/" + path.lstrip("/"), method=method,
                                 data=json.dumps(body).encode(),
                                 headers={"User-Agent": "molido-core-updates",
                                          "Accept": "application/vnd.github+json",
                                          "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b"{}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def stable_releases(repo: str) -> list[dict]:
    rels = gh_api(f"repos/{repo}/releases?per_page=30")   # asset lists make big pages slow
    return [r for r in rels if not r.get("prerelease") and not r.get("draft")]


def asset_url(release: dict, name: str) -> str | None:
    for a in release.get("assets", []):
        if a["name"] == name:
            return a["browser_download_url"]
    return None


def download_verified_dgst(release: dict, name: str) -> bytes:
    """Downloads an Xray asset and checks it against the release's .dgst file."""
    url = asset_url(release, name)
    dgst_url = asset_url(release, name + ".dgst")
    if not url or not dgst_url:
        raise RuntimeError(f"{release['tag_name']}: {name} or its .dgst is missing")
    data = http_get(url)
    m = re.search(r"SHA2-256=\s*([0-9a-f]{64})", http_get(dgst_url).decode())
    if not m or m.group(1) != sha256(data):
        raise RuntimeError(f"{name}: SHA-256 does not match the published .dgst")
    return data


# ---------------------------------------------------------------- state

def load_state(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {"components": {}}


def recently_attempted(state: dict, component: str, version: str, now: dt.datetime) -> bool:
    ts = state.get("components", {}).get(component, {}).get("attempts", {}).get(version)
    if not ts:
        return False
    return now - dt.datetime.fromisoformat(ts) < RETRY_WINDOW


def record(state: dict, component: str, version: str, now: dt.datetime, applied: bool = True) -> None:
    c = state.setdefault("components", {}).setdefault(component, {})
    c.setdefault("attempts", {})[version] = now.isoformat(timespec="seconds")
    # Keep the attempts map small.
    c["attempts"] = dict(sorted(c["attempts"].items(), key=lambda kv: kv[1])[-10:])
    if applied:
        c["applied"] = version


# ---------------------------------------------------------------- checks

class Ctx:
    def __init__(self, args):
        self.args = args
        self.now = dt.datetime.now(dt.timezone.utc)
        self.state = load_state(args.state)
        with open(args.release_yml, encoding="utf-8", newline="") as f:
            self.yml = f.read()
        self.sh = None
        self.sh_path = None
        if args.android_dir:
            self.sh_path = os.path.join(args.android_dir, "tools", "fetch-binaries.sh")
            with open(self.sh_path, encoding="utf-8", newline="") as f:
                self.sh = f.read()
        self.cross = bool(os.environ.get("CROSS_REPO_TOKEN")) and self.sh is not None
        self.mobin_changes: list[str] = []
        self.android_changes: list[str] = []
        self.review: list[dict] = []   # {"title": ..., "body": ...} -> one issue each
        self.report: list[str] = []    # lines for the manual follow-up issue
        self.mirror_replace: dict[str, bytes] = {}
        self.needs_token = False       # an Android update was skipped for lack of CROSS_REPO_TOKEN

    def skip_recent(self, component: str, version: str) -> bool:
        if recently_attempted(self.state, component, version, self.now):
            print(f"{component} {version}: already attempted in the last 24 h, skipping")
            return True
        return False


def check_xray(ctx: Ctx) -> None:
    cur = pin_group(RX_XRAY_VER, ctx.yml, "XRAY_VERSION")
    rels = stable_releases("XTLS/Xray-core")
    latest = newest_stable([r["tag_name"] for r in rels])
    if not latest or not is_newer(latest, cur):
        print(f"Xray: {cur} is current")
        return
    if ctx.skip_recent("xray", latest):
        return
    rel = next(r for r in rels if r["tag_name"] == latest)
    win = download_verified_dgst(rel, "Xray-windows-64.zip")
    ctx.yml = set_pin(RX_XRAY_VER, latest, ctx.yml, "XRAY_VERSION")
    ctx.yml = set_pin(RX_XRAY_SHA, sha256(win), ctx.yml, "XRAY_SHA256")
    ctx.mobin_changes.append(f"Xray {cur} → {latest}")
    record(ctx.state, "xray", latest, ctx.now)
    # Android: libxray.so in the mirror release is the plain xray executable per ABI.
    android_assets = {"arm64-v8a__libxray.so": "Xray-android-arm64-v8a.zip",
                      "armeabi-v7a__libxray.so": "Xray-linux-arm32-v7a.zip"}
    if ctx.cross:
        for mirror_name, zname in android_assets.items():
            z = zipfile.ZipFile(io.BytesIO(download_verified_dgst(rel, zname)))
            ctx.mirror_replace[mirror_name] = z.read("xray")
        ctx.android_changes.append(f"Xray {cur} → {latest}")
    else:
        ctx.needs_token = True
        ctx.report.append(f"- Android: rebuild mirror `binaries-N` with Xray {latest} "
                          f"(`Xray-android-arm64-v8a.zip`, `Xray-linux-arm32-v7a.zip` → `libxray.so`).")


def check_singbox(ctx: Ctx) -> None:
    rels = stable_releases("SagerNet/sing-box")
    tags = [r["tag_name"] for r in rels]
    newest = newest_stable(tags)
    win_minor = pin_group(RX_WIN_SB_MINOR, ctx.yml, "Windows sing-box minor")
    base = ctx.sh and pin_group(RX_SB_VER, ctx.sh, "SINGBOX_VERSION")
    base = base or win_minor + ".0"
    # New minor/major: never automatic.
    if newest and not same_minor(newest, base) and is_newer(newest, base):
        v = parse_version(newest)
        series = f"{v[0]}.{v[1]}.x"
        ctx.review.append({
            "title": f"Core update needs review: sing-box {series}",
            "body": (f"sing-box {newest} is out; the app is pinned to the {win_minor}.x series "
                     f"(Windows: latest v{win_minor}.x at build time, Android: {base}).\n\n"
                     "Minor/major sing-box releases change the config schema and are not applied "
                     "automatically. To adopt it: bump the `startswith(\"v{0}.\")` filter in "
                     "`.github/workflows/release.yml`, `SINGBOX_VERSION` + hashes in "
                     "molidovpn-android `tools/fetch-binaries.sh`, then check the generated configs "
                     "(`sing-box check` step) and the emulator connection test.".format(win_minor)),
        })
    # Windows already takes the newest v1.12.x at build time; only the Android pin needs bumping.
    if ctx.sh is None:
        return
    minor = parse_version(base)[:2]
    patch = newest_stable(tags, minor)
    if not patch or not is_newer(patch, base):
        print(f"sing-box: {base} is current in its series")
        return
    ver = patch.lstrip("v")
    if ctx.skip_recent("sing-box-android", ver):
        return
    if not ctx.cross:
        ctx.needs_token = True
        ctx.report.append(f"- Android: `SINGBOX_VERSION` {base} → {ver} in `tools/fetch-binaries.sh` (+ both SHA-256).")
        return
    rel = next(r for r in rels if r["tag_name"] == patch)
    sh = set_pin(RX_SB_VER, ver, ctx.sh, "SINGBOX_VERSION")
    for abi, arch in (("arm64-v8a", "arm64"), ("armeabi-v7a", "arm")):
        name = f"sing-box-{ver}-android-{arch}.tar.gz"
        url = asset_url(rel, name)
        if not url:
            raise RuntimeError(f"sing-box {ver}: {name} missing")
        sh = set_pin(rx_sb_sha(abi), sha256(http_get(url)), sh, f"sing-box {abi} sha")
    ctx.sh = sh
    ctx.android_changes.append(f"sing-box {base} → {ver}")
    ctx.mobin_changes.append(f"sing-box (Android) {base} → {ver}")
    record(ctx.state, "sing-box-android", ver, ctx.now)


def _commit_date(repo: str, sha: str) -> str:
    return gh_api(f"repos/{repo}/commits/{sha}")["commit"]["committer"]["date"]


def check_psiphon(ctx: Ctx) -> None:
    repo = "Psiphon-Labs/psiphon-tunnel-core-binaries"
    cur = pin_group(RX_PSI_COMMIT, ctx.yml, "PSIPHON_COMMIT")
    cur_date = _commit_date(repo, cur)
    latest = gh_api(f"repos/{repo}/commits?path=windows/psiphon-tunnel-core-i686.exe&per_page=1")[0]
    sha, date = latest["sha"], latest["commit"]["committer"]["date"]
    if sha != cur and date > cur_date and not ctx.skip_recent("psiphon", sha):
        data = http_get(f"https://raw.githubusercontent.com/{repo}/{sha}/windows/psiphon-tunnel-core-i686.exe")
        if len(data) < 1_000_000 or data[:2] != b"MZ":
            raise RuntimeError("Psiphon download is not a Windows executable")
        ctx.yml = set_pin(RX_PSI_COMMIT, sha, ctx.yml, "PSIPHON_COMMIT")
        ctx.yml = set_pin(RX_PSI_SHA, sha256(data), ctx.yml, "PSIPHON_SHA256")
        ctx.mobin_changes.append(f"Psiphon {cur[:7]} → {sha[:7]}")
        record(ctx.state, "psiphon", sha, ctx.now)
    else:
        print(f"Psiphon (Windows): {cur[:7]} is current")
    # Android AAR comes from the MSN-GUARD mirror (different build/version scheme): report only.
    a = gh_api(f"repos/{repo}/commits?path=android&per_page=1")
    if a:
        asha = a[0]["sha"]
        seen = ctx.state.get("components", {}).get("psiphon-android-upstream", {}).get("seen")
        if asha != seen:
            ctx.report.append(f"- Android: Psiphon upstream `android/ca.psiphon.aar` changed "
                              f"(commit {asha[:7]}); the app ships `psiphontunnel-2.0.39.aar` from the "
                              "mirror. Review before replacing (API differences).")
            ctx.state.setdefault("components", {}).setdefault("psiphon-android-upstream", {})["seen"] = asha


def check_tor(ctx: Ctx) -> None:
    cur = pin_group(RX_TOR_VER, ctx.yml, "TOR_BROWSER_VERSION")
    index = http_get("https://dist.torproject.org/torbrowser/").decode("utf-8", "replace")
    versions = re.findall(r'href="(\d+\.\d+(?:\.\d+)*)/"', index)   # alphas look like 15.0a2 -> excluded
    latest = newest_stable(versions)
    if not latest or not is_newer(latest, cur):
        print(f"Tor: {cur} is current")
        return
    if ctx.skip_recent("tor", latest):
        return
    base = f"https://dist.torproject.org/torbrowser/{latest}"
    name = f"tor-expert-bundle-windows-x86_64-{latest}.tar.gz"
    expected = None
    for sums in ("sha256sums-signed-build.txt", "sha256sums-unsigned-build.txt"):
        try:
            text = http_get(f"{base}/{sums}").decode()
        except Exception:
            continue
        for line in text.splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1].lstrip("*") == name:
                expected = parts[0].lower()
        if expected:
            break
    if not expected:
        print(f"Tor {latest}: no published checksum yet, trying later")
        return
    actual = sha256(http_get(f"{base}/{name}"))
    if actual != expected:
        raise RuntimeError(f"Tor {latest}: SHA-256 mismatch {actual} vs {expected}")
    ctx.yml = set_pin(RX_TOR_VER, latest, ctx.yml, "TOR_BROWSER_VERSION")
    ctx.yml = set_pin(RX_TOR_SHA, actual, ctx.yml, "TOR_BUNDLE_SHA256")
    ctx.mobin_changes.append(f"Tor {cur} → {latest}")
    record(ctx.state, "tor", latest, ctx.now)
    ctx.report.append(f"- Android: Tor {latest} is out; `libtor.so` / `libobfs4proxy.so` come from the "
                      "MSN-GUARD mirror and are not rebuilt automatically.")


def check_amneziawg(ctx: Ctx) -> None:
    cur = pin_group(RX_AWG_VER, ctx.yml, "AWG_VERSION")
    rels = stable_releases("amnezia-vpn/amneziawg-windows-client")
    latest = newest_stable([r["tag_name"] for r in rels])
    if not latest or not is_newer(latest, cur):
        print(f"AmneziaWG: {cur} is current")
        return
    if ctx.skip_recent("amneziawg", latest):
        return
    rel = next(r for r in rels if r["tag_name"] == latest)
    url = asset_url(rel, f"amneziawg-amd64-{latest}.msi")
    if not url:   # the release.yml URL scheme assumes tag == version == asset suffix
        ctx.review.append({"title": f"Core update needs review: AmneziaWG {latest}",
                           "body": f"Release {latest} has no `amneziawg-amd64-{latest}.msi` asset; "
                                   "the download step in release.yml needs adjusting."})
        record(ctx.state, "amneziawg", latest, ctx.now, applied=False)
        return
    ctx.yml = set_pin(RX_AWG_VER, latest, ctx.yml, "AWG_VERSION")
    ctx.yml = set_pin(RX_AWG_SHA, sha256(http_get(url)), ctx.yml, "AWG_MSI_SHA256")
    ctx.mobin_changes.append(f"AmneziaWG {cur} → {latest}")
    record(ctx.state, "amneziawg", latest, ctx.now)


def check_msn_guard(ctx: Ctx) -> None:
    rels = stable_releases("mbm110/MSN-GUARD")
    latest = newest_stable([r["tag_name"] for r in rels])
    comp = ctx.state.setdefault("components", {}).setdefault("msn-guard", {})
    seen = comp.get("seen")
    if latest and (seen is None or is_newer(latest, seen)):
        ctx.report.append(f"- MSN-GUARD (Rust core / Android mirror upstream) released {latest}"
                          f" (last seen: {seen or 'none'}). Not merged automatically: review the code "
                          "and license before porting core changes or refreshing mirrored binaries.")
        comp["seen"] = latest


# ---------------------------------------------------------------- mirror + issues

def publish_mirror(ctx: Ctx) -> None:
    """Copies the current mirror release, replaces changed assets, publishes binaries-N+1."""
    env = dict(os.environ, GH_TOKEN=os.environ["CROSS_REPO_TOKEN"])
    cur_tag = pin_group(RX_BIN_TAG, ctx.sh, "BINARIES_TAG")
    tags = subprocess.run(["gh", "release", "list", "-R", ANDROID_REPO, "--limit", "200",
                           "--json", "tagName", "--jq", ".[].tagName"],
                          env=env, check=True, capture_output=True, text=True).stdout.split()
    n = max([int(t.split("-")[1]) for t in tags if re.fullmatch(r"binaries-\d+", t)] + [0]) + 1
    new_tag = f"binaries-{n}"
    work = tempfile.mkdtemp()
    try:
        subprocess.run(["gh", "release", "download", cur_tag, "-R", ANDROID_REPO, "-D", work],
                       env=env, check=True)
        for name, data in ctx.mirror_replace.items():
            with open(os.path.join(work, name), "wb") as f:
                f.write(data)
        files = sorted(f for f in os.listdir(work) if f != "SHA256SUMS.txt")
        with open(os.path.join(work, "SHA256SUMS.txt"), "w", newline="\n") as out:
            for f in files:
                with open(os.path.join(work, f), "rb") as fh:
                    out.write(f"{sha256(fh.read())} *{f}\n")
        notes = f"Mirror of {cur_tag} with updated: {', '.join(sorted(ctx.mirror_replace))}"
        subprocess.run(["gh", "release", "create", new_tag, "-R", ANDROID_REPO, "--title", new_tag,
                        "--notes", notes, "--latest=false",
                        *[os.path.join(work, f) for f in files + ["SHA256SUMS.txt"]]],
                       env=env, check=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    ctx.sh = set_pin(RX_BIN_TAG, new_tag, ctx.sh, "BINARIES_TAG")
    ctx.sh = ctx.sh.replace(f'our own release "{cur_tag}"', f'our own release "{new_tag}"')


def upsert_issue(title: str, body: str) -> None:
    q = gh_api(f"repos/{MOBIN_REPO}/issues?state=open&per_page=100")
    for i in q:
        if i.get("title") == title and "pull_request" not in i:
            if i.get("body") != body:
                gh_api_write("PATCH", f"repos/{MOBIN_REPO}/issues/{i['number']}", {"body": body})
            print(f"issue #{i['number']} refreshed: {title}")
            return
    r = gh_api_write("POST", f"repos/{MOBIN_REPO}/issues", {"title": title, "body": body})
    print(f"issue #{r.get('number')} opened: {title}")


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--release-yml", default=".github/workflows/release.yml")
    ap.add_argument("--state", default=".github/core-versions.json")
    ap.add_argument("--android-dir", help="checkout of molidovpn-android (fetch-binaries.sh pins)")
    ap.add_argument("--apply", action="store_true", help="write files, publish mirror, open issues")
    ap.add_argument("--summary", default="core-updates-summary.json")
    args = ap.parse_args()

    ctx = Ctx(args)
    errors = []
    for check in (check_xray, check_singbox, check_psiphon, check_tor, check_amneziawg, check_msn_guard):
        try:
            check(ctx)
        except Exception as e:  # one broken upstream must not block the others
            errors.append(f"{check.__name__}: {e}")
            print(f"::warning::{check.__name__} failed: {e}")

    if ctx.android_changes and not ctx.cross:
        ctx.android_changes.clear()
    if ctx.needs_token:
        ctx.report.append("\nAndroid updates above need the `CROSS_REPO_TOKEN` secret (fine-grained PAT with "
                          "Contents: read and write on hidooch980/molidovpn-android) to be applied automatically.")

    if args.apply:
        if ctx.mirror_replace:
            publish_mirror(ctx)
        if ctx.mobin_changes or ctx.android_changes:
            with open(args.release_yml, "w", encoding="utf-8", newline="") as f:
                f.write(ctx.yml)
            if ctx.android_changes:
                with open(ctx.sh_path, "w", encoding="utf-8", newline="") as f:
                    f.write(ctx.sh)
        # No timestamp here: an unchanged file means nothing to commit.
        with open(args.state, "w", encoding="utf-8", newline="\n") as f:
            json.dump(ctx.state, f, indent=2, sort_keys=True)
            f.write("\n")
        if os.environ.get("GITHUB_TOKEN"):
            for r in ctx.review:
                upsert_issue(r["title"], r["body"])
            if ctx.report:
                upsert_issue(ISSUE_TITLE_REPORT, "Detected by the core-updates workflow on "
                             f"{ctx.now:%Y-%m-%d %H:%M} UTC:\n\n" + "\n".join(ctx.report))

    summary = {
        "mobin_commit": ("Core update: " + "; ".join(ctx.mobin_changes)) if ctx.mobin_changes else "",
        "android_commit": ("Core update: " + "; ".join(ctx.android_changes)) if ctx.android_changes else "",
        "review": [r["title"] for r in ctx.review],
        "report": ctx.report,
        "errors": errors,
    }
    with open(args.summary, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Build changelog.json + Persian release notes for one release. Never fails (fallback text).

usage: changelog.py VERSION SINCE_ISO WIN_REPO_DIR ANDROID_REPO_DIR OUT_JSON OUT_MD
"""
import json, re, subprocess, sys

FALLBACK = "بهبود پایداری و سرعت"
NOISE = re.compile(r"^(Sync lists|Core update state|keepalive|Merge |Release MolidoVPN|Windows screenshots|Android screenshots)|\[skip ci\]|^core-updates:", re.I)
CORE = re.compile(r"^Core updates? ?(\((Android|Windows)\))?:\s*(.+)$", re.I)
WORDS = [
    (r"\bfix(es|ed)?\b", "رفع مشکل"), (r"\badd(s|ed)?\b", "افزودن"), (r"\bremove(s|d)?\b", "حذف"),
    (r"\bimprove(s|d)?\b", "بهبود"), (r"\bfaster\b", "سریع‌تر"), (r"\bservers?\b", "سرور"),
    (r"\bupdate(s|d)?\b", "به‌روزرسانی"), (r"\bsettings?\b", "تنظیمات"), (r"\bcountry\b", "کشور"),
    (r"\bannouncement\b", "اطلاعیه"), (r"\bshare\b", "اشتراک‌گذاری"), (r"\bspeed\b", "سرعت"),
    (r"\bconnection\b", "اتصال"), (r"\bconnect\b", "اتصال"), (r"\bstability\b", "پایداری"),
]


def log(repo, since):
    try:
        out = subprocess.run(["git", "-C", repo, "log", "--no-merges", f"--since={since}", "--format=%s"],
                             capture_output=True, text=True, timeout=60).stdout
        return [l.strip() for l in out.splitlines() if l.strip()]
    except Exception:
        return []


def items_for(subjects, default_platform):
    core, feats = [], []
    for s in subjects:
        if NOISE.search(s):
            continue
        m = CORE.match(s)
        if m:
            plat = (m.group(2) or "").lower() or default_platform
            for part in m.group(3).split(","):
                mm = re.match(r"\s*(.+?)\s+(\S+)\s*(→|->)\s*(\S+)\s*$", part)
                if mm:
                    core.append({"text": f"🔄 {mm.group(1)} به نسخهٔ {mm.group(4)} به‌روز شد", "platform": plat})
            continue
        t = s.split(";")[0]
        for pat, fa in WORDS:
            t = re.sub(pat, fa, t, flags=re.I)
        feats.append({"text": "✨ " + t[:90], "platform": default_platform})
    return core, feats


def main():
    version, since, win, andr, out_json, out_md = sys.argv[1:7]
    items = []
    try:
        wc, wf = items_for(log(win, since), "all")
        ac, af = items_for(log(andr, since), "android")
        seen, items = set(), []
        for it in wc + ac + wf + af:
            if it["text"] not in seen:
                seen.add(it["text"]); items.append(it)
        items = items[:8]
    except Exception as e:
        print("changelog error:", e)
    if not items:
        items = [{"text": FALLBACK, "platform": "all"}]
    json.dump({"version": version, "items": items}, open(out_json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    tag = {"android": " (اندروید)", "windows": " (ویندوز)"}
    open(out_md, "w", encoding="utf-8").write(
        "## تغییرات این نسخه\n" + "".join(f"- {i['text']}{tag.get(i['platform'], '')}\n" for i in items) + "\n")
    print(json.dumps(items, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("changelog fatal:", e)

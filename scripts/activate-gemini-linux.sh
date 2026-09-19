#!/usr/bin/env bash
# 激活 Chrome 隐藏的原生 Gemini 侧边栏（Glic）— Linux 移植版
# 基于 https://github.com/345632699/activate-chrome-gemini (macOS 版) 改写
set -euo pipefail

CHROME_BIN="google-chrome"
USER_DATA="$HOME/.config/google-chrome"
LOCAL_STATE="$USER_DATA/Local State"

say() { printf '%s\n' "$*"; }

# ---------- 1. 环境检查 ----------
command -v "$CHROME_BIN" >/dev/null 2>&1 || { say "❌ 未找到 google-chrome"; exit 1; }
[ -f "$LOCAL_STATE" ] || { say "❌ 未找到 Local State（$LOCAL_STATE）"; exit 1; }
command -v python3 >/dev/null 2>&1 || { say "❌ 需要 python3"; exit 1; }

VERSION=$(google-chrome --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
say "Chrome 版本: ${VERSION:-未知}"
say "User Data:  $USER_DATA"

# ---------- 2. 退出 Chrome ----------
if pgrep -f "/opt/google/chrome/chrome" >/dev/null 2>&1; then
  say "→ 正在退出 Chrome…"
  pkill -TERM -f "/opt/google/chrome/chrome" 2>/dev/null || true
  for _ in $(seq 1 30); do pgrep -f "/opt/google/chrome/chrome" >/dev/null 2>&1 || break; sleep 0.5; done
  if pgrep -f "/opt/google/chrome/chrome" >/dev/null 2>&1; then
    say "→ 优雅退出超时，强制结束…"
    pkill -KILL -f "/opt/google/chrome/chrome" 2>/dev/null || true
    sleep 1
  fi
  pgrep -f "/opt/google/chrome/chrome" >/dev/null 2>&1 && { say "❌ Chrome 无法退出，请手动处理后重试"; exit 1; }
else
  say "→ Chrome 已处于退出状态"
fi

# ---------- 3. 备份 ----------
BACKUP="$LOCAL_STATE.backup-$(date +%Y%m%d-%H%M%S)"
cp "$LOCAL_STATE" "$BACKUP"
say "→ 已备份 Local State → $(basename "$BACKUP")"

# ---------- 4. 写配置 ----------
python3 - "$USER_DATA" "${VERSION:-}" <<'PYEOF'
import glob
import json
import os
import sys

user_data, version = sys.argv[1], sys.argv[2]

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def save(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))

ls_path = os.path.join(user_data, "Local State")
ls = load(ls_path)

ls["variations_permanent_overridden_country"] = "us"
ls["variations_country"] = "us"
ls["variations_safe_seed_permanent_consistency_country"] = "us"
ls["variations_safe_seed_session_consistency_country"] = "us"

pair = ls.get("variations_permanent_consistency_country")
if version:
    ls["variations_permanent_consistency_country"] = [version, "us"]
elif isinstance(pair, list) and len(pair) == 2:
    pair[1] = "us"

labs = ls.setdefault("browser", {}).setdefault("enabled_labs_experiments", [])
if "glic@1" not in labs:
    labs.append("glic@1")

save(ls_path, ls)
print("→ Local State: 国家覆盖=us（含持久覆盖字段），glic@1 已确保启用")

profiles = [d for d in sorted(glob.glob(os.path.join(user_data, "Default"))
        + glob.glob(os.path.join(user_data, "Profile *")))
        if os.path.isdir(d) and os.path.isfile(os.path.join(d, "Preferences"))]

for prof in profiles:
    pref_path = os.path.join(prof, "Preferences")
    p = load(pref_path)
    p.setdefault("sync", {})["glic_rollout_eligibility"] = True
    p.setdefault("glic", {})["pinned_to_tabstrip"] = True
    save(pref_path, p)
    print(f"→ {os.path.basename(prof)}: rollout_eligibility=true, pinned_to_tabstrip=true")

print(f"→ 共处理 {len(profiles)} 个 Profile")
PYEOF

# ---------- 5. 带参重启 ----------
say "→ 启动 Chrome（--glic-dev --variations-override-country=us）…"
nohup "$CHROME_BIN" --glic-dev --variations-override-country=us >/dev/null 2>&1 &
sleep 3

if pgrep -f "/opt/google/chrome/chrome.*--glic-dev" >/dev/null 2>&1; then
  say "✅ Chrome 已带参启动，配置全部写入"
else
  say "⚠️ 未检测到带参的 Chrome 进程，请重跑一次本脚本"
fi

say ""
say "接下来："
say "  1. 看浏览器右上角是否出现 ✨ Gemini 按钮"
say "  2. 出现后立即点开完成首次登录/授权（FRE），此后正常启动也会保留入口"
say "  3. 若未出现，打开 chrome://glic/internals 查看哪项是 🚫，对照文档排查"

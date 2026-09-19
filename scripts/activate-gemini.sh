#!/usr/bin/env bash
# 激活 Chrome 隐藏的原生 Gemini 侧边栏（Glic）— 一键脚本
# 用法:
#   bash activate-gemini.sh        # 交互确认后执行
#   bash activate-gemini.sh -y     # 跳过确认（可用于自动化）
# 做了什么:
#   1. 完全退出 Chrome（优雅退出，失败则强制结束）
#   2. 备份 Local State
#   3. 写入持久国家覆盖 + 灰度资格 + 按钮固定（Local State 和所有 Profile）
#   4. 确保 chrome://flags 的 glic@1 已启用
#   5. 带 --glic-dev --variations-override-country=us 重启 Chrome
# 回滚: 用同目录下自动生成的 Local State.backup-* 覆盖回 Local State 即可

set -euo pipefail

CHROME_APP="/Applications/Google Chrome.app"
CHROME_BIN="$CHROME_APP/Contents/MacOS/Google Chrome"
USER_DATA="$HOME/Library/Application Support/Google/Chrome"
LOCAL_STATE="$USER_DATA/Local State"

say() { printf '%s\n' "$*"; }

# ---------- 1. 环境检查 ----------
[ -d "$CHROME_APP" ] || { say "❌ 未找到 Google Chrome（$CHROME_APP）"; exit 1; }
[ -f "$LOCAL_STATE" ] || { say "❌ 未找到 Local State（$LOCAL_STATE）"; exit 1; }
command -v python3 >/dev/null 2>&1 || { say "❌ 需要 python3"; exit 1; }

VERSION=$(defaults read "$CHROME_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)
say "Chrome 版本: ${VERSION:-未知}"
say "User Data:  $USER_DATA"

# ---------- 2. 退出 Chrome ----------
if pgrep -x "Google Chrome" >/dev/null 2>&1; then
  if [ "${1:-}" != "-y" ]; then
    read -r -p "需要先完全退出 Chrome（未保存的表单内容会丢失），继续？[y/N] " ans
    case "$ans" in [Yy]*) ;; *) say "已取消"; exit 1 ;; esac
  fi
  say "→ 正在退出 Chrome…"
  osascript -e 'quit app "Google Chrome"' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do pgrep -x "Google Chrome" >/dev/null 2>&1 || break; sleep 0.5; done
  if pgrep -x "Google Chrome" >/dev/null 2>&1; then
    say "→ 优雅退出超时，强制结束…"
    killall "Google Chrome" >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do pgrep -x "Google Chrome" >/dev/null 2>&1 || break; sleep 0.5; done
  fi
  pgrep -x "Google Chrome" >/dev/null 2>&1 && { say "❌ Chrome 无法退出，请手动处理后重试"; exit 1; }
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

# --- Local State：持久国家覆盖 + flags ---
ls_path = os.path.join(user_data, "Local State")
ls = load(ls_path)

ls["variations_permanent_overridden_country"] = "us"   # 核心：持久覆盖，压过服务器下发
ls["variations_country"] = "us"
ls["variations_safe_seed_permanent_consistency_country"] = "us"
ls["variations_safe_seed_session_consistency_country"] = "us"

# variations_permanent_consistency_country 是 [版本, 国家] 二元组
pair = ls.get("variations_permanent_consistency_country")
if version:
    ls["variations_permanent_consistency_country"] = [version, "us"]
elif isinstance(pair, list) and len(pair) == 2:
    pair[1] = "us"

# 确保 chrome://flags 的 Glic = Enabled（glic@1）
labs = ls.setdefault("browser", {}).setdefault("enabled_labs_experiments", [])
if "glic@1" not in labs:
    labs.append("glic@1")

save(ls_path, ls)
print("→ Local State: 国家覆盖=us（含持久覆盖字段），glic@1 已确保启用")

# --- 所有 Profile：灰度资格 + 按钮固定 ---
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
open -a "Google Chrome" --args --glic-dev --variations-override-country=us
sleep 3

if ps ax -o command= | grep -v grep | grep -F "$CHROME_BIN" | grep -q -- "--glic-dev"; then
  say "✅ Chrome 已带参启动，配置全部写入"
else
  say "⚠️ Chrome 已启动但未检测到参数（可能退出不彻底被旧实例唤起），请重跑一次本脚本"
fi

say ""
say "接下来："
say "  1. 看浏览器右上角是否出现 ✨ Gemini 按钮"
say "  2. 出现后立即点开完成首次登录/授权（FRE），此后正常启动也会保留入口"
say "  3. 若未出现，打开 chrome://glic/internals 查看哪项是 🚫，对照技能文档排查"

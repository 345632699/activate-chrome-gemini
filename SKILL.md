---
name: activate-chrome-gemini
description: 激活 Chrome 隐藏的原生 Gemini 侧边栏（内部代号 Glic）。当用户想让 Chrome 右上角出现 Gemini ✨ 按钮、激活 Chrome 自带 AI 助手、打开 Glic/Gemini in Chrome 侧边栏，或按知乎教程修改 Local State（Variations_country / is_glic_eligible）却无效时使用。macOS 为主，含一键脚本、门控原理、诊断方法和持久化方案。
---

# 激活 Chrome 原生 Gemini 侧边栏（Glic）

## 快速路径：一键脚本

macOS 上优先执行技能自带脚本（自动完成退出、备份、写入、带参重启全流程）：

```bash
bash ~/.claude/skills/activate-chrome-gemini/scripts/activate-gemini.sh       # 交互确认
bash ~/.claude/skills/activate-chrome-gemini/scripts/activate-gemini.sh -y   # 跳过确认
```

脚本做的事（与门控一一对应）：

1. 优雅退出 Chrome（失败则 `killall`，确保配置文件不被内存态覆盖）
2. 备份 `Local State` → `Local State.backup-时间戳`
3. `Local State`：`variations_permanent_overridden_country="us"`（**核心持久覆盖**）+ `variations_country` / safe_seed 各字段 = "us" + 确保 `browser.enabled_labs_experiments` 含 `glic@1`
4. 所有 Profile 的 `Preferences`：`sync.glic_rollout_eligibility=true` + `glic.pinned_to_tabstrip=true`
5. `open -a "Google Chrome" --args --glic-dev --variations-override-country=us` 重启并验证参数

**执行后必须告知用户：按钮出现后立即点开完成首次登录/授权（FRE）**——完成后，后续正常启动（不带参数）时入口按 anchor 逻辑保留。

## 门控原理（为什么照网上教程改没用）

按钮判定在 Chromium 源码 `chrome/browser/glic/public/glic_enabling.cc` 的 `ShouldShowGlicButton()` → `IsEnabled()`，以下条件**必须同时满足**：

| 门控 | 判定内容 | 满足方法 |
|---|---|---|
| feature_flag | `kGlic` 特性开启 | `chrome://flags` 搜 Glic → Enabled（脚本写 `glic@1`） |
| country filter | **permanent country** 在允许名单（us, ca, hk, jp, sg…**不含 cn**） | `variations_permanent_overridden_country="us"` |
| locale filter | 界面语言在允许名单（默认**含 zh-CN**，无需改英文） | 默认即过 |
| is_rolled_out | `kGlicRollout` 开启，或灰度资格 pref 为 true，或有 AI 订阅 | `sync.glic_rollout_eligibility=true` |
| primary_account_is_capable | Google 账号有 "Gemini in Chrome" capability（服务端下发，中国区账号没有） | `--glic-dev` 启动参数绕过；FRE 完成后入口保留 |
| chrome policy | `browser.gemini_settings` == 0（Enabled） | 默认即过 |
| remote admin/other | `glic.user_status` 缓存无禁用状态 | 默认即过 |
| 常规条件 | Regular profile、已登录 Google 账号、RAM 达标 | 用户侧满足 |

### 陷阱（脚本已规避，手动操作时注意）

1. **`is_glic_eligible` 会被 Chrome 启动时重算并覆盖回 false**——手改无效，不要碰它。
2. **`variations_country` 会被 variations 种子按联网 IP 重新地理定位刷新**——直接改它只撑到下次取种子。真正持久的是 `variations_permanent_overridden_country`（源码 `LoadPermanentConsistencyCountry()` 中它的优先级高于一切）。
3. **国家过滤只看 permanent country**（session country 仅在 `kGlicUseSessionCountryForFiltering` 开启时参与，且是 OR 关系）。
4. macOS 上 Chrome 界面语言不读 Profile 的 `intl.app_locale`，跟随系统 App 语言——但 zh-CN 本来就允许，无需改英文。
5. **改任何 Chrome 配置前必须完全退出 Chrome**（`pgrep -x "Google Chrome"` 确认），否则退出时被覆盖。改前备份。

## 诊断：chrome://glic/internals

**正确地址是 `chrome://glic/internals`**（`chrome://glic-internals` 不存在，用户常记错）。页面直接列出每道门的状态，红叉 🚫 对照上表定位：

- `Passed country filter` 🚫 → permanent country 为 cn → 跑脚本（或手写 `variations_permanent_overridden_country` + 带参重启）
- `Pref or flag based rollout` 🚫 → `sync.glic_rollout_eligibility` 未写入
- `Account ... Gemini in Chrome capability` 🚫 → 账号地区问题 → `--glic-dev` 绕过（注意：`--glic-dev` 生效时此项显示 ✅ 是被跳过的假象）
- `Passed locale filter` 🚫 → 极少见，需改界面语言为 en-US
- 页面底部直接显示 Locale、Permanent/Session Country Code、Guest URL，可核对

辅助页面：`chrome://settings/ai/gemini`（Glic 设置页）、`chrome://version`（核对命令行参数）。

## 手动步骤（脚本不可用时的替代 / 其他系统参考）

路径：macOS `~/Library/Application Support/Google/Chrome/`；Windows `%LOCALAPPDATA%\Google\Chrome\User Data\`；Linux `~/.config/google-chrome/`

1. 完全退出 Chrome，备份 `Local State`
2. `Local State` 写入：`variations_permanent_overridden_country="us"`、`variations_country="us"`、`variations_safe_seed_permanent_consistency_country="us"`、`variations_safe_seed_session_consistency_country="us"`、`variations_permanent_consistency_country=["<版本>","us"]`
3. 每个 Profile 的 `Preferences` 写入：`sync.glic_rollout_eligibility=true`、`glic.pinned_to_tabstrip=true`
4. `chrome://flags` 确认 Glic = Enabled
5. macOS 带参重启：`open -a "Google Chrome" --args --glic-dev --variations-override-country=us`（`open --args` 只在冷启动时传参，务必先完全退出）

## 命令行开关速查

| 开关 | 作用 |
|---|---|
| `--glic-dev` | 官方开发后门，跳过灰度 + 账号能力两道检查（每次启动需带） |
| `--variations-override-country=us` | 会话级国家覆盖（不跨会话持久） |
| `--variations-seed-fetch-interval` / `--disable-variations-seed-fetch` | 可选：干扰种子拉取，非必需 |

## 回滚

退出 Chrome → `cp "Local State.backup-<时间戳>" "Local State"` → 重启。命令行参数只在带参会话生效，重启即消失；`variations_permanent_overridden_country` 需删除或改回才失效。

## 依据（Chromium 源码，2026-09 main 分支核实）

- `chrome/browser/glic/public/glic_enabling.cc` — 全部门控判定（`ShouldShowGlicButton` / `IsEnabled` / `EvaluateCountryEnablement`）
- `components/variations/service/variations_field_trial_creator.cc` — `GetLatestCountry()` / `LoadPermanentConsistencyCountry()`：覆盖开关与持久 pref 的优先级
- `components/variations/variations_switches.cc` — `--variations-override-country` 等开关定义
- `components/variations/pref_names.h` — `variations_permanent_overridden_country` 等 pref 名
- `chrome/browser/glic/glic_pref_names.h` — `sync.glic_rollout_eligibility`、`glic.pinned_to_tabstrip`
- `chrome/common/chrome_switches.h` — `--glic-dev` 定义
- `chrome/common/webui_url_constants.h` — `chrome://glic/` 系列 URL（internals 在其 `/internals` 路径下）

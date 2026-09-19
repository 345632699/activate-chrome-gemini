# activate-chrome-gemini

一键激活 Chrome 隐藏的原生 Gemini 侧边栏（内部代号 **Glic**），让浏览器右上角出现 ✨ Gemini 按钮——可直接总结网页、多标签对比、写邮件，无需在标签页之间横跳。

> 原理基于 Chromium 源码分析（`chrome/browser/glic/public/glic_enabling.cc`），不是玄学改注册表。

## 快速开始（macOS）

```bash
bash scripts/activate-gemini.sh
```

脚本会自动完成：

1. 完全退出 Chrome（优雅退出，失败才强制结束）
2. 备份 `Local State`
3. 写入持久国家覆盖（`variations_permanent_overridden_country=us`）
4. 写入灰度资格（`sync.glic_rollout_eligibility=true`）和按钮固定
5. 确保 `chrome://flags` 的 Glic = Enabled
6. 带 `--glic-dev --variations-override-country=us` 重启 Chrome 并验证参数

**重要**：按钮出现后，立即点开完成首次登录/授权（FRE）。完成后，以后正常双击启动（不带参数）入口也会保留。

## 为什么网上教程改了没用

流行教程让你改 `Variations_country` → "us"、`is_glic_eligible` → "true"，但按钮判定要**同时**过 8 道门，教程只覆盖了一部分：

| 门控 | 判定内容 | 满足方法 |
|---|---|---|
| feature_flag | `kGlic` 特性开启 | `chrome://flags` Glic → Enabled |
| country filter | **permanent country** 在允许名单（**不含 cn**） | `variations_permanent_overridden_country="us"` |
| locale filter | 界面语言在允许名单（默认**含 zh-CN**，无需改英文） | 默认即过 |
| is_rolled_out | 灰度开启 / 灰度资格 / AI 订阅 | `sync.glic_rollout_eligibility=true` |
| 账号能力 | Google 账号有 "Gemini in Chrome" capability（中国区账号没有） | `--glic-dev` 启动参数绕过 |
| 企业策略 | `browser.gemini_settings` == Enabled | 默认即过 |
| 服务器状态 | `glic.user_status` 缓存无禁用 | 默认即过 |
| 常规条件 | Regular profile、已登录、RAM 达标 | 正常满足 |

### 三个关键陷阱

1. **`is_glic_eligible` 会被 Chrome 启动时重算覆盖回 false**——手改无效
2. **`variations_country` 会被服务器按联网 IP 重新地理定位刷新**——直接改它只撑到下次取种子；持久生效的是 `variations_permanent_overridden_country`（源码里优先级最高）
3. macOS 界面语言跟随系统 App 语言，不读 Profile 里的 `intl.app_locale`——但 zh-CN 本来就允许，不用改英文

## 诊断

按钮没出现时，打开：

```
chrome://glic/internals
```

（注意：不是 `chrome://glic-internals`，这个地址不存在。）页面直接列出每道门的 ✅/🚫 状态，红叉对照上表即可定位。

## 回滚

脚本每次执行前都会自动备份。出问题时：

```bash
cd ~/Library/Application\ Support/Google/Chrome
cp "Local State.backup-<时间戳>" "Local State"
```

命令行参数只在带参会话生效，重启即消失；`variations_permanent_overridden_country` 删掉即失效。

## 作为 Claude Code 技能使用

本仓库同时是一个 [Claude Code](https://claude.com/claude-code) 技能：

```bash
git clone https://github.com/<你的用户名>/activate-chrome-gemini ~/.claude/skills/activate-chrome-gemini
```

之后对 Claude 说"激活 Chrome Gemini 侧边栏"即可触发完整流程（含诊断和排查）。

## 参考

- [知乎：手把手教你激活 Chrome 隐藏的原生 Gemini 侧边栏](https://zhuanlan.zhihu.com/p/2004545554017965494)（基础教程，本方案在其基础上补齐了持久化和门控分析）
- Chromium 源码：`chrome/browser/glic/public/glic_enabling.cc`、`components/variations/service/variations_field_trial_creator.cc`（2026-09 main 分支核实）

## License

[MIT](LICENSE)

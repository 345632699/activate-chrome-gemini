#Requires -Version 5.1
# 激活 Chrome 隐藏的原生 Gemini 侧边栏（Glic）— Windows 移植版
# 用法（PowerShell）:
#   .\scripts\activate-gemini-windows.ps1            # 交互确认后执行
#   .\scripts\activate-gemini-windows.ps1 -y         # 跳过确认
# 做了什么（与 macOS/Linux 版一致）:
#   1. 完全退出 Chrome（优雅退出，失败则强制结束）
#   2. 备份 Local State
#   3. 写入持久国家覆盖 + 灰度资格 + 按钮固定（Local State 和所有 Profile）
#   4. 确保 chrome://flags 的 glic@1 已启用
#   5. 带 --glic-dev --variations-override-country=us 重启 Chrome
# 回滚: 用同目录自动生成的 Local State.backup-* 覆盖回 Local State
# 注意: 若被 ExecutionPolicy 拦截，用 powershell -ExecutionPolicy Bypass -File 运行

param([switch]$y)

$ErrorActionPreference = "Stop"

# ---------- 1. 环境检查 ----------
$chromeCandidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chromeExe = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chromeExe) {
    Write-Host "[X] 未找到 Google Chrome，已检查路径:"; $chromeCandidates | ForEach-Object { Write-Host "    $_" }
    exit 1
}

$userData   = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$localState = Join-Path $userData "Local State"
if (-not (Test-Path $localState)) {
    Write-Host "[X] 未找到 Local State（$localState），请先运行一次 Chrome"
    exit 1
}

$version = (Get-Item $chromeExe).VersionInfo.ProductVersion
Write-Host "Chrome 版本: $version"
Write-Host "chrome.exe:  $chromeExe"
Write-Host "User Data:   $userData"

# ---------- 2. 退出 Chrome ----------
$procs = Get-Process chrome -ErrorAction SilentlyContinue
if ($procs) {
    if (-not $y) {
        $ans = Read-Host "需要先完全退出 Chrome（未保存的表单内容会丢失），继续？[y/N]"
        if ($ans -notmatch '^[Yy]$') { Write-Host "已取消"; exit 1 }
    }
    Write-Host "-> 正在退出 Chrome..."
    foreach ($p in $procs) { $null = $p.CloseMainWindow() }   # 优雅关闭窗口
    for ($i = 0; $i -lt 30; $i++) {
        if (-not (Get-Process chrome -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process chrome -ErrorAction SilentlyContinue) {
        Write-Host "-> 优雅退出超时，强制结束..."
        Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    if (Get-Process chrome -ErrorAction SilentlyContinue) {
        Write-Host "[X] Chrome 无法退出，请手动处理后重试"
        exit 1
    }
} else {
    Write-Host "-> Chrome 已处于退出状态"
}

# ---------- 3. 备份 ----------
$stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$localState.backup-$stamp"
Copy-Item $localState $backup
Write-Host "-> 已备份 Local State -> $(Split-Path $backup -Leaf)"

# ---------- 4. 写配置 ----------
# Chrome 的 JSON 为 UTF-8 无 BOM，必须用 WriteAllText 保持一致
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Json([string]$path) {
    (Get-Content $path -Raw -Encoding UTF8) | ConvertFrom-Json
}
function Write-Json([string]$path, $obj) {
    [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 100), $utf8NoBom)
}
function Set-Member($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.PSObject.Properties[$name].Value = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# --- Local State: 持久国家覆盖 + flags ---
$ls = Read-Json $localState

Set-Member $ls "variations_permanent_overridden_country" "us"   # 核心: 持久覆盖，压过服务器下发
Set-Member $ls "variations_country" "us"
Set-Member $ls "variations_safe_seed_permanent_consistency_country" "us"
Set-Member $ls "variations_safe_seed_session_consistency_country" "us"

# variations_permanent_consistency_country 是 [版本, 国家] 二元组
$pcc = $ls.variations_permanent_consistency_country
if ($pcc -is [array] -and $pcc.Count -eq 2) { Set-Member $ls "variations_permanent_consistency_country" @($version, "us") }
elseif ($version)                            { Set-Member $ls "variations_permanent_consistency_country" @($version, "us") }

# 确保 chrome://flags 的 Glic = Enabled（glic@1）
$browser = $ls.browser
if (-not $browser) {
    $browser = New-Object PSObject
    Set-Member $ls "browser" $browser
}
$labs = $browser.enabled_labs_experiments
if (-not $labs) {
    $labs = @()
    Set-Member $browser "enabled_labs_experiments" $labs
    $labs = $browser.enabled_labs_experiments
}
if (@($labs) -notcontains "glic@1") {
    Set-Member $browser "enabled_labs_experiments" (@($labs) + "glic@1")
}

Write-Json $localState $ls
Write-Host "-> Local State: 国家覆盖=us（含持久覆盖字段），glic@1 已确保启用"

# --- 所有 Profile: 灰度资格 + 按钮固定 ---
$profiles = Get-ChildItem $userData -Directory | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" }
$count = 0
foreach ($prof in $profiles) {
    $prefPath = Join-Path $prof.FullName "Preferences"
    if (-not (Test-Path $prefPath)) { continue }
    $p = Read-Json $prefPath

    $sync = $p.sync
    if (-not $sync) { $sync = New-Object PSObject; Set-Member $p "sync" $sync }
    Set-Member $sync "glic_rollout_eligibility" $true

    $glic = $p.glic
    if (-not $glic) { $glic = New-Object PSObject; Set-Member $p "glic" $glic }
    Set-Member $glic "pinned_to_tabstrip" $true

    Write-Json $prefPath $p
    Write-Host "-> $($prof.Name): rollout_eligibility=true, pinned_to_tabstrip=true"
    $count++
}
Write-Host "-> 共处理 $count 个 Profile"

# ---------- 5. 带参重启 ----------
Write-Host "-> 启动 Chrome（--glic-dev --variations-override-country=us）..."
Start-Process -FilePath $chromeExe -ArgumentList "--glic-dev", "--variations-override-country=us"
Start-Sleep -Seconds 3

$running = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
    Where-Object { $_.CommandLine -match "--glic-dev" }
if ($running) {
    Write-Host "[OK] Chrome 已带参启动，配置全部写入"
} else {
    Write-Host "[!] Chrome 已启动但未检测到参数（可能退出不彻底被旧实例唤起），请重跑一次本脚本"
}

Write-Host ""
Write-Host "接下来："
Write-Host "  1. 看浏览器右上角是否出现 [G] Gemini 按钮"
Write-Host "  2. 出现后立即点开完成首次登录/授权（FRE），此后正常启动也会保留入口"
Write-Host "  3. 若未出现，打开 chrome://glic/internals 查看哪项是 [X]，对照文档排查"

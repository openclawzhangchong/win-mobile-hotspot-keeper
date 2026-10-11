<#
    install.ps1  —  Windows Mobile Hotspot Keeper 安装器
    ------------------------------------------------------------------
    版本：v1.1.0（2026-10-11）
    一键完成：
      1. 注册「任务计划程序」任务，登录后自动开启移动热点
      2. 每 5 分钟自动复查一次，热点被关闭则自动重开（保活）
      3. 在桌面生成一个双击即用的快捷启停器

    静默说明：计划任务不直接调用 powershell.exe（那会瞬间闪一个黑框），
    而是经由 run-hotspot.vbs（WScript.Shell.Run 窗口模式 0）真正零窗口启动，
    屏幕上不会出现任何闪烁。

    用法（以管理员身份运行 Windows PowerShell 5.1）：
        powershell -ExecutionPolicy Bypass -File install.ps1

    可选参数：
      -TaskName <string>   计划任务名称，默认 XiaoZhiHotspotKeeper
      -IntervalMinutes <int>  保活复查间隔（分钟），默认 5
      -NoDesktopShortcut   不生成桌面启动器
      -Uninstall           卸载：删除计划任务与桌面启动器

    许可：MIT
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'XiaoZhiHotspotKeeper',
    [int]$IntervalMinutes = 5,
    [switch]$NoDesktopShortcut,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# ---------- 公共 ----------
function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[ERROR] 请以管理员身份运行本脚本。" -ForegroundColor Red
        Write-Host "        右键 PowerShell → 以管理员身份运行，然后执行：" -ForegroundColor Red
        Write-Host "        powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -ForegroundColor Yellow
        exit 2
    }
}

$here      = Split-Path -Parent $PSCommandPath
$mainPs1   = Join-Path $here 'hotspot-on.ps1'
$vbsPath   = Join-Path $here 'run-hotspot.vbs'
$logPath   = Join-Path $here 'hotspot.log'
$desktop   = [Environment]::GetFolderPath('Desktop')
$launcher  = Join-Path $desktop '开启移动热点.bat'

Assert-Admin

# ============================================================
#  卸载模式
# ============================================================
if ($Uninstall) {
    Write-Host "=== 卸载 Windows Mobile Hotspot Keeper ===" -ForegroundColor Cyan

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[OK] 已删除计划任务：$TaskName" -ForegroundColor Green
    } else {
        Write-Host "[--] 计划任务不存在：$TaskName" -ForegroundColor DarkGray
    }

    if (Test-Path $launcher) {
        Remove-Item $launcher -Force
        Write-Host "[OK] 已删除桌面启动器：$launcher" -ForegroundColor Green
    } else {
        Write-Host "[--] 桌面启动器不存在" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "主脚本与日志保留在：$here" -ForegroundColor Gray
    Write-Host "如需彻底清除，手动删除该目录即可。" -ForegroundColor Gray
    exit 0
}

# ============================================================
#  安装模式
# ============================================================
Write-Host "=== 安装 Windows Mobile Hotspot Keeper ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $mainPs1)) {
    Write-Host "[ERROR] 找不到主脚本：$mainPs1" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $vbsPath)) {
    Write-Host "[ERROR] 找不到静默启动器：$vbsPath" -ForegroundColor Red
    exit 1
}

$ps51     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$currentUser    = [Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "主脚本      : $mainPs1"
Write-Host "静默启动器  : $vbsPath"
Write-Host "日志        : $logPath"
Write-Host "运行账户    : $currentUser"
Write-Host "保活间隔    : 每 $IntervalMinutes 分钟"
Write-Host ""

# ---------- 1. 生成计划任务 XML ----------
$intervalIso = "PT${IntervalMinutes}M"

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Keep Windows Mobile Hotspot turned ON. Starts the WinRT tethering script at logon and rechecks every $IntervalMinutes minute(s).</Description>
    <URI>\$TaskName</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
    </LogonTrigger>
    <TimeTrigger>
      <StartBoundary>2026-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>$intervalIso</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$currentUserSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$env:SystemRoot\System32\wscript.exe</Command>
      <Arguments>//B //Nologo "$vbsPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# 写一份 XML 存档（便于排查），再用原生 cmdlet 注册
$xmlPath = Join-Path $here 'task.xml'
[System.IO.File]::WriteAllText($xmlPath, $xml, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "[1/3] 注册计划任务：$TaskName ..." -ForegroundColor Yellow
try {
    Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force -ErrorAction Stop | Out-Null
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "      [OK] 已注册（State=$($t.State), RunLevel=$($t.Principal.RunLevel)）" -ForegroundColor Green
} catch {
    Write-Host "      [ERROR] 注册失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ---------- 2. 生成桌面启动器 ----------
if (-not $NoDesktopShortcut) {
    Write-Host "[2/3] 生成桌面启动器 ..." -ForegroundColor Yellow
    $bat = @"
@echo off
chcp 65001 >nul 2>&1
title Mobile Hotspot Launcher

set "PS1=$mainPs1"
set "LOG=$logPath"

if not exist "%PS1%" (
    echo [ERROR] Script not found: %PS1%
    pause
    exit /b 2
)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================
echo   Turning ON Windows Mobile Hotspot...
echo ============================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -LogFile "%LOG%"

echo.
if %errorlevel% equ 0 (
    echo [OK] Mobile hotspot is ON.
) else (
    echo [FAILED] Could not confirm hotspot is ON. Exit code: %errorlevel%
    echo See log: %LOG%
)

echo.
echo Closing in 5 seconds...
timeout /t 5 >nul
exit /b %errorlevel%
"@
    # .bat 用 ANSI/GBK 写入，避免 cmd 中文乱码
    $enc = [System.Text.Encoding]::GetEncoding('GB2312')
    [System.IO.File]::WriteAllText($launcher, $bat, $enc)
    Write-Host "      [OK] 已生成：$launcher" -ForegroundColor Green
} else {
    Write-Host "[2/3] 跳过桌面启动器（-NoDesktopShortcut）" -ForegroundColor DarkGray
}

# ---------- 3. 立即跑一次验证 ----------
Write-Host "[3/3] 立即执行一次以验证 ..." -ForegroundColor Yellow
try {
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 8
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    if ($info.LastTaskResult -eq 0) {
        Write-Host "      [OK] 执行成功（LastResult=0）" -ForegroundColor Green
    } else {
        Write-Host "      [WARN] LastResult=$($info.LastTaskResult)，请查看日志：$logPath" -ForegroundColor Yellow
    }
    Write-Host "      下次自动运行：$($info.NextRunTime)" -ForegroundColor Gray
} catch {
    Write-Host "      [WARN] 立即执行失败：$($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 安装完成 ===" -ForegroundColor Cyan
Write-Host "  任务名：$TaskName" -ForegroundColor White
Write-Host "  登录后自动开启，之后每 $IntervalMinutes 分钟复查保活。" -ForegroundColor White
Write-Host "  桌面启动器：双击即可手动开启热点（会弹一次 UAC）。" -ForegroundColor White
Write-Host "  日志：$logPath" -ForegroundColor White
Write-Host ""
Write-Host "  卸载：powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Uninstall" -ForegroundColor Gray

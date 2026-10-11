# Changelog

本文件记录本项目的版本变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

---

## [1.1.0] - 2026-10-11

### 修复 —— 计划任务触发时屏幕闪现黑框

**现象**：升级到 v1.0 并运行一天后，发现屏幕**每隔 5 分钟闪一下黑框**。

**根因**：
计划任务每 5 分钟直接调用 `powershell.exe`。虽然任务配置里已设置
`Hidden=true`、命令行也加了 `-WindowStyle Hidden`，但 **`powershell.exe` 是控制台子系统程序**——
Windows 在进程启动的**最初几毫秒必然创建一个控制台窗口**，然后才把它隐藏。
用户看到的正是这一瞬间的窗口。**这一点无法在 PowerShell 脚本内部解决**，
必须在「创建进程」时就指定无窗口。

**修复**：
- 新增 `run-hotspot.vbs` 静默启动器，使用
  `WScript.Shell.Run(cmd, 0, True)`——第 2 个参数 `0` 表示窗口**完全不显示**，
  从进程创建那一刻起就没有窗口，**屏幕上不会有任何闪烁**。
- 计划任务改为调用 `wscript.exe //B //Nologo run-hotspot.vbs`，
  不再直接调用 `powershell.exe`。

### 修复 —— 日志无限膨胀

**现象**：v1.0 每次运行都写一行日志，一天下来滚了 241 行（每 5 分钟一条 = 约 288 行/天）。

**修复**：
静默模式（计划任务所用的 `-Quiet`）下调整日志策略——
**只在热点状态真正发生变化时记录**：

- 热点本就正常开着 → **不写日志**（绝大多数情况）；
- 热点被关、脚本把它重新开启 → 写一行 `[OK] 完成：热点已开启`；
- 出现异常 → 写 `[ERROR]`。

### 变更

- `hotspot-on.ps1`：`Write-Log` 增加 `-Always` 开关；`-Quiet` 模式下
  `INFO` / `DEBUG` 一律不落盘，只有 `OK` / `WARN` / `ERROR` 才写入。
- `install.ps1`：计划任务 Action 由 `powershell.exe` 改为
  `wscript.exe //B //Nologo run-hotspot.vbs`；新增对 `run-hotspot.vbs` 的存在性校验。
- 新增文件：`run-hotspot.vbs`。
- 脚本头部补充版本号与静默调用说明。

### 实测（Windows 11 25H2 / Windows PowerShell 5.1）

| 场景 | 结果 |
|---|---|
| VBS 调用启动器 | `wscript` 退出码 `0`，**无窗口** |
| 热点本已开启时运行 | 日志行数 **241 → 241**（零增长） |
| 热点关闭后运行 | 成功开启，日志 **241 → 242**（仅新增 1 行），状态恢复 `On` |
| 计划任务手动触发 | `LastResult=0` |

### 升级方法

从 v1.0 升级：把新的三个文件（`hotspot-on.ps1`、`run-hotspot.vbs`、`install.ps1`）
覆盖到原目录，然后**重新运行一次安装器**，即可把计划任务切换到 VBS 静默启动器：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

---

## [1.0.0] - 2026-10-10

### 新增

- 首个公开版本。
- `hotspot-on.ps1`：基于 WinRT API
  （`Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager`）
  检测并开启 Windows「移动热点」，幂等，可重复执行。
- `install.ps1`：一键安装 / 卸载器，自动注册计划任务、生成桌面启动器
  （`开启移动热点.bat`），安装后立即验证一次。
- 计划任务：登录后 30 秒自动开启热点，之后每 5 分钟复查保活。
- 桌面启动器：双击即以管理员权限开启热点（弹一次 UAC）。
- `README.md`（中文，含 FAQ）、`LICENSE`（MIT）、`.gitignore`。

### 已知问题（v1.1.0 已修复）

- 计划任务直接调用 `powershell.exe`，每 5 分钟触发时**屏幕闪一下黑框**。
- 日志每次运行都写一行，**一天约 288 行，持续膨胀**。

### 实测（Windows 11 25H2 / Windows PowerShell 5.1）

- 热点**关闭**状态下运行脚本，成功开启（状态 `Off → On`）。
- 计划任务手动触发返回 `LastResult=0`，日志正常写入。

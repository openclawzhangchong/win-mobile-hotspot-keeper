# Windows 移动热点保活 · Mobile Hotspot Keeper

让 Windows 的**移动热点（Mobile Hotspot）**开机登录后自动开启，并周期复查保活——
热点被系统或其它软件关掉了，会自动重新打开。

附带一个**双击即用的桌面批处理器**，换到别的电脑、没装计划任务时也能一键开热点。

> 只用 Windows 自带的 WinRT API，**不装任何第三方软件、不改注册表、不装驱动**。

---

## 它解决什么问题

Windows 自带的「移动热点」（设置 → 网络和 Internet → 移动热点）有两个烦人之处：

1. **重启 / 重新登录后不会自动打开**，每次都要手动去点一下；
2. **有时会被系统悄悄关掉**（省电策略、驱动重置等），发现时设备已经断网了。

这个工具把这两件事自动化了：

- 登录后 30 秒自动打开热点；
- 之后每 5 分钟复查一次，只要发现是关的，立刻重新打开。

---

## 特性

- **纯系统能力**：基于 `Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager`（WinRT），
  调的就是系统设置里那个开关，最正宗。
- **不碰已废弃的 netsh**：`netsh wlan hostednetwork` 在现代网卡上早已失效，本工具不依赖它。
- **真正零窗口 / 不闪屏**：计划任务经由 VBScript 启动器（`WScript.Shell.Run` 窗口模式 `0`）调用，
  屏幕上**不会有任何黑框闪烁**（直接调 `powershell.exe` 即使加 `-WindowStyle Hidden` 也会瞬闪一下）。
- **日志不膨胀**：静默模式下**只在热点状态发生变化时**写一行；热点一直正常时不写。
- **零残留**：一条命令安装，一条命令卸载。
- **不改你的热点配置**：默认沿用系统里现有的 SSID 和密码，只负责「开」，不偷偷改设置。
- **可选覆盖**：需要的话可以指定 SSID / 密码（见下文）。

---

## 快速开始

### 环境要求

| 项目 | 要求 |
|---|---|
| 系统 | Windows 10 / 11 |
| PowerShell | **Windows PowerShell 5.1**（系统自带，路径 `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`） |
| 权限 | 管理员 |
| 硬件 | 无线网卡驱动支持「移动热点」（绝大多数现代网卡都支持） |

> ⚠️ **不支持 PowerShell 7（Core）**。PS7 加载不了本工具用到的 WinRT 投影。
> 脚本内部已固定走 5.1，你只要用系统自带的那个 PowerShell 就行。

### 安装（一键）

1. 把**整个文件夹**（`hotspot-on.ps1`、`run-hotspot.vbs`、`install.ps1` 三个文件缺一不可）
   放到一个**固定位置**，例如 `C:\Tools\win-mobile-hotspot-keeper`
   （放好后别再挪动，计划任务里记的是绝对路径）。
2. 在该文件夹里**以管理员身份**打开 Windows PowerShell，执行：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

安装器会自动完成：

- 注册计划任务（登录后 30 秒触发 + 每 5 分钟复查保活），经 VBS 静默调用，**不闪屏**
- 在桌面生成启动器 `开启移动热点.bat`
- 立刻跑一次验证，并打印结果

### 卸载

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
```

会删除计划任务和桌面启动器（主脚本与日志保留，手动删目录即可彻底清除）。

---

## 手动使用

### 双击开热点

双击桌面的 **`开启移动热点.bat`** → 弹一次 UAC → 热点开启。

### 直接调用核心脚本

```powershell
# 最简：热点关着就开，已开则跳过
powershell -ExecutionPolicy Bypass -File hotspot-on.ps1

# 指定热点名称与密码（8-63 位）
powershell -ExecutionPolicy Bypass -File hotspot-on.ps1 -Ssid "MyHotspot" -Passphrase "12345678"

# 静默模式 + 写日志（计划任务用的就是这种）
powershell -ExecutionPolicy Bypass -File hotspot-on.ps1 -Quiet -LogFile "hotspot.log"
```

### 参数说明

| 参数 | 说明 |
|---|---|
| `-Ssid <string>` | 可选。要写入的热点名称；省略则沿用现有配置 |
| `-Passphrase <string>` | 可选。热点密码（8–63 位）；省略则沿用现有配置 |
| `-Quiet` | 静默模式，只输出最终结果（供计划任务使用） |
| `-LogFile <path>` | 把日志同时追加写入指定文件 |

### 退出码

| 码 | 含义 |
|---|---|
| `0` | 热点最终处于开启状态（成功） |
| `1` | 执行出错，热点未能确认开启 |
| `2` | 环境不具备（非 PS 5.1 / 无管理员权限 / 无可用网络） |

---

## 安装器参数

```powershell
# 自定义计划任务名与保活间隔（分钟）
powershell -ExecutionPolicy Bypass -File install.ps1 -TaskName "MyHotspotTask" -IntervalMinutes 10

# 不生成桌面启动器
powershell -ExecutionPolicy Bypass -File install.ps1 -NoDesktopShortcut
```

---

## 工作原理

```
任务计划程序（登录时 + 每 N 分钟）
   │
   └─ wscript.exe //B //Nologo run-hotspot.vbs      ← 无窗口
          │
          └─ WScript.Shell.Run(powershell.exe ..., 0, True)   ← 窗口模式 0 = 完全隐藏
                 │
                 └─ hotspot-on.ps1（Windows PowerShell 5.1）
                      │
                      ├─ 1. 校验环境（PS 5.1 + 管理员）
                      ├─ 2. 加载 WinRT，定位当前联网连接（以太网 / WiFi）
                      ├─ 3. 创建 NetworkOperatorTetheringManager
                      ├─ 4. 读 TetheringOperationalState
                      │        ├─ On  → 直接退出（幂等，且不写日志）
                      │        └─ Off → 继续
                      ├─ 5. 如需改 SSID/密码 → ConfigureAccessPointAsync
                      └─ 6. StartTetheringAsync → 复查状态 → 写一行 OK 日志
```

计划任务负责定时唤起这个脚本；脚本本身是**幂等**的，重复跑多少次都安全。
**VBS 这一层是消除黑框闪烁的关键**——直接让计划任务调 `powershell.exe`，
即使指定 `-WindowStyle Hidden`，仍会瞬闪一个控制台窗口。

---

## 常见问题（FAQ）

### Q：为什么必须用 PowerShell 5.1？我装的是 PowerShell 7。

本工具通过 WinRT 调热点接口。**PowerShell 7 无法加载该 WinRT 投影**，
会报 `Unable to find type [Windows.Networking.NetworkOperators...]`。
系统自带的 `powershell.exe`（5.1）可以，无需额外安装。

### Q：热点开了，但手机/其它设备连不上？

先确认这几件事：

1. 本机**能正常上网**（热点是把你已有的网络共享出去）；
2. 网卡驱动支持移动热点——在 Windows 设置里手动点一次那个开关，看能不能正常开；
3. 有些网卡型号/驱动对「移动热点」支持不完整，这种情况本工具也无能为力（因为它调的
   就是系统那个开关）。

### Q：会不会改掉我原来的热点名字和密码？

不会。默认**沿用现有配置**，只负责开。只有你显式传 `-Ssid` / `-Passphrase` 时才会写入。

### Q：屏幕上会闪一个黑框吗？

**不会（v1.1 起）**。计划任务不直接调用 `powershell.exe`——那即使加 `-WindowStyle Hidden`，
Windows 在进程启动的最初几毫秒仍会创建控制台窗口，表现为「黑框一闪」。
本工具改为经 `run-hotspot.vbs` 调用，`WScript.Shell.Run(cmd, 0, True)` 的第 2 个参数 `0`
表示**窗口完全不显示**，屏幕上没有任何闪烁。

> 升级提示：如果你是从 v1.0（直接调 powershell 的版本）升级，重新跑一次 `install.ps1`
> 即可把计划任务切换到 VBS 启动器。

### Q：日志一直增长怎么办？

**默认已经不会了（v1.1 起）**。静默模式（计划任务用的 `-Quiet`）下：

- 热点**本就正常开着** → **不写任何日志**（这是绝大多数情况）；
- 热点**被关、脚本把它重新打开** → 写一行 `[OK] 完成：热点已开启`；
- 出异常 → 写 `[ERROR]`。

也就是说日志**只记录真正发生的事**，稳定运行一天通常只有几行。
如果还想进一步控制，可以：

- 定期手动清空 `hotspot.log`；
- 或调大 `-IntervalMinutes`（比如 15 分钟）减少检查频率。

### Q：任务没跑起来 / 热点没自动开？

排查顺序：

```powershell
# 看任务状态
Get-ScheduledTask -TaskName "XiaoZhiHotspotKeeper" | Select TaskName,State
# 看上次执行结果（0 = 成功）
Get-ScheduledTaskInfo -TaskName "XiaoZhiHotspotKeeper" | Select LastTaskResult,NextRunTime
# 手动跑一次看日志
Start-ScheduledTask -TaskName "XiaoZhiHotspotKeeper"; Start-Sleep 8
Get-Content .\hotspot.log
```

### Q：安装脚本报「请以管理员身份运行」？

用**管理员身份**启动 PowerShell，再执行。或者：

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File .\install.ps1'
```

---

## 文件说明

| 文件 | 说明 |
|---|---|
| `hotspot-on.ps1` | 核心脚本：检测并开启移动热点（幂等） |
| `run-hotspot.vbs` | **静默启动器**：以零窗口方式调用核心脚本，消除黑框闪烁 |
| `install.ps1` | 安装 / 卸载器：注册计划任务、生成桌面启动器 |
| `task.xml` | 安装时自动生成的计划任务定义（存档，便于排查） |
| `hotspot.log` | 运行日志（安装后生成；只在状态变化时记录） |

---

## 已验证环境

- Windows 11 25H2（Build 26200）
- Windows PowerShell 5.1.26100
- 网卡：Realtek 8822CE Wireless LAN 802.11ac PCI-E NIC

实测结论：

- 热点**关闭**状态下运行脚本，能成功开启（状态 `Off → On`）；
- 计划任务手动触发返回 `LastResult=0`，日志按预期写入；
- 经 VBS 静默启动器调用时，**窗口完全不显示**（`wscript` 退出码 0）；
- 静默模式下热点一直正常时，**日志零增长**（241 → 241 行）；
  热点被关并经脚本重开后，**只新增一行** `[OK] 完成：热点已开启`。

---

## 免责声明

- 本工具调用 Windows 官方 WinRT 接口，不修改系统文件与注册表。
- 移动热点是否可用最终取决于**网卡驱动**与**系统版本**，本工具不对硬件兼容性作保证。
- 请遵守当地关于无线频谱与网络共享的法律法规。

---

## 许可

[MIT](LICENSE)

---

## 备注

本仓库由「小爪」为张哥定制并整理开源，代码可直接复用、二次开发。

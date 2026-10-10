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
- **零残留**：一条命令安装，一条命令卸载。
- **不改你的热点配置**：默认沿用系统里现有的 SSID 和密码，只负责「开」，不偷偷改设置。
- **可选覆盖**：需要的话可以指定 SSID / 密码（见下文）。
- **日志可查**：每次运行都写日志，成功失败一目了然。

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

1. 把整个文件夹放到一个**固定位置**，例如 `C:\Tools\win-mobile-hotspot-keeper`
   （放好后别再挪动，计划任务里记的是绝对路径）。
2. 在该文件夹里**以管理员身份**打开 Windows PowerShell，执行：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

安装器会自动完成：

- 注册计划任务（登录后 30 秒触发 + 每 5 分钟复查保活）
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
hotspot-on.ps1
   │
   ├─ 1. 校验环境（PS 5.1 + 管理员）
   ├─ 2. 加载 WinRT，定位当前联网连接（以太网 / WiFi）
   ├─ 3. 创建 NetworkOperatorTetheringManager
   ├─ 4. 读 TetheringOperationalState
   │        ├─ On  → 直接成功退出（幂等）
   │        └─ Off → 继续
   ├─ 5. 如需改 SSID/密码 → ConfigureAccessPointAsync
   └─ 6. StartTetheringAsync → 复查状态 → 写日志
```

计划任务负责定时唤起这个脚本；脚本本身是**幂等**的，重复跑多少次都安全。

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

### Q：日志一直增长怎么办？

`hotspot.log` 每次复查追加一行。日积月累会变大，可以：
- 直接把日志改成**只记内容**（默认 `-Quiet` 模式下每次只写一行最终结果，增长很慢）；
- 或定期手动清空；
- 或调大 `-IntervalMinutes`（比如 15 分钟）减少频率。

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
| `install.ps1` | 安装 / 卸载器：注册计划任务、生成桌面启动器 |
| `task.xml` | 安装时自动生成的计划任务定义（存档，便于排查） |
| `hotspot.log` | 运行日志（安装后生成） |

---

## 已验证环境

- Windows 11 25H2（Build 26200）
- Windows PowerShell 5.1.26100
- 网卡：Realtek 8822CE Wireless LAN 802.11ac PCI-E NIC

实测结论：热点**关闭**状态下运行脚本，能成功开启（状态 `Off → On`）；
计划任务手动触发返回 `LastResult=0`，日志正常写入。

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

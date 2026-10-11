' ============================================================
'  run-hotspot.vbs  —  Windows Mobile Hotspot Keeper 静默启动器
' ------------------------------------------------------------
'  作用：以「完全不显示窗口」的方式调用 hotspot-on.ps1，
'        彻底消除计划任务每 5 分钟触发的瞬时黑框闪烁。
'
'  原理：powershell.exe 是控制台程序，即使加 -WindowStyle Hidden，
'        Windows 在进程启动的最初几毫秒仍会创建控制台窗口（闪黑框）。
'        用 WScript.Shell.Run 的第 2 个参数 = 0，可让子进程完全无窗口启动。
'
'  被谁调用：任务计划程序（XiaoZhiHotspotKeeper）
'  许可：MIT
' ============================================================

Option Explicit

Dim fso, shell, scriptDir, ps1Path, logPath, cmd
Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' 取本 VBS 所在目录，拼出同目录下的 ps1 与日志路径（不硬编码绝对路径）
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path   = fso.BuildPath(scriptDir, "hotspot-on.ps1")
logPath   = fso.BuildPath(scriptDir, "hotspot.log")

If Not fso.FileExists(ps1Path) Then
    ' 脚本缺失时静默退出（避免弹窗打扰用户）
    WScript.Quit 2
End If

' 用 Windows PowerShell 5.1（本工具必需；PS7 不支持所用 WinRT 投影）
Dim sysRoot
sysRoot = shell.ExpandEnvironmentStrings("%SystemRoot%")
Dim ps51
ps51 = sysRoot & "\System32\WindowsPowerShell\v1.0\powershell.exe"

' 组装命令行：-Quiet 只输出状态变化；-LogFile 追加日志
cmd = """" & ps51 & """ -NoProfile -ExecutionPolicy Bypass -File """ & ps1Path & """ -Quiet -LogFile """ & logPath & """"

' 第 2 个参数 0 = 窗口完全不显示；第 3 个参数 True = 等待执行结束
Dim exitCode
exitCode = shell.Run(cmd, 0, True)

WScript.Quit exitCode

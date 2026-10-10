<#
    hotspot-on.ps1  —  Windows Mobile Hotspot Keeper (核心脚本)
    ------------------------------------------------------------------
    用途：检测 Windows「移动热点（Mobile Hotspot）」开关状态；
          处于关闭状态时自动打开；已打开则跳过，不做多余操作。
          可供「任务计划程序」开机/登录调用，也可被桌面批处理器调用。

    技术路线：WinRT API
              Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager
              （即系统「设置 → 网络和 Internet → 移动热点」里那个开关，
                非已废弃的 netsh hostednetwork）

    运行环境：必须是 Windows PowerShell 5.1（powershell.exe）。
              PowerShell 7 (Core) 无法加载该 WinRT 投影，会报
              "Unable to find type"。

    参数：
      -Ssid <string>        可选。要写入的热点名称；省略则沿用现有配置。
      -Passphrase <string>  可选。热点密码（8-63 位）；省略则沿用现有配置。
      -Quiet                静默模式：只输出最终结果，供计划任务使用。
      -LogFile <path>       可选。把日志同时追加写入该文件。

    退出码：
      0 = 热点最终处于开启状态（成功）
      1 = 执行出错，热点未能确认开启
      2 = 环境不具备（非 Windows PowerShell 5.1 / 无管理员权限 / 无可用网络）

    原作者：小爪（为张哥定制）
    许可：MIT
#>

[CmdletBinding()]
param(
    [string]$Ssid,
    [string]$Passphrase,
    [switch]$Quiet,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    if ($Quiet -and $Level -eq 'INFO') { return }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    if ($LogFile) {
        try { $line | Out-File -FilePath $LogFile -Append -Encoding utf8 } catch { }
    }
}

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    # ---------- 0. 环境检查 ----------
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Write-Log -Message "本脚本需要 Windows PowerShell 5.1，当前为 PowerShell 7 (Core)。请改用 powershell.exe 运行。" -Level 'ERROR'
        exit 2
    }

    if (-not (Test-IsAdmin)) {
        Write-Log -Message "需要管理员权限才能操控移动热点，请以管理员身份运行。" -Level 'ERROR'
        exit 2
    }

    # ---------- 1. 加载 WinRT ----------
    Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

    $tmType = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]
    $niType = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]

    # 异步等待器：Start/Stop/Configure 返回 IAsyncOperation，需要手动 await
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]

    function Await-Op {
        param($Operation, [Type]$ResultType, [int]$TimeoutMs = 20000)
        $task = $asTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
        if (-not $task.Wait($TimeoutMs)) { throw "操作超时（${TimeoutMs}ms）" }
        return $task.Result
    }

    # ---------- 2. 找到用于共享的互联网连接 ----------
    $profile = $niType::GetInternetConnectionProfile()
    if ($null -eq $profile) {
        Write-Log -Message "未检测到可用的互联网连接。热点需要一个能上网的连接来共享。" -Level 'ERROR'
        Write-Log -Message "请确认本机已联网（网线 / WiFi）后再试。" -Level 'ERROR'
        exit 1
    }
    Write-Log "共享源连接：$($profile.ProfileName)"

    # ---------- 3. 创建 Tethering Manager ----------
    $tm = $tmType::CreateFromConnectionProfile($profile)
    if ($null -eq $tm) {
        Write-Log -Message "无法创建移动热点管理器。" -Level 'ERROR'
        exit 1
    }

    $stateBefore = $tm.TetheringOperationalState.ToString()
    Write-Log "当前热点状态：$stateBefore"

    # ---------- 4. 已开则直接成功返回 ----------
    if ($stateBefore -eq 'On') {
        Write-Log "热点已处于开启状态，跳过。当前连接设备数：$($tm.ClientCount)"
        Write-Log -Message "完成：热点已开启。" -Level 'OK'
        exit 0
    }

    # ---------- 5. 必要时写入 SSID / 密码 ----------
    $conf      = $tm.GetCurrentAccessPointConfiguration()
    $newSsid   = $conf.Ssid
    $newPass   = $conf.Passphrase
    $needConf  = $false

    Write-Log "现有热点配置：SSID=[$($conf.Ssid)]"

    if ($PSBoundParameters.ContainsKey('Ssid') -and -not [string]::IsNullOrWhiteSpace($Ssid) -and $Ssid -ne $conf.Ssid) {
        $newSsid = $Ssid; $needConf = $true
    }
    if ($PSBoundParameters.ContainsKey('Passphrase') -and -not [string]::IsNullOrWhiteSpace($Passphrase) -and $Passphrase -ne $conf.Passphrase) {
        $newPass = $Passphrase; $needConf = $true
    }
    if ([string]::IsNullOrWhiteSpace($newSsid)) { $newSsid = "MobileHotspot"; $needConf = $true }
    if ([string]::IsNullOrWhiteSpace($newPass)) { $newPass = "12345678";    $needConf = $true }

    if ($needConf) {
        Write-Log "写入热点配置：SSID=[$newSsid]"
        $ap = New-Object Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration
        $ap.Ssid = $newSsid
        $ap.Passphrase = $newPass
        $cfgRes = Await-Op -Operation ($tm.ConfigureAccessPointAsync($ap)) `
                           -ResultType ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
        Write-Log "配置结果：$($cfgRes.Status) $($cfgRes.AdditionalErrorMessage)"
    }

    # ---------- 6. 打开热点 ----------
    Write-Log "正在开启移动热点……"
    $startRes = Await-Op -Operation ($tm.StartTetheringAsync()) `
                         -ResultType ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
    Write-Log "开启请求返回：$($startRes.Status) $($startRes.AdditionalErrorMessage)"

    Start-Sleep -Seconds 3
    $stateAfter = $tm.TetheringOperationalState.ToString()
    Write-Log "开启后热点状态：$stateAfter"

    if ($stateAfter -eq 'On') {
        Write-Log -Message "完成：热点已开启。SSID=[$newSsid]  设备数：$($tm.ClientCount)" -Level 'OK'
        exit 0
    } else {
        Write-Log -Message "热点未能确认开启（当前：$stateAfter）。" -Level 'ERROR'
        exit 1
    }
}
catch {
    Write-Log -Message "执行出错：$($_.Exception.Message)" -Level 'ERROR'
    exit 1
}

param(
    [string]$Root = (Join-Path $PSScriptRoot '../..'),
    [int]$Port = 4330,
    [string]$Godot = ''
)
$ErrorActionPreference = 'Stop'
$started = $null
try {
    $projectRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $url = "http://127.0.0.1:$Port"
    function Get-Health {
        try { return Invoke-RestMethod -Uri "$url/api/health" -TimeoutSec 2 } catch { return $null }
    }
    function Test-Project($health) {
        return $health -and $health.service -eq 'nightcrow-modifier' -and [string]::Equals(([IO.Path]::GetFullPath($health.projectRoot)).TrimEnd('\', '/'), $projectRoot, [StringComparison]::OrdinalIgnoreCase)
    }
    $health = Get-Health
    # 还开着的是旧版本的服务：网页和接口对不上，换掉它。
    if ((Test-Project $health) -and [int]$health.version -lt 3) {
        foreach ($owner in (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).OwningProcess) {
            Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
        $health = $null
    }
    if ($health -and !(Test-Project $health)) { throw "端口 $Port 已被其他项目或服务占用。" }
    if (!(Test-Project $health)) {
        $listener = [Net.Sockets.TcpClient]::new()
        try {
            $connection = $listener.ConnectAsync('127.0.0.1', $Port)
            if ($connection.Wait(300) -and $listener.Connected) { throw "端口 $Port 已被其他服务占用。" }
        } catch [AggregateException] { } finally { $listener.Dispose() }
        $node = 'E:\node.exe'
        if (!(Test-Path -LiteralPath $node)) { $node = (Get-Command node.exe -ErrorAction Stop).Source }
        $server = Join-Path $PSScriptRoot 'server.js'
        $runtime = Join-Path $PSScriptRoot 'runtime'
        New-Item -ItemType Directory -Force -Path $runtime | Out-Null
        function Quote-Argument([string]$value) {
            if ($value.Contains('"') -or $value.Contains([string][char]13) -or $value.Contains([string][char]10)) { throw '路径包含不支持的字符。' }
            return '"' + $value.TrimEnd('\') + '"'
        }
        $arguments = @((Quote-Argument $server), '--root', (Quote-Argument $projectRoot), '--port', $Port)
        if ($Godot) { $arguments += @('--godot', (Quote-Argument ([IO.Path]::GetFullPath($Godot)))) }
        $started = Start-Process -FilePath $node -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtime 'server.log') -RedirectStandardError (Join-Path $runtime 'server-error.log') -PassThru
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 250
            $health = Get-Health
            if (Test-Project $health) { break }
            if ($health) { throw "端口 $Port 的服务属于其他项目。" }
            if ($started.HasExited) { throw ('修改器启动失败：' + (Get-Content -LiteralPath (Join-Path $runtime 'server-error.log') -Raw)) }
        }
        if (!(Test-Project $health)) { throw '等待修改器启动超时。' }
    }
    Start-Process $url
} catch {
    if ($started -and !$started.HasExited) { Stop-Process -Id $started.Id -ErrorAction SilentlyContinue }
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, '夜鸦修改器', 'OK', 'Error') | Out-Null
    exit 1
}

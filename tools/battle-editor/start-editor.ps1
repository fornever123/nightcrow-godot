param([switch]$NoBrowser, [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodePath = 'E:\node.exe'
$npmPath = 'E:\npm.cmd'
$editorUrl = 'http://127.0.0.1:4329/'
$dist = Join-Path $PSScriptRoot 'dist\index.html'
try {
    if (-not (Test-Path -LiteralPath $nodePath)) { throw '缺少 E:\node.exe' }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules'))) {
        Push-Location $PSScriptRoot
        try { & $npmPath ci --no-audit --no-fund; if ($LASTEXITCODE -ne 0) { throw '安装修改器依赖失败' } } finally { Pop-Location }
    }
    $sourceTime = (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -File -Recurse | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    if (-not $SkipBuild -and ((-not (Test-Path -LiteralPath $dist)) -or $sourceTime -gt (Get-Item -LiteralPath $dist).LastWriteTimeUtc)) {
        Push-Location $PSScriptRoot
        try { & $npmPath run build; if ($LASTEXITCODE -ne 0) { throw '构建修改器失败' } } finally { Pop-Location }
    }
    function Test-Server {
        try {
            $data = Invoke-RestMethod ($editorUrl + 'api/health') -TimeoutSec 1
            if ($data.projectRoot -ne $projectRoot) { throw '端口 4329 被其他项目占用' }
            return $data.engine -eq 'Godot'
        } catch { return $false }
    }
    if (-not (Test-Server)) {
        $serverPath = Join-Path $PSScriptRoot 'server.js'
        Start-Process -FilePath $nodePath -ArgumentList @(('"' + $serverPath + '"'), '--root', ('"' + $projectRoot + '"'), '--port', '4329') -WorkingDirectory $projectRoot -WindowStyle Hidden | Out-Null
    }
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) { if (Test-Server) { $ready = $true; break }; Start-Sleep -Milliseconds 250 }
    if (-not $ready) { throw '修改器未启动，请检查端口 4329' }
    if (-not $NoBrowser) { Start-Process $editorUrl | Out-Null }
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '夜鸦修改器') | Out-Null
    exit 1
}

param([string]$Message = '', [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\', '/')
$gitExe = (Get-Command git.exe -ErrorAction Stop).Source

function Invoke-Git {
    param([string[]]$GitArgs)
    $ErrorActionPreference = 'Continue'
    $output = & $gitExe -C $projectRoot @GitArgs 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    return $output
}

try {
    $actualRoot = [IO.Path]::GetFullPath([string](Invoke-Git @('rev-parse', '--show-toplevel'))).TrimEnd('\', '/')
    if ($actualRoot -ne $projectRoot) { throw 'This folder must have its own Git repository.' }
    if (@(Invoke-Git @('ls-files', '--unmerged')).Count) { throw 'Unresolved conflicts exist. Finish resolving them before uploading.' }
    foreach ($operation in @('MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','rebase-apply','rebase-merge','sequencer')) {
        $statePath = [string](Invoke-Git @('rev-parse', '--git-path', $operation))
        if (-not [IO.Path]::IsPathRooted($statePath)) { $statePath = Join-Path $projectRoot $statePath }
        if (Test-Path -LiteralPath $statePath) { throw 'A Git operation is still in progress. Complete it before uploading.' }
    }
    $files = @(Invoke-Git @('-c', 'core.quotepath=false', 'ls-files', '--cached', '--others', '--exclude-standard') | Sort-Object -Unique)
    $textTypes = @('.gd','.gdshader','.ts','.vue','.js','.mjs','.cjs','.ps1','.bat','.json','.md','.txt','.yaml','.yml','.toml','.cfg','.tscn','.tres','.godot','.svg','.ini')
    $patterns = @(
        'gh[pousr]_[A-Za-z0-9]{20,}',
        'github_pat_[A-Za-z0-9_]{40,}',
        'AKIA[A-Z0-9]{16}',
        '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        'https?://[^/\s:@]+:[^/\s@]+@'
    )
    $issues = @()
    foreach ($relative in $files) {
        $full = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $full
        if ($file.Length -ge 100MB) { $issues += "File exceeds 100 MiB: $relative"; continue }
        if ($textTypes -notcontains $file.Extension.ToLowerInvariant()) { continue }
        $content = [IO.File]::ReadAllText($full)
        foreach ($pattern in $patterns) {
            if ($content -cmatch $pattern) { $issues += "Possible credential in: $relative"; break }
        }
    }
    if ($issues.Count) { throw ($issues -join "`n") }
    Write-Host "Upload check passed: $($files.Count) project files."
    if ($CheckOnly) { exit 0 }

    $remote = [string](Invoke-Git @('config', '--get', 'remote.origin.url'))
    if ($remote -notmatch '^(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?|git@github\.com:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$') {
        throw 'Origin must be a GitHub repository URL without embedded credentials.'
    }
    $branch = [string](Invoke-Git @('symbolic-ref', '--short', 'HEAD'))
    $null = Invoke-Git @('fetch', 'origin', $branch)
    $counts = ([string](Invoke-Git @('rev-list', '--left-right', '--count', "HEAD...refs/remotes/origin/$branch"))).Trim() -split '\s+'
    if ([int]$counts[1] -gt 0) { throw 'GitHub has newer commits. Integrate them before uploading; local files were not overwritten.' }
    $null = Invoke-Git @('add', '-A', '--', '.')
    & $gitExe -C $projectRoot diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        if (-not $Message) { $Message = 'Update game ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
        Invoke-Git @('commit', '-m', $Message) | Write-Host
    } elseif ($LASTEXITCODE -ne 0) { throw 'Unable to inspect staged changes.' }
    Invoke-Git @('push', '-u', 'origin', $branch) | Write-Host
    Write-Host 'GitHub update complete.' -ForegroundColor Green
} catch {
    Write-Host ('Update stopped: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

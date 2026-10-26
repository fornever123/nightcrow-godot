# Build a single-file Windows playable. Requires Godot 4.7.2 + export templates.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $Root "engine\Godot_v4.7.2-stable_win64_console.exe"
$OutDir = Join-Path $Root "dist"
$ExeName = "yuexia-trial.exe"
$OutExe = Join-Path $OutDir $ExeName
$TemplatesDir = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable"
$Tpz = Join-Path $env:TEMP "godot-templates\Godot_v4.7.2-stable_export_templates.tpz"
$TpzUrl = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"

if (-not (Test-Path $Godot)) {
	throw "Missing Godot console exe at $Godot"
}

function Ensure-Templates {
	$marker = Join-Path $TemplatesDir "version.txt"
	$win = Join-Path $TemplatesDir "windows_release_x86_64.exe"
	if ((Test-Path $marker) -and (Test-Path $win) -and ((Get-Item $win).Length -gt 10MB)) {
		Write-Host "Export templates already installed."
		return
	}
	New-Item -ItemType Directory -Force -Path (Split-Path $Tpz) | Out-Null
	if (-not (Test-Path $Tpz) -or (Get-Item $Tpz).Length -lt 100MB) {
		Write-Host "Downloading export templates (~1.2 GB)..."
		curl.exe -L --retry 3 -o $Tpz $TpzUrl
		if ($LASTEXITCODE -ne 0) { throw "Template download failed." }
	}
	$extract = Join-Path $env:TEMP "godot-templates\extract-4.7.2"
	if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
	New-Item -ItemType Directory -Force -Path $extract | Out-Null
	Write-Host "Extracting templates..."
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	[System.IO.Compression.ZipFile]::ExtractToDirectory($Tpz, $extract)
	$source = Join-Path $extract "templates"
	if (-not (Test-Path $source)) {
		$source = Get-ChildItem $extract -Directory | Select-Object -First 1 -ExpandProperty FullName
	}
	if (-not (Test-Path $source)) {
		throw "Could not find templates/ inside the tpz."
	}
	New-Item -ItemType Directory -Force -Path $TemplatesDir | Out-Null
	Copy-Item -Path (Join-Path $source "*") -Destination $TemplatesDir -Recurse -Force
	Set-Content -Path (Join-Path $TemplatesDir "version.txt") -Value "4.7.2.stable" -Encoding ascii
	Write-Host "Templates installed to $TemplatesDir"
}

# Playable action folders are .gdignore'd so the editor stays light. Export must see them.
$Ignored = @(
	(Join-Path $Root "assets\image\desktop-actions\.gdignore"),
	(Join-Path $Root "assets\image\desktop-actions-clean\.gdignore")
)
$Parked = @()
function Park-GdIgnore {
	foreach ($path in $Ignored) {
		if (Test-Path $path) {
			$park = "$path.pack-parked"
			Move-Item -LiteralPath $path -Destination $park -Force
			$script:Parked += @{ From = $park; To = $path }
			Write-Host "Parked $path"
		}
	}
}


function Restore-GdIgnore {
	foreach ($item in $Parked) {
		if (Test-Path $item.From) {
			Move-Item -LiteralPath $item.From -Destination $item.To -Force
			Write-Host "Restored $($item.To)"
		}
	}
}

Ensure-Templates
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-Process -Name "yuexia-trial" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
if (Test-Path $OutExe) { Remove-Item -Force $OutExe }

try {
	Park-GdIgnore
	Write-Host "Importing playable frames..."
	& $Godot --headless --path $Root --import
	Write-Host "Exporting Windows release (embedded PCK)..."
	& $Godot --headless --path $Root --export-release "Windows Desktop" $OutExe
	if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutExe)) {
		throw "Export failed (exit $LASTEXITCODE)."
	}
}
finally {
	Restore-GdIgnore
}

$sizeMb = [math]::Round((Get-Item $OutExe).Length / 1MB, 1)
$readmePath = Join-Path $OutDir "README.txt"
$readmeLines = @(
	"Yuexia Di'an trial build",
	"",
	"Double-click yuexia-trial.exe to play. Godot does not need to be installed.",
	"",
	"Approx size: $sizeMb MB."
)
[System.IO.File]::WriteAllLines($readmePath, $readmeLines, [System.Text.UTF8Encoding]::new($false))

Start-Sleep -Seconds 2
$zip = Join-Path $OutDir "yuexia-trial.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
	[void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $OutExe, $ExeName)
	[void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $readmePath, "README.txt")
}
finally {
	$archive.Dispose()
}

Write-Host "Done."
Write-Host "  EXE: $OutExe ($sizeMb MB)"
Write-Host "  ZIP: $zip"

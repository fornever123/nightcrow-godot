# 程序动效样片截图：Edge 无头 1920x1080，按 ?d=&at=&menu=&go= 定格。输出到 frames\。
# 用法：powershell -File render.ps1 [-Only 1]
param([string]$Only = '')
$ErrorActionPreference = 'Stop'
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$src = Join-Path $PSScriptRoot 'title_proc.html'
$out = Join-Path $PSScriptRoot 'frames'
New-Item -ItemType Directory -Force $out | Out-Null
$uri = ([System.Uri]$src).AbsoluteUri
$shots = @(
  @('1','0_intro1','at=1.6'), @('1','1_intro2','at=3.0'), @('1','2_idle','at=6.5'), @('1','3_menu','at=9&menu=7&sel=0'), @('1','4_go','at=9.25&menu=7&go=9'), @('1','5_go2','at=9.9&menu=7&go=9'),
  @('2','0_intro1','at=1.0'), @('2','1_intro2','at=2.4'), @('2','2_cut','at=3.05'), @('2','3_menu','at=11&menu=7&sel=0'), @('2','4_go','at=11.3&menu=7&go=11'), @('2','5_idle','at=8.2'),
  @('3','0_intro1','at=1.0'), @('3','1_intro2','at=2.4'), @('3','2_idle','at=6.5'), @('3','3_menu','at=9&menu=7&sel=2'), @('3','4_go','at=9.3&menu=7&go=9'), @('3','5_go2','at=10.0&menu=7&go=9')
)
foreach ($s in $shots) {
  if ($Only -and $s[0] -ne $Only) { continue }
  $png = Join-Path $out "d$($s[0])_$($s[1]).png"
  & $edge --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 `
    --window-size=1920,1080 --virtual-time-budget=8000 --screenshot="$png" "$uri`?d=$($s[0])&$($s[2])" 2>$null | Out-Null
}
Get-ChildItem $out | Select-Object Name, Length

# 首页样图截图：Edge 无头 1280x720，每个方向 f0 定稿 + f1~f3 进场关键帧，输出到上一级 _frames。
# 第二版：A 用名字 2（五点五十九）、B 用 1（断晓）、C 用 0（沉影之昼）；N 是三个候选名的字标对比。
$ErrorActionPreference = 'Stop'
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$src = Join-Path $PSScriptRoot 'title_mock.html'
$out = Join-Path $PSScriptRoot '..\_frames'
New-Item -ItemType Directory -Force $out | Out-Null
$uri = ([System.Uri]$src).AbsoluteUri
$name = @{ A = 2; B = 1; C = 0; N = 0 }
foreach ($d in 'A','B','C','N') {
  $fs = if ($d -eq 'N') { @(0) } else { 0..3 }
  foreach ($f in $fs) {
    $png = Join-Path $out "$d-f$f.png"
    & $edge --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 `
      --window-size=1280,720 --virtual-time-budget=1500 --screenshot="$png" "$uri`?d=$d&f=$f&n=$($name[$d])" 2>$null | Out-Null
  }
}
Get-ChildItem $out | Select-Object Name, Length

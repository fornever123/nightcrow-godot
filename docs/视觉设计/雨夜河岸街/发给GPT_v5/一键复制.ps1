# 发给 GPT 用：先把 3 张图复制到剪贴板（在 ChatGPT 输入框里 Ctrl+V 粘贴），
# 按回车后再把提示词复制到剪贴板（再 Ctrl+V 粘贴）。
Add-Type -AssemblyName System.Windows.Forms
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = New-Object System.Collections.Specialized.StringCollection
foreach ($n in @("1_明暗草图_v5.png", "2_画法参考_泪城.png", "3_画法参考_莉莉.png")) {
    [void]$files.Add((Join-Path $dir $n))
}
[System.Windows.Forms.Clipboard]::SetFileDropList($files)
Write-Host "第 1 步：3 张图已复制。到 ChatGPT 输入框按 Ctrl+V 粘贴，然后回到这里按回车。"
[void](Read-Host)
$text = Get-Content -Raw -Encoding UTF8 (Join-Path $dir "提示词.txt")
[System.Windows.Forms.Clipboard]::SetText($text)
Write-Host "第 2 步：提示词已复制。到 ChatGPT 输入框按 Ctrl+V 粘贴后发送。按回车关闭。"
[void](Read-Host)

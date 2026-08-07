param(
    [Parameter(Mandatory = $true)][long]$AppleMusicId,
    [Parameter(Mandatory = $true)][string]$Artist,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$TtmlPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $repoRoot 'index.json'
$lyricsDir = Join-Path $repoRoot 'am-lyrics'

if (-not (Test-Path -LiteralPath $TtmlPath -PathType Leaf)) {
    throw "TTML 文件不存在: $TtmlPath"
}
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $TtmlPath))
if ($bytes.Length -gt 512 * 1024) {
    throw "TTML 超过 512 KiB 上限（当前 $($bytes.Length) bytes）"
}

$text = [System.Text.Encoding]::UTF8.GetString($bytes)
foreach ($marker in @('<tt', '<body')) {
    if (-not $text.Contains($marker)) {
        throw "TTML 缺少必需标记: $marker"
    }
}
if (([regex]::Matches($text, '<p')).Count -gt 4096) {
    throw '<p> 元素超过 4096 上限'
}
if (([regex]::Matches($text, '<span')).Count -gt 65536) {
    throw '<span> 元素超过 65536 上限'
}

if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "index.json 不存在: $indexPath"
}
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($index.entries.appleMusicId) -contains $AppleMusicId) {
    throw "Apple Music ID $AppleMusicId 已存在于 index.json"
}

function Clean-Name([string]$value) {
    return ($value -replace '[\\/:*?"<>|]', '、').TrimEnd(' ', '.')
}

$safeArtist = Clean-Name $Artist
$safeTitle = Clean-Name $Title
$fileName = "$safeArtist - $safeTitle - $AppleMusicId.ttml"
$dest = Join-Path $lyricsDir $fileName
if (Test-Path -LiteralPath $dest) {
    throw "目标文件已存在: $fileName"
}

Copy-Item -LiteralPath $TtmlPath -Destination $dest

$finalBytes = [System.IO.File]::ReadAllBytes($dest)
$sha = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::HashData([byte[]]$finalBytes)
).Replace('-', '').ToLowerInvariant()

$entry = [pscustomobject]@{
    appleMusicId = $AppleMusicId
    artist       = $Artist
    title        = $Title
    displayName  = "$Title - $Artist"
    path         = "am-lyrics/$fileName"
    source       = 'manual'
    enabled      = $true
    sizeBytes    = $finalBytes.Length
    sha256       = $sha
}
$index.entries = @($index.entries) + $entry
[System.IO.File]::WriteAllText(
    $indexPath,
    ($index | ConvertTo-Json -Depth 5),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "已添加歌词文件: $fileName"
Write-Host "sizeBytes=$($finalBytes.Length)"
Write-Host "sha256=$sha"
Write-Host "请运行 git diff 核对后提交推送。"

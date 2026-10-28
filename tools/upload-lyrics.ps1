param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [Alias('TtmlPath')]
    [string[]]$TtmlPaths,
    [string]$AppleMusicId,
    [string]$Artist,
    [string]$Title,
    [string]$Album,
    [long[]]$AlternateIds,
    [long]$TargetAppleMusicId,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate_ttml.py'
$upserter = Join-Path $PSScriptRoot 'upsert-lyrics.ps1'
$lyricsDir = Join-Path $repoRoot 'am-lyrics'
$indexPath = Join-Path $repoRoot 'index.json'

function Invoke-Git([string[]]$GitArgs) {
    & git -C $repoRoot @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Git 命令失败: git $($GitArgs -join ' ')"
    }
}

function Assert-RepositoryReady {
    $branch = & git -C $repoRoot branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
        throw '请在本仓库的 main 分支运行上传脚本'
    }

    $indexChanges = @(& git -C $repoRoot status --porcelain -- index.json)
    if ($LASTEXITCODE -ne 0) { throw '无法检查 index.json 的状态' }
    if ($indexChanges.Count -gt 0) { throw 'index.json 已有未提交修改，请先处理' }

    $lyricChanges = @(& git -C $repoRoot status --porcelain -- am-lyrics)
    if ($LASTEXITCODE -ne 0) { throw '无法检查 am-lyrics 的状态' }
    if ($lyricChanges.Count -gt 0) {
        throw 'am-lyrics 下已有未提交改动；请先处理后再批量上传，避免覆盖现有工作。'
    }

    $staged = @(& git -C $repoRoot diff --cached --name-only)
    if ($LASTEXITCODE -ne 0) { throw '无法检查暂存区' }
    if ($staged.Count -gt 0) { throw '暂存区已有其他文件，请先提交或取消暂存' }
}

function Get-TtmlUploadInfo {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [string]$ArtistOverride,
        [string]$TitleOverride,
        [string]$AlbumOverride,
        [string]$AppleMusicIdOverride,
        [bool]$Interactive
    )

    # Read from a stream so percent-encoded-looking filenames stay literal paths.
    $xml = [System.Xml.XmlDocument]::new()
    $xml.XmlResolver = $null
    $xmlStream = [IO.File]::OpenRead($SourcePath)
    try {
        $xml.Load($xmlStream)
    } finally {
        $xmlStream.Dispose()
    }

    $metaArtist = ''
    $metaTitle = ''
    $metaAlbum = ''
    $metaIds = @()
    $ns = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('tt', 'http://www.w3.org/ns/ttml')
    $ns.AddNamespace('ttm', 'http://www.w3.org/ns/ttml#metadata')
    $head = $xml.SelectSingleNode('/tt:tt/tt:head', $ns)
    if ($head) {
        foreach ($meta in $head.SelectNodes('.//*[local-name()="meta"]')) {
            $value = $meta.GetAttribute('value').Trim()
            if (-not $value) { continue }
            switch ($meta.GetAttribute('key')) {
                'artists'   { $metaArtist = $value }
                'musicName' { $metaTitle = $value }
                'album'     { $metaAlbum = $value }
                'appleMusicId' {
                    if ($metaIds -notcontains $value) { $metaIds += $value }
                }
            }
        }
        if (-not $metaTitle) {
            $titleNode = $head.SelectSingleNode('.//ttm:title', $ns)
            if ($titleNode) { $metaTitle = $titleNode.InnerText.Trim() }
        }
        if (-not $metaArtist) {
            $agentNames = @(
                foreach ($agent in $head.SelectNodes('.//ttm:agent', $ns)) {
                    if ($agent.GetAttribute('type') -notin @('person', 'group')) { continue }
                    $nameNode = $agent.SelectSingleNode('ttm:name[@type="full"]', $ns)
                    if (-not $nameNode) { $nameNode = $agent.SelectSingleNode('ttm:name', $ns) }
                    if ($nameNode -and -not [string]::IsNullOrWhiteSpace($nameNode.InnerText)) {
                        $nameNode.InnerText.Trim()
                    }
                }
            )
            $agentNames = @($agentNames | Select-Object -Unique)
            if ($agentNames.Count -eq 1) { $metaArtist = $agentNames[0] }
        }
    }
    $metaId = if ($metaIds.Count -gt 0) { $metaIds[-1] } else { '' }

    $fileArtist = ''
    $fileTitle = ''
    $fileId = ''
    $parts = [IO.Path]::GetFileNameWithoutExtension($SourcePath) -split ' - '
    if ($parts.Count -eq 3 -and $parts[2] -match '^[1-9][0-9]*$') {
        $fileArtist, $fileTitle, $fileId = $parts
    }
    if ($fileArtist -and $metaArtist -and $fileArtist -ne $metaArtist) {
        Write-Warning "文件名歌手「$fileArtist」与 TTML 内「$metaArtist」不同，请核对。"
    }
    if ($fileTitle -and $metaTitle -and $fileTitle -ne $metaTitle) {
        Write-Warning "文件名歌名「$fileTitle」与 TTML 内「$metaTitle」不同，请核对。"
    }
    if ($fileId -and $metaId -and $fileId -ne $metaId) {
        Write-Warning "文件名 ID「$fileId」与 TTML 内「$metaId」不同，请核对。"
    }

    $artistName = $ArtistOverride
    $songTitle = $TitleOverride
    $albumName = $AlbumOverride
    if ([string]::IsNullOrWhiteSpace($albumName)) { $albumName = $metaAlbum }
    $appleMusicId = $AppleMusicIdOverride
    $fromMetadata = @()
    if ([string]::IsNullOrWhiteSpace($artistName)) {
        if ($fileArtist) { $artistName = $fileArtist }
        elseif ($metaArtist) { $artistName = $metaArtist; $fromMetadata += '歌手' }
    }
    if ([string]::IsNullOrWhiteSpace($songTitle)) {
        if ($fileTitle) { $songTitle = $fileTitle }
        elseif ($metaTitle) { $songTitle = $metaTitle; $fromMetadata += '歌名' }
    }
    if ([string]::IsNullOrWhiteSpace($appleMusicId)) {
        if ($fileId) { $appleMusicId = $fileId }
        elseif ($metaId) { $appleMusicId = $metaId; $fromMetadata += 'Apple Music ID' }
    }
    if ([string]::IsNullOrWhiteSpace($AlbumOverride) -and $metaAlbum) {
        $fromMetadata += '专辑'
    }
    if ($fromMetadata.Count -gt 0) {
        Write-Host "$([IO.Path]::GetFileName($SourcePath))：已从 TTML 读取$($fromMetadata -join '、')"
    }

    if ([string]::IsNullOrWhiteSpace($artistName)) {
        if (-not $Interactive) { throw "文件缺少歌手元数据: $SourcePath" }
        $artistName = Read-Host "歌手（$([IO.Path]::GetFileName($SourcePath))）"
    }
    if ([string]::IsNullOrWhiteSpace($songTitle)) {
        if (-not $Interactive) { throw "文件缺少歌名元数据: $SourcePath" }
        $songTitle = Read-Host "歌名（$([IO.Path]::GetFileName($SourcePath))）"
    }
    if ([string]::IsNullOrWhiteSpace($appleMusicId)) {
        if (-not $Interactive) { throw "文件缺少 Apple Music ID 元数据: $SourcePath" }
        $appleMusicId = Read-Host "Apple Music ID（$([IO.Path]::GetFileName($SourcePath))）"
    }

    $artistName = $artistName.Trim()
    $songTitle = $songTitle.Trim()
    $appleMusicId = $appleMusicId.Trim()
    if (-not $artistName -or -not $songTitle) { throw "歌手和歌名不能为空: $SourcePath" }

    [long]$id = 0
    if (-not [long]::TryParse($appleMusicId, [ref]$id) -or $id -le 0) {
        throw "Apple Music ID 必须为正整数（文件: $SourcePath）: $appleMusicId"
    }

    $embeddedAltIds = @()
    foreach ($value in $metaIds) {
        [long]$embeddedId = 0
        if (-not [long]::TryParse($value, [ref]$embeddedId) -or $embeddedId -le 0) {
            throw "TTML 内嵌的 Apple Music ID 非法（文件: $SourcePath）: $value"
        }
        if ($embeddedId -ne $id -and $embeddedAltIds -notcontains $embeddedId) {
            $embeddedAltIds += $embeddedId
        }
    }

    return [pscustomobject]@{
        Path = $SourcePath
        Artist = $artistName
        Title = $songTitle
        Album = $albumName
        AppleMusicId = $id
        AlternateIds = @($embeddedAltIds)
    }
}

function Get-LyricSnapshot {
    $snapshot = @{}
    foreach ($file in Get-ChildItem -LiteralPath $lyricsDir -File -Recurse) {
        $snapshot[$file.FullName] = [IO.File]::ReadAllBytes($file.FullName)
    }
    return $snapshot
}

function Restore-LyricSnapshot($Snapshot, [byte[]]$IndexBytes) {
    [IO.File]::WriteAllBytes($indexPath, $IndexBytes)
    foreach ($file in Get-ChildItem -LiteralPath $lyricsDir -File -Recurse) {
        if ($Snapshot.ContainsKey($file.FullName)) {
            $before = [Convert]::ToBase64String([byte[]]$Snapshot[$file.FullName])
            $after = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
            if ($before -ne $after) {
                [IO.File]::WriteAllBytes($file.FullName, [byte[]]$Snapshot[$file.FullName])
            }
        } else {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
}

function Split-TtmlPathInput {
    param([Parameter(Mandatory = $true)][string]$InputText)

    # Read-Host returns one string, even when several files were dragged into
    # the console. Split on whitespace outside quotes so paths with spaces stay
    # intact, matching the format emitted by Windows Explorer.
    $paths = [System.Collections.Generic.List[string]]::new()
    $token = [System.Text.StringBuilder]::new()
    $insideQuotes = $false
    $tokenStarted = $false

    foreach ($character in $InputText.ToCharArray()) {
        if ($character -eq '"') {
            $insideQuotes = -not $insideQuotes
            $tokenStarted = $true
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $insideQuotes) {
            if ($tokenStarted) {
                $paths.Add($token.ToString())
                [void]$token.Clear()
                $tokenStarted = $false
            }
            continue
        }

        [void]$token.Append($character)
        $tokenStarted = $true
    }

    if ($insideQuotes) {
        throw '路径输入中的双引号没有配对；请重新粘贴或拖入文件。'
    }
    if ($tokenStarted) { $paths.Add($token.ToString()) }

    return $paths.ToArray()
}

$inputPaths = @()
if ($null -ne $TtmlPaths) { $inputPaths = @($TtmlPaths) }
if ($inputPaths.Count -eq 0) {
    $rawPathInput = Read-Host 'TTML 文件路径（可一次拖入多个文件）'
    $inputPaths = @(Split-TtmlPathInput -InputText $rawPathInput)
}

$sourcePaths = @()
$seenPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($inputPath in $inputPaths) {
    $path = ([string]$inputPath).Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "TTML 文件不存在: $path"
    }
    $resolvedPath = (Resolve-Path -LiteralPath $path).ProviderPath
    if ([IO.Path]::GetExtension($resolvedPath) -ine '.ttml') {
        throw "请选择 .ttml 文件: $resolvedPath"
    }
    if ($seenPaths.Add($resolvedPath)) { $sourcePaths += $resolvedPath }
}
if ($sourcePaths.Count -eq 0) { throw '没有收到 TTML 文件' }

if ($sourcePaths.Count -gt 1) {
    $singleFileOptionNames = @('AppleMusicId', 'Artist', 'Title', 'Album', 'AlternateIds', 'TargetAppleMusicId')
    $singleFileOptions = @($singleFileOptionNames | Where-Object {
        $PSBoundParameters.ContainsKey($_)
    })
    if ($singleFileOptions.Count -gt 0) {
        throw "批量上传不能共用单曲参数：$($singleFileOptions -join ', ')。请将这些参数用于单文件上传。"
    }
}

$python = Get-Command python -ErrorAction SilentlyContinue
$py = Get-Command py -ErrorAction SilentlyContinue
$validatorArgs = @($validator) + $sourcePaths
if ($python) {
    & $python.Source @validatorArgs
} elseif ($py) {
    $validatorArgs = @('-3', $validator) + $sourcePaths
    & $py.Source @validatorArgs
} else {
    throw '未找到 Python 3，无法运行 TTML 格式校验'
}
if ($LASTEXITCODE -ne 0) { throw 'TTML 格式校验未通过，整批均未上传' }

$records = @()
foreach ($sourcePath in $sourcePaths) {
    $artistOverride = if ($sourcePaths.Count -eq 1) { $Artist } else { '' }
    $titleOverride = if ($sourcePaths.Count -eq 1) { $Title } else { '' }
    $albumOverride = if ($sourcePaths.Count -eq 1) { $Album } else { '' }
    $idOverride = if ($sourcePaths.Count -eq 1) { $AppleMusicId } else { '' }
    $record = Get-TtmlUploadInfo -SourcePath $sourcePath `
        -ArtistOverride $artistOverride -TitleOverride $titleOverride -AlbumOverride $albumOverride `
        -AppleMusicIdOverride $idOverride -Interactive (-not $Yes)

    $recordAlternates = @($record.AlternateIds)
    if ($sourcePaths.Count -eq 1 -and $AlternateIds.Count -gt 0) {
        $recordAlternates += $AlternateIds
    }
    $recordAlternates = @($recordAlternates | Select-Object -Unique)
    foreach ($alt in $recordAlternates) {
        if ($alt -le 0) { throw "备用 ID 必须为正整数（文件: $sourcePath）: $alt" }
        if ($alt -eq $record.AppleMusicId) { throw "备用 ID 不能与主 ID 相同（文件: $sourcePath）: $alt" }
    }
    $record.AlternateIds = @($recordAlternates)
    $records += $record
}

$batchIds = @{}
foreach ($record in $records) {
    foreach ($batchId in @([long]$record.AppleMusicId) + @($record.AlternateIds)) {
        $key = [string]$batchId
        if ($batchIds.ContainsKey($key)) {
            throw "本批文件重复包含 ID $key：`n  $($batchIds[$key])`n  $($record.Path)`n请每个 ID 只保留一个 TTML 文件后再上传。"
        }
        $batchIds[$key] = $record.Path
    }
}

Assert-RepositoryReady

Write-Host "`n本批准备上传 $($records.Count) 个文件："
foreach ($record in $records) {
    Write-Host "  $($record.Artist) - $($record.Title) ($($record.AppleMusicId))"
    if ($record.Album) { Write-Host "    专辑：$($record.Album)" }
    Write-Host "    $($record.Path)"
    if ($record.AlternateIds.Count -gt 0) {
        Write-Host "    备用 ID：$($record.AlternateIds -join ', ')"
    }
}
if (-not $Yes) {
    $answer = Read-Host '确认整批提交并推送到 origin/main？输入 y 继续'
    if ($answer -notin @('y', 'Y', '是')) {
        Write-Host '已取消，仓库没有改动。'
        exit 0
    }
}

# 先同步远端，避免在旧索引上增加条目。
Invoke-Git -GitArgs @('pull', '--ff-only', 'origin', 'main')
Assert-RepositoryReady

# 保留提交前快照；若批次中某个 ID/索引操作失败，撤销这一批已写入的文件。
$indexSnapshot = [IO.File]::ReadAllBytes($indexPath)
$lyricSnapshot = Get-LyricSnapshot
$results = @()
$changedLyricPaths = @()
try {
    foreach ($record in $records) {
        Write-Host "`n处理：$($record.Artist) - $($record.Title) ($($record.AppleMusicId))"
        $upsertArgs = @{
            AppleMusicId = [long]$record.AppleMusicId
            Artist = [string]$record.Artist
            Title = [string]$record.Title
            TtmlPath = [string]$record.Path
            Interactive = -not $Yes
        }
        if ($record.Album) { $upsertArgs.Album = [string]$record.Album }
        if ($record.AlternateIds.Count -gt 0) {
            $upsertArgs.AlternateIds = @($record.AlternateIds)
        }
        if ($sourcePaths.Count -eq 1 -and $TargetAppleMusicId -gt 0) {
            $upsertArgs.TargetAppleMusicId = $TargetAppleMusicId
        }
        $result = & $upserter @upsertArgs
        $results += $result
        if ($result.Changed -and $result.Action -in @('added', 'added-version', 'updated', 'updated-and-alternate')) {
            if ($changedLyricPaths -notcontains [string]$result.Path) {
                $changedLyricPaths += [string]$result.Path
            }
        }
    }
} catch {
    $failure = $_.Exception.Message
    try {
        Restore-LyricSnapshot -Snapshot $lyricSnapshot -IndexBytes $indexSnapshot
        Write-Warning '批次中途遇到错误，已撤销本批对索引和歌词文件的修改。'
    } catch {
        throw "批量处理失败：$failure；自动恢复也失败：$($_.Exception.Message)"
    }
    throw "批量处理失败，整批改动已撤销：$failure"
}

$changedResults = @($results | Where-Object { $_.Changed })
if ($changedResults.Count -eq 0) {
    Write-Host "`n整批文件均已是最新，无需提交。"
    exit 0
}

$stagePaths = @('index.json') + @($changedLyricPaths)
Invoke-Git -GitArgs (@('add', '--') + $stagePaths)
Invoke-Git -GitArgs @('diff', '--cached', '--check')

if ($records.Count -eq 1) {
    $result = $changedResults[0]
    $record = $records[0]
    $commitMessage = switch ($result.Action) {
        'added'                 { "lyrics: add $($result.Artist) - $($result.Title) ($($result.PrimaryId))" }
        'added-version'         { "lyrics: add version $($result.Artist) - $($result.Title) ($($result.PrimaryId))" }
        'alternate'             { "lyrics: add alternate ID $($result.AddedIds -join ', ') for $($result.PrimaryId)" }
        'updated'               { "lyrics: update $($result.Artist) - $($result.Title) ($($result.PrimaryId))" }
        'updated-and-alternate' { "lyrics: update $($result.Artist) - $($result.Title) ($($result.PrimaryId))" }
        default                 { throw "未知上传操作: $($result.Action)" }
    }
} else {
    $commitMessage = "lyrics: batch upload $($records.Count) files"
}

Invoke-Git -GitArgs @('commit', '-m', $commitMessage)
try {
    Invoke-Git -GitArgs @('push', 'origin', 'main')
} catch {
    throw "歌词已在本地提交，但推送失败。处理 Git 报错后运行 git push origin main。$($_.Exception.Message)"
}

Write-Host "`n批量上传完成：$($changedResults.Count)/$($records.Count) 个文件有索引或歌词改动。"
foreach ($result in $changedResults) {
    Write-Host "  $($result.Path) [$($result.Action)]"
}

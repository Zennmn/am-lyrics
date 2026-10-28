param(
    [Parameter(Mandatory = $true)][long]$AppleMusicId,
    [Parameter(Mandatory = $true)][string]$Artist,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$TtmlPath,
    [string]$Album,
    [long[]]$AlternateIds,
    [long]$TargetAppleMusicId,
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $repoRoot 'index.json'
$lyricsDir = Join-Path $repoRoot 'am-lyrics'
$adder = Join-Path $PSScriptRoot 'add-lyrics.ps1'
if ($null -eq $AlternateIds) { $AlternateIds = @() }
if ($AppleMusicId -le 0) { throw 'Apple Music ID 必须为正整数' }
if ([string]::IsNullOrWhiteSpace($Artist) -or [string]::IsNullOrWhiteSpace($Title)) {
    throw '歌手和歌名不能为空'
}
if (-not (Test-Path -LiteralPath $TtmlPath -PathType Leaf)) { throw "TTML 文件不存在: $TtmlPath" }
$sourcePath = (Resolve-Path -LiteralPath $TtmlPath).ProviderPath
$sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
if ($sourceBytes.Length -gt 512 * 1024) { throw 'TTML 超过 512 KiB 上限' }

function Get-Sha256([byte[]]$content) {
    return [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::HashData($content)
    ).Replace('-', '').ToLowerInvariant()
}

function Get-TimingSignature([string]$TtmlPath) {
    $xml = [System.Xml.XmlDocument]::new()
    $xml.XmlResolver = $null
    $stream = [IO.File]::OpenRead($TtmlPath)
    try {
        $xml.Load($stream)
    } finally {
        $stream.Dispose()
    }

    $body = $xml.SelectSingleNode('//*[local-name()="body"]')
    if (-not $body) { return $null }

    $segments = [System.Collections.Generic.List[string]]::new()
    $bodyBegin = $body.GetAttribute('begin')
    $bodyEnd = $body.GetAttribute('end')
    $bodyDur = $body.GetAttribute('dur')
    if ($bodyBegin -or $bodyEnd -or $bodyDur) {
        $segments.Add("body|$bodyBegin|$bodyEnd|$bodyDur")
    }
    foreach ($node in $body.SelectNodes('.//*[@begin or @end or @dur]')) {
        $begin = $node.GetAttribute('begin')
        $end = $node.GetAttribute('end')
        $dur = $node.GetAttribute('dur')
        $segments.Add("$($node.LocalName)|$begin|$end|$dur")
    }
    if ($segments.Count -eq 0) { return $null }

    $signature = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $segments))
    return Get-Sha256 $signature
}

function Get-TtmlAlbum([string]$TtmlPath) {
    $xml = [System.Xml.XmlDocument]::new()
    $xml.XmlResolver = $null
    $stream = [IO.File]::OpenRead($TtmlPath)
    try {
        $xml.Load($stream)
    } finally {
        $stream.Dispose()
    }

    foreach ($meta in $xml.SelectNodes('//*[local-name()="meta"]')) {
        if ($meta.GetAttribute('key') -eq 'album') {
            $value = $meta.GetAttribute('value').Trim()
            if ($value) { return $value }
        }
    }
    return ''
}

function Same-Song($entry, [string]$artistName, [string]$songTitle) {
    $form = [Text.NormalizationForm]::FormC
    $entryArtist = ([string]$entry.artist).Trim().Normalize($form)
    $entryTitle = ([string]$entry.title).Trim().Normalize($form)
    return ($entryArtist -eq $artistName.Trim().Normalize($form)) -and
           ($entryTitle -eq $songTitle.Trim().Normalize($form))
}

function Get-LyricPath($entry) {
    $fullPath = [IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$entry.path)))
    $prefix = [IO.Path]::GetFullPath($lyricsDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetExtension($fullPath) -ine '.ttml') {
        throw "索引路径不在 am-lyrics 目录内: $($entry.path)"
    }
    return $fullPath
}

function Get-EntryAlbum($entry) {
    $albumName = ([string]$entry.album).Trim()
    if ($albumName) { return $albumName }

    $entryPath = Get-LyricPath $entry
    if (Test-Path -LiteralPath $entryPath -PathType Leaf) {
        return Get-TtmlAlbum $entryPath
    }
    return ''
}

function Same-Album([string]$left, [string]$right) {
    if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) {
        return $false
    }
    $form = [Text.NormalizationForm]::FormC
    $normalizedLeft = $left.Trim().Normalize($form)
    $normalizedRight = $right.Trim().Normalize($form)
    return [string]::Equals($normalizedLeft, $normalizedRight, [StringComparison]::OrdinalIgnoreCase)
}

$sourceSha = Get-Sha256 $sourceBytes
$sourceTimingSignature = Get-TimingSignature $sourcePath
$Album = if ([string]::IsNullOrWhiteSpace($Album)) { Get-TtmlAlbum $sourcePath } else { $Album.Trim() }
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$idOwners = @($index.entries | Where-Object {
    [long]$_.appleMusicId -eq $AppleMusicId -or @($_.alternateIds) -contains $AppleMusicId
})
if ($idOwners.Count -gt 1) { throw "ID $AppleMusicId 在索引中属于多条记录，请先修复索引" }
$idMatched = $idOwners.Count -eq 1
$idMatchedAsAlternate = $false
$splitAlternateOwner = $null
if ($idMatched) {
    $idMatchedAsAlternate = [long]$idOwners[0].appleMusicId -ne $AppleMusicId
    if ($idMatchedAsAlternate -and $TargetAppleMusicId -eq 0) {
        $ownerPath = Get-LyricPath $idOwners[0]
        $ownerAlbum = Get-EntryAlbum $idOwners[0]
        $albumDiffers = $Album -and $ownerAlbum -and -not (Same-Album $Album $ownerAlbum)
        $ownerTimingSignature = if ($sourceTimingSignature) { Get-TimingSignature $ownerPath } else { $null }
        $timingDiffers = $sourceTimingSignature -and $ownerTimingSignature -and
            $ownerTimingSignature -ne $sourceTimingSignature
        if ($albumDiffers -or $timingDiffers) {
            $splitAlternateOwner = $idOwners[0]
            $idMatched = $false
            $idMatchedAsAlternate = $false
        }
    }
}
$target = $null
$separateVersion = $false

if ($idMatched) {
    $target = $idOwners[0]
    if ($TargetAppleMusicId -gt 0 -and $TargetAppleMusicId -ne [long]$target.appleMusicId) {
        throw "ID $AppleMusicId 已属于主 ID $($target.appleMusicId)，不能指定到 $TargetAppleMusicId"
    }
    if (-not (Same-Song $target $Artist $Title)) {
        Write-Warning "ID $AppleMusicId 已属于「$($target.artist) - $($target.title)」；沿用索引中的歌手和歌名，继续更新歌词。"
    }
    $Artist = [string]$target.artist
    $Title = [string]$target.title
} else {
    $sameNames = @($index.entries | Where-Object { Same-Song $_ $Artist $Title })
    if ($TargetAppleMusicId -eq 0 -and $sameNames.Count -gt 0 -and $Album) {
        $sameAlbum = @()
        $unknownAlbum = @()
        foreach ($candidate in $sameNames) {
            $candidateAlbum = Get-EntryAlbum $candidate
            if (-not $candidateAlbum) {
                $unknownAlbum += $candidate
            } elseif (Same-Album $candidateAlbum $Album) {
                $sameAlbum += $candidate
            }
        }
        if ($sameAlbum.Count -gt 0) {
            $sameNames = $sameAlbum
        } elseif ($unknownAlbum.Count -gt 0) {
            $sameNames = $unknownAlbum
        } else {
            $sameNames = @()
            $separateVersion = $true
        }
    }
    if ($TargetAppleMusicId -eq 0 -and $sameNames.Count -gt 0 -and $sourceTimingSignature) {
        $sameTimeline = @()
        foreach ($candidate in $sameNames) {
            $candidateTimingSignature = Get-TimingSignature (Get-LyricPath $candidate)
            if ($candidateTimingSignature -and $candidateTimingSignature -eq $sourceTimingSignature) {
                $sameTimeline += $candidate
            }
        }
        if ($sameTimeline.Count -eq 0) {
            $sameNames = @()
            $separateVersion = $true
        } else {
            $sameNames = $sameTimeline
        }
    }
    if ($sameNames.Count -eq 1) {
        $target = $sameNames[0]
        if ($TargetAppleMusicId -gt 0 -and $TargetAppleMusicId -ne [long]$target.appleMusicId) {
            throw "同名歌曲的主 ID 是 $($target.appleMusicId)，不是 $TargetAppleMusicId"
        }
    } elseif ($sameNames.Count -gt 1) {
        if ($TargetAppleMusicId -eq 0) {
            $sameContent = @($sameNames | Where-Object { [string]$_.sha256 -eq $sourceSha })
            if ($sameContent.Count -eq 1) { $TargetAppleMusicId = [long]$sameContent[0].appleMusicId }
        }
        if ($TargetAppleMusicId -eq 0 -and $Interactive) {
            Write-Host '找到多条同名歌曲，请选择要追加备用 ID 的主 ID：'
            foreach ($candidate in $sameNames) {
                Write-Host "  $($candidate.appleMusicId)  $($candidate.path)"
            }
            $answer = Read-Host '输入主 ID'
            if (-not [long]::TryParse($answer, [ref]$TargetAppleMusicId)) {
                throw '主 ID 不是有效数字，未修改仓库'
            }
        }
        $selected = @($sameNames | Where-Object { [long]$_.appleMusicId -eq $TargetAppleMusicId })
        if ($selected.Count -ne 1) {
            throw "同名歌曲有 $($sameNames.Count) 条，请用 -TargetAppleMusicId 指定要追加到哪条"
        }
        $target = $selected[0]
    } elseif ($TargetAppleMusicId -gt 0) {
        throw "未找到匹配「$Artist - $Title」的主 ID $TargetAppleMusicId"
    }
}

foreach ($alt in $AlternateIds) {
    if ($alt -eq $AppleMusicId) { throw "备用 ID 不能与本次上传 ID 相同: $alt" }
}

if (-not $target) {
    $argsForAdd = @{
        AppleMusicId = $AppleMusicId; Artist = $Artist; Title = $Title
        TtmlPath = $sourcePath; SkipNextSteps = $true
    }
    if ($Album) { $argsForAdd.Album = $Album }
    if ($AlternateIds.Count -gt 0) { $argsForAdd.AlternateIds = $AlternateIds }

    $indexBytesBeforeSplit = $null
    $lyricPathsBeforeSplit = $null
    if ($splitAlternateOwner) {
        $indexBytesBeforeSplit = [IO.File]::ReadAllBytes($indexPath)
        $lyricPathsBeforeSplit = [System.Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($file in Get-ChildItem -LiteralPath $lyricsDir -File -Recurse) {
            [void]$lyricPathsBeforeSplit.Add($file.FullName)
        }

        $remainingAlternateIds = @($splitAlternateOwner.alternateIds | Where-Object {
            [long]$_ -ne $AppleMusicId
        })
        if ($remainingAlternateIds.Count -gt 0) {
            $splitAlternateOwner.alternateIds = $remainingAlternateIds
        } else {
            $splitAlternateOwner.PSObject.Properties.Remove('alternateIds')
        }
        if (-not [string]$splitAlternateOwner.album -and $ownerAlbum) {
            $splitAlternateOwner | Add-Member -NotePropertyName album -NotePropertyValue $ownerAlbum
        }
        [IO.File]::WriteAllText(
            $indexPath,
            ($index | ConvertTo-Json -Depth 5),
            [Text.UTF8Encoding]::new($false)
        )
    }

    try {
        & $adder @argsForAdd
        $updatedIndex = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $newEntry = @($updatedIndex.entries | Where-Object { [long]$_.appleMusicId -eq $AppleMusicId })
        if ($newEntry.Count -ne 1) { throw "无法找到新添加的 ID: $AppleMusicId" }
    } catch {
        if ($splitAlternateOwner) {
            [IO.File]::WriteAllBytes($indexPath, [byte[]]$indexBytesBeforeSplit)
            foreach ($file in Get-ChildItem -LiteralPath $lyricsDir -File -Recurse) {
                if (-not $lyricPathsBeforeSplit.Contains($file.FullName)) {
                    Remove-Item -LiteralPath $file.FullName -Force
                }
            }
        }
        throw
    }

    if ($separateVersion -or $splitAlternateOwner) {
        Write-Host '检测到同歌手、同歌名的专辑或时间轴不同，已作为独立版本添加。'
    }
    return [pscustomobject]@{
        Action = if ($separateVersion -or $splitAlternateOwner) { 'added-version' } else { 'added' }
        Changed = $true; Path = [string]$newEntry[0].path
        PrimaryId = $AppleMusicId; Artist = [string]$newEntry[0].artist
        Title = [string]$newEntry[0].title; AddedIds = @($AlternateIds)
    }
}

$dest = Get-LyricPath $target
if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
    throw "索引指向的歌词文件不存在: $($target.path)"
}
$existingBytes = [IO.File]::ReadAllBytes($dest)
$existingSha = Get-Sha256 $existingBytes
$albumUpdated = $false
if ($Album -and [string]$target.album -ne $Album) {
    if ($target.PSObject.Properties['album']) {
        $target.album = $Album
    } else {
        $target | Add-Member -NotePropertyName album -NotePropertyValue $Album
    }
    $albumUpdated = $true
}

$requestedIds = @($AlternateIds)
if (-not $idMatched) { $requestedIds = @($AppleMusicId) + $requestedIds }
$newAltIds = @()
$seen = @{}
foreach ($alt in $requestedIds) {
    if ($alt -le 0) { throw "备用 ID 必须为正整数: $alt" }
    # TTML may list the existing primary ID among its Apple Music IDs; it is
    # already represented by the entry and must not be added as an alternate.
    if ($alt -eq [long]$target.appleMusicId) { continue }
    if ($seen.ContainsKey([string]$alt)) { throw "重复的备用 ID: $alt" }
    $seen[[string]$alt] = $true
    $owners = @($index.entries | Where-Object {
        [long]$_.appleMusicId -eq $alt -or @($_.alternateIds) -contains $alt
    })
    if ($owners.Count -gt 1 -or ($owners.Count -eq 1 -and
        [long]$owners[0].appleMusicId -ne [long]$target.appleMusicId)) {
        throw "备用 ID $alt 已属于其他索引记录"
    }
    if ($owners.Count -eq 0) { $newAltIds += [long]$alt }
}

$contentUpdated = $false
if ($idMatched -and -not $idMatchedAsAlternate) {
    if ($sourceSha -ne $existingSha -or $sourceSha -ne [string]$target.sha256 -or
        $sourceBytes.Length -ne [long]$target.sizeBytes) {
        if ($sourcePath -ne $dest) { Copy-Item -LiteralPath $sourcePath -Destination $dest -Force }
        $target.sizeBytes = $sourceBytes.Length
        $target.sha256 = $sourceSha
        $contentUpdated = $true
    }
} elseif ($sourceSha -ne $existingSha) {
    Write-Warning '备用 ID 或同专辑、同时间轴的新 ID 对应内容不同；本次保留已有歌词，不覆盖原文件。'
}

if ($newAltIds.Count -gt 0) {
    $allAlternates = @($target.alternateIds | Where-Object { $null -ne $_ }) + $newAltIds
    if ($target.PSObject.Properties['alternateIds']) {
        $target.alternateIds = @($allAlternates)
    } else {
        $target | Add-Member -NotePropertyName alternateIds -NotePropertyValue @($allAlternates)
    }
}

if (-not $contentUpdated -and $newAltIds.Count -eq 0 -and -not $albumUpdated) {
    Write-Host "歌词和索引已是最新，无需上传：$($target.path)"
    return [pscustomobject]@{
        Action = 'unchanged'; Changed = $false; Path = [string]$target.path
        PrimaryId = [long]$target.appleMusicId; Artist = [string]$target.artist
        Title = [string]$target.title; AddedIds = @()
    }
}

[IO.File]::WriteAllText(
    $indexPath,
    ($index | ConvertTo-Json -Depth 5),
    [Text.UTF8Encoding]::new($false)
)

$action = if ($contentUpdated -and $newAltIds.Count -gt 0) { 'updated-and-alternate' }
          elseif ($contentUpdated) { 'updated' }
          elseif ($albumUpdated) { 'updated' }
          else { 'alternate' }
switch ($action) {
    'alternate'             { Write-Host "已给 $($target.path) 追加备用 ID: $($newAltIds -join ', ')" }
    'updated'               {
        if ($contentUpdated) {
            Write-Host "已覆盖歌词并更新大小和哈希: $($target.path)"
        } else {
            Write-Host "已更新索引中的专辑信息: $($target.path)"
        }
    }
    'updated-and-alternate' { Write-Host "已覆盖歌词并追加备用 ID: $($target.path)" }
}
return [pscustomobject]@{
    Action = $action; Changed = $true; Path = [string]$target.path
    PrimaryId = [long]$target.appleMusicId; Artist = [string]$target.artist
    Title = [string]$target.title; AddedIds = @($newAltIds)
}

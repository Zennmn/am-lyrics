# 维护者指南（审核后上传歌词）

本仓库通过 Issue 接收歌词投稿。投稿者在 Issue 中填写 Apple Music ID、歌手、歌名、TTML 和版权声明，由维护者审核通过后上传。本文档说明审核要点和上传流程。

## 一、审核要点

收到歌词投稿 Issue 后，逐项检查：

1. **Apple Music ID**：必须是正整数，且与 `index.json` 中已有条目不重复（含其他条目的 `alternateIds`）。投稿注明其他地区 ID 时，只有同专辑且时间轴相同才作为 `alternateIds` 收录。
2. **歌手 / 歌名**：填写是否清晰，与投稿文件内容一致。
3. **TTML 内容**：
   - 是 Apple Music Word-TTML，包含 `<tt>`、`<body>`、逐词 `<span>` 时间轴。
   - 不超过 512 KiB，`<p>` 不超过 4096、`<span>` 不超过 65536。
   - 抽查时间轴起点是否对齐，歌词文本无明显乱码或错行。
4. **版权声明**：两个复选框必须勾选。对明显未经授权、整段照搬他人的歌词应拒绝合并。
5. **附件/粘贴内容**：如果 TTML 是附件，下载后解压或读取；如果是粘贴文本，保存为 `.ttml` 文件（UTF-8，LF 行尾）。

审核通过后在 Issue 回复"已通过，正在上传"；不通过则回复原因（ID 重复、TTML 无效、缺少版权声明等），可关闭 Issue。

## 二、自己快速上传（推荐）

把多个 TTML 文件一起拖到仓库根目录的 `upload-lyrics.cmd` 上，即可批量上传；单文件拖拽仍可照常使用。也可以只上传一个文件，在仓库根目录运行：

```powershell
.\upload-lyrics.cmd "C:\歌词\歌手 - 歌名 - 123456789.ttml"
```

脚本会从规范文件名或 TTML 内的 AMLL 元数据自动识别歌手、歌名和 Apple Music ID，缺少时再询问；冲突时提示并默认使用文件名。批量上传会先逐首完成整批 TTML 校验和变更汇总；任一文件未通过校验，整批停止且不会改动仓库。全部通过后只需确认一次，随后统一更新歌词与索引，有实际改动时只创建一个提交并推送。要求 PowerShell 7、Python 3、Git 和推送权限；如果推送失败，本地提交会保留，可处理报错后运行 `git push origin main`。

同一 Apple Music ID 不能重复出现在本批多个文件的主 ID 或备用 ID 中；遇到重复时，脚本会提示并停止。

批量和单文件上传都沿用同一套重复上传规则：歌手和歌名相同的新 ID 若专辑不同，或时间轴不同，会新建独立条目和歌词文件；只有专辑与时间轴都相同，才加入对应条目的 `alternateIds`。已有主 ID 对应的歌词内容不同时会覆盖原文件并重算大小和哈希，内容相同则跳过；备用 ID 不会覆盖主条目的歌词。即使上传文件里的歌手名或歌名与已匹配的 ID 不同，也按索引记录更新。同名条目有多条时，脚本会按专辑和时间轴匹配，仍无法确定时请指定目标主 ID。旧索引条目缺少 `album` 时，脚本会从对应 TTML 读取；`alternateIds` 目前不参与 AM++ 的导入匹配。

只想更新工作区、不自动提交推送时，继续使用底层脚本：

```powershell
# 在本仓库根目录执行
.\tools\add-lyrics.ps1 -AppleMusicId 123456789 -Artist "歌手名" -Title "歌名" -Album "专辑名" -TtmlPath "C:\path\to\投稿的.ttml" -AlternateIds 987654321,555555555
```

脚本会自动：校验 TTML 和 ID 重复（含备用 ID）、按 `歌手 - 歌名 - AppleMusicID.ttml` 命名、复制文件、计算 `sizeBytes`/`sha256` 并追加到 `index.json`。`-Album` 可选；使用 `upload-lyrics.ps1` 时，专辑会从 TTML 的 AMLL 元数据读取，也可通过 `-Album` 覆盖。可选 `-AlternateIds` 收录其他地区 ID，逗号分隔。

`add-lyrics.ps1` 只修改工作区，不会提交。

## 三、手动上传（不用脚本时）

1. 把投稿 TTML 保存为：

```text
am-lyrics/歌手 - 歌名 - AppleMusicID.ttml
```

2. 在 `index.json` 的 `entries` 末尾追加一条：

```json
{
  "appleMusicId": 123456789,
  "artist": "歌手名",
  "title": "歌名",
  "album": "专辑名",
  "displayName": "歌名 - 歌手名",
  "path": "am-lyrics/歌手名 - 歌名 - 123456789.ttml",
  "source": "manual",
  "enabled": true,
  "sizeBytes": 12345,
  "sha256": "（该文件 UTF-8 内容的 SHA-256 小写十六进制）",
  "alternateIds": [987654321]
}
```

（可选）`album`：专辑名；新条目优先从 TTML 元数据读取，旧条目缺失时可由工具回读 TTML。

（可选）`alternateIds`：同一专辑、同一时间轴录音在其他地区的 Apple Music ID 数组，主 ID 仍是 `appleMusicId`（文件名用主 ID）。

3. 计算实际大小和哈希：

```powershell
$bytes = [System.IO.File]::ReadAllBytes("am-lyrics\歌手名 - 歌名 - 123456789.ttml")
$sha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([byte[]]$bytes)).Replace('-','').ToLowerInvariant()
"sizeBytes=$($bytes.Length) sha256=$sha"
```

## 四、上传前校验（每次必做）

```powershell
# 1. 确认所有条目与文件一致（无失配、无孤儿文件）
$index = Get-Content -Raw -Encoding UTF8 "index.json" | ConvertFrom-Json
$errors = @()
foreach ($entry in @($index.entries)) {
    $file = Join-Path (Get-Location) ([string]$entry.path)
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $errors += "缺失:$($entry.appleMusicId)"; continue }
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $sha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([byte[]]$bytes)).Replace('-','').ToLowerInvariant()
    if ($bytes.Length -ne [int64]$entry.sizeBytes -or $sha -ne [string]$entry.sha256) { $errors += "失配:$($entry.appleMusicId)" }
}
if ($errors.Count -eq 0) { "全部一致，共 $($index.entries.Count) 条" } else { $errors }

# 2. 检查 ID 唯一（主 ID + alternateIds 全部纳入）
$allIds = @()
foreach ($entry in @($index.entries)) {
    $allIds += [long]$entry.appleMusicId
    if ($entry.alternateIds) { $allIds += @($entry.alternateIds | ForEach-Object { [long]$_ }) }
}
$dups = @($allIds | Group-Object | Where-Object Count -gt 1)
if ($dups.Count -eq 0) { "ID 唯一（含 alternateIds）" } else { $dups }

# 3. 查看本次改动
git diff
```

## 五、提交并推送

```powershell
git add am-lyrics/ index.json
git diff --cached --check
git commit -m "lyrics: add 歌手 - 歌名 (AppleMusicID)"
git push origin main
```

提交后 `index.json` 变化会立刻被 AM++ 读取到；投稿者在 AM++ 设置页重新导入该 ID 即可生效。

## 六、关闭 Issue

推送成功后，在对应 Issue 回复并关闭：

> 已审核通过并上传。请在 AM++ 设置页重新导入该 Apple Music ID；如果导入时提示"GitHub 未找到可用 TTML"，通常是网络无法访问 raw.githubusercontent.com，可稍后重试。

## 七、下架与删除

- **临时下架**：把该条目 `enabled` 改为 `false`，提交推送；文件保留。
- **彻底删除**：删除对应 TTML 文件和 `index.json` 条目，提交推送。
- 如果收到版权下架请求：优先彻底删除，并在 README 版权段落说明。

## 八、注意事项

- **不要用网页编辑器整行替换 TTML**：GitHub 网页编辑会把文件重写为 LF，导致该条目的 `sizeBytes`/`sha256` 与文件失配；如需修正请重新计算后更新 `index.json`（见第四节）。
- 每次合并前运行第四节校验，确保 `index.json` 与实际文件一致。
- 多个投稿可合并成一次提交，但务必逐条校验。
- 保持 `index.json` 的 `version` 和 `layout` 字段不变。

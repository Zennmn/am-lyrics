# am-lyrics

为 [AM++](https://github.com/Zennmn/AM-plus-plus) 准备的 Apple Music TTML 歌词收藏仓库，按 Apple Music ID 索引。AM++ 模块通过 `main` 分支上的 `index.json` 消费本仓库。

## 目录结构

- `index.json` — AM++ 使用的条目索引：每个 Apple Music ID 一条，包含歌手、歌名、（可选）专辑、文件路径、大小和 sha256。同一录音在不同地区 ID 不同时，可用 `alternateIds` 数组收录其他地区 ID（主 ID 仍为 `appleMusicId`）；同歌手、同歌名但专辑不同或时间轴不同的版本应各自建立独立条目。
- `am-lyrics/` — TTML 文件，命名格式为 `歌手 - 歌名 - AppleMusicID.ttml`。
- `ttml格式.md` — Apple Music TTML 格式参考，供投稿者参考。
- `tools/validate_ttml.py` — TTML 格式校验脚本，按 [ttml格式.md](ttml格式.md) 的规则检查 `am-lyrics/` 下所有文件。

## AM++ 如何使用本仓库

AM++ 读取 `https://raw.githubusercontent.com/Zennmn/am-lyrics/main/index.json`，按 Apple Music ID 精确匹配，再下载索引路径指向的 TTML。用户在 AM++ 设置页的编辑器中显式导入并保存到本地；应用不会在播放时监视本仓库。当前应用按 `appleMusicId`（主 ID）匹配；`alternateIds` 供后续应用版本匹配其他地区 ID，不影响现有导入。

## 提交歌词

[👉 点此提交歌词](https://github.com/Zennmn/am-lyrics/issues/new?template=lyrics-submission.yml)

填写 Apple Music ID、歌手、歌名、TTML 内容和版权声明。TTML 格式请参考 [ttml格式.md](ttml格式.md)，提交前可运行 `python tools/validate_ttml.py` 检测格式错误。维护者审核通过后会代为上传。详见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [维护者指南](MAINTAINING.md)。

## 仓库所有者自己上传

在 Windows 上，可以一次把多个本地 `.ttml` 文件一起拖到仓库根目录的 `upload-lyrics.cmd` 上；只上传一首时也可以直接拖入单个文件。也可以在仓库根目录运行一条命令：

```powershell
.\upload-lyrics.cmd "C:\歌词\歌手 - 歌名 - 123456789.ttml"
```

脚本会从规范文件名或 TTML 内的 AMLL 元数据读取歌手、歌名和 Apple Music ID，并从 TTML 读取专辑；仍缺少的必需字段才会询问。文件名与内嵌信息冲突时会提示，默认使用文件名。TTML 若内嵌多个 Apple Music ID，上传器会把所选主 ID 以外的 ID 一并写入 `alternateIds`。需要本机有 PowerShell 7、Python 3、Git 和本仓库推送权限。也可通过 `& .\tools\upload-lyrics.ps1 -TtmlPath "文件路径" -Album "专辑名" -AlternateIds 987654321,555555555` 手动指定专辑和其他 ID。

批量上传时，脚本会先逐首读取信息并校验整个选择；任一文件未通过校验，整批停止，仓库不会改动。全部通过后，脚本会汇总本次要处理的文件，让用户确认一次；确认后统一更新歌词与 `index.json`，有实际改动时只创建一个提交并推送到 `origin/main`。

同一 Apple Music ID 不能重复出现在本批多个文件的主 ID 或备用 ID 中；遇到重复时，脚本会提示并停止。

批量和单文件上传都按以下重复上传规则处理：

- 歌手、歌名相同而 ID 不同：专辑不同，或时间轴不同，就建立独立条目和歌词文件；专辑和时间轴都相同，才把新 ID 追加到对应条目的 `alternateIds`。同名条目有多条时，先按专辑和时间轴匹配，仍无法确定时询问目标主 ID。
- ID 已属于已有主条目：沿用索引里的歌手名和歌名；歌词内容不同就覆盖原 TTML，并更新 `sizeBytes` 和 `sha256`，内容相同则跳过。已登记为备用 ID 的歌曲只有专辑和时间轴都相同时才共用原 TTML，否则拆成独立条目。即使上传文件里的歌手名或歌名不同，也按该 ID 更新，不因此跳过。

AM++ 当前仅按主 `appleMusicId` 导入；新加的 `alternateIds` 暂不能直接用于导入。

## 版权

歌词和翻译的版权归原始权利人所有，本仓库不主张歌词内容的版权。如果本仓库中的内容侵犯了您的权利，请提交 Issue 或联系仓库所有者，相关内容将被移除。

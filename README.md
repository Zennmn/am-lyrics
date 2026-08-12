# am-lyrics

为 [AM++](https://github.com/Zennmn/AM-plus-plus) 准备的 Apple Music TTML 歌词收藏仓库，按 Apple Music ID 索引。AM++ 模块通过 `main` 分支上的 `index.json` 消费本仓库。

## 目录结构

- `index.json` — AM++ 使用的条目索引：每个 Apple Music ID 一条，包含歌手、歌名、文件路径、大小和 sha256。同一首歌在不同地区 ID 不同时，可用 `alternateIds` 数组收录其他地区 ID（主 ID 仍为 `appleMusicId`）。
- `am-lyrics/` — TTML 文件，命名格式为 `歌手 - 歌名 - AppleMusicID.ttml`。
- `ttml格式.md` — Apple Music TTML 格式参考，供投稿者参考。
- `tools/validate_ttml.py` — TTML 格式校验脚本，按 [ttml格式.md](ttml格式.md) 的规则检查 `am-lyrics/` 下所有文件。

## AM++ 如何使用本仓库

AM++ 读取 `https://raw.githubusercontent.com/Zennmn/am-lyrics/main/index.json`，按 Apple Music ID 精确匹配，再下载索引路径指向的 TTML。用户在 AM++ 设置页的编辑器中显式导入并保存到本地；应用不会在播放时监视本仓库。当前应用按 `appleMusicId`（主 ID）匹配；`alternateIds` 供后续应用版本匹配其他地区 ID，不影响现有导入。

## 提交歌词

[👉 点此提交歌词](https://github.com/Zennmn/am-lyrics/issues/new?template=lyrics-submission.yml)

填写 Apple Music ID、歌手、歌名、TTML 内容和版权声明。TTML 格式请参考 [ttml格式.md](ttml格式.md)，提交前可运行 `python tools/validate_ttml.py` 检测格式错误。维护者审核通过后会代为上传。详见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [维护者指南](MAINTAINING.md)。

## 版权

歌词和翻译的版权归原始权利人所有，本仓库不主张歌词内容的版权。如果本仓库中的内容侵犯了您的权利，请提交 Issue 或联系仓库所有者，相关内容将被移除。

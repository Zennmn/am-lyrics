# am-lyrics

为 [AM++](https://github.com/Zennmn/AM-plus-plus) 准备的 Apple Music TTML 歌词收藏仓库，按 Apple Music ID 索引。AM++ 模块通过 `main` 分支上的 `index.json` 消费本仓库。

其他播放器或工具可参考[第三方接入文档](接入文档.md)。

## 目录结构

- `index.json` — AM++ 使用的条目索引：每个 Apple Music ID 一条，包含歌手、歌名、（可选）专辑、文件路径、大小和 sha256。同一录音在不同地区 ID 不同时，可用 `alternateIds` 数组收录其他地区 ID（主 ID 仍为 `appleMusicId`）；同歌手、同歌名但专辑不同或时间轴不同的版本应各自建立独立条目。
- `am-lyrics/` — TTML 文件，命名格式为 `歌手 - 歌名 - AppleMusicID.ttml`。
- `ttml格式.md` — Apple Music TTML 格式参考，供投稿者参考。
- `tools/validate_ttml.py` — TTML 格式校验脚本，检查格式错误和零时长歌词单元，默认扫描 `am-lyrics/` 下的 TTML 文件。

## AM++ 如何使用本仓库

AM++ 读取 `https://raw.githubusercontent.com/Zennmn/am-lyrics/main/index.json`，按 Apple Music ID 精确匹配，再下载索引路径指向的 TTML。当前 AM++ 同时匹配 `appleMusicId`（主 ID）和 `alternateIds`（备用 ID），同一条目的 ID 共用一份歌词。旧版 AM++ 是否支持备用 ID 取决于所安装的版本。

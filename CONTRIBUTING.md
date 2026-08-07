# Contributing lyrics

Thank you for helping grow the collection. This repository is consumed by the
AM++ module, which fetches `index.json` and exact Apple Music ID matches from
`am-lyrics/` on the `main` branch.

## How to submit lyrics

1. Open the **Lyrics submission** issue form.
2. Provide the numeric Apple Music ID, artist, title, and the TTML content.
3. Confirm the rights declaration checkboxes.
4. A maintainer reviews the submission and uploads it after approval.

You do not need write access to submit. Please do not open pull requests with
manual edits to `index.json` unless asked.

## TTML requirements

- Apple Music Word-TTML: contains `<tt>`, `<body>`, and word-level `<span>`
  timing; `itunes:timing="Word"` is preferred.
- Within AM++ limits: UTF-8 under 512 KiB, fewer than 4096 `<p>` and 65536
  `<span>` elements.
- The lyric file must be placed under `am-lyrics/` with a filename ending in
  `- <appleMusicId>.ttml`.
- Each Apple Music ID must be unique in `index.json`.

## Review expectations

- Content and word timing are checked by a human; CI cannot verify how the
  native Apple Music parser renders the file.
- Merged entries are publicly visible and can be viewed, forked, and copied.
- Lyric and translation rights belong to the original right holders. If you
  did not create the lyric and lack permission to redistribute it, do not
  submit it.

# am-lyrics

A personal collection of Apple Music TTML lyrics for AM++, indexed by Apple
Music ID. The repository is consumed by the AM++ module through
`index.json` on the `main` branch.

## Layout

- `index.json` — entry index used by AM++: one entry per Apple Music ID with
  artist, title, path, size and sha256.
- `am-lyrics/` — TTML files named `Artist - Title - AppleMusicID.ttml`.

## How AM++ uses this repository

AM++ reads `https://raw.githubusercontent.com/Zennmn/am-lyrics/main/index.json`,
matches the exact Apple Music ID, then downloads the TTML at the indexed path.
Users import a lyric explicitly from the AM++ settings editor and save it
locally; the app does not watch this repository at playback time.

## Submitting lyrics

Open the **Lyrics submission** issue form and fill in the Apple Music ID,
artist, title, TTML, and the rights declaration. A maintainer reviews and
uploads submissions after approval. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Rights

Lyrics and translations belong to their original right holders. This
repository does not claim ownership of lyric content. If content here
infringes your rights, open an issue or contact the repository owner and it
will be removed.

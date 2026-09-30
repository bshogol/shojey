# shojey

A tiny music player plugin for the Omarchy shell.

Pick something from the bar, it plays through `mpv` in the background. Because
the system `mpv-mpris` script exposes mpv over MPRIS, Omarchy's media keys, OSD
and media widget control it like any other player.

## Sources

| Source | What | Key needed |
|---|---|---|
| [SomaFM](https://somafm.com) | ~45 curated, ad-free radio channels | no |
| [Radio Paradise](https://radioparadise.com) | 7 ad-free channels, with cover art for the song on air | no |
| [Radio Browser](https://www.radio-browser.info) | ~50k community-listed internet radio stations | no |
| [Audius](https://audius.co) | on-demand tracks: trending and search | no |
| [ccMixter](https://ccmixter.org) | Creative Commons tracks and remixes: editor's picks and search | no |

Audius and ccMixter results are queued as a playlist, so next / previous walk
through them.

## Bar widget

| Click | Action |
|---|---|
| left | open the now-playing card |
| right | play / pause |
| middle | stop |

The card shows artwork, track and source, prev / play / next / favorite, a
LIVE marker or track position, buttons for each source, and your favorites and
recent plays. Everything happens in the card: pick a source and its channels or
search results open in place.

Keys: space play/pause, ←/→ previous/next, f favorite, s/p/r/a/c open
SomaFM/Paradise/Radio/Audius/ccMixter, ↑/↓ and enter in a list, esc back.

Bind the card to a key with:

```
omarchy-shell shell summon boris.shojey
```

## CLI

```
bin/shojey menu                 source picker (default)
bin/shojey soma|paradise|radio|audius|trending|search|ccmixter|favorites
bin/shojey list <source> [query]  print a source's entries as JSON
bin/shojey play <url> [title]   play a stream or file
bin/shojey play-saved <url>     replay a recent or favorite entry
bin/shojey fav [url] [title]    toggle a favorite (default: what's playing)
bin/shojey toggle|stop|status
```

State lives in `$XDG_RUNTIME_DIR/shojey/` (what's playing) and
`$XDG_STATE_HOME/shojey/` (`recent.json`, `favorites.json`).

`SHOJEY_MPV_ARGS` passes extra flags to mpv (e.g. `--ao=null` for silent tests).

## Requirements

`mpv`, `mpv-mpris`, `socat`, `jq`, `curl` — plus Omarchy's `omarchy-menu-select`
and `omarchy-menu-input`.

## Install

```
omarchy plugin add <git-url> --enable
```

For development, symlink the checkout instead:

```
ln -sfn "$PWD" ~/.config/omarchy/plugins/boris.shojey
omarchy-shell shell rescanPlugins
omarchy plugin enable boris.shojey --section right
```

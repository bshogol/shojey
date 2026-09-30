# shojey

A tiny music player plugin for the Omarchy shell.

Pick something from the bar, it plays through `mpv` in the background. Because
the system `mpv-mpris` script exposes mpv over MPRIS, Omarchy's media keys, OSD
and media widget control it like any other player.

## Sources

| Source | What | Key needed |
|---|---|---|
| [SomaFM](https://somafm.com) | ~45 curated, ad-free radio channels | no |
| [Radio Browser](https://www.radio-browser.info) | ~50k community-listed internet radio stations | no |
| [Audius](https://audius.co) | on-demand tracks: trending and search | no |

Audius results are queued as a playlist, so next / previous walk through them.

## Bar widget

| Click | Action |
|---|---|
| left | open the now-playing card |
| right | play / pause |
| middle | stop |

The card shows artwork, track and source, prev / play / next / favorite, a
LIVE marker or track position, buttons for each source, and your favorites and
recent plays. Bind it to a key with:

```
omarchy-shell shell summon boris.shojey
```

## CLI

```
bin/shojey menu                 source picker (default)
bin/shojey soma|radio|audius|trending|search|favorites
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

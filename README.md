# TrafficFlow Tracking for Omarchy

The [TrafficFlow Tracking](https://tracking.trafficflow.ch) macOS menu bar app,
as an [Omarchy](https://omarchy.org) bar widget: your running timer (or today's
hours) in the bar, a play/pause button, and the compact tracker one key away.

```
  ▶ 4:30        idle — today's total; press ▶ to resume the last timer
  ⏸ 0:25        tracking — the running timer; press ⏸ to pause
  ◷             not connected — hover for why
```

| Where | Left press | Right press | Middle press |
| --- | --- | --- | --- |
| **▶ / ⏸** (the wave on the Mac) | start / stop the timer | open the full app | refresh |
| **time** | open the compact tracker | open the full app | refresh |

`SUPER + SHIFT + T` opens the compact tracker from anywhere (after `install` below).

## Install

```sh
omarchy plugin add https://github.com/trafficflowhq/trafficflow-omarchy.git --enable --yes
```

Then, once:

```sh
P=~/.config/omarchy/plugins/trafficflow.tracker/bin
$P/trafficflow-setup token      # paste a token — see below
$P/trafficflow-setup install    # the popover window rule + SUPER+SHIFT+T
```

**The token.** In TrafficFlow go to *Settings → Personal API access*, name a
token (say "Omarchy"), tick **"Can start and stop my timer"**, create it and
paste it into `trafficflow-setup token`. It is written to
`~/.config/trafficflow/token` with mode 600 and sent only in the `Authorization`
header, only to your TrafficFlow. Without the tick the widget still shows your
hours, but the play/pause button opens the tracker instead. `trafficflow-setup
status` tells you what is set up and whether the API answers.

**The popover.** The compact tracker is the web app's `/compact` view in a
Chromium app window. `install` adds a window rule to `~/.config/hypr/bindings.lua`
(inside marker lines, so it is added once and removed whole) that floats it at
344×560 under the top-right of the bar and pins it to every workspace — the Mac
popover, as a window. Close it like any window (`SUPER + W`); the bar refreshes
when it goes.

## How it stays cheap

TrafficFlow's database bills for awake-time, so the widget polls the way the
Mac app does: every 30 s while a tracker window is open, every 60 s while a
timer runs (so a stop on another device shows up), and **not at all when
idle** — then it refreshes only when you press something or a tracker window
opens or closes. The clock ticks locally; the bar never freezes while the API
rests. Both intervals are settings (see below).

## What it knows

Only what `bin/trafficflow-status` is told by `GET /api/v1/timer`: today's
stored seconds and the running timer's start, project and task. **Hours only,
never a rate or an amount** — the API does not carry them, and the widget
draws no number it was not given: when nothing answers it shows a dimmed clock
and says why on hover, not a zero.

Start/stop goes through `POST /api/v1/timer/toggle` with an explicit intent
(`start` or `stop`), so a click on stale state, or a retry after a lost
response, can never flip the timer the wrong way.

## IPC

```sh
omarchy-shell trafficflow.tracker refresh    # re-read the timer now
omarchy-shell trafficflow.tracker toggle     # start / stop
omarchy-shell trafficflow.tracker open       # the compact tracker
omarchy-shell trafficflow.tracker app        # the full app
omarchy-shell trafficflow.tracker demo running   # fixed data, no network — for screenshots
omarchy-shell trafficflow.tracker demo idle
omarchy-shell trafficflow.tracker demo off
```

## Settings

In `~/.config/omarchy/shell.json`, on the widget's layout entry:

| key | default | |
| --- | --- | --- |
| `baseUrl` | `https://tracking.trafficflow.ch` | your TrafficFlow |
| `runningIntervalMs` | `60000` | poll interval while a timer runs (min 15000) |

The scripts read `TRAFFICFLOW_URL` and `TRAFFICFLOW_TOKEN` from the environment
as overrides, e.g. for a staging server.

## Uninstall

```sh
~/.config/omarchy/plugins/trafficflow.tracker/bin/trafficflow-setup remove
omarchy plugin remove trafficflow.tracker --yes
rm -rf ~/.config/trafficflow        # the token
```

and revoke the token under *Settings → Personal API access*.

## Development

`./selftest` checks the manifest, every script, the status/toggle contract in
its demo and failure modes and the setup round trip — no Omarchy needed. On
Omarchy, `omarchy plugin validate .` checks the manifest against the shell.
Pure QML + bash + curl + jq: nothing to compile, works on x86_64 and aarch64
(Asahi) alike.

MIT — see LICENSE.

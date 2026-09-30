# GearShift

Shift a running Claude Code session's model and effort like gears. GearShift is a small macOS app
with a gear stick: drop into Haiku for quick edits, shift up to Opus at max effort for the hard
part, and back down again, without leaving the session. It finds the session's tab in Warp, iTerm2
or Terminal and types `/model …` and `/effort …` into it for you, and it refuses to type anything
when that wouldn't be safe.

Inspired by [ModelShift](https://shiftcc.app); not affiliated.

## Requirements

- macOS 14 or later, on Apple Silicon
- [Claude Code](https://claude.com/claude-code)
- A session running in [Warp](https://www.warp.dev), [iTerm2](https://iterm2.com) or Terminal

## Install

One line, in a terminal:

```sh
claude plugin marketplace add FedericoCharbonnier/gearshift && claude plugin install gearshift@gearshift
```

or, inside Claude Code, the same two steps:

```
/plugin marketplace add FedericoCharbonnier/gearshift
/plugin install gearshift@gearshift
```

The plugin holds the `/gearshift:gearshift` skill. The app itself is downloaded the first time you
run it (see below).

## Use

1. In a Claude Code session, run `/gearshift:gearshift`, or `/gearshift:gearshift <nickname>` to give
   the session a name of your own (e.g. `/gearshift:gearshift backend`). The first run downloads
   GearShift from this repo's GitHub release, checks its SHA-256 against the one pinned in the
   plugin, and installs it at `~/Applications/GearShift.app`. Every run registers the session and
   opens GearShift.
2. Keep that session's input empty and let Claude finish its turn.
3. Drag the knob, or click a gear label. GearShift finds the session's tab and types the gear's
   commands into it. Each command must show up in the session's transcript before the next one is
   typed.

| Gear | Label | Readout | Typed |
|------|-------|---------|-------|
| R | Haiku | HAIKU 4.5 | `/model haiku`, `/effort auto` |
| N | Default | DEFAULT | `/model default`, `/effort auto` |
| 1 | Sonnet · med | SONNET 5 · MED | `/model sonnet`, `/effort medium` |
| 2 | Sonnet · high | SONNET 5 · HIGH | `/model sonnet`, `/effort high` |
| 3 | Opus · med | OPUS 5.5 · MED | `/model opus`, `/effort medium` |
| 4 | Opus · max | OPUS 5.5 · MAX | `/model opus`, `/effort max` |
| 5 | Fable | FABLE 5.1 | `/model fable`, `/effort auto` |

Each gear's label, readout, model and effort can be edited with the sliders button.

**Engine sounds.** Every shift plays a gearbox clack and then a rev in the character of the gear's
model: a buzzy two-stroke for Haiku, a clean four-cylinder for Sonnet, a lumpy V8 for Opus, a
screaming V12 for Fable, and a short idle blip in neutral. More effort revs harder and longer. The
sounds are tuned to be audible on laptop speakers; turn them off with "Mute shift sounds".

**Shifting without leaving your app.** In iTerm2, GearShift types `/model` and `/effort` into the
session in the background: nothing comes to the front, and the window and tab you're looking at stay
put. Warp and Terminal can't be typed into in the background, so they come to the front for about a
second while GearShift types. Then GearShift brings back the app you were in, and in Warp or
Terminal, the window and tab you were on. To stay in the terminal after a shift instead, turn off
Settings › "Return to where I was after shifting (Warp, Terminal)". If you move to another app
during a shift, GearShift leaves you there.

GearShift floats above other windows (and over full-screen terminals) so it stays in view after a
shift; turn that off with Settings › "Keep GearShift above other windows".

Connect as many sessions as you like: the first one is selected, later ones are only announced
("‹name› connected") unless nothing is selected; pick one from the green SESSION strip.

**TURBO.** The red button next to Settings asks for a password. Ask around for it.

## Permissions

- **Accessibility** (System Settings › Privacy & Security › Accessibility), asked for on the first
  shift. GearShift needs it to read window titles, switch Warp tabs and type. Until it's granted the
  footer shows a "grant Accessibility" button, and nothing is typed.
- **Automation**, for iTerm2 and Terminal only: the first shift into each asks "GearShift wants
  access to control …". It's how GearShift finds the tab with the session's tty.

The release is ad-hoc signed, so macOS treats each new version as a new app: after an update, grant
Accessibility again (remove the old GearShift entry first if it's still listed).

## Safety, in brief

GearShift types only into the session's own tab, and only while Claude is idle there. Before each
command and each Return it checks again that the terminal is frontmost on that tab, that no modifier
key or mouse button is held, and that Claude isn't working or waiting for you. If any check fails,
or the whole shift takes longer than 10 seconds, it stops and says why. Keys are sent only to the
terminal's process. See [What GearShift refuses to do](#what-gearshift-refuses-to-do).

## Limitations

- A draft in the session's input gets submitted along with the command: keep the input empty.
- Shifting only works while the session is idle.
- Switching models costs the prompt cache: the next turn re-reads the whole conversation uncached.
- GearShift can't ask Claude Code which model is active; the gear shown is the last one it shifted
  that session into.
- In Warp, a session needs a title (`/rename` it) to be told apart from other untitled sessions.
- Other terminals (tmux, editors' terminals, Ghostty, …) are listed but never shifted.

More in [Limitations in detail](#limitations-in-detail).

## Update and uninstall

From a shell: `claude plugin marketplace update gearshift`, then
`claude plugin update gearshift@gearshift`, and restart Claude Code. The next `/gearshift:gearshift`
replaces the app with the version the plugin pins, quitting it first if it's running.

To uninstall: `/plugin uninstall gearshift@gearshift`, then delete `~/Applications/GearShift.app`
and `~/Library/Application Support/GearShift`.

## Build from source

With the Swift Command Line Tools (Swift 5.10):

```sh
make test      # skill tests and core tests
make install   # builds GearShift.app, copies it to ~/Applications, installs the skill as /gearshift
make run       # install, then open the app
```

`make install` puts the skill at `~/.claude/skills/gearshift/` without the pinned app version, so
it never downloads anything and is invoked as `/gearshift`. An installed gearshift plugin shadows
it. Rebuilds keep the permission grants only if they're signed with the same identity: `make` uses
a local "GearShift Local" code-signing identity if you have one, and ad-hoc signing otherwise
(`make app SIGN_IDENTITY=-` forces ad-hoc).

To release: `make version V=2.2.0` sets the version in `Resources/Info.plist` and
`.claude-plugin/plugin.json` (plugin updates are keyed on it), then `make release` builds an
ad-hoc signed `build/GearShift.zip`, writes its SHA-256 and version to
`skills/gearshift/APP_SHA256` and `APP_VERSION`, and prints the commit, tag and
`gh release create` steps. Upload exactly that zip.

`register.sh` honours a few environment variables, mainly for tests: `GEARSHIFT_APP` (where the
app lives), `GEARSHIFT_NO_INSTALL=1` (never download or replace it), `GEARSHIFT_RELEASE_URL`,
`GEARSHIFT_NO_OPEN=1`, `GEARSHIFT_CLAUDE_HOME` and `GEARSHIFT_SESSIONS_DIR`.

## How it works

### Sessions and nicknames

The SESSION strip shows the selected session's colour dot and nickname (or its Claude title), and
under it `folder · branch · model`, e.g. `gearshift · main · opus 5.5`. Clicking it lists every
connected session with its terminal and its last prompt, e.g.
`Terminal · gearshift · main · opus 5.5`. The model is the one the session last answered with, or
the one a later `/model` switched to.

A nickname is 1–24 letters, digits, spaces, `_`, `.` or `-`; anything else is refused. Running the
skill again without one keeps it, and giving another replaces it. Each nickname (or, without one,
each session) always gets the same colour. Nicknames are only for you: GearShift still finds the
session's tab by its Claude title (Warp) or its tty (iTerm2, Terminal).

Models may contain only letters, digits and `. _ : [ ] -`. The config lives in
`~/Library/Application Support/GearShift/config.json`, and connected sessions are in
`…/GearShift/sessions/`.

The gear shown is the last one GearShift shifted that session into (the model in the SESSION strip
is read from the transcript). It shows `?` when a shift stopped half way, for example when the
model was set but the effort wasn't.

### Supported terminals

The skill records the terminal from `TERM_PROGRAM`, which Claude Code passes on to it, and the
tty of the Claude Code process (e.g. `/dev/ttys007`).

| Terminal | `TERM_PROGRAM` | How the tab is found | How GearShift knows Claude is idle |
|----------|----------------|----------------------|------------------------------------|
| Warp | `WarpTerminal` | window title (`✳ <title>`), cycling tabs through the Tab menu | the title's glyph, and the transcript |
| iTerm2 | `iTerm.app` | the session (split pane) whose tty is the session's, through AppleScript | the transcript |
| Terminal | `Apple_Terminal` | the tab whose tty is the session's, through AppleScript | the transcript |

Anything else (tmux, an editor's terminal, Ghostty, …) is listed but not shifted: the hint says
"GearShift supports Warp, iTerm2 and Terminal; this session runs in …". Sessions connected before
terminals were recorded count as Warp's until the skill runs in them again.

In iTerm2 and Terminal, exactly one tab (or pane) must have the session's tty; GearShift selects
it, brings its window to the front and activates the app. Before each command and before each
Return it checks through AppleScript that the app is frontmost and its front window's selected
tab (iTerm2: current session) is still on that tty, and through Accessibility that this window has
keyboard focus. It never uses iTerm2's `write text` or Terminal's `do script`: keys are posted to
the app's process like in Warp, so the same checks guard every keystroke.

Without a title glyph to read, "idle" comes from the transcript: the last turn must have ended (an
assistant message with `stop_reason` `end_turn`, a `turn_duration` line, or an interruption), and
no tool call may be waiting for its result.

### Automation permission

If you click Don't Allow when GearShift asks to control iTerm2 or Terminal, shifts into that app
stop with "allow GearShift to control Terminal in System Settings › Privacy & Security ›
Automation", and the footer shows an "allow Automation" button that opens that pane. GearShift
isn't sandboxed and has no hardened runtime, so no entitlement is needed: only the usage
description in its Info.plist. An ad-hoc signed rebuild counts as a new app to macOS and asks
again.

### What GearShift refuses to do

It types nothing, and the hint says why, when:

- the session runs in a terminal other than Warp, iTerm2 or Terminal, or its tty wasn't recorded
- (Warp) two live sessions share a title, or two have no title yet (`/rename` one, e.g.
  `/rename backend`); the session's tab can't be found, or two Warp tabs show the same title
- (iTerm2, Terminal) no tab has the session's tty, or more than one does, or two connected
  sessions registered the same tty
- Claude is working (Warp: the tab's glyph is a spinner, not `✳`; iTerm2 and Terminal: the
  transcript shows a turn in progress), or waiting for you (a permission prompt or a question)
- the terminal isn't frontmost on that tab, a modifier key or mouse button is held, or the session
  ended
- GearShift isn't allowed to control iTerm2 or Terminal (Automation)
- the whole shift takes longer than 10 seconds

These checks run again right before each keystroke. Keys are sent only to the terminal's process.

### Limitations in detail

- **A session without a title** (Claude Code hasn't named it yet, and it wasn't `/rename`d) has the
  generic tab title `Claude Code`. GearShift looks for that tab only while it is the only connected
  session without a title, and, as always, only if exactly one Warp tab shows it: an untitled
  session that isn't connected to GearShift shows up as a second `Claude Code` tab and makes the
  shift refuse. But two such tabs side by side look like one (see below), so the command could land
  in the other session; GearShift then says it couldn't confirm it in this one. `/rename` the
  session to be sure: the SESSION strip says `untitled` until it has a title.
- **A draft in the session's input gets submitted.** The command is typed after whatever is
  there, and Return sends it all.
- A dialog that leaves no trace in the transcript (for example a `/model` picker left open) can't
  be detected.
- Under tmux the tab glyph never animates, so only the transcript shows that Claude is busy. With
  Claude Code's `showStatusInTerminalTab` setting, titles have no glyph, and Warp tabs are never
  found. (tmux sets `TERM_PROGRAM=tmux`, so a session started in tmux is refused as "tmux".)
- Two neighbouring Warp tabs with the same title can't be told apart. A minimized Warp window
  can't be searched, so shifting is refused until you restore it. (A minimized Terminal window is
  restored.)
- Warp must keep "Switch to Next Tab" and "Switch to Previous Tab" in its Tab menu.
- In iTerm2 and Terminal, a turn that stopped without writing its end to the transcript (e.g. a
  prompt that failed before any answer) looks busy until the next turn ends.
- With "Secure Keyboard Entry" on in iTerm2 or Terminal, typed keys may not arrive; GearShift then
  says it couldn't confirm the command.
- iTerm2 and Terminal support are built against their AppleScript dictionaries (iTerm2 3.7,
  macOS 26's Terminal), whose scripts compile, but haven't been tried live yet.
- The app isn't notarized. The skill downloads it with `curl` (so it isn't quarantined) and
  installs it only if its SHA-256 matches the one pinned in the plugin.

## License

MIT. See [LICENSE](LICENSE).

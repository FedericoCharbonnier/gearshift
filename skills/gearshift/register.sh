#!/usr/bin/env bash
# Registers a Claude Code session with GearShift: writes a JSON record the app polls, then opens
# (or focuses) the app. Invoked by the `/gearshift` skill's injected command.
#
# Usage: register.sh <sessionId> [nickname]
#
# The nickname (from `/gearshift <nickname>`) is 1–24 characters of letters, digits, space, `_`,
# `.` and `-`; anything else is refused. An empty one means none was given: a nickname the session
# was registered with before is kept.
#
# Env overrides (used by tests, and by anyone who wants to avoid touching the real filesystem):
#   GEARSHIFT_CLAUDE_HOME   default: $HOME/.claude               (where transcripts live)
#   GEARSHIFT_SESSIONS_DIR  default: $HOME/Library/Application Support/GearShift/sessions
#   GEARSHIFT_APP           default: $HOME/Applications/GearShift.app
#   GEARSHIFT_NO_OPEN=1     skip `open`-ing the app (tests always set this)
#   GEARSHIFT_NO_INSTALL=1  skip installing or updating the app (see step 9)
#   GEARSHIFT_RELEASE_URL   default: the GitHub release zip for APP_VERSION
#   GEARSHIFT_TEST_ARCH, GEARSHIFT_TEST_MACOS_VERSION
#                           stand in for the machine's architecture and macOS version (tests only)
set -euo pipefail

fail() {
    echo "GearShift: $1" >&2
    exit 1
}

session_id="${1:-}"
nickname_arg="${2:-}"

# 1. Validate that the session id looks like a UUID.
uuid_pattern='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
if [[ -z "$session_id" ]]; then
    fail "no session id given"
fi
if [[ ! "$session_id" =~ $uuid_pattern ]]; then
    fail "\"$session_id\" doesn't look like a session id"
fi

# 2. Validate the nickname. Claude Code pastes the skill's arguments into the command without
#    shell-escaping them (the skill puts them in single quotes), so this is where they're checked.
#    `C` collation keeps the ranges ASCII-only.
trim_spaces() {
    local s="$1"
    s="${s#"${s%%[! ]*}"}"
    s="${s%"${s##*[! ]}"}"
    printf '%s' "$s"
}

is_valid_nickname() {
    local LC_ALL=C
    [[ "$1" =~ ^[A-Za-z0-9\ _.-]{1,24}$ ]]
}

# More than two arguments: a quote in the nickname split it.
nickname="$(trim_spaces "$nickname_arg")"
if [[ $# -gt 2 ]] || { [[ -n "$nickname" ]] && ! is_valid_nickname "$nickname"; }; then
    fail "a nickname must be 1–24 letters, digits, spaces, or _ . - (e.g. backend)"
fi

claude_home="${GEARSHIFT_CLAUDE_HOME:-$HOME/.claude}"
sessions_dir="${GEARSHIFT_SESSIONS_DIR:-$HOME/Library/Application Support/GearShift/sessions}"
app_path="${GEARSHIFT_APP:-$HOME/Applications/GearShift.app}"

# 3. cwd.
cwd="$PWD"

# 4. Find the transcript: the first match of <claude_home>/projects/*/<id>.jsonl. A brand-new
#    session has no transcript until its first message is saved, and /gearshift is often that first
#    message, so fall back to where Claude Code will create it: the physical cwd with every
#    non-alphanumeric character replaced by "-".
transcript_path=""
shopt -s nullglob
for candidate in "$claude_home"/projects/*/"$session_id".jsonl; do
    transcript_path="$candidate"
    break
done
shopt -u nullglob
if [[ -z "$transcript_path" ]]; then
    physical_cwd="$(pwd -P)"
    transcript_path="$claude_home/projects/${physical_cwd//[^A-Za-z0-9]/-}/$session_id.jsonl"
fi

# 5. claudePid: walk up from $PPID to the Claude Code process. Its executable is `claude` or
#    `claude.exe` (the native build), or it's a node script that renamed itself `claude`, so the
#    executable name (`ps -c`) and the first word of its command line are both checked. The
#    session is dropped from GearShift when this process exits, so a wrong pid must never be kept.
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

is_claude_name() {
    [[ "$1" == "claude" || "$1" == "claude.exe" ]]
}

find_claude_pid() {
    local pid="$PPID"
    local hops=0
    while [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 && "$hops" -lt 32 ]]; do
        local comm args first_word ppid
        comm="$(trim "$(ps -c -o comm= -p "$pid" 2>/dev/null || true)")"
        args="$(trim "$(ps -o args= -p "$pid" 2>/dev/null || true)")"
        first_word="${args%% *}"
        if is_claude_name "${comm##*/}" || is_claude_name "${first_word##*/}"; then
            echo "$pid"
            return 0
        fi
        ppid="$(trim "$(ps -o ppid= -p "$pid" 2>/dev/null || true)")"
        if [[ -z "$ppid" || "$ppid" == "$pid" ]]; then
            break
        fi
        pid="$ppid"
        hops=$((hops + 1))
    done
    return 1
}

claude_pid="$(find_claude_pid || true)"
if [[ -z "$claude_pid" ]]; then
    fail "couldn't find the Claude Code process"
fi

# 6. The terminal: GearShift finds a Warp tab by its title, and an iTerm2 or Terminal tab by its
#    tty. TERM_PROGRAM is set by the terminal in its shells, and Claude Code 2.1.282 passes it on to
#    this injected command (it runs like a Bash tool call, with Claude Code's environment). Claude
#    Code drops it for sessions its background daemon starts, which then count as "other", as do
#    tmux (TERM_PROGRAM=tmux), editors' terminals and anything else.
terminal_kind() {
    case "${TERM_PROGRAM:-}" in
        WarpTerminal) echo "warp" ;;
        iTerm.app) echo "iterm" ;;
        Apple_Terminal) echo "terminal" ;;
        *) echo "other" ;;
    esac
}

is_plain_name() {
    local LC_ALL=C
    [[ "$1" =~ ^[A-Za-z0-9._-]{1,32}$ ]]
}

terminal="$(terminal_kind)"
# For "other", the program's own name, so the app can say which terminal it doesn't support. Only a
# plain name is kept: it comes from the environment.
term_program_json=""
if [[ "$terminal" == "other" ]] && is_plain_name "${TERM_PROGRAM:-}"; then
    term_program_json=",\"termProgram\":\"$TERM_PROGRAM\""
fi

# 7. The Claude Code process's controlling tty (e.g. ttys007), which is what iTerm2 and Terminal
#    report for the tab it runs in. None (`??`) or anything unexpected is left out.
tty_json=""
claude_tty="$(trim "$(ps -o tty= -p "$claude_pid" 2>/dev/null || true)")"
if [[ "$claude_tty" =~ ^ttys[0-9]{1,5}$ ]]; then
    tty_json=",\"tty\":\"/dev/$claude_tty\""
fi

# 8. Reject control characters in cwd / transcript path, then escape \ and " for JSON.
has_control_chars() {
    [[ "$1" =~ [[:cntrl:]] ]]
}
if has_control_chars "$cwd"; then
    fail "cwd contains control characters"
fi
if has_control_chars "$transcript_path"; then
    fail "transcript path contains control characters"
fi

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

cwd_json="$(json_escape "$cwd")"
transcript_json="$(json_escape "$transcript_path")"
# UTC with milliseconds: GearShift selects by the newest registration, and two can land in the same
# second. `$EPOCHREALTIME` needs bash 5; perl ships with macOS; whole seconds otherwise.
utc_timestamp() {
    local now seconds fraction
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        now="$EPOCHREALTIME"
    else
        now="$(perl -MTime::HiRes=time -e 'printf "%.6f", time' 2>/dev/null || date +%s)"
    fi
    seconds="${now%%[.,]*}"
    fraction="${now#"$seconds"}"
    fraction="${fraction#[.,]}000"
    printf '%s.%sZ' "$(date -u -r "$seconds" +%Y-%m-%dT%H:%M:%S)" "${fraction:0:3}"
}
registered_at="$(utc_timestamp)"

# 9. Install the app, or update it, when it's missing or isn't the version this skill was released
#    with: the release zip is downloaded, checked against the SHA-256 the skill ships with, and
#    swapped in. APP_VERSION and APP_SHA256 are written next to this script by `make release`; a
#    skill without them (`make install-skill`, for development) leaves the app to `make install`.
skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_bundle_id="app.gearshift.GearShift"

app_version_of() {
    plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
}

is_apple_silicon() {
    if [[ -n "${GEARSHIFT_TEST_ARCH:-}" ]]; then
        [[ "$GEARSHIFT_TEST_ARCH" == "arm64" ]]
        return
    fi
    # A shell running under Rosetta reports x86_64 from `uname -m`, so ask the hardware too.
    [[ "$(uname -m)" == "arm64" || "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]
}

is_macos_14_or_later() {
    local version major
    version="${GEARSHIFT_TEST_MACOS_VERSION:-$(sw_vers -productVersion 2>/dev/null || true)}"
    major="${version%%.*}"
    [[ "$major" =~ ^[0-9]+$ && "$major" -ge 14 ]]
}

# Quits GearShift if it's running from $1, and waits up to 3 s for it to exit.
quit_running_app() {
    local executable="$1/Contents/MacOS/GearShift" pid running=""
    for pid in $(pgrep -x GearShift 2>/dev/null || true); do
        if [[ "$(ps -o comm= -p "$pid" 2>/dev/null || true)" == "$executable" ]]; then
            running="$pid"
        fi
    done
    [[ -z "$running" ]] && return 0
    osascript -e "quit app id \"$app_bundle_id\"" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        kill -0 "$running" 2>/dev/null || return 0
        sleep 0.1
    done
}

# Moves the app bundle $1 to $2: first next to it, then swapped in, so $2 is never half-written.
swap_in_app() {
    local new_app="$1" dest="$2" parent staging old
    parent="$(dirname "$dest")"
    mkdir -p "$parent"
    staging="$parent/.GearShift.app.new.$$"
    old="$parent/.GearShift.app.old.$$"
    rm -rf "$staging" "$old"
    mv "$new_app" "$staging" || { rm -rf "$staging"; fail "couldn't copy the app to \"$parent\""; }
    if [[ -e "$dest" ]]; then
        mv "$dest" "$old" || { rm -rf "$staging"; fail "couldn't replace \"$dest\""; }
    fi
    if ! mv "$staging" "$dest"; then
        [[ -e "$old" ]] && mv "$old" "$dest"
        rm -rf "$staging"
        fail "couldn't replace \"$dest\""
    fi
    rm -rf "$old"
}

install_app() {
    local version="$1" sha="$2" dest="$3" url work zip actual unpacked
    is_apple_silicon || fail "GearShift needs a Mac with Apple Silicon"
    is_macos_14_or_later || fail "GearShift needs macOS 14 or later"
    url="${GEARSHIFT_RELEASE_URL:-https://github.com/FedericoCharbonnier/gearshift/releases/download/v$version/GearShift.zip}"
    work="$(mktemp -d "${TMPDIR:-/tmp}/gearshift.XXXXXX")"
    # Removed however this script exits.
    install_work_dir="$work"
    trap 'rm -rf "$install_work_dir"' EXIT
    zip="$work/GearShift.zip"
    curl -fsSL --max-time 60 -o "$zip" "$url" 2>/dev/null || fail "couldn't download GearShift $version from $url"
    actual="$(shasum -a 256 "$zip" | awk '{print $1}')"
    if [[ "$actual" != "$sha" ]]; then
        rm -f "$zip"
        fail "the downloaded GearShift $version doesn't match its checksum, so it wasn't installed"
    fi
    mkdir "$work/unpacked"
    ditto -x -k "$zip" "$work/unpacked" 2>/dev/null || fail "couldn't unzip GearShift $version"
    unpacked="$work/unpacked/GearShift.app"
    if [[ "$(app_version_of "$unpacked")" != "$version" ]]; then
        fail "the downloaded GearShift isn't version $version"
    fi
    quit_running_app "$dest"
    swap_in_app "$unpacked" "$dest"
    xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
    echo "GearShift $version installed: allow it in System Settings › Privacy & Security › Accessibility the first time you shift."
}

if [[ "${GEARSHIFT_NO_INSTALL:-}" != "1" && -f "$skill_dir/APP_VERSION" ]]; then
    wanted_version="$(tr -d '[:space:]' < "$skill_dir/APP_VERSION")"
    wanted_sha="$(tr -d '[:space:]' < "$skill_dir/APP_SHA256" 2>/dev/null || true)"
    if [[ ! "$wanted_version" =~ ^[0-9]+(\.[0-9]+){0,3}$ || ! "$wanted_sha" =~ ^[0-9a-f]{64}$ ]]; then
        fail "the skill's APP_VERSION or APP_SHA256 is malformed; reinstall the plugin"
    fi
    if [[ ! -d "$app_path" || "$(app_version_of "$app_path")" != "$wanted_version" ]]; then
        install_app "$wanted_version" "$wanted_sha" "$app_path"
    fi
fi

mkdir -p "$sessions_dir"

dest_file="$sessions_dir/$session_id.json"

# 10. Without a new nickname, keep the one this session was registered with, if it's still valid.
if [[ -z "$nickname" && -f "$dest_file" ]]; then
    previous="$(plutil -extract nickname raw -o - "$dest_file" 2>/dev/null || true)"
    if is_valid_nickname "$previous"; then
        nickname="$previous"
    fi
fi
nickname_json=""
if [[ -n "$nickname" ]]; then
    nickname_json=",\"nickname\":\"$(json_escape "$nickname")\""
fi

# The registry only reads *.json files, so the temp file must not end in .json while it's being
# written, and must be moved into place atomically.
tmp_file="$sessions_dir/.$session_id.json.tmp"

printf '{"sessionId":"%s","cwd":"%s","transcriptPath":"%s","claudePid":%s,"registeredAt":"%s"%s,"terminal":"%s"%s%s}\n' \
    "$session_id" "$cwd_json" "$transcript_json" "$claude_pid" "$registered_at" "$nickname_json" \
    "$terminal" "$term_program_json" "$tty_json" > "$tmp_file"
mv "$tmp_file" "$dest_file"

# 11. Open (or focus) the app, unless suppressed for tests.
if [[ "${GEARSHIFT_NO_OPEN:-}" != "1" ]]; then
    if [[ -d "$app_path" ]]; then
        open "$app_path"
    else
        echo "GearShift: app not found at \"$app_path\" — reinstall the gearshift plugin, or run \`make install\` from source" >&2
    fi
fi

# 12. Status line. In Warp, a session without a title yet shows Claude Code's generic "Claude Code"
#     tab title, which GearShift can use only while no other connected session is untitled. iTerm2
#     and Terminal tabs are found by tty instead; any other terminal can't be shifted.
folder_name="$(basename "$cwd")"
short_id="${session_id:0:8}"
status="GearShift: connected \"$folder_name\" ($short_id)"
if [[ -n "$nickname" ]]; then
    status="$status as \"$nickname\""
fi
case "$terminal" in
    warp)
        if [[ ! -f "$transcript_path" ]] || ! grep -q -F -e '-title"' "$transcript_path" 2>/dev/null; then
            status="$status. It has no title yet: /rename it (e.g. /rename backend) so GearShift can tell its Warp tab apart"
        fi
        ;;
    iterm | terminal)
        if [[ -z "$tty_json" ]]; then
            status="$status, but its tty wasn't found, so GearShift can't shift it"
        fi
        ;;
    *)
        other_name="another terminal"
        if is_plain_name "${TERM_PROGRAM:-}"; then
            other_name="$TERM_PROGRAM"
        fi
        status="$status, but GearShift can only shift sessions in Warp, iTerm2 and Terminal, and this one runs in $other_name"
        ;;
esac
echo "$status"

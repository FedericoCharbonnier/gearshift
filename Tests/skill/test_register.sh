#!/usr/bin/env bash
# Tests for skills/gearshift/register.sh. Runs entirely against temp directories via the GEARSHIFT_*
# overrides; never touches the real ~/Library/Application Support/GearShift or ~/Applications, opens
# the app, or downloads anything but local file:// fixtures.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
skill_src="$repo_root/skills/gearshift"
register_sh="$skill_src/register.sh"

failures=0
passes=0

pass() {
    passes=$((passes + 1))
}

fail() {
    failures=$((failures + 1))
    echo "  ✗ $1" >&2
}

assert_equal() {
    local actual="$1" expected="$2" message="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass
    else
        fail "$message: expected [$expected], got [$actual]"
    fi
}

assert_true() {
    local condition="$1" message="$2"
    if [[ "$condition" == "true" ]]; then
        pass
    else
        fail "$message"
    fi
}

# Sets up a fresh fake HOME with a fake transcript for session $1, returns via globals. Also makes
# fake Claude Code launchers: symlinks to bash named like the real executables, so `ps` reports
# them as `claude` / `claude.exe` and register.sh's walk up the process tree finds them.
make_fixture() {
    local session_id="$1"
    fixture_dir="$(mktemp -d)"
    claude_home="$fixture_dir/claude-home"
    sessions_dir="$fixture_dir/sessions"
    project_dir="$claude_home/projects/-some-project"
    mkdir -p "$project_dir" "$fixture_dir/bin"
    echo '{"type":"ai-title","aiTitle":"Test session"}' > "$project_dir/$session_id.jsonl"
    ln -s /bin/bash "$fixture_dir/bin/claude"
    ln -s /bin/bash "$fixture_dir/bin/claude.exe"
}

cleanup() {
    [[ -n "${fixture_dir:-}" ]] && rm -rf "$fixture_dir"
}
trap cleanup EXIT

# Runs register.sh in directory $2 for session $3 (and nickname $4, if given) as a grandchild of
# launcher $1 (a fake `claude`), with a plain bash in between, so the walk has to go up more than
# one level. Sets: output, status, launcher_pid. The trailing `exit`s keep bash from exec-ing the
# next process in its place.
# The terminal the fake session runs in, as the TERM_PROGRAM register.sh sees; "-" leaves it unset.
# Set explicitly, so the results don't depend on the terminal the tests run in.
term_program="WarpTerminal"

# Sets `term_env`: the `env` prefix that gives the command `term_program`.
set_term_env() {
    term_env=(env -u TERM_PROGRAM)
    if [[ "$term_program" != "-" ]]; then
        term_env+=("TERM_PROGRAM=$term_program")
    fi
}

run_under() {
    local launcher="$1" dir="$2" id="$3"
    local pid_file="$fixture_dir/launcher.pid"
    local args=("$id")
    if [[ $# -ge 4 ]]; then
        args+=("$4")
    fi
    rm -f "$pid_file"
    set_term_env
    set +e
    output="$(cd "$dir" && "${term_env[@]}" GEARSHIFT_NO_OPEN=1 GEARSHIFT_NO_INSTALL=1 GEARSHIFT_CLAUDE_HOME="$claude_home" GEARSHIFT_SESSIONS_DIR="$sessions_dir" \
        "$launcher" -c 'echo $$ > "$1"; shift; /bin/bash -c '"'"'"$0" "$@"; exit $?'"'"' "$@"; exit $?' \
        launcher "$pid_file" "$register_sh" "${args[@]}" 2>&1)"
    status=$?
    set -e
    launcher_pid="$(cat "$pid_file" 2>/dev/null || true)"
}

# Like run_under, but the fake claude runs on a pseudo-terminal of its own (through `script`), as it
# would in a terminal tab. Sets: output, status, launcher_pid, launcher_tty (e.g. ttys012).
run_on_tty() {
    local launcher="$1" dir="$2" id="$3"
    local pid_file="$fixture_dir/launcher.pid" tty_file="$fixture_dir/launcher.tty"
    local out_file="$fixture_dir/register.out" status_file="$fixture_dir/register.status"
    rm -f "$pid_file" "$tty_file" "$out_file" "$status_file"
    set_term_env
    (cd "$dir" && "${term_env[@]}" GEARSHIFT_NO_OPEN=1 GEARSHIFT_NO_INSTALL=1 GEARSHIFT_CLAUDE_HOME="$claude_home" GEARSHIFT_SESSIONS_DIR="$sessions_dir" \
        OUT_FILE="$out_file" STATUS_FILE="$status_file" \
        script -q /dev/null "$launcher" -c 'echo $$ > "$1"; ps -o tty= -p $$ > "$2"; shift 2; /bin/bash -c '"'"'"$0" "$@" > "$OUT_FILE" 2>&1; echo $? > "$STATUS_FILE"'"'"' "$@"; exit 0' \
        launcher "$pid_file" "$tty_file" "$register_sh" "$id") < /dev/null > /dev/null 2>&1 || true
    output="$(cat "$out_file" 2>/dev/null || true)"
    status="$(cat "$status_file" 2>/dev/null || echo "no status")"
    launcher_pid="$(cat "$pid_file" 2>/dev/null || true)"
    launcher_tty="$(tr -d ' \r\n' < "$tty_file" 2>/dev/null || true)"
}

# The record's value for key $2 in file $1, or "(none)" when it has no such key.
record_value() {
    plutil -extract "$2" raw -o - "$1" 2>/dev/null || echo "(none)"
}

echo "▸ happy path"
session_id="11111111-2222-3333-4444-555555555555"
make_fixture "$session_id"
work_dir="$fixture_dir/work dir with \"quote\""
mkdir -p "$work_dir"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id"
assert_equal "$status" "0" "happy path exit code ($output)"

record_file="$sessions_dir/$session_id.json"
if [[ -f "$record_file" ]]; then
    pass
else
    fail "record file was not created at $record_file"
fi

# No stray temp files left behind.
leftover="$(find "$sessions_dir" -maxdepth 1 -name '.*.tmp' 2>/dev/null || true)"
assert_equal "$leftover" "" "no leftover temp files"

if [[ -f "$record_file" ]]; then
    contents="$(cat "$record_file")"
    for key in sessionId cwd transcriptPath claudePid registeredAt; do
        if [[ "$contents" == *"\"$key\""* ]]; then
            pass
        else
            fail "missing key \"$key\" in record: $contents"
        fi
    done

    # transcriptPath is correct (escaped backslashes undone isn't needed here: no backslashes on
    # this path, but the embedded quote in cwd must have been escaped).
    expected_transcript="$claude_home/projects/-some-project/$session_id.jsonl"
    escaped_transcript="${expected_transcript//\\/\\\\}"
    escaped_transcript="${escaped_transcript//\"/\\\"}"
    if [[ "$contents" == *"\"transcriptPath\":\"$escaped_transcript\""* ]]; then
        pass
    else
        fail "transcriptPath not as expected: $contents"
    fi

    # The embedded double quote in cwd must appear escaped, not raw.
    if [[ "$contents" == *'\"quote\"'* ]]; then
        pass
    else
        fail "cwd quote not escaped: $contents"
    fi

    # Valid JSON, per plutil (macOS base tool, no jq/python dependency).
    if plutil -convert json -o - "$record_file" >/dev/null 2>&1; then
        pass
    else
        fail "record is not valid JSON per plutil: $contents"
    fi

    # registeredAt is an ISO 8601 UTC string with milliseconds.
    registered_at="$(plutil -extract registeredAt raw -o - "$record_file" 2>/dev/null || true)"
    if [[ "$registered_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]; then
        pass
    else
        fail "registeredAt doesn't look like ISO 8601 UTC with milliseconds: $registered_at"
    fi

    # claudePid is the (fake) Claude Code process, found by walking up from register.sh.
    claude_pid="$(plutil -extract claudePid raw -o - "$record_file" 2>/dev/null || true)"
    assert_equal "$claude_pid" "$launcher_pid" "claudePid is the claude ancestor"
fi

echo "▸ claude.exe (the native build) is found too"
rm -f "$record_file"
run_under "$fixture_dir/bin/claude.exe" "$work_dir" "$session_id"
assert_equal "$status" "0" "claude.exe exit code ($output)"
claude_pid="$(plutil -extract claudePid raw -o - "$record_file" 2>/dev/null || true)"
assert_equal "$claude_pid" "$launcher_pid" "claudePid is the claude.exe ancestor"

echo "▸ no Claude Code ancestor"
# An orphaned subshell (its parent exits at once, so it's re-parented to launchd) runs register.sh:
# the walk goes subshell → launchd and finds no claude, even when these tests run inside Claude Code.
orphan_session="22222222-3333-4444-5555-666666666666"
echo '{"type":"ai-title","aiTitle":"Orphan"}' > "$project_dir/$orphan_session.jsonl"
orphan_status="$fixture_dir/orphan.status"
orphan_output="$fixture_dir/orphan.out"
(
    (
        set +e
        sleep 0.5
        cd "$work_dir" && GEARSHIFT_NO_OPEN=1 GEARSHIFT_NO_INSTALL=1 GEARSHIFT_CLAUDE_HOME="$claude_home" GEARSHIFT_SESSIONS_DIR="$sessions_dir" \
            "$register_sh" "$orphan_session" > "$orphan_output" 2>&1
        echo $? > "$orphan_status"
    ) &
)
for _ in $(seq 1 100); do
    [[ -s "$orphan_status" ]] && break
    sleep 0.1
done
assert_equal "$(cat "$orphan_status" 2>/dev/null || echo timeout)" "1" "no claude ancestor exit code"
assert_equal "$(cat "$orphan_output" 2>/dev/null)" "GearShift: couldn't find the Claude Code process" "no claude ancestor message"
if [[ ! -f "$sessions_dir/$orphan_session.json" ]]; then
    pass
else
    fail "no record should be written without a claude ancestor"
fi

echo "▸ backslash in cwd"
backslash_dir="$fixture_dir/back\\slash"
mkdir -p "$backslash_dir"
rm -f "$record_file"
run_under "$fixture_dir/bin/claude" "$backslash_dir" "$session_id"
assert_equal "$status" "0" "backslash cwd exit code ($output)"
recorded_cwd="$(plutil -extract cwd raw -o - "$record_file" 2>/dev/null || true)"
assert_equal "$recorded_cwd" "$(cd "$backslash_dir" && pwd)" "backslash cwd round-trips through JSON"

echo "▸ control characters in cwd are rejected"
for control in $'\n' $'\t' $'\x1b'; do
    control_dir="$fixture_dir/ctl${control}dir"
    mkdir -p "$control_dir"
    rm -f "$record_file"
    run_under "$fixture_dir/bin/claude" "$control_dir" "$session_id"
    assert_equal "$status" "1" "control character cwd exit code"
    assert_equal "$output" "GearShift: cwd contains control characters" "control character message"
    if [[ ! -f "$record_file" ]]; then
        pass
    else
        fail "no record should be written for a cwd with control characters"
    fi
done

echo "▸ bad session id"
run_under "$fixture_dir/bin/claude" "$work_dir" "not-a-uuid"
assert_equal "$status" "1" "bad session id exit code"

echo "▸ transcript not written yet (brand-new session)"
other_id="66666666-7777-8888-9999-000000000000"
run_under "$fixture_dir/bin/claude" "$work_dir" "$other_id"
assert_equal "$status" "0" "new-session exit code"
missing_record="$sessions_dir/$other_id.json"
physical_work_dir="$(cd "$work_dir" && pwd -P)"
expected_path="$claude_home/projects/${physical_work_dir//[^A-Za-z0-9]/-}/$other_id.jsonl"
if [[ -f "$missing_record" ]]; then
    assert_equal "$(plutil -extract transcriptPath raw -o - "$missing_record")" "$expected_path" \
        "new session points at the transcript Claude Code will create"
else
    fail "record should be written even before the transcript exists"
fi

echo "▸ nickname"
rm -f "$record_file"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id" "my backend"
assert_equal "$status" "0" "nickname exit code ($output)"
assert_equal "$(plutil -extract nickname raw -o - "$record_file" 2>/dev/null)" "my backend" "nickname recorded"
if plutil -convert json -o - "$record_file" >/dev/null 2>&1; then pass; else fail "record with nickname is not valid JSON: $(cat "$record_file")"; fi
assert_equal "$output" "GearShift: connected \"$(basename "$work_dir")\" (${session_id:0:8}) as \"my backend\"" "status names the nickname"
leftover="$(find "$sessions_dir" -maxdepth 1 -name '.*.tmp' 2>/dev/null || true)"
assert_equal "$leftover" "" "no leftover temp files after a nickname write"

echo "▸ nickname is kept when /gearshift runs again without one"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id" ""
assert_equal "$status" "0" "re-register exit code ($output)"
assert_equal "$(plutil -extract nickname raw -o - "$record_file" 2>/dev/null)" "my backend" "empty argument keeps the nickname"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id"
assert_equal "$(plutil -extract nickname raw -o - "$record_file" 2>/dev/null)" "my backend" "no argument keeps the nickname"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id" "   "
assert_equal "$(plutil -extract nickname raw -o - "$record_file" 2>/dev/null)" "my backend" "blank argument keeps the nickname"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id" " api.v2_x-1 "
assert_equal "$status" "0" "rename exit code ($output)"
assert_equal "$(plutil -extract nickname raw -o - "$record_file" 2>/dev/null)" "api.v2_x-1" "a new nickname replaces it, trimmed"
twenty_four="abcdefghijklmnopqrstuvwx"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id" "$twenty_four"
assert_equal "$(plutil -extract nickname raw -o - "$record_file" 2>/dev/null)" "$twenty_four" "24 characters is allowed"

echo "▸ no nickname: none recorded"
fresh_id="77777777-8888-9999-aaaa-bbbbbbbbbbbb"
echo '{"type":"ai-title","aiTitle":"Fresh"}' > "$project_dir/$fresh_id.jsonl"
run_under "$fixture_dir/bin/claude" "$work_dir" "$fresh_id" ""
assert_equal "$status" "0" "no-nickname exit code ($output)"
if [[ "$(cat "$sessions_dir/$fresh_id.json")" != *nickname* ]]; then pass; else fail "no nickname key expected: $(cat "$sessions_dir/$fresh_id.json")"; fi

echo "▸ invalid nicknames are refused, and nothing is written"
before="$(cat "$record_file")"
for bad in "a'b" 'x; touch pwned' '$(touch pwned)' 'back`tick`' 'quo"te' 'back\slash' 'semi;colon' $'tab\tx' $'new\nline' 'café' '日本' 'abcdefghijklmnopqrstuvwxy' 'a/b' 'a!b' '$ARGUMENTS'; do
    run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id" "$bad"
    assert_equal "$status" "1" "invalid nickname [$bad] exit code"
    assert_equal "$output" "GearShift: a nickname must be 1–24 letters, digits, spaces, or _ . - (e.g. backend)" "invalid nickname [$bad] message"
done
assert_equal "$(cat "$record_file")" "$before" "the record is untouched by invalid nicknames"
if [[ ! -e "$work_dir/pwned" ]]; then pass; else fail "a nickname ran a command"; fi
bad_id="88888888-9999-aaaa-bbbb-cccccccccccc"
run_under "$fixture_dir/bin/claude" "$work_dir" "$bad_id" "no'pe"
if [[ ! -f "$sessions_dir/$bad_id.json" ]]; then pass; else fail "no record should be written for an invalid nickname"; fi

echo "▸ a session without a title is told to /rename"
untitled_id="99999999-aaaa-bbbb-cccc-dddddddddddd"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"what is an \"ai-title\"?"}}' > "$project_dir/$untitled_id.jsonl"
run_under "$fixture_dir/bin/claude" "$work_dir" "$untitled_id"
assert_equal "$status" "0" "untitled exit code ($output)"
assert_equal "$output" "GearShift: connected \"$(basename "$work_dir")\" (${untitled_id:0:8}). It has no title yet: /rename it (e.g. /rename backend) so GearShift can tell its Warp tab apart" "untitled status suggests /rename"
run_under "$fixture_dir/bin/claude" "$work_dir" "$session_id"
if [[ "$output" != *"/rename"* ]]; then pass; else fail "a titled session isn't told to /rename: $output"; fi
printf '%s\n' '{"type":"custom-title","customTitle":"Named","sessionId":"x"}' >> "$project_dir/$untitled_id.jsonl"
run_under "$fixture_dir/bin/claude" "$work_dir" "$untitled_id"
if [[ "$output" != *"/rename"* ]]; then pass; else fail "a renamed session isn't told to /rename: $output"; fi

echo "▸ terminal: from TERM_PROGRAM"
terminal_id="aaaaaaaa-1111-2222-3333-444444444444"
echo '{"type":"ai-title","aiTitle":"Terminal test"}' > "$project_dir/$terminal_id.jsonl"
terminal_record="$sessions_dir/$terminal_id.json"
for pair in "WarpTerminal=warp" "iTerm.app=iterm" "Apple_Terminal=terminal" "vscode=other" "tmux=other" "-=other" "=other"; do
    term_program="${pair%%=*}"
    rm -f "$terminal_record"
    run_under "$fixture_dir/bin/claude" "$work_dir" "$terminal_id"
    assert_equal "$status" "0" "TERM_PROGRAM [$term_program] exit code ($output)"
    assert_equal "$(record_value "$terminal_record" terminal)" "${pair#*=}" "TERM_PROGRAM [$term_program] is recorded as"
    if plutil -convert json -o - "$terminal_record" >/dev/null 2>&1; then pass; else fail "record for [$term_program] is not valid JSON: $(cat "$terminal_record")"; fi
done

echo "▸ terminal: another terminal's name is kept only when it's a plain name"
for pair in "vscode=vscode" "tmux=tmux" "WezTerm=WezTerm" "ghostty=ghostty" "-=(none)" "=(none)" \
    'a"b=(none)' 'a\b=(none)' 'a b=(none)' 'x$(touch pwned)=(none)' "$(printf 'tab\tx')=(none)" "abcdefghijklmnopqrstuvwxyz0123456=(none)" "WarpTerminal=(none)" "iTerm.app=(none)"; do
    term_program="${pair%=*}"
    rm -f "$terminal_record"
    run_under "$fixture_dir/bin/claude" "$work_dir" "$terminal_id"
    assert_equal "$status" "0" "TERM_PROGRAM [$term_program] exit code ($output)"
    assert_equal "$(record_value "$terminal_record" termProgram)" "${pair##*=}" "termProgram for TERM_PROGRAM [$term_program]"
    if plutil -convert json -o - "$terminal_record" >/dev/null 2>&1; then pass; else fail "record for [$term_program] is not valid JSON: $(cat "$terminal_record")"; fi
done
if [[ ! -e "$work_dir/pwned" ]]; then pass; else fail "TERM_PROGRAM ran a command"; fi

echo "▸ status line: by terminal"
term_program="Apple_Terminal"
run_on_tty "$fixture_dir/bin/claude" "$work_dir" "$untitled_id"
assert_equal "$output" "GearShift: connected \"$(basename "$work_dir")\" (${untitled_id:0:8})" "a Terminal session isn't told to /rename (it's found by tty)"
term_program="iTerm.app"
run_on_tty "$fixture_dir/bin/claude" "$work_dir" "$untitled_id"
assert_equal "$output" "GearShift: connected \"$(basename "$work_dir")\" (${untitled_id:0:8})" "an iTerm session isn't told to /rename"
term_program="vscode"
run_under "$fixture_dir/bin/claude" "$work_dir" "$untitled_id" "ed"
assert_equal "$output" "GearShift: connected \"$(basename "$work_dir")\" (${untitled_id:0:8}) as \"ed\", but GearShift can only shift sessions in Warp, iTerm2 and Terminal, and this one runs in vscode" "another terminal is named"
term_program="-"
run_under "$fixture_dir/bin/claude" "$work_dir" "$untitled_id"
assert_equal "$output" "GearShift: connected \"$(basename "$work_dir")\" (${untitled_id:0:8}) as \"ed\", but GearShift can only shift sessions in Warp, iTerm2 and Terminal, and this one runs in another terminal" "no TERM_PROGRAM"
term_program="WarpTerminal"

echo "▸ tty: the claude process's controlling tty"
# On a pseudo-terminal of its own, as in a terminal tab.
term_program="Apple_Terminal"
rm -f "$terminal_record"
run_on_tty "$fixture_dir/bin/claude" "$work_dir" "$terminal_id"
assert_equal "$status" "0" "tty exit code ($output)"
if [[ "$launcher_tty" =~ ^ttys[0-9]+$ ]]; then pass; else fail "the fake claude should have a tty under script, got [$launcher_tty]"; fi
assert_equal "$(record_value "$terminal_record" tty)" "/dev/$launcher_tty" "tty is the claude process's"
assert_equal "$(record_value "$terminal_record" claudePid)" "$launcher_pid" "claudePid under script"
assert_equal "$(record_value "$terminal_record" terminal)" "terminal" "terminal under script"
if plutil -convert json -o - "$terminal_record" >/dev/null 2>&1; then pass; else fail "record with a tty is not valid JSON: $(cat "$terminal_record")"; fi
# Without one of its own, it's the tests' own controlling tty, if they have one (none when run
# from an app, e.g. inside Claude Code), and then no key at all.
term_program="WarpTerminal"
rm -f "$terminal_record"
run_under "$fixture_dir/bin/claude" "$work_dir" "$terminal_id"
own_tty="$(ps -o tty= -p $$ | tr -d ' ')"
if [[ "$own_tty" =~ ^ttys[0-9]+$ ]]; then
    assert_equal "$(record_value "$terminal_record" tty)" "/dev/$own_tty" "tty inherited from the tests' terminal"
else
    assert_equal "$(record_value "$terminal_record" tty)" "(none)" "no tty: no key"
    if [[ "$(cat "$terminal_record")" != *'"tty"'* ]]; then pass; else fail "no tty key expected: $(cat "$terminal_record")"; fi
fi
# An iTerm or Terminal session whose tty can't be found is told it can't be shifted.
if [[ ! "$own_tty" =~ ^ttys[0-9]+$ ]]; then
    term_program="iTerm.app"
    run_under "$fixture_dir/bin/claude" "$work_dir" "$terminal_id"
    assert_equal "$output" "GearShift: connected \"$(basename "$work_dir")\" (${terminal_id:0:8}), but its tty wasn't found, so GearShift can't shift it" "no tty: the status says so"
    term_program="WarpTerminal"
fi

echo "▸ SKILL.md: allowed-tools pre-approves the injected command"
# Claude Code 2.1.282 matches a Bash(...) allow rule as a regex over the raw command text: every
# character literal (quotes included), `*` as `.*`, and a single trailing ` *` also matching nothing.
# It substitutes the skill's arguments first (raw, not shell-escaped), then ${CLAUDE_SKILL_DIR}, then
# ${CLAUDE_SESSION_ID}; `/gearshift` with no arguments substitutes an empty string.
skill_md="$skill_src/SKILL.md"
injected_template="$(sed -n 's/^!`\(.*\)`$/\1/p' "$skill_md")"
allowed="$(sed -n 's/^allowed-tools: //p' "$skill_md")"

# Sets `injected` for skill dir $1 and arguments $2, as Claude Code would.
render_injected() {
    injected="$injected_template"
    injected="${injected//\$ARGUMENTS/$2}"
    injected="${injected//\$\{CLAUDE_SKILL_DIR\}/$1}"
    injected="${injected//\$\{CLAUDE_SESSION_ID\}/$session_id}"
}

is_allowed_command() {
    local command="$1" skill_dir="$2" rule regex
    while IFS= read -r rule; do
        [[ -z "$rule" ]] && continue
        rule="${rule//\$\{CLAUDE_SKILL_DIR\}/$skill_dir}"
        regex="$(printf '%s' "$rule" | sed -e 's/[][\.^$()|+?{}"]/\\&/g' -e 's/\*/.*/g')"
        if [[ "$regex" == *" .*" && "$(printf '%s' "$rule" | tr -cd '*' | wc -c | tr -d ' ')" == "1" ]]; then
            regex="${regex% .*}( .*)?"
        fi
        if [[ "$command" =~ ^${regex}$ ]]; then
            return 0
        fi
    done < <(printf '%s\n' "$allowed" | grep -o 'Bash([^)]*)' | sed 's/^Bash(//; s/)$//')
    return 1
}

# A personal skill, and the plugin's skill in Claude Code's plugin cache.
for skill_dir in "/Users/someone/.claude/skills/gear shift" "/Users/someone/.claude/plugins/cache/gearshift/gearshift/2.1.0/skills/gearshift"; do
    for arguments in "" "backend" "my backend"; do
        render_injected "$skill_dir" "$arguments"
        assert_equal "$injected" "\"$skill_dir/register.sh\" $session_id '$arguments'" "injected command for [$arguments]"
        if is_allowed_command "$injected" "$skill_dir"; then pass; else fail "no allowed-tools rule matches [$injected]"; fi
    done
done

echo "▸ SKILL.md: the injected command runs register.sh with the nickname"
# End to end through a shell, as Claude Code runs it; the repo's skill dir stands in for the
# installed one.
run_injected() {
    set +e
    set_term_env
    output="$(cd "$work_dir" && "${term_env[@]}" GEARSHIFT_NO_OPEN=1 GEARSHIFT_NO_INSTALL=1 GEARSHIFT_CLAUDE_HOME="$claude_home" GEARSHIFT_SESSIONS_DIR="$sessions_dir" \
        "$fixture_dir/bin/claude" -c '/bin/bash -c "$0"; exit $?' "$injected" 2>&1)"
    status=$?
    set -e
}
for arguments in "" "my backend"; do
    render_injected "$skill_src" "$arguments"
    rm -f "$record_file"
    run_injected
    assert_equal "$status" "0" "injected command exit code for [$arguments] ($output)"
    assert_equal "$(plutil -extract nickname raw -o - "$record_file" 2>/dev/null || true)" "$arguments" "nickname from [$arguments]"
done
# A quote in the arguments ends the single quotes early. Claude Code refuses that command (it's more
# than the allowed one); run anyway, register.sh still refuses the nickname and nothing is recorded.
render_injected "$skill_src" "x' 'y"
rm -f "$record_file"
run_injected
assert_equal "$status" "1" "a quote in the arguments doesn't register"
assert_equal "$output" "GearShift: a nickname must be 1–24 letters, digits, spaces, or _ . - (e.g. backend)" "a split nickname is refused"
if [[ ! -f "$record_file" ]]; then pass; else fail "a nickname with a quote was recorded"; fi

echo "▸ install: fixtures"
# A copy of the skill with its own APP_VERSION and APP_SHA256, a fake GearShift.app release zipped
# with ditto (as `make release` does) and served from a file:// URL, and a fake ~/Applications.
term_program="WarpTerminal"
install_skill="$fixture_dir/installed-skill"
mkdir -p "$install_skill"
cp "$skill_src/SKILL.md" "$register_sh" "$install_skill/"
install_app="$fixture_dir/Applications/GearShift.app"
install_tmp="$fixture_dir/tmp"
mkdir -p "$install_tmp"

# Makes a fake app bundle at $1 with version $2, and a marker file to tell copies apart.
make_fake_app() {
    local app="$1" version="$2"
    mkdir -p "$app/Contents/MacOS"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>app.gearshift.GearShift</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
</dict>
</plist>
PLIST
    echo "$version" > "$app/Contents/MacOS/marker"
}

app_version() {
    plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist" 2>/dev/null || echo "(none)"
}

release_version="9.8.7"
make_fake_app "$fixture_dir/release/GearShift.app" "$release_version"
release_zip="$fixture_dir/release/GearShift.zip"
ditto -c -k --keepParent "$fixture_dir/release/GearShift.app" "$release_zip"
release_sha="$(shasum -a 256 "$release_zip" | awk '{print $1}')"
release_url="file://$release_zip"

# Sets the skill copy's APP_VERSION and APP_SHA256.
set_release() {
    echo "$1" > "$install_skill/APP_VERSION"
    echo "$2" > "$install_skill/APP_SHA256"
}

# Runs the skill copy's register.sh for $session_id under the fake claude, with the fake app and
# release, on Apple Silicon and macOS 15 unless the extra `VAR=value` arguments say otherwise.
run_install() {
    set +e
    output="$(cd "$work_dir" && env -u TERM_PROGRAM -u GEARSHIFT_NO_INSTALL TERM_PROGRAM=WarpTerminal GEARSHIFT_NO_OPEN=1 \
        GEARSHIFT_CLAUDE_HOME="$claude_home" GEARSHIFT_SESSIONS_DIR="$sessions_dir" GEARSHIFT_APP="$install_app" \
        GEARSHIFT_RELEASE_URL="$release_url" GEARSHIFT_TEST_ARCH=arm64 GEARSHIFT_TEST_MACOS_VERSION=15.1 TMPDIR="$install_tmp" \
        "$@" "$fixture_dir/bin/claude" -c '"$0" "$@"; exit $?' "$install_skill/register.sh" "$session_id" 2>&1)"
    status=$?
    set -e
}

connected_line="GearShift: connected \"$(basename "$work_dir")\" (${session_id:0:8})"
installed_line="GearShift $release_version installed: allow it in System Settings › Privacy & Security › Accessibility the first time you shift."

# No staging copies next to the app, and nothing left in the temp dir.
assert_clean_install() {
    local label="$1"
    assert_equal "$(find "$(dirname "$install_app")" -mindepth 1 -maxdepth 1 -name '.GearShift.app.*' 2>/dev/null)" "" "$label: no staging copies left"
    assert_equal "$(find "$install_tmp" -mindepth 1 2>/dev/null)" "" "$label: temp download removed"
}

echo "▸ install: a missing app is downloaded and installed"
set_release "$release_version" "$release_sha"
rm -rf "$(dirname "$install_app")" "$record_file"
run_install
assert_equal "$status" "0" "missing app exit code ($output)"
assert_equal "$output" "$installed_line"$'\n'"$connected_line" "missing app: installed, then connected"
assert_equal "$(app_version "$install_app")" "$release_version" "missing app: the release is installed"
assert_equal "$(cat "$install_app/Contents/MacOS/marker" 2>/dev/null)" "$release_version" "missing app: the release's files"
if [[ -f "$record_file" ]]; then pass; else fail "missing app: the session is still registered"; fi
assert_clean_install "missing app"

echo "▸ install: the same version isn't downloaded again"
echo "local" > "$install_app/Contents/MacOS/marker"
release_url="file://$fixture_dir/release/does-not-exist.zip"
run_install
assert_equal "$status" "0" "same version exit code ($output)"
assert_equal "$output" "$connected_line" "same version: only connected"
assert_equal "$(cat "$install_app/Contents/MacOS/marker")" "local" "same version: the app is untouched"
release_url="file://$release_zip"

echo "▸ install: an older version is replaced"
rm -rf "$install_app"
make_fake_app "$install_app" "2.0"
echo "extra" > "$install_app/Contents/old-only"
run_install
assert_equal "$status" "0" "older version exit code ($output)"
assert_equal "$output" "$installed_line"$'\n'"$connected_line" "older version: installed, then connected"
assert_equal "$(app_version "$install_app")" "$release_version" "older version: replaced by the release"
if [[ ! -e "$install_app/Contents/old-only" ]]; then pass; else fail "older version: the old app's files are gone"; fi
assert_clean_install "older version"

echo "▸ install: a newer local build is replaced too (the skill pins its version)"
rm -rf "$install_app"
make_fake_app "$install_app" "10.0"
run_install
assert_equal "$status" "0" "newer version exit code ($output)"
assert_equal "$(app_version "$install_app")" "$release_version" "newer version: the pinned release is installed"

echo "▸ install: a checksum mismatch installs nothing"
rm -rf "$install_app" "$record_file"
make_fake_app "$install_app" "2.0"
set_release "$release_version" "0000000000000000000000000000000000000000000000000000000000000000"
run_install
assert_equal "$status" "1" "checksum mismatch exit code"
assert_equal "$output" "GearShift: the downloaded GearShift $release_version doesn't match its checksum, so it wasn't installed" "checksum mismatch message"
assert_equal "$(app_version "$install_app")" "2.0" "checksum mismatch: the existing app is untouched"
assert_equal "$(cat "$install_app/Contents/MacOS/marker")" "2.0" "checksum mismatch: the existing app's files are untouched"
if [[ ! -f "$record_file" ]]; then pass; else fail "checksum mismatch: nothing is registered"; fi
assert_clean_install "checksum mismatch"

echo "▸ install: a failed download installs nothing"
set_release "$release_version" "$release_sha"
release_url="file://$fixture_dir/release/does-not-exist.zip"
run_install
assert_equal "$status" "1" "failed download exit code"
assert_equal "$output" "GearShift: couldn't download GearShift $release_version from $release_url" "failed download message"
assert_equal "$(app_version "$install_app")" "2.0" "failed download: the existing app is untouched"
assert_clean_install "failed download"
release_url="file://$release_zip"

echo "▸ install: a zip of another version is refused"
set_release "9.9.9" "$release_sha"
run_install
assert_equal "$status" "1" "wrong version in zip exit code"
assert_equal "$output" "GearShift: the downloaded GearShift isn't version 9.9.9" "wrong version in zip message"
assert_equal "$(app_version "$install_app")" "2.0" "wrong version in zip: the existing app is untouched"
assert_clean_install "wrong version in zip"
set_release "$release_version" "$release_sha"

echo "▸ install: malformed APP_VERSION or APP_SHA256"
for pair in "9.8.7 abc" "latest $release_sha" "9.8.7;rm $release_sha"; do
    set_release "${pair% *}" "${pair##* }"
    run_install
    assert_equal "$status" "1" "malformed [$pair] exit code"
    assert_equal "$output" "GearShift: the skill's APP_VERSION or APP_SHA256 is malformed; reinstall the plugin" "malformed [$pair] message"
done
set_release "$release_version" "$release_sha"

echo "▸ install: GEARSHIFT_NO_INSTALL=1 skips it"
rm -rf "$install_app" "$record_file"
run_install GEARSHIFT_NO_INSTALL=1
assert_equal "$status" "0" "no install exit code ($output)"
assert_equal "$output" "$connected_line" "no install: only connected"
if [[ ! -e "$install_app" ]]; then pass; else fail "no install: nothing is installed"; fi
if [[ -f "$record_file" ]]; then pass; else fail "no install: the session is registered"; fi

echo "▸ install: a skill without APP_VERSION (make install-skill) leaves the app alone"
rm -f "$install_skill/APP_VERSION" "$install_skill/APP_SHA256"
run_install
assert_equal "$status" "0" "no APP_VERSION exit code ($output)"
if [[ ! -e "$install_app" ]]; then pass; else fail "no APP_VERSION: nothing is installed"; fi
set_release "$release_version" "$release_sha"

echo "▸ install: needs Apple Silicon and macOS 14"
run_install GEARSHIFT_TEST_ARCH=x86_64
assert_equal "$status" "1" "Intel exit code"
assert_equal "$output" "GearShift: GearShift needs a Mac with Apple Silicon" "Intel message"
if [[ ! -e "$install_app" ]]; then pass; else fail "Intel: nothing is installed"; fi
for version in "13.6.1" "12" "x"; do
    run_install GEARSHIFT_TEST_MACOS_VERSION="$version"
    assert_equal "$status" "1" "macOS [$version] exit code"
    assert_equal "$output" "GearShift: GearShift needs macOS 14 or later" "macOS [$version] message"
done
if [[ ! -e "$install_app" ]]; then pass; else fail "old macOS: nothing is installed"; fi
run_install GEARSHIFT_TEST_MACOS_VERSION=14.0
assert_equal "$status" "0" "macOS 14 exit code ($output)"
assert_equal "$(app_version "$install_app")" "$release_version" "macOS 14: installed"
# An Intel Mac with the right version installed has nothing to download, so nothing to refuse.
run_install GEARSHIFT_TEST_ARCH=x86_64
assert_equal "$status" "0" "Intel with the app installed exit code ($output)"

echo "▸ plugin manifests"
info_version="$(plutil -extract CFBundleShortVersionString raw -o - "$repo_root/Resources/Info.plist")"
plugin_json="$repo_root/.claude-plugin/plugin.json"
marketplace_json="$repo_root/.claude-plugin/marketplace.json"
for manifest in "$plugin_json" "$marketplace_json"; do
    if plutil -convert xml1 -o /dev/null "$manifest" 2>/dev/null; then pass; else fail "$manifest is not valid JSON"; fi
done
assert_equal "$(plutil -extract version raw -o - "$plugin_json" 2>/dev/null)" "$info_version" "plugin.json version is the app's CFBundleShortVersionString"
assert_equal "$(plutil -extract name raw -o - "$plugin_json" 2>/dev/null)" "gearshift" "plugin name"
assert_equal "$(plutil -extract plugins.0.name raw -o - "$marketplace_json" 2>/dev/null)" "gearshift" "marketplace lists the plugin"
assert_equal "$(plutil -extract plugins.0.source raw -o - "$marketplace_json" 2>/dev/null)" "./" "marketplace plugin source is the repo root"
if [[ -x "$register_sh" ]]; then pass; else fail "register.sh must be executable (Claude Code runs it directly)"; fi

echo
echo "$passes passed, $failures failed"
[[ "$failures" -eq 0 ]]

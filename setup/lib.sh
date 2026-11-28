# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────────────────────
#  Installer UI and bookkeeping, sourced by install.sh.
#  Layout: a logo, then each step as a timeline (header with an overall progress bar, its details
#  on a connecting line, and a closing line with how it went), and boxes for the plan and summary.
#  gum (https://github.com/charmbracelet/gum, in Fedora's repos) is used for the checklist and
#  yes/no questions when it's installed and we're on a terminal; everything has a plain fallback.
# ─────────────────────────────────────────────────────────────────────────────

# ── Colours (lilac → pink, like the theme) ─────────────────────────────────
c_acc=$'\e[38;5;183m' c_pink=$'\e[38;5;218m' c_bold=$'\e[1m' c_ok=$'\e[38;5;114m' c_warn=$'\e[38;5;222m'
c_err=$'\e[38;5;210m' c_dim=$'\e[2m' c_line=$'\e[38;5;103m' c_off=$'\e[0m'
ACCENT_256=183

INTERACTIVE=0; [[ -t 0 && -t 1 ]] && INTERACTIVE=1
use_gum() { (( INTERACTIVE )) && command -v gum >/dev/null; }
COLS=$( (( INTERACTIVE )) && tput cols 2>/dev/null || echo 80 )
WIDTH=$(( COLS < 82 ? COLS - 4 : 78 )) # Content width (boxes, rules), with a 2-column margin

# ── Log: every command's output goes here; the screen only shows a summary ──
LOG_DIR="$HOME/.cache/ninomae-install"
mkdir -p "$LOG_DIR"
find "$LOG_DIR" -name '*.log' -mtime +30 -delete 2>/dev/null # Keep a month of logs
LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
: >"$LOG"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG"; }

# ── Text helpers ────────────────────────────────────────────────────────────
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g' <<<"$1"; }
vlen() { local plain; plain=$(strip_ansi "$1"); echo "${#plain}"; } # Visible length
repeat() { local i out=""; for ((i = 0; i < $2; i++)); do out+=$1; done; printf '%s' "$out"; } # repeat "─" 10
# fit "text" N: cut plain text to N visible characters, with an ellipsis
fit() { local t=$1 n=$2; (( ${#t} > n )) && t="${t:0:n-1}…"; printf '%s' "$t"; }

# box "Title" "line" …: a rounded box, title in the top border. Lines may contain colours
box() {
    local title=$1; shift
    local inner=$((WIDTH - 4)) line pad
    printf '  %s╭─ %s%s%s %s╮%s\n' "$c_line" "$c_bold$c_acc" "$title" "$c_off$c_line" "$(repeat ─ $((WIDTH - 5 - ${#title})))" "$c_off"
    for line in "$@"; do
        if (( $(vlen "$line") > inner )); then # Too long: wrap the plain text, continuation indented
            local first=1 part
            while IFS= read -r part; do
                (( first )) || part="  $part"; first=0
                printf '  %s│%s %s%*s %s│%s\n' "$c_line" "$c_off" "$part" $((inner - ${#part})) "" "$c_line" "$c_off"
            done < <(strip_ansi "$line" | fold -s -w $((inner - 2)))
            continue
        fi
        pad=$((inner - $(vlen "$line"))); (( pad < 0 )) && pad=0
        printf '  %s│%s %s%*s %s│%s\n' "$c_line" "$c_off" "$line" "$pad" "" "$c_line" "$c_off"
    done
    printf '  %s╰%s╯%s\n' "$c_line" "$(repeat ─ $((WIDTH - 2)))" "$c_off"
}

# ── Logo ────────────────────────────────────────────────────────────────────
LOGO=(
    "███╗   ██╗██╗███╗   ██╗ ██████╗ ███╗   ███╗ █████╗ ███████╗"
    "████╗  ██║██║████╗  ██║██╔═══██╗████╗ ████║██╔══██╗██╔════╝"
    "██╔██╗ ██║██║██╔██╗ ██║██║   ██║██╔████╔██║███████║█████╗  "
    "██║╚██╗██║██║██║╚██╗██║██║   ██║██║╚██╔╝██║██╔══██║██╔══╝  "
    "██║ ╚████║██║██║ ╚████║╚██████╔╝██║ ╚═╝ ██║██║  ██║███████╗"
    "╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝"
)
LOGO_SHADES=(141 147 183 182 218 212) # Lilac at the top, pink at the bottom
banner() { # banner "what this run is" "system info"
    echo
    local i indent=$(( (WIDTH - 59) / 2 + 2 ))
    if (( WIDTH >= 61 )); then
        for i in "${!LOGO[@]}"; do printf '%*s\e[38;5;%sm%s%s\n' "$indent" "" "${LOGO_SHADES[i]}" "${LOGO[i]}" "$c_off"; done
    else
        printf '  %s%sN I N O M A E%s\n' "$c_bold" "$c_acc" "$c_off"
    fi
    local tag="◆  $1  ◆" info=$2
    printf '\n%*s%s%s%s\n' $(( (WIDTH - ${#tag}) / 2 + 2 )) "" "$c_pink$c_bold" "$tag" "$c_off"
    printf '%*s%s%s%s\n' $(( (WIDTH - ${#info}) / 2 + 2 )) "" "$c_dim" "$info" "$c_off"
    printf '  %s%s%s\n' "$c_line" "$(repeat ─ "$WIDTH")" "$c_off"
}
section() { # section "Title": a heading outside the steps
    printf '\n  %s◆%s %s%s%s\n' "$c_acc" "$c_off" "$c_bold" "$*" "$c_off"
    log "== $*"
}

# ── Lines: inside a step they hang off the step's timeline ─────────────────
IN_STEP=0
gutter() { (( IN_STEP )) && printf '  %s│%s  ' "$c_line" "$c_off" || printf '    '; }
ok()   { gutter; printf '%s✓%s %s\n' "$c_ok" "$c_off" "$*"; log "ok: $*"; }
info() { gutter; printf '%s· %s%s\n' "$c_dim" "$*" "$c_off"; log "info: $*"; }
warn() { gutter; printf '%s!%s %s\n' "$c_warn" "$c_off" "$*"; log "warn: $*"; }
err()  { gutter; printf '%s✗%s %s\n' "$c_err" "$c_off" "$*"; log "error: $*"; }
die()  { IN_STEP=0; printf '\n  %s✗ %s%s\n\n' "$c_err" "$*" "$c_off" >&2; log "fatal: $*"; exit 1; }

# ── Running commands ────────────────────────────────────────────────────────
dry() { gutter; printf '%s[dry-run] %s%s\n' "$c_dim" "$(fit "$*" $((WIDTH - 14)))" "$c_off"; }
# run CMD…: runs it (output to the log), or only shows it in dry-run mode
run() {
    log "\$ $*"
    if (( DRY_RUN )); then dry "$@"; return 0; fi
    "$@" >>"$LOG" 2>&1
}
# run_visible CMD…: like run, but the command's own output is shown as well as logged, for steps
# that talk to the user (the Steam theme's installer, say)
run_visible() {
    log "\$ $*"
    if (( DRY_RUN )); then dry "$@"; return 0; fi
    local prefix; prefix="$(gutter)  "
    "$@" 2>&1 | tee -a "$LOG" | sed -u "s/^\s*/${prefix//\//\\/}/"
    return "${PIPESTATUS[0]}"
}
# spin "Title" CMD…: runs a long command behind a spinner. On failure, shows its last lines
spin() {
    local title=$1; shift
    log "\$ $*"
    if (( DRY_RUN )); then dry "$@"; return 0; fi
    local out; out=$(mktemp "$LOG_DIR/cmd.XXXXXX")
    "$@" >"$out" 2>&1 &
    local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 start=$SECONDS status
    # Ctrl+C stops the command as well: a script's background job ignores SIGINT, so it kept running
    # (dnf, say) after the installer had quit. pkill -P: its children too (sudo → dnf)
    trap 'pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; (( INTERACTIVE )) && printf "\r\e[K"; rm -f "$out"; die "Cancelled during: $title"' INT TERM
    if (( INTERACTIVE )); then
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r%s%s%s%s %s %s%ss%s ' "$(gutter)" "$c_pink" "${frames:i++%10:1}" "$c_off" "$title" "$c_dim" "$((SECONDS - start))" "$c_off"
            sleep 0.1
        done
        printf '\r\e[K'
    fi
    wait "$pid"; status=$?
    trap - INT TERM
    cat "$out" >>"$LOG"
    if (( status == 0 )); then
        ok "$title"
    else
        err "$title failed (exit $status). Last lines:"
        tail -n 6 "$out" | while IFS= read -r line; do gutter; printf '  %s%s%s\n' "$c_dim" "$(fit "$line" $((WIDTH - 10)))" "$c_off"; done
    fi
    rm -f "$out"
    return "$status"
}

# ── Questions ───────────────────────────────────────────────────────────────
# confirm "Question?" [default: yes|no]
confirm() {
    local question=$1 default=${2:-yes}
    (( ASSUME_YES )) && return 0
    (( INTERACTIVE )) || { [[ $default == yes ]]; return; }
    if use_gum; then
        local flag=--default=true; [[ $default == no ]] && flag=--default=false
        gum confirm "$question" "$flag" --prompt.foreground="$ACCENT_256" \
            --selected.background="$ACCENT_256" --selected.foreground=0
        return
    fi
    local hint='[Y/n]' reply; [[ $default == no ]] && hint='[y/N]'
    printf '%s%s?%s %s %s%s%s ' "$(gutter)" "$c_acc" "$c_off" "$question" "$c_dim" "$hint" "$c_off"
    read -r reply
    if [[ -z $reply ]]; then [[ $default == yes ]]; else [[ $reply =~ ^[Yy] ]]; fi
}

# choose_many "Header" "label|key|on" …  → prints the chosen keys, one per line.
# Labels mustn't contain commas (gum uses them to list the preselected items).
choose_many() {
    local header=$1; shift
    local -a labels keys states
    local item
    for item in "$@"; do
        labels+=("${item%%|*}"); item=${item#*|}
        keys+=("${item%%|*}"); states+=("${item#*|}")
    done
    local n=${#labels[@]} i
    if (( ASSUME_YES || ! INTERACTIVE )); then
        for ((i = 0; i < n; i++)); do [[ ${states[i]} == on ]] && echo "${keys[i]}"; done
        return 0
    fi
    if use_gum; then
        local selected="" chosen
        for ((i = 0; i < n; i++)); do [[ ${states[i]} == on ]] && selected+="${selected:+,}${labels[i]}"; done
        printf '\n  %s◆%s %s%s%s  %s(space toggles · enter confirms)%s\n' "$c_acc" "$c_off" "$c_bold" "$header" "$c_off" "$c_dim" "$c_off" >&2
        chosen=$(gum choose --no-limit --header "" --selected "$selected" --height $((n + 1)) \
            --cursor "  › " --cursor-prefix "○ " --selected-prefix "● " --unselected-prefix "○ " \
            --cursor.foreground="$ACCENT_256" --selected.foreground="$ACCENT_256" \
            "${labels[@]}") || return 1
        while IFS= read -r item; do
            for ((i = 0; i < n; i++)); do [[ ${labels[i]} == "$item" ]] && echo "${keys[i]}"; done
        done <<<"$chosen"
        return 0
    fi
    # Plain: numbered checklist, type numbers to toggle, Enter to go on
    local reply num
    while true; do
        printf '\n  %s◆%s %s%s%s\n\n' "$c_acc" "$c_off" "$c_bold" "$header" "$c_off" >&2
        for ((i = 0; i < n; i++)); do
            if [[ ${states[i]} == on ]]; then printf '    %s%d  ●%s %s\n' "$c_acc" $((i + 1)) "$c_off" "${labels[i]}" >&2
            else printf '    %s%d  ○ %s%s\n' "$c_dim" $((i + 1)) "${labels[i]}" "$c_off" >&2; fi
        done
        printf '\n    %sNumbers to toggle (e.g. 3 5), or Enter to continue:%s ' "$c_dim" "$c_off" >&2
        read -r reply
        [[ -z $reply ]] && break
        for num in $reply; do
            [[ $num =~ ^[0-9]+$ ]] && (( num >= 1 && num <= n )) || continue
            [[ ${states[num - 1]} == on ]] && states[num - 1]=off || states[num - 1]=on
        done
    done
    for ((i = 0; i < n; i++)); do [[ ${states[i]} == on ]] && echo "${keys[i]}"; done
    return 0
}

# choose_one "Question" "default-key" "label|key" …  → prints the chosen key
choose_one() {
    local question=$1 default=$2; shift 2
    local -a labels keys
    local item i n
    for item in "$@"; do labels+=("${item%%|*}"); keys+=("${item#*|}"); done
    n=${#labels[@]}
    if (( ASSUME_YES || ! INTERACTIVE )); then echo "$default"; return 0; fi
    local def_label="${labels[0]}"
    for ((i = 0; i < n; i++)); do [[ ${keys[i]} == "$default" ]] && def_label=${labels[i]}; done
    if use_gum; then
        printf '\n  %s◆%s %s%s%s\n' "$c_acc" "$c_off" "$c_bold" "$question" "$c_off" >&2
        local chosen
        chosen=$(gum choose --header "" --selected "$def_label" --height $((n + 1)) --cursor "  › " \
            --cursor.foreground="$ACCENT_256" --selected.foreground="$ACCENT_256" "${labels[@]}") || return 1
        for ((i = 0; i < n; i++)); do [[ ${labels[i]} == "$chosen" ]] && echo "${keys[i]}"; done
        return 0
    fi
    printf '\n  %s◆%s %s%s%s\n\n' "$c_acc" "$c_off" "$c_bold" "$question" "$c_off" >&2
    for ((i = 0; i < n; i++)); do
        if [[ ${keys[i]} == "$default" ]]; then printf '    %s%d  ● %s%s  %s(default)%s\n' "$c_acc" $((i + 1)) "${labels[i]}" "$c_off" "$c_dim" "$c_off" >&2
        else printf '    %d  ○ %s\n' $((i + 1)) "${labels[i]}" >&2; fi
    done
    local reply
    printf '\n    %sNumber, or Enter for the default:%s ' "$c_dim" "$c_off" >&2
    read -r reply
    if [[ $reply =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= n )); then echo "${keys[reply - 1]}"; else echo "$default"; fi
}

# ── Steps and the final report ──────────────────────────────────────────────
STEP_TOTAL=0 STEP_NUM=0
declare -a RES_NAME=() RES_STATUS=() RES_MSG=() TODO=()
CUR_STEP=""
progress_bar() { # progress_bar DONE TOTAL WIDTH
    local filled=$(( $1 * $3 / ($2 > 0 ? $2 : 1) ))
    printf '%s%s%s%s%s' "$c_acc" "$(repeat ━ "$filled")" "$c_line" "$(repeat ━ $(($3 - filled)))" "$c_off"
}
step() { # step "Title": opens a step on the timeline
    STEP_NUM=$((STEP_NUM + 1)); CUR_STEP=$1; IN_STEP=1
    local counter="$STEP_NUM/$STEP_TOTAL" bar_w=16
    local gap=$((WIDTH - 6 - ${#counter} - ${#1} - bar_w))
    (( gap < 1 )) && { bar_w=$((bar_w + gap - 1)); gap=1; }
    (( bar_w < 4 )) && bar_w=0
    printf '\n  %s╭─%s %s%s%s  %s%s%*s' "$c_line" "$c_off" "$c_pink$c_bold" "$counter" "$c_off" "$c_bold" "$1$c_off" "$gap" ""
    (( bar_w )) && progress_bar $((STEP_NUM - 1)) "$STEP_TOTAL" "$bar_w"
    echo
    log "==== [$STEP_NUM/$STEP_TOTAL] $1"
}
# result done|skip|fail|todo "message": closes the step with how it went (also in the summary)
result() {
    RES_NAME+=("$CUR_STEP"); RES_STATUS+=("$1"); RES_MSG+=("$2")
    local icon colour
    case $1 in
        done) icon="✓"; colour=$c_ok ;; skip) icon="↷"; colour=$c_dim ;;
        fail) icon="✗"; colour=$c_err ;; todo) icon="!"; colour=$c_warn ;;
    esac
    printf '  %s╰─%s %s%s %s%s\n' "$c_line" "$c_off" "$colour" "$icon" "$2" "$c_off"
    IN_STEP=0
    log "result: $1 $2"
}
needs_you() { TODO+=("$*"); log "todo: $*"; } # A follow-up for the "What's left for you" box

report() { # report "Next-steps line" …
    local i n=${#RES_NAME[@]} done=0 skipped=0 failed=0 todo=0 icon name_w=28 msg_w
    msg_w=$((WIDTH - 4 - 2 - name_w - 1))
    local -a rows=()
    for ((i = 0; i < n; i++)); do
        case ${RES_STATUS[i]} in
            done) icon="${c_ok}✓${c_off}"; done=$((done + 1)) ;;
            skip) icon="${c_dim}↷${c_off}"; skipped=$((skipped + 1)) ;;
            fail) icon="${c_err}✗${c_off}"; failed=$((failed + 1)) ;;
            todo) icon="${c_warn}!${c_off}"; todo=$((todo + 1)) ;;
        esac
        rows+=("$icon $(printf '%-*s' "$name_w" "$(fit "${RES_NAME[i]}" "$name_w")") ${c_dim}$(fit "${RES_MSG[i]}" "$msg_w")${c_off}")
    done
    local tally="${c_ok}${done} done${c_off}"
    (( skipped )) && tally+="  ·  ${skipped} skipped"
    (( todo )) && tally+="  ·  ${c_warn}${todo} need you${c_off}"
    (( failed )) && tally+="  ·  ${c_err}${failed} failed${c_off}"
    echo
    if (( failed )); then box "Summary" "${rows[@]}" "" "$tally"
    else box "All set" "${rows[@]}" "" "$tally"; fi
    if (( ${#TODO[@]} )); then
        local -a todo_rows=()
        for i in "${TODO[@]}"; do todo_rows+=("${c_warn}•${c_off} $i"); done
        echo; box "What's left for you" "${todo_rows[@]}"
    fi
    if (( $# )); then
        echo
        for i in "$@"; do printf '  %s→%s %s\n' "$c_pink" "$c_off" "$i"; done
    fi
    printf '\n  %sFull log: %s%s\n\n' "$c_dim" "${LOG/#$HOME/\~}" "$c_off"
    (( failed == 0 ))
}

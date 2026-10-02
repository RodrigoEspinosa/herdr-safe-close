#!/usr/bin/env bash
# Close the focused tab or pane. If anything other than an idle shell is in
# the foreground of one of its panes (agent, dev server, vim, ssh...), or the
# tab is the last one in its space, open an overlay asking for confirmation.
#
# Usage: safe-close.sh tab|pane      (plugin actions)
#        safe-close.sh confirm       (overlay pane entrypoint)
# Written for bash 3.2 (macOS default).
set -euo pipefail

PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
herdr="${HERDR_BIN_PATH:-herdr}"
mode="${1:-tab}"

if ! command -v jq >/dev/null; then
  echo "herdr-safe-close: jq is required (brew install jq / apt install jq)" >&2
  exit 1
fi

close_target() { # kind id
  if [[ $1 == tab ]]; then "$herdr" tab close "$2" >/dev/null
  else "$herdr" pane close "$2" >/dev/null; fi
}

# One line per busy pane: "<label>". Empty output means everything is idle.
busy_lines() { # pane ids...
  local panes p info agent status leader
  panes=$("$herdr" pane list)
  for p in "$@"; do
    agent=$(jq -r --arg p "$p" '.result.panes[] | select(.pane_id == $p) | .agent // empty' <<<"$panes")
    status=$(jq -r --arg p "$p" '.result.panes[] | select(.pane_id == $p) | .agent_status // empty' <<<"$panes")
    if [[ -n $agent ]]; then
      echo "$agent ($status)"
      continue
    fi
    info=$("$herdr" pane process-info --pane "$p" 2>/dev/null) || continue
    # Idle shell: the shell itself owns the terminal's foreground group.
    leader=$(jq -r '.result.process_info
      | select(.foreground_process_group_id != .shell_pid)
      | .foreground_process_group_id as $g
      | ([.foreground_processes[] | select(.pid == $g)][0] // .foreground_processes[0])
      | (.cmdline // .argv0 // .name)' <<<"$info")
    [[ -n $leader ]] && echo "${leader:0:60}"
  done
  return 0
}

if [[ $mode == confirm ]]; then
  kind="$SAFE_CLOSE_KIND" id="$SAFE_CLOSE_ID"
  # Plain padded lines, no cursor addressing: the popup may still be resizing
  # when this starts, so anything computed from tput would land in the wrong place.
  printf '\033[?25l\n'
  while IFS= read -r l; do
    [[ -n $l ]] || continue
    # Red for losing the whole space, yellow for something running.
    if [[ $l == "last tab"* ]]; then printf '  \033[31m●\033[0m %s\n' "$l"
    else printf '  \033[33m●\033[0m %s\n' "$l"; fi
  done <<<"$SAFE_CLOSE_REASONS"
  printf '\n  \033[1mClose this %s?\033[0m\n\n' "$kind"
  printf '  \033[7m y \033[0m close   \033[2m\033[7m n \033[0m\033[2m cancel\033[0m'
  IFS= read -rsn1 key || key=n
  printf '\033[?25h'
  case $key in
    y | Y | "") close_target "$kind" "$id" ;;
  esac
  exit 0
fi

case $mode in
  tab | pane) ;;
  *) echo "usage: safe-close.sh tab|pane|confirm" >&2; exit 2 ;;
esac

# Plugin actions get HERDR_TAB_ID / HERDR_PANE_ID; fall back to focus.
if [[ $mode == tab ]]; then
  tabs=$("$herdr" tab list)
  id="${HERDR_TAB_ID:-${HERDR_ACTIVE_TAB_ID:-}}"
  [[ -n $id ]] || id=$(jq -r '.result.tabs[] | select(.focused) | .tab_id' <<<"$tabs")
  ws=$(jq -r --arg t "$id" '.result.tabs[] | select(.tab_id == $t) | .workspace_id' <<<"$tabs")
  siblings=$(jq --arg ws "$ws" '[.result.tabs[] | select(.workspace_id == $ws)] | length' <<<"$tabs")
  panes=($("$herdr" pane list | jq -r --arg t "$id" '.result.panes[] | select(.tab_id == $t) | .pane_id'))
  reasons=$(busy_lines "${panes[@]}")
  if (( siblings <= 1 )); then
    reasons=$(printf '%s\n%s' "last tab — closing it closes the space" "$reasons")
  fi
else
  id="${HERDR_PANE_ID:-}"
  [[ -n $id ]] || id=$("$herdr" pane list | jq -r '.result.panes[] | select(.focused) | .pane_id')
  reasons=$(busy_lines "$id")
fi

reasons=$(sed '/^$/d' <<<"$reasons")
if [[ -z $reasons ]]; then
  close_target "$mode" "$id"
  exit 0
fi

# Size the popup to its content: widest line + padding, lines + border/margins.
w=24  # "Close this pane?" / key hints
while IFS= read -r l; do (( ${#l} + 4 > w )) && w=$(( ${#l} + 4 )); done <<<"$reasons"
n=$(wc -l <<<"$reasons")
"$herdr" plugin pane open --plugin "${HERDR_PLUGIN_ID:-herdr-safe-close}" \
  --entrypoint confirm --placement popup --focus \
  --width $(( w + 6 )) --height $(( n + 7 )) \
  --env "SAFE_CLOSE_KIND=$mode" --env "SAFE_CLOSE_ID=$id" \
  --env "SAFE_CLOSE_REASONS=$reasons" >/dev/null

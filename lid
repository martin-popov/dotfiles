#!/usr/bin/env bash
# lid off [8h|90m] | on | status — keep the Mac awake with the lid closed.
# `off` disables all sleep (pmset disablesleep) until a deadline (default 8h)
# or the battery drops below MIN_BATTERY% on battery power, whichever comes
# first. The com.martinpopov.lid LaunchAgent (installed by setup.sh) runs
# `check` every minute to enforce that, so it holds across reboots too.
# pmset goes through a sudoers rule allowing exactly these two commands.
set -euo pipefail

STATE="$HOME/.local/state/lid" # deadline (epoch seconds); present = lid is holding sleep off
MIN_BATTERY=20

sleep_disabled() { pmset -g | grep -Eq 'SleepDisabled[[:space:]]+1'; }
set_disablesleep() { # 1 = never sleep, 0 = normal
  sudo -n /usr/bin/pmset -a disablesleep "$1" 2>/dev/null \
    || { echo "lid: no sudo rule for pmset — run: bash ~/dotfiles/setup.sh macos" >&2; exit 1; }
}
until_time() { date -r "$(cat "$STATE")" +%H:%M; }
notify() { osascript -e "display notification \"$1\" with title \"lid\"" >/dev/null 2>&1 || true; }

case "${1:-status}" in
  off)
    if [[ ! "${2:-8h}" =~ ^([0-9]+)([hm]?)$ ]] || [ "${BASH_REMATCH[1]}" -eq 0 ]; then
      echo "usage: lid off [8h|90m]  (a bare number means hours)" >&2
      exit 1
    fi
    secs=$((BASH_REMATCH[1] * 3600))
    [ "${BASH_REMATCH[2]}" = m ] && secs=$((BASH_REMATCH[1] * 60))
    set_disablesleep 1
    mkdir -p "$(dirname "$STATE")"
    echo $(($(date +%s) + secs)) > "$STATE"
    echo "lid: staying awake with the lid closed until $(until_time) (or battery below $MIN_BATTERY%)"
    ;;
  on)
    rm -f "$STATE"
    set_disablesleep 0
    echo "lid: sleep back to normal"
    ;;
  check) # the LaunchAgent, every minute: revert once time's up or battery's low
    [ -f "$STATE" ] || exit 0
    reason=""
    if [ "$(date +%s)" -ge "$(cat "$STATE")" ]; then
      reason="time's up"
    else
      batt="$(pmset -g batt)"
      pct="$(grep -Eo '[0-9]+%' <<<"$batt" | head -1 | tr -d %)"
      if grep -q "'Battery Power'" <<<"$batt" && [ -n "$pct" ] && [ "$pct" -lt "$MIN_BATTERY" ]; then
        reason="battery at $pct%"
      fi
    fi
    if [ -n "$reason" ]; then
      rm -f "$STATE"
      set_disablesleep 0
      notify "Sleep back to normal ($reason)"
    fi
    ;;
  status)
    if ! sleep_disabled; then
      echo "lid: normal"
    elif [ -f "$STATE" ]; then
      echo "lid: staying awake with the lid closed until $(until_time)"
    else
      echo "lid: sleep disabled outside lid (pmset disablesleep 1) — no auto-revert; lid on to undo"
    fi
    ;;
  *)
    echo "usage: lid [off [8h|90m] | on | status]" >&2
    exit 1
    ;;
esac

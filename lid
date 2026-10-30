#!/usr/bin/env bash
# lid off [8h|90m] | on | status — keep the Mac awake with the lid closed.
# `off` disables all sleep (pmset disablesleep) until `lid on` or an optional
# deadline. Below MIN_BATTERY% on battery power it only pauses — sleep is
# allowed again until the battery recovers or the charger is plugged in. The
# com.martinpopov.lid LaunchAgent (installed by setup.sh) runs `check` every
# minute to enforce that, across reboots too.
# pmset goes through a sudoers rule allowing exactly these two commands.
set -euo pipefail

STATE="$HOME/.local/state/lid" # deadline (epoch seconds, 0 = none); present = lid is holding sleep off
MIN_BATTERY=20

sleep_disabled() { pmset -g | grep -Eq 'SleepDisabled[[:space:]]+1'; }
set_disablesleep() { # 1 = never sleep, 0 = normal
  sudo -n /usr/bin/pmset -a disablesleep "$1" 2>/dev/null \
    || { echo "lid: no sudo rule for pmset — run: bash ~/dotfiles/setup.sh macos" >&2; exit 1; }
}
until_time() { [ "$(cat "$STATE")" -eq 0 ] && echo "you run lid on" || date -r "$(cat "$STATE")" +%H:%M; }
battery_low() { # on battery power and below MIN_BATTERY%
  local batt pct
  batt="$(pmset -g batt)"
  pct="$(grep -Eo '[0-9]+%' <<<"$batt" | head -1 | tr -d %)"
  grep -q "'Battery Power'" <<<"$batt" && [ -n "$pct" ] && [ "$pct" -lt "$MIN_BATTERY" ]
}
notify() { osascript -e "display notification \"$1\" with title \"lid\"" >/dev/null 2>&1 || true; }

case "${1:-status}" in
  off)
    deadline=0 # no duration: until `lid on`
    if [ -n "${2:-}" ]; then
      if [[ ! "$2" =~ ^([0-9]+)([hm]?)$ ]] || [ "${BASH_REMATCH[1]}" -eq 0 ]; then
        echo "usage: lid off [8h|90m]  (a bare number means hours; none = until lid on)" >&2
        exit 1
      fi
      secs=$((BASH_REMATCH[1] * 3600))
      [ "${BASH_REMATCH[2]}" = m ] && secs=$((BASH_REMATCH[1] * 60))
      deadline=$(($(date +%s) + secs))
    fi
    set_disablesleep 1
    mkdir -p "$(dirname "$STATE")"
    echo "$deadline" > "$STATE"
    echo "lid: staying awake with the lid closed until $(until_time) (pausing while battery is below $MIN_BATTERY%)"
    ;;
  on)
    rm -f "$STATE"
    set_disablesleep 0
    echo "lid: sleep back to normal"
    ;;
  check) # the LaunchAgent, every minute: revert once time's up; pause while battery's low
    [ -f "$STATE" ] || exit 0
    deadline="$(cat "$STATE")"
    if [ "$deadline" -ne 0 ] && [ "$(date +%s)" -ge "$deadline" ]; then
      rm -f "$STATE"
      set_disablesleep 0
      notify "Sleep back to normal (time's up)"
    elif battery_low; then
      if sleep_disabled; then
        set_disablesleep 0
        notify "Battery below $MIN_BATTERY% — sleep allowed until it's charging"
      fi
    elif ! sleep_disabled; then # battery recovered, or a reboot reset it
      set_disablesleep 1
      notify "Staying awake again"
    fi
    ;;
  status)
    if [ -f "$STATE" ] && ! sleep_disabled; then
      echo "lid: paused while battery is below $MIN_BATTERY% — stays awake again once charging (lid on to stop)"
    elif ! sleep_disabled; then
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

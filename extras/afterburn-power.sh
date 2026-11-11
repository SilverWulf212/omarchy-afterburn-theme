# shellcheck shell=bash
# afterburn-power.sh: which power supplies count as "this machine's battery". Source it, do not run it.
# Used by afterburn-watch (battery saver) and the afterburn CLI (status, doctor).
#
# Linux lists every battery it knows in /sys/class/power_supply, wireless mice and keyboards (Logitech
# hidpp_battery_0, hid-*-battery) and game controllers included. Those say `scope` = Device. A laptop's
# own battery has scope System, or no scope file at all. Only the second kind means "this is a
# laptop", so a desktop with a wireless mouse is not one.
#
# POWER_DIR overrides the sysfs folder (tests).

: "${POWER_DIR:=/sys/class/power_supply}"

# Reads one attribute of a power supply folder; empty if missing.
ab_ps_attr() { cat "$1/$2" 2>/dev/null || true; }

# Prints one word: system, peripheral, mains or other. system = a battery that powers this machine.
ab_ps_kind() {
  local d=$1 type scope
  type=$(ab_ps_attr "$d" type)
  case $type in
    Mains) echo mains ;;
    Battery)
      scope=$(ab_ps_attr "$d" scope)
      case ${scope,,} in
        ''|system) echo system ;;
        *)         echo peripheral ;;
      esac ;;
    *) echo other ;;
  esac
}

# The system batteries' folder names, one per line.
ab_system_batteries() {
  local d
  for d in "$POWER_DIR"/*; do
    [[ -d $d && $(ab_ps_kind "$d") == system ]] && basename "$d"
  done
  return 0
}

ab_has_battery() { [[ -n $(ab_system_batteries) ]]; }

# True when a mains adapter reports online.
ab_on_ac() {
  local d
  for d in "$POWER_DIR"/*; do
    [[ $(ab_ps_attr "$d" type) == Mains && $(ab_ps_attr "$d" online) == 1 ]] && return 0
  done
  return 1
}

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

# ab_ps_read VAR DIR ATTR: sets VAR to one attribute of a power supply folder; empty if missing or unreadable.
# A builtin read, no fork: the watcher asks on every power event. (A sysfs attribute is one line.)
ab_ps_read() { printf -v "$1" %s ""; { IFS= read -r "$1" < "$2/$3"; } 2>/dev/null; return 0; }

# Prints one attribute of a power supply folder; empty if missing.
ab_ps_attr() { local v; ab_ps_read v "$1" "$2"; printf '%s' "$v"; }

# Prints one word: system, peripheral, mains or other. system = a battery that powers this machine.
ab_ps_kind() {
  local d=$1 type scope
  ab_ps_read type "$d" type
  case $type in
    Mains) echo mains ;;
    Battery)
      ab_ps_read scope "$d" scope
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
    [[ -d $d && $(ab_ps_kind "$d") == system ]] && printf '%s\n' "${d##*/}"
  done
  return 0
}

ab_has_battery() { [[ -n $(ab_system_batteries) ]]; }

# True when a mains adapter reports online.
ab_on_ac() {
  local d type online
  for d in "$POWER_DIR"/*; do
    ab_ps_read type "$d" type
    [[ $type == Mains ]] || continue
    ab_ps_read online "$d" online
    [[ $online == 1 ]] && return 0
  done
  return 1
}

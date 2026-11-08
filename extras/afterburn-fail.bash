# afterburn-fail.bash - red-hot "command failed" flash for bash.
# Part of the Afterburn subtle pack. Source it from ~/.bashrc:
#   [[ -f ~/.config/omarchy/themes/afterburn/extras/afterburn-fail.bash ]] && source ...
#
# After a failed command, plays one short truecolor animation (burn, cascade,
# dissolve) on a line showing "✗ <command>  exit N", then erases the line.
# Animation duration is about 400 ms; configuration and palette are validated before playback.
#
# Skips: exit 130/148 (Ctrl-C, Ctrl-Z), non-interactive shells, NO_MOTION set.
# FAIL_FX (random|burn|cascade|dissolve|off) comes from
# ${XDG_CONFIG_HOME:-~/.config}/afterburn/afterburn.conf, read as validated data on each failed command.

if [[ $- == *i* && -t 1 && -z ${__AFTERBURN_FAIL_HOOKED-} ]]; then
  __AFTERBURN_FAIL_HOOKED=1
  __AFTERBURN_FAIL_FX=${__AFTERBURN_FAIL_FX-random}

  __AFB_FRAMES=8
  __AFB_DELAY=0.05
  # Base theme colours. An edition's colours replace these from palette.env (see below).
  __AFB_FLARE=$'\e[38;2;255;196;138m'   # #ffc48a
  __AFB_EMBER=$'\e[38;2;255;90;31m'     # #ff5a1f
  __AFB_RUST=$'\e[38;2;122;62;22m'      # #7a3e16
  __AFB_ASH=$'\e[38;2;94;91;85m'        # #5e5b55
  __AFB_BURN=("$__AFB_FLARE" "$__AFB_EMBER" "$__AFB_RUST" "$__AFB_ASH")
  __AFTERBURN_PAL_MTIME=${__AFTERBURN_PAL_MTIME-}
  __AFB_CASCADE=('▀' '▄' '_' '.')
  __AFB_DISSOLVE=('▓' '▒' '░')

  # Read only the two relevant validated values, without evaluating shell syntax.
  __afterburn_fail_load_conf() {
    local helper="$HOME/.config/omarchy/themes/afterburn/extras/afterburn-theme.sh"
    if ! declare -F ab_load_conf >/dev/null; then
      [[ -r $helper ]] || { __AFTERBURN_FAIL_FX=off; return; }
      . "$helper"
    fi
    # Values are validated data; atomic replacement can occur within one timestamp
    # second, so do not cache solely by mtime.
    local MOTION=on FAIL_FX=random k v
    for k in MOTION FAIL_FX; do
      if v=$(ab_file_value "$(ab_conf_path)" "$k") && ab_config_valid "$k" "$v"; then printf -v "$k" %s "$v"; fi
    done
    __AFTERBURN_FAIL_FX=$FAIL_FX
    ab_motion_enabled || __AFTERBURN_FAIL_FX=off
  }

  # Colours of the active Afterburn theme or edition, written by the theme-set hook to
  # ${XDG_STATE_HOME:-~/.local/state}/afterburn/palette.env (FLARE=, EMBER=, RUST=, ASH= as 6-digit hex).
  # Re-read only when the file's mtime changes; no file means the base colours.
  __afterburn_fail_load_palette() {
    local pal=${XDG_STATE_HOME:-$HOME/.local/state}/afterburn/palette.env
    local mtime k v
    mtime=$(stat -c %Y -- "$pal" 2>/dev/null) || mtime=missing
    [[ $mtime == "$__AFTERBURN_PAL_MTIME" ]] && return 0
    __AFTERBURN_PAL_MTIME=$mtime
    __AFB_FLARE=$'\e[38;2;255;196;138m' __AFB_EMBER=$'\e[38;2;255;90;31m'
    __AFB_RUST=$'\e[38;2;122;62;22m' __AFB_ASH=$'\e[38;2;94;91;85m'
    if [[ -r $pal ]]; then
      while IFS='=' read -r k v || [[ -n $k ]]; do
        [[ $v =~ ^[0-9a-fA-F]{6}$ ]] || continue
        v=$'\e[38;2;'$((16#${v:0:2}))';'$((16#${v:2:2}))';'$((16#${v:4:2}))'m'
        case $k in
          FLARE) __AFB_FLARE=$v ;; EMBER) __AFB_EMBER=$v ;;
          RUST) __AFB_RUST=$v ;; ASH) __AFB_ASH=$v ;;
        esac
      done < "$pal"
    fi
    __AFB_BURN=("$__AFB_FLARE" "$__AFB_EMBER" "$__AFB_RUST" "$__AFB_ASH")
  }

  # $1 exit code, $2 effect name, $3 command text (already truncated).
  __afterburn_fail_play() {
    local rc=$1 fx=$2 cmd=$3
    local text n i f s ch out
    local -a offs=()
    text="✗ ${cmd}  exit ${rc}"
    n=${#text}
    for ((i = 0; i < n; i++)); do
      if [[ $fx == burn ]]; then
        offs[i]=$(( i * 3 / n + RANDOM % 2 ))   # left to right, with jitter
      else
        offs[i]=$(( RANDOM % 4 ))               # random order
      fi
    done
    for ((f = 0; f < __AFB_FRAMES; f++)); do
      out=$'\r\e[2K'
      for ((i = 0; i < n; i++)); do
        ch=${text:i:1}
        s=$(( f - offs[i] ))
        if (( s < 0 )); then
          out+="${__AFB_FLARE}${ch}"
          continue
        fi
        case $fx in
          burn)
            if (( s < 4 )); then out+="${__AFB_BURN[s]}${ch}"; else out+=' '; fi ;;
          cascade)
            if (( s < 4 )); then out+="${__AFB_EMBER}${__AFB_CASCADE[s]}"; else out+=' '; fi ;;
          dissolve)
            if (( s < 3 )); then out+="${__AFB_EMBER}${__AFB_DISSOLVE[s]}"; else out+=' '; fi ;;
        esac
      done
      printf '%s' "$out"
      sleep "$__AFB_DELAY"
    done
    printf '\r\e[2K'
  }

  # PROMPT_COMMAND hook. Must be first so later entries (Starship) see $?.
  __afterburn_fail_hook() {
    local rc=$?
    local LC_ALL=C.UTF-8   # so ${#text} and ${text:i:1} count characters, not bytes
    if (( rc != 0 && rc != 130 && rc != 148 )) \
       && [[ $- == *i* && -t 1 && -z ${NO_MOTION+x} ]]; then
      __afterburn_fail_load_conf
      __afterburn_fail_load_palette
      local line cmd fx
      line=$(builtin history 1 2>/dev/null)
      read -r _ cmd <<<"$line"        # drop the history number
      cmd=${cmd//[[:cntrl:]]/}
      cmd=${cmd:0:40}
      [[ -n $cmd ]] || cmd=command
      case $__AFTERBURN_FAIL_FX in
        off) ;;
        burn|cascade|dissolve) __afterburn_fail_play "$rc" "$__AFTERBURN_FAIL_FX" "$cmd" ;;
        *)
          local -a fxs=(burn cascade dissolve)
          __afterburn_fail_play "$rc" "${fxs[RANDOM % 3]}" "$cmd" ;;
      esac
    fi
    return "$rc"                          # restore $? for the rest of PROMPT_COMMAND
  }

  # Prepend the hook to PROMPT_COMMAND (array on bash 5.1+, string otherwise).
  __afterburn_fail_register() {
    local decl e
    decl=$(declare -p PROMPT_COMMAND 2>/dev/null) || decl=""
    if [[ $decl == "declare -a"* ]]; then
      for e in ${PROMPT_COMMAND[@]+"${PROMPT_COMMAND[@]}"}; do
        [[ $e == __afterburn_fail_hook* ]] && return 0
      done
      PROMPT_COMMAND=(__afterburn_fail_hook ${PROMPT_COMMAND[@]+"${PROMPT_COMMAND[@]}"})
    else
      case ${PROMPT_COMMAND-} in *__afterburn_fail_hook*) return 0 ;; esac
      PROMPT_COMMAND="__afterburn_fail_hook${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    fi
  }

  __afterburn_fail_register
fi

# afterburn-fail.zsh - red-hot "command failed" flash for zsh. The zsh twin of afterburn-fail.bash.
# Part of the Afterburn subtle pack. Source it from ~/.zshrc:
#   [[ -f ~/.config/omarchy/themes/afterburn/extras/afterburn-fail.zsh ]] && source ...
#
# Same effects, settings and skips as afterburn-fail.bash (see there): after a failed command, one short
# truecolor animation (burn, cascade, dissolve) on a line showing "✗ <command>  exit N", then the line is
# erased. FAIL_FX from afterburn.conf, colours from the theme-set hook's palette.env, both re-read on mtime.
#
# zsh differences: preexec says a command ran and hands over its text (no history read, no \# trick);
# zsh gives every precmd hook the real $? and $pipestatus, so the hook's place in precmd_functions does not
# matter and Starship still sees the exit code. No forks at all: zstat for mtimes, zselect for the frame delay
# (falls back to sleep when the modules are missing).

# No -t 1 here: setups such as Powerlevel10k's instant prompt redirect stdout while ~/.zshrc runs. precmd checks it.
if [[ -o interactive && -z ${__AFTERBURN_FAIL_HOOKED-} ]]; then
  typeset -g __AFTERBURN_FAIL_HOOKED=1
  typeset -g __AFTERBURN_FAIL_MTIME= __AFTERBURN_PAL_MTIME= __AFTERBURN_FAIL_FX=random
  typeset -g __AFB_RAN=0 __AFB_CMD=
  typeset -g __AFB_FRAMES=8 __AFB_DELAY_CS=5   # 8 frames, 50 ms each
  typeset -ga __AFB_CASCADE=('▀' '▄' '_' '.') __AFB_DISSOLVE=('▓' '▒' '░') __AFB_BURN=()
  typeset -g __AFB_FLARE __AFB_EMBER __AFB_RUST __AFB_ASH
  zmodload -F zsh/stat b:zstat 2>/dev/null
  zmodload zsh/zselect 2>/dev/null

  # Every function starts with emulate -L zsh: your options (ksh_arrays, ...) must not change indexing here.
  __afterburn_fail_mtime() {   # $1 file -> REPLY (mtime, or "missing")
    emulate -L zsh
    local -a m
    if (( $+builtins[zstat] )) && zstat -A m +mtime -- "$1" 2>/dev/null; then REPLY=$m[1]
    elif [[ -e $1 ]]; then REPLY=$(stat -c %Y -- "$1" 2>/dev/null) || REPLY=missing
    else REPLY=missing; fi
  }

  __afterburn_fail_load_conf() {
    emulate -L zsh
    local conf=${XDG_CONFIG_HOME:-$HOME/.config}/afterburn/afterburn.conf k v REPLY
    __afterburn_fail_mtime "$conf"
    [[ $REPLY == "$__AFTERBURN_FAIL_MTIME" ]] && return 0
    __AFTERBURN_FAIL_MTIME=$REPLY
    __AFTERBURN_FAIL_FX=random
    [[ -r $conf ]] || return 0
    while IFS='=' read -r k v || [[ -n $k ]]; do
      if [[ $k == FAIL_FX ]]; then
        v=${v%%\#*}
        __AFTERBURN_FAIL_FX=${v//[[:space:]]/}
      fi
    done < "$conf"
  }

  __afterburn_fail_load_palette() {
    emulate -L zsh
    local pal=${XDG_STATE_HOME:-$HOME/.local/state}/afterburn/palette.env k v REPLY
    __afterburn_fail_mtime "$pal"
    [[ $REPLY == "$__AFTERBURN_PAL_MTIME" ]] && return 0
    __AFTERBURN_PAL_MTIME=$REPLY
    __AFB_FLARE=$'\e[38;2;255;196;138m' __AFB_EMBER=$'\e[38;2;255;90;31m'
    __AFB_RUST=$'\e[38;2;122;62;22m' __AFB_ASH=$'\e[38;2;94;91;85m'
    if [[ -r $pal ]]; then
      while IFS='=' read -r k v || [[ -n $k ]]; do
        [[ $v =~ '^[0-9a-fA-F]{6}$' ]] || continue
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
    emulate -L zsh
    local rc=$1 fx=$2 cmd=$3 text out ch
    local -i n i f s
    local -a offs
    text="✗ ${cmd}  exit ${rc}"
    n=${#text}
    for (( i = 1; i <= n; i++ )); do
      if [[ $fx == burn ]]; then
        offs[i]=$(( (i - 1) * 3 / n + RANDOM % 2 ))   # left to right, with jitter
      else
        offs[i]=$(( RANDOM % 4 ))                     # random order
      fi
    done
    for (( f = 0; f < __AFB_FRAMES; f++ )); do
      out=$'\r\e[2K'
      for (( i = 1; i <= n; i++ )); do
        ch=${text[i]}
        s=$(( f - offs[i] ))
        if (( s < 0 )); then
          out+="${__AFB_FLARE}${ch}"
          continue
        fi
        case $fx in
          burn)     if (( s < 4 )); then out+="${__AFB_BURN[s+1]}${ch}"; else out+=' '; fi ;;
          cascade)  if (( s < 4 )); then out+="${__AFB_EMBER}${__AFB_CASCADE[s+1]}"; else out+=' '; fi ;;
          dissolve) if (( s < 3 )); then out+="${__AFB_EMBER}${__AFB_DISSOLVE[s+1]}"; else out+=' '; fi ;;
        esac
      done
      print -rn -- "$out"
      if (( $+builtins[zselect] )); then zselect -t $__AFB_DELAY_CS; else sleep 0.05; fi
    done
    print -rn -- $'\r\e[2K'
  }

  # preexec: a command is about to run. An empty Enter runs no preexec, so it never replays a failure.
  __afterburn_fail_preexec() {
    emulate -L zsh
    __AFB_RAN=1
    __AFB_CMD=$1
  }

  __afterburn_fail_precmd() {
    local rc=$?   # first: emulate would reset it
    emulate -L zsh
    local ran=$__AFB_RAN
    __AFB_RAN=0
    (( ran && rc != 0 && rc != 130 && rc != 148 )) || return 0
    [[ -o interactive && -t 1 && -z ${NO_MOTION+x} ]] || return 0
    local LC_ALL=C.UTF-8   # so ${#text} and ${text[i]} count characters
    local theme=
    { read -r theme < "$HOME/.local/state/omarchy/current/theme.name" } 2>/dev/null
    [[ $theme == afterburn || $theme == afterburn-* ]] || return 0
    [[ -f ${XDG_CONFIG_HOME:-$HOME/.config}/afterburn/afterburn.conf ]] || return 0
    __afterburn_fail_load_conf
    [[ $__AFTERBURN_FAIL_FX == off ]] && return 0
    __afterburn_fail_load_palette
    local cmd=${__AFB_CMD//[[:cntrl:]]/}
    cmd=${cmd[1,40]}
    [[ -n $cmd ]] || cmd=command
    case $__AFTERBURN_FAIL_FX in
      burn|cascade|dissolve) __afterburn_fail_play "$rc" "$__AFTERBURN_FAIL_FX" "$cmd" ;;
      *) local -a fxs=(burn cascade dissolve); __afterburn_fail_play "$rc" "${fxs[RANDOM % 3 + 1]}" "$cmd" ;;
    esac
    return 0
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec __afterburn_fail_preexec
  add-zsh-hook precmd __afterburn_fail_precmd
fi

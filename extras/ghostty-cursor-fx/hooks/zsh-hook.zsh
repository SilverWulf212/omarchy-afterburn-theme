# Cursor FX for Ghostty (see `cursor-fx`): the Enter signal before every command, and the
# "done" signal after a command that took more than 5 seconds. Both run in the background.
# Add this to ~/.zshrc.
if [[ -n $GHOSTTY_RESOURCES_DIR ]] && (( $+commands[cursor-fx] )); then
  autoload -Uz add-zsh-hook
  zmodload zsh/datetime
  _cursor_fx_enter() {
    _cursor_fx_t0=$EPOCHREALTIME
    cursor-fx signal --tty "$TTY" &!
  }
  _cursor_fx_done() {
    if [[ -n $_cursor_fx_t0 ]] && (( EPOCHREALTIME - _cursor_fx_t0 > 5 )); then
      cursor-fx signal done --tty "$TTY" &!
    fi
    _cursor_fx_t0=
  }
  add-zsh-hook preexec _cursor_fx_enter
  add-zsh-hook precmd _cursor_fx_done
fi

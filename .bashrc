# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

# pnpm
export PNPM_HOME="/home/adeadrat/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export PATH=$PATH:/usr/local/go/bin
alias vim='nvim'

export OPENCODE_CONFIG=~/.config/opencode/opencode.json

# opencode
export PATH=/home/adeadrat/.opencode/bin:$PATH

# Created by `pipx` on 2025-12-16 23:26:38
export PATH="$PATH:/home/adeadrat/.local/bin"

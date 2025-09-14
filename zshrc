# SSH Agent starten
if [ -z "$SSH_AGENT_PID" ]; then
    eval "$(ssh-agent -s)"
fi

ssh-add --apple-use-keychain ~/.ssh/id_ed25519

setopt EXTENDED_HISTORY      # Speichere Timestamps
setopt SHARE_HISTORY         # Teile History zwischen Sessions
setopt HIST_VERIFY           # Bestätige History-Expansion
setopt INC_APPEND_HISTORY    # Speichere sofort, nicht erst beim Exit
export HISTTIMEFORMAT="%d.%m.%Y %H:%M:%S "

# Completion-System aktivieren
autoload -Uz compinit
compinit
# load aliases first
if [ -f ~/.aliases ]; then
    source ~/.aliases
fi

# Shell helpers
export PATH="/opt/homebrew/bin:$PATH"
eval "$(/Users/abaer/.local/bin/mise activate zsh)"
export TOKENIZERS_PARALLELISM=false
eval "$(direnv hook zsh)"

# kubectl completion und alias
source <(kubectl completion zsh)
alias k='kubectl'
compdef k=kubectl

# shell design
PROMPT='[%F{green}%n%f]-(%F{blue}%~%f)-
%F{red}└─▶%f '

# Embedding my own shell helpers
if [ -d "$HOME/.shell-helpers" ]; then
    for helper in "$HOME/.shell-helpers"/*; do
        [ -r "$helper" ] && source "$helper"
    done
fi

# Personal Homebrew
export PATH="$HOME/.homebrew/bin:$PATH"

if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
fi

source ~/.shell-helpers/shell-helpers.bashrc

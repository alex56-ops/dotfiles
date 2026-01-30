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
alias k='kubectl $([ ! -z "$KUBECTL_NAMESPACE" ] && echo -n "--namespace=${KUBECTL_NAMESPACE}")'
if command -v kubectl &> /dev/null; then
    source <(kubectl completion zsh)
    compdef k=kubectl
fi

# shell design
PROMPT='[%F{green}%n%f]-(%F{blue}%~%f)-
%F{red}└─▶%f '

# Embedding my own shell scripts
if [ -d "$HOME/.shell-scripts" ]; then
    for helper in "$HOME/.shell-scripts"/*.sh; do
        [ -r "$helper" ] && source "$helper"
    done
fi

# Personal Homebrew
export PATH="$HOME/.homebrew/bin:$PATH"

if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
fi

# Nur für User "abaer" ausführen
if [[ "$USER" == "abaer" ]]; then
    source ~/.shell-helpers/shell-helpers.bashrc
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

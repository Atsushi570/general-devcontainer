# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
export CLICOLOR=1
export TERM=xterm-256color

ZSH_THEME="af-magic"
plugins=(git zsh-completions)
autoload -U compinit && compinit
source $ZSH/oh-my-zsh.sh

# Shorten directory in prompt (current directory only)
PROMPT="${PROMPT//\%\~/%1~}"

# fzf (Ctrl+R for history search, Ctrl+T for file search)
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --reverse --border'
source <(fzf --zsh) 2>/dev/null \
  || { [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh; \
       [ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh; }

# mise
eval "$(mise activate zsh)"

# History
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS
setopt SHARE_HISTORY

# dev: ghq + fzf + tmux
function dev() {
  local selected
  selected=$(ghq list --full-path | fzf --preview 'ls -la {}')
  if [[ -n "$selected" ]]; then
    cd "$selected"
    if [[ -n "$TMUX" ]]; then
      local repo_name
      repo_name=$(basename "$selected")
      tmux rename-session "$repo_name"
    fi
  fi
}

# tm: tmux session manager
function tm() {
  if [[ -n "$1" ]]; then
    tmux attach -t "$1" 2>/dev/null || tmux new -s "$1"
    return
  fi
  local selected_name
  selected_name=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | fzf --print-query --reverse)
  if [[ -z "$selected_name" ]]; then return 0; fi
  local target_session
  target_session=$(echo "$selected_name" | tail -n 1)
  if tmux has-session -t "$target_session" 2>/dev/null; then
    tmux attach -t "$target_session"
  else
    tmux new -s "$target_session"
  fi
}

# Aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

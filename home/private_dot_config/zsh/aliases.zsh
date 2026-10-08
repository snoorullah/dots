# Aliases and helper functions (sourced by ~/.zshrc). Git aliases come from zimfw/git.
alias ls='eza --icons=auto' ll='eza -la --icons=auto --git' la='eza -la --icons=auto' l='eza --icons=auto'
alias cat='bat --paging=never'
alias lg='lazygit'
alias k='kubectl' kgp='kubectl get pods' kgs='kubectl get svc' kgn='kubectl get nodes'
alias kdp='kubectl describe pod' kds='kubectl describe svc'
alias mtl='microk8s kubectl' m8='microk8s'
alias nv='nvim' x='clear' shm='ssh-manager' yv='yaml-validator-cli'
alias szh='source ~/.zshrc'
alias zedit='$EDITOR ~/.zshrc && szh'

copyfile() { wl-copy < "$1"; }
web()      { xdg-open "https://duckduckgo.com/?q=${*// /+}"; }

# Claude Code has no Linux clipboard-image paste. Copy an image, run ccimg,
# then paste the printed path into the prompt (Claude Code reads image paths).
ccimg() { local f="$HOME/Pictures/cc-$(date +%s).png"; wl-paste --type image/png > "$f" && echo "$f"; }

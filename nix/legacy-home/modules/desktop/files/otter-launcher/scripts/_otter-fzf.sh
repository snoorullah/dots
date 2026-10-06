#!/usr/bin/env bash
# Shared otter-styled fzf options + PATH, sourced by the otter module scripts.
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:$HOME/.cargo/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin${PATH:+:$PATH}"
export FZF_DEFAULT_OPTS="--reverse --no-scrollbar --no-separator --info=inline \
--border=none --margin=1 --padding=1 --prompt='  ' --pointer='▌' --marker='▌' \
--color=bg:-1,bg+:-1,fg:-1,fg+:15,hl:5,hl+:13,pointer:5,prompt:5,marker:5,gutter:-1,header:8,preview-bg:-1"

#!/usr/bin/env bash
# Spawn a script in a floating Ghostty popup window
# Usage: fzf-float.sh <script> [args...]

set -eu

script="$1"
shift

# Derive a human-readable title from the script name
title=$(basename "$script" .sh)
title=${title#.}
case "$title" in
    main|fzf-main-menu) title="tmux-fzf" ;;
    pass-menu)   title="Passwords" ;;
    ssh-menu)    title="SSH Keys" ;;
    mux-picker)  title="Projects" ;;
    window)      title="Windows" ;;
    session)     title="Sessions" ;;
    command)     title="Commands" ;;
    keybinding)  title="Keybindings" ;;
    pane)        title="Panes" ;;
    clipboard)   title="Clipboard" ;;
    process)     title="Processes" ;;
esac

SHIM_DIR="$HOME/.cache/tmux-fzf-shim"
mkdir -p "$SHIM_DIR"

# Shim: fzf-tmux → plain fzf (strip tmux popup/split flags)
cat > "$SHIM_DIR/fzf-tmux" << 'SHIM'
#!/usr/bin/env bash
args=()
skip_next=false
for arg in "$@"; do
    if $skip_next; then skip_next=false; continue; fi
    case "$arg" in
        -d|-u|-l|-r|-w|-h) skip_next=true; continue ;;
        -d*|-u*|-l*|-r*|-w*|-h*) continue ;;
        -p) continue ;;
        -p*) continue ;;
        *) args+=("$arg") ;;
    esac
done
exec fzf "${args[@]}"
SHIM
chmod +x "$SHIM_DIR/fzf-tmux"

# Grab tmux environment variables that plugins depend on (properly quoted)
tmux_env=$(tmux show-environment -g 2>/dev/null | grep -E '^TMUX_FZF_' | sed "s/=/='/;s/$/'/" | sed 's/^/export /' || true)

# Build quoted args
args_str=""
for arg in "$@"; do
    args_str="$args_str $(printf '%q' "$arg")"
done

cat > "$SHIM_DIR/runner.sh" << RUNNER
#!/usr/bin/env bash
export PATH="$SHIM_DIR:\$PATH"
export TMUX_FZF_FLOAT=1
$tmux_env
export FZF_DEFAULT_OPTS="\$FZF_DEFAULT_OPTS \\
  --color=bg+:#282a46,bg:#1a1a2e,fg:#f8f8f2,fg+:#f8f8f2 \\
  --color=hl:#bd93f9,hl+:#50fa7b,info:#585880,marker:#50fa7b \\
  --color=prompt:#bd93f9,spinner:#bd93f9,pointer:#ff9e3b,header:#585880 \\
  --color=border:#585880,separator:#585880,label:#bd93f9 \\
  --layout=reverse --no-border --margin=0 --padding=0"
"$script" $args_str 2>&1
ret=\$?
if [ \$ret -ne 0 ]; then
    echo ""
    echo "--- exited with code \$ret ---"
    read -r
fi
RUNNER
chmod +x "$SHIM_DIR/runner.sh"

ghostty \
    --class=dots.tmuxfzf \
    --title="$title" \
    --gtk-single-instance=false \
    --config-file="$HOME/.config/ghostty/popup" \
    --window-width=80 \
    --window-height=20 \
    -e "$SHIM_DIR/runner.sh"

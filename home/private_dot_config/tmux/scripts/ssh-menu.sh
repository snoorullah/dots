#!/usr/bin/env bash
# SSH key manager popup for tmux
# Shows all keys with load status, load/unload via fzf
#
# enter   = load key into agent (passphrase from pass)
# ctrl-u  = unload key from agent
# ctrl-a  = load ALL keys
# ctrl-d  = flush agent (unload all)
# ctrl-p  = add passphrase to unprotected key + store in pass

set -eu

# Re-launch in floating terminal if called from tmux directly
if [ -z "${TMUX_FZF_FLOAT:-}" ] && [ -n "${TMUX:-}" ]; then
    export TMUX_FZF_FLOAT=1
    exec "$HOME/.config/tmux/scripts/fzf-float.sh" "$0" "$@"
fi

SSH_DIR="$HOME/.ssh"
ASKPASS="$HOME/.config/tmux/scripts/ssh-askpass.sh"

# Key registry: name|file|description
KEYS=(
    "github_keys|$SSH_DIR/github_keys|GitHub (personal)"
    "pnow-github|$SSH_DIR/pnow-devsupreme-github|GitHub (pnow)"
    "wbslk_platform|$SSH_DIR/wbslk_platform|Contabo (wbslk)"
    "hostinger|$SSH_DIR/hostinger|Hostinger VPS"
    "aws-hg-keypair|$SSH_DIR/aws-hg-keypair.pem|AWS (hg)"
)

# Get fingerprints currently loaded in agent
loaded_fps=$(ssh-add -l 2>/dev/null | awk '{print $2}' || true)

# Build display list
entries=""
for entry in "${KEYS[@]}"; do
    IFS='|' read -r name file desc <<< "$entry"
    [ ! -f "$file" ] && continue

    # Get this key's fingerprint
    fp=$(ssh-keygen -lf "$file" 2>/dev/null | awk '{print $2}' || true)

    # Check if loaded
    if echo "$loaded_fps" | grep -qF "$fp" 2>/dev/null; then
        status="●"
    else
        status="○"
    fi

    # Check if key has passphrase
    if ssh-keygen -y -P "" -f "$file" &>/dev/null; then
        lock="  unlocked"
    else
        lock="  locked"
    fi

    line="$status  $name${lock}  $desc"
    if [ -z "$entries" ]; then
        entries="$line"
    else
        entries="$entries
$line"
    fi
done

if [ -z "$entries" ]; then
    tmux display-message "No SSH keys found in $SSH_DIR"
    exit 0
fi

# Fuzzy pick
result=$(printf '%s\n' "$entries" | fzf \
    --prompt='  SSH Keys  ' \
    --header='enter=load  ^u=unload  ^a=load-all  ^d=flush  ^p=add-passphrase' \
    --expect='ctrl-u,ctrl-a,ctrl-d,ctrl-p' \
    --ansi \
    --no-multi \
    --layout=reverse \
    --border=rounded \
    --margin=1,2) || exit 0

[ -z "$result" ] && exit 0

# Parse fzf --expect
key=$(printf '%s' "$result" | head -1)
selection=$(printf '%s' "$result" | tail -1)

# Extract key name from selection (second field after status icon)
selected_name=$(echo "$selection" | awk '{print $2}')

# Find the file path for selected key
selected_file=""
for entry in "${KEYS[@]}"; do
    IFS='|' read -r name file desc <<< "$entry"
    if [ "$name" = "$selected_name" ]; then
        selected_file="$file"
        break
    fi
done

case "$key" in
    ctrl-a)
        # Load ALL keys
        export SSH_ASKPASS="$ASKPASS"
        export SSH_ASKPASS_REQUIRE="force"
        count=0
        for entry in "${KEYS[@]}"; do
            IFS='|' read -r name file desc <<< "$entry"
            [ ! -f "$file" ] && continue
            if ssh-add -t 3600 "$file" 2>/dev/null; then
                count=$((count + 1))
            fi
        done
        tmux display-message "Loaded $count SSH keys (expire in 1h)"
        ;;

    ctrl-d)
        # Flush all keys from agent
        ssh-add -D 2>/dev/null
        tmux display-message "All SSH keys unloaded from agent"
        ;;

    ctrl-u)
        # Unload selected key
        if [ -n "$selected_file" ]; then
            ssh-add -d "$selected_file" 2>/dev/null
            tmux display-message "Unloaded: $selected_name"
        fi
        ;;

    ctrl-p)
        # Add passphrase to key and store in pass
        if [ -z "$selected_file" ]; then
            tmux display-message "No key selected"
            exit 0
        fi

        # Check if already has passphrase
        if ! ssh-keygen -y -P "" -f "$selected_file" &>/dev/null; then
            tmux display-message "$selected_name already has a passphrase"
            exit 0
        fi

        # Generate a strong passphrase
        new_pass=$(pass generate -n "ssh/$selected_name" 32 2>/dev/null | tail -1)

        if [ -z "$new_pass" ]; then
            tmux display-message "Failed to generate passphrase"
            exit 1
        fi

        # Add passphrase to the key
        # ssh-keygen -p requires interactive input, so use expect-like approach
        ssh-keygen -p -f "$selected_file" -N "$new_pass" 2>/dev/null
        if [ $? -eq 0 ]; then
            tmux display-message "Passphrase added to $selected_name and stored in pass (ssh/$selected_name)"
        else
            # Clean up pass entry if key encryption failed
            pass rm -f "ssh/$selected_name" 2>/dev/null
            tmux display-message "Failed to add passphrase to $selected_name"
        fi
        ;;

    *)
        # Load selected key
        if [ -n "$selected_file" ]; then
            export SSH_ASKPASS="$ASKPASS"
            export SSH_ASKPASS_REQUIRE="force"
            if ssh-add -t 3600 "$selected_file" 2>/dev/null; then
                tmux display-message "Loaded: $selected_name (expires in 1h)"
            else
                tmux display-message "Failed to load: $selected_name"
            fi
        fi
        ;;
esac

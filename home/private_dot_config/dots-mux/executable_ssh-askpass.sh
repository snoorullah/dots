#!/usr/bin/env bash
# SSH_ASKPASS provider that reads passphrases from pass (password-store)
# ssh-add calls this with a prompt like "Enter passphrase for /home/user/.ssh/keyname:"
# We extract the key filename and look it up in pass under ssh/

set -eu

prompt="${1:-}"

# Extract key filename from ssh-add's prompt
# Prompt format: "Enter passphrase for /path/to/.ssh/keyname:"
keypath=$(echo "$prompt" | grep -oP '(?<=for ).+(?=:)' || true)

if [ -z "$keypath" ]; then
    # Fallback: if prompt doesn't match, show a pinentry/zenity dialog
    if command -v zenity &>/dev/null; then
        zenity --password --title="SSH Passphrase" --text="$prompt" 2>/dev/null
    else
        echo "" >&2
        exit 1
    fi
    exit $?
fi

# Get the key basename (e.g., github_keys, hostinger)
keyname=$(basename "$keypath" | sed 's/\.pem$//')

# Look up in pass: ssh/<keyname>
passphrase=$(pass show "ssh/$keyname" 2>/dev/null | head -1)

if [ -n "$passphrase" ]; then
    printf '%s\n' "$passphrase"
else
    # Passphrase not in store — fall back to zenity
    if command -v zenity &>/dev/null; then
        zenity --password --title="SSH Passphrase" --text="$prompt" 2>/dev/null
    else
        echo "ERROR: No passphrase found in pass for ssh/$keyname" >&2
        exit 1
    fi
fi

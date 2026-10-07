#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  install.sh — tmux-config installer                                ║
# ║  https://github.com/shaiknoorullah/tmux-config                     ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# one-liner:
#   curl -fsSL https://raw.githubusercontent.com/shaiknoorullah/tmux-config/main/install.sh | bash
#
# or clone first:
#   git clone https://github.com/shaiknoorullah/tmux-config.git ~/tmux-config
#   cd ~/tmux-config && ./install.sh
#
# flags: --deps-only | --no-deps | --uninstall | --help

set -euo pipefail

REPO_URL="https://github.com/shaiknoorullah/tmux-config.git"
CLONE_DIR="$HOME/tmux-config"
TMUX_DIR="$HOME/.config/tmux"
TPM_DIR="$TMUX_DIR/plugins/tpm"

# ── Bootstrap: clone repo if running from curl pipe ───────────────────
# Detect if we're inside the repo or piped from curl/wget
REPO_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || echo "")"

if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$SCRIPT_DIR/tmux.conf" ]]; then
    # Running from inside cloned repo
    REPO_DIR="$SCRIPT_DIR"
else
    # Running from curl pipe or outside repo — need to clone
    REPO_DIR="$CLONE_DIR"
fi

# ── Terminal Colors ───────────────────────────────────────────────────
readonly R=$'\033[0m'     # reset
readonly B=$'\033[1m'     # bold
readonly D=$'\033[2m'     # dim
readonly I=$'\033[3m'     # italic
readonly RED=$'\033[0;31m'
readonly GRN=$'\033[0;32m'
readonly YLW=$'\033[0;33m'
readonly BLU=$'\033[0;34m'
readonly MAG=$'\033[0;35m'
readonly CYN=$'\033[0;36m'

# ── Output Helpers ────────────────────────────────────────────────────
ok()    { printf "  ${GRN}${B}✓${R}  %s\n" "$*"; }
err()   { printf "  ${RED}${B}✗${R}  %s\n" "$*"; }
wrn()   { printf "  ${YLW}${B}!${R}  %s\n" "$*"; }
inf()   { printf "  ${BLU}${B}::${R} %s\n" "$*"; }
ask()   { printf "  ${MAG}${B}?${R}  %s " "$*"; }
dim()   { printf "${D}%s${R}" "$*"; }
step()  { printf "\n${CYN}${B}─── %s${R}\n\n" "$*"; }

# Detect working TTY once at startup
HAS_TTY=false
(echo </dev/tty) 2>/dev/null && HAS_TTY=true

# Interactive read — uses /dev/tty if available, falls back to stdin
# Returns 1 (no) if not interactive
prompt_yn() {
    local reply=""
    if [[ "$HAS_TTY" == true ]]; then
        read -r reply </dev/tty
    elif [[ -t 0 ]]; then
        read -r reply
    else
        printf "\n"
        reply="n"
    fi
    [[ "$reply" =~ ^[Yy] ]]
}

# ── Banner ────────────────────────────────────────────────────────────
banner() {
    printf "\n"
    printf "${D}    ┌─────────────────────────────────────────┐${R}\n"
    printf "${D}    │${R}  ${B}tmux-config${R}  ${D}installer${R}                  ${D}│${R}\n"
    printf "${D}    │${R}  ${D}prefix key finally makes sense${R}           ${D}│${R}\n"
    printf "${D}    │${R}  ${D}github.com/shaiknoorullah/tmux-config${R}   ${D}│${R}\n"
    printf "${D}    └─────────────────────────────────────────┘${R}\n"
    printf "\n"
}

# ── Usage ─────────────────────────────────────────────────────────────
usage() {
    banner
    cat <<EOF
  ${B}usage:${R} ./install.sh [options]

  ${B}options:${R}
    --deps-only    install dependencies only, don't link config
    --no-deps      skip dependency installation
    --uninstall    remove symlink and restore backup if available
    --help, -h     show this message

  ${B}what it does:${R}
    1. detects your package manager
    2. installs required dependencies (tmux, fzf, git, clipboard)
    3. prompts for optional tools (taskwarrior, pass, gh, etc.)
    4. backs up existing ~/.config/tmux
    5. symlinks this repo as ~/.config/tmux
    6. installs TPM + all 14 plugins
    7. reloads tmux if running
EOF
    exit 0
}

# ── Parse args ────────────────────────────────────────────────────────
DEPS_ONLY=false
NO_DEPS=false
UNINSTALL=false

for arg in "$@"; do
    case "$arg" in
        --deps-only)  DEPS_ONLY=true ;;
        --no-deps)    NO_DEPS=true ;;
        --uninstall)  UNINSTALL=true ;;
        --help|-h)    usage ;;
        *)            wrn "unknown arg: $arg"; usage ;;
    esac
done

# ── Detect package manager ────────────────────────────────────────────
detect_pm() {
    if command -v apt-get &>/dev/null; then   echo "apt"
    elif command -v dnf &>/dev/null; then     echo "dnf"
    elif command -v pacman &>/dev/null; then  echo "pacman"
    elif command -v zypper &>/dev/null; then  echo "zypper"
    elif command -v apk &>/dev/null; then     echo "apk"
    elif command -v brew &>/dev/null; then    echo "brew"
    else                                      echo "unknown"
    fi
}

PM=$(detect_pm)

pm_install() {
    local pkg="$1"
    inf "installing ${B}$pkg${R} via $PM..."
    case "$PM" in
        apt)    sudo apt-get install -y -qq "$pkg" 2>/dev/null ;;
        dnf)    sudo dnf install -y -q "$pkg" 2>/dev/null ;;
        pacman) sudo pacman -S --noconfirm --quiet "$pkg" 2>/dev/null ;;
        zypper) sudo zypper install -y "$pkg" 2>/dev/null ;;
        apk)    sudo apk add -q "$pkg" 2>/dev/null ;;
        brew)   brew install -q "$pkg" 2>/dev/null ;;
        *)      err "unknown package manager — install ${B}$pkg${R} manually"; return 1 ;;
    esac
}

# ── Dependency Checkers ───────────────────────────────────────────────
has() { command -v "$1" &>/dev/null; }

check_required() {
    local cmd="$1" pkg="${2:-$1}"
    if has "$cmd"; then
        ok "$cmd $(dim "$(command -v "$cmd")")"
        return 0
    fi
    pm_install "$pkg"
    has "$cmd" && ok "$cmd installed" || { err "failed to install $cmd"; return 1; }
}

check_optional() {
    local cmd="$1" pkg="${2:-$1}" desc="${3:-}"
    if has "$cmd"; then
        ok "$cmd $(dim "$(command -v "$cmd")")"
        return 0
    fi
    ask "${B}$cmd${R} not found${desc:+ — $desc}. install? [y/N]"
    prompt_yn || { printf "     ${D}skipped${R}\n"; return 0; }
    pm_install "$pkg"
    has "$cmd" && ok "$cmd installed" || err "failed to install $cmd"
}

check_pipx() {
    local pkg="$1" cmd="${2:-$1}" desc="${3:-}"
    if has "$cmd"; then
        ok "$cmd $(dim "$(command -v "$cmd")")"
        return 0
    fi
    ask "${B}$cmd${R} not found${desc:+ — $desc}. install via pipx? [y/N]"
    prompt_yn || { printf "     ${D}skipped${R}\n"; return 0; }
    if ! has pipx; then
        inf "installing pipx first..."
        pm_install pipx || { err "can't install pipx"; return 1; }
    fi
    pipx install "$pkg" 2>/dev/null
    has "$cmd" && ok "$cmd installed" || err "failed to install $cmd"
}

# ── Dependencies ──────────────────────────────────────────────────────
install_deps() {
    step "dependencies"

    inf "package manager: ${B}$PM${R}"
    echo

    printf "  ${BLU}${B}required${R}\n"
    check_required tmux
    check_required fzf
    check_required git

    # clipboard — need at least one
    if has xclip || has xsel || has wl-copy; then
        ok "clipboard $(dim "$(command -v xclip 2>/dev/null || command -v xsel 2>/dev/null || command -v wl-copy 2>/dev/null)")"
    else
        inf "no clipboard tool found"
        pm_install xclip
        has xclip && ok "xclip installed" || wrn "install xclip, xsel, or wl-clipboard manually"
    fi

    # nerd font check (best effort)
    if fc-list 2>/dev/null | grep -qi "nerd"; then
        ok "nerd font $(dim "detected")"
    else
        wrn "nerd font not detected — icons will be broken without one"
        printf "     ${D}install from: https://www.nerdfonts.com/${R}\n"
    fi

    echo
    printf "  ${BLU}${B}optional ${D}(press y to install, anything else to skip)${R}\n"
    check_optional pass pass "password manager popup (prefix+*)"
    check_optional gpg gnupg "GPG encryption for pass"
    check_optional task taskwarrior "focus dashboard — active task in status bar"
    check_optional timew timewarrior "focus dashboard — elapsed timer in status bar"
    check_optional gh gh "PR count widget in status bar"
    check_optional tmuxinator tmuxinator "declarative project layouts (prefix+O)"

    # exa/eza for sessionx
    if has eza; then
        ok "eza $(dim "$(command -v eza)")"
    elif has exa; then
        ok "exa $(dim "$(command -v exa)")"
    else
        check_optional eza eza "sessionx directory preview"
    fi

    check_optional zoxide zoxide "sessionx smart directory jump"
    check_pipx brotab bt "browser tab switcher (prefix+b)"

    echo
    ok "dependency check complete"
}

# ── Uninstall ─────────────────────────────────────────────────────────
uninstall() {
    step "uninstall"

    if [[ -L "$TMUX_DIR" ]]; then
        rm "$TMUX_DIR"
        ok "removed symlink $TMUX_DIR"
    elif [[ -d "$TMUX_DIR" ]]; then
        wrn "$TMUX_DIR is a directory, not a symlink — not touching it"
    else
        wrn "nothing to remove at $TMUX_DIR"
    fi

    # Restore most recent backup if available
    local latest_backup
    latest_backup=$(ls -td "$TMUX_DIR".bak.* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        ask "restore backup from ${B}$latest_backup${R}? [y/N]"
        if prompt_yn; then
            mv "$latest_backup" "$TMUX_DIR"
            ok "restored $latest_backup"
        fi
    fi

    echo
    ok "uninstalled"
    exit 0
}

# ── Link Config ───────────────────────────────────────────────────────
link_config() {
    step "config"

    # Handle existing config
    if [[ -e "$TMUX_DIR" ]] && [[ ! -L "$TMUX_DIR" ]]; then
        local backup="$TMUX_DIR.bak.$(date +%Y%m%d%H%M%S)"
        wrn "existing config at $TMUX_DIR"
        inf "backing up to $(dim "$backup")"
        mv "$TMUX_DIR" "$backup"
        ok "backup created"
    elif [[ -L "$TMUX_DIR" ]]; then
        local target
        target=$(readlink -f "$TMUX_DIR")
        if [[ "$target" == "$REPO_DIR" ]]; then
            ok "already linked"
            chmod +x "$REPO_DIR"/scripts/*.sh 2>/dev/null || true
            return 0
        else
            wrn "symlink points to $(dim "$target")"
            ask "replace? [y/N]"
            prompt_yn || { err "aborted"; exit 1; }
            rm "$TMUX_DIR"
        fi
    fi

    if [[ ! -e "$TMUX_DIR" ]]; then
        mkdir -p "$(dirname "$TMUX_DIR")"
        ln -s "$REPO_DIR" "$TMUX_DIR"
        ok "linked $(dim "$REPO_DIR") -> $(dim "$TMUX_DIR")"
    fi

    chmod +x "$REPO_DIR"/scripts/*.sh 2>/dev/null || true
    ok "scripts marked executable"
}

# ── TPM + Plugins ─────────────────────────────────────────────────────
install_tpm() {
    step "plugins"

    if [[ -d "$TPM_DIR" ]]; then
        ok "TPM already installed"
    else
        inf "cloning TPM..."
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" 2>/dev/null
        ok "TPM cloned"
    fi

    if tmux info &>/dev/null 2>&1; then
        inf "installing plugins..."
        if "$TPM_DIR/bin/install_plugins" 2>/dev/null; then
            ok "all plugins installed"
        else
            wrn "some plugins may need manual install — press ${B}prefix+I${R} inside tmux"
        fi
    else
        wrn "tmux not running"
        printf "     ${D}start tmux and press prefix+I to install plugins${R}\n"
    fi
}

# ── Reload ────────────────────────────────────────────────────────────
reload_tmux() {
    if tmux info &>/dev/null 2>&1; then
        step "reload"
        if tmux source-file "$TMUX_DIR/tmux.conf" 2>/dev/null; then
            ok "tmux reloaded"
        else
            wrn "reload failed — press ${B}prefix+R${R} manually"
        fi
    fi
}

# ── Summary ───────────────────────────────────────────────────────────
summary() {
    printf "\n"
    printf "${D}    ┌─────────────────────────────────────────┐${R}\n"
    printf "${D}    │${R}  ${GRN}${B}done.${R}                                    ${D}│${R}\n"
    printf "${D}    │${R}                                           ${D}│${R}\n"
    printf "${D}    │${R}  prefix: ${B}Ctrl-Space${R}                      ${D}│${R}\n"
    printf "${D}    │${R}  reload: ${B}prefix+R${R}                        ${D}│${R}\n"
    printf "${D}    │${R}  plugins: ${B}prefix+I${R} ${D}(install/update)${R}     ${D}│${R}\n"
    printf "${D}    │${R}  help: ${B}prefix+?${R} ${D}(command palette)${R}       ${D}│${R}\n"
    printf "${D}    │${R}                                           ${D}│${R}\n"
    printf "${D}    │${R}  ${D}see README.md for the full keybinding${R}   ${D}│${R}\n"
    printf "${D}    │${R}  ${D}table and kitty Super key mappings${R}      ${D}│${R}\n"
    printf "${D}    └─────────────────────────────────────────┘${R}\n"
    printf "\n"
}

# ── Clone (if needed) ─────────────────────────────────────────────────
clone_repo() {
    step "clone"

    if [[ -d "$REPO_DIR/.git" ]]; then
        ok "repo already at $(dim "$REPO_DIR")"
        return 0
    fi

    if ! has git; then
        err "git is required to clone the repo"
        printf "     ${D}install git and try again${R}\n"
        exit 1
    fi

    inf "cloning into $(dim "$REPO_DIR")..."
    git clone "$REPO_URL" "$REPO_DIR" 2>/dev/null
    ok "cloned"
}

# ── Main ──────────────────────────────────────────────────────────────
banner

[[ "$UNINSTALL" == true ]] && uninstall

if [[ "$DEPS_ONLY" == true ]]; then
    install_deps
    exit 0
fi

[[ "$NO_DEPS" != true ]] && install_deps
clone_repo
link_config
install_tpm
reload_tmux
summary

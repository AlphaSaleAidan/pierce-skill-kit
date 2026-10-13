#!/usr/bin/env bash
# Pierce Skill Kit one-line setup for Ubuntu / Debian:
#   curl -fsSL https://raw.githubusercontent.com/AlphaSaleAidan/pierce-skill-kit/main/get.sh | bash
#   ... | bash -s -- --dry-run     show the plan, change nothing
#   ... | bash -s -- --yes         no questions (sane defaults)
#   ... | bash -s -- --vps         also harden a fresh server (asks per step)
# It shows every step before doing it, prints every sudo command it runs, and is safe to run again.
set -euo pipefail
REPO=${PSK_REPO:-https://github.com/AlphaSaleAidan/pierce-skill-kit}
DIR=${PSK_DIR:-$HOME/pierce-skill-kit}
DRY=0; YES=0; VPS=0
for a in "$@"; do case $a in --dry-run) DRY=1;; --yes|-y) YES=1;; --vps) VPS=1;; -h|--help) sed -n 2,7p "$0" 2>/dev/null || true; exit 0;;
  *) echo "unknown option: $a" >&2; exit 2;; esac; done

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
TTY=/dev/tty; [ -r "$TTY" ] || TTY=''
ask() { # ask "question": yes in --yes mode; reads the terminal even when piped from curl
  [ "$YES" = 1 ] && return 0
  [ -n "$TTY" ] || { warn "no terminal to ask '$1': re-run with --yes, or download get.sh and run it"; return 1; }
  printf '%s [y/N] ' "$1" > "$TTY"; read -r r < "$TTY"; [ "$r" = y ] || [ "$r" = Y ]; }
SUDO=''; [ "$(id -u)" = 0 ] || SUDO=sudo
run()  { echo "  + $*"; [ "$DRY" = 1 ] || "$@"; }                 # run a normal command
srun() { echo "  + ${SUDO:+sudo }$*"; [ "$DRY" = 1 ] || $SUDO "$@"; }   # run with sudo, always shown first
have() { command -v "$1" >/dev/null 2>&1; }

command -v apt-get >/dev/null || { warn "this script supports Ubuntu/Debian (apt). Elsewhere: install tmux, git, Node 18+ and Claude Code, then run ./install.sh"; exit 1; }
[ -z "$SUDO" ] || have sudo || { warn "not root and no sudo: run as root or install sudo"; exit 1; }

# ---------- 1. the plan ----------
pkgs=''
for p in tmux git curl jq; do have "$p" || pkgs="$pkgs $p"; done
have flock || pkgs="$pkgs util-linux"
node_ok=0; have node && [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge 18 ] && node_ok=1
[ "$node_ok" = 1 ] || pkgs="$pkgs nodejs npm"
have gh || pkgs="$pkgs gh"
need_claude=0; have claude || [ -x "$HOME/.local/bin/claude" ] || need_claude=1

say "Plan"
[ -n "$pkgs" ] && echo "  - install packages:$pkgs (apt, with sudo)" || echo "  - packages: all present"
[ "$need_claude" = 1 ] && echo "  - install Claude Code (official installer: https://claude.ai/install.sh)" || echo "  - Claude Code: present"
[ -d "$DIR/.git" ] && echo "  - update the kit in $DIR (git pull --ff-only)" || echo "  - clone the kit into $DIR"
echo "  - run install.sh $( [ "$YES" = 1 ] && echo '--defaults' || echo '(asks per step)')"
[ "$VPS" = 1 ] && echo "  - harden this server (updates, auto security updates, firewall, fail2ban, swap if small, key-only ssh): asks per step"
[ "$DRY" = 1 ] && { say "Dry run: nothing changed."; exit 0; }
ask "Go ahead?" || { echo "Stopped. Nothing changed."; exit 1; }

# ---------- 2. dependencies ----------
if [ -n "$pkgs" ]; then
  say "Installing packages"
  srun env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  # gh is optional (PRs in the projects hub); don't fail the whole run if a distro lacks it
  # shellcheck disable=SC2086
  srun env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ${pkgs/ gh/}
  case $pkgs in *gh*) srun env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh || warn "gh not available here; skip it or see https://cli.github.com";; esac
fi
if [ "$need_claude" = 1 ]; then
  say "Installing Claude Code"
  run bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || { warn "official installer failed, trying npm"; srun npm install -g @anthropic-ai/claude-code; }
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH"
  grep -qs 'local/bin' "$HOME/.profile" || { echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"; echo "  + added ~/.local/bin to PATH in ~/.profile"; };; esac

# ---------- 3. the kit ----------
if [ -d "$DIR/.git" ] && [ "${PSK_NO_PULL:-0}" = 1 ]; then say "Using the kit in $DIR as is"
elif [ -d "$DIR/.git" ] && ! git -C "$DIR" symbolic-ref -q HEAD >/dev/null; then say "The kit in $DIR is not on a branch; using it as is (git -C $DIR checkout main to update)"
elif [ -d "$DIR/.git" ]; then say "Updating the kit"; run git -C "$DIR" pull -q --ff-only
else say "Cloning the kit"; run git clone -q "$REPO" "$DIR"; fi
say "Running install.sh"
if [ "$YES" = 1 ]; then run bash "$DIR/install.sh" --defaults
elif [ -n "$TTY" ]; then bash "$DIR/install.sh" < "$TTY"
else run bash "$DIR/install.sh" --defaults; fi

# ---------- 4. optional: harden the server ----------
if [ "$VPS" = 1 ]; then
  say "Server hardening (each step asks first)"
  if ask "Install OS updates now?"; then srun env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq; fi
  if ask "Turn on automatic security updates (unattended-upgrades)?"; then
    srun env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
    srun sh -c 'printf "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\n" > /etc/apt/apt.conf.d/20auto-upgrades'
  fi
  mem_mb=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  if [ "$mem_mb" -lt 4000 ] && [ -z "$(swapon --show 2>/dev/null)" ] && ask "Only ${mem_mb} MB RAM and no swap: add a 2 GB swap file?"; then
    srun fallocate -l 2G /swapfile; srun chmod 600 /swapfile; srun mkswap /swapfile; srun swapon /swapfile
    srun sh -c 'grep -q "^/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab'
  fi
  ssh_port=$($SUDO sshd -T 2>/dev/null | awk '/^port /{print $2; exit}'); ssh_port=${ssh_port:-22}
  if ask "Firewall (ufw): allow ssh on port $ssh_port, block other incoming traffic?"; then
    srun env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
    srun ufw allow "$ssh_port/tcp"; srun ufw --force enable
  fi
  if ask "Install fail2ban (bans IPs that keep failing ssh logins)?"; then
    srun env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban
  fi
  # Key-only ssh: only when THIS ssh session logged in with a key, so you can't lock yourself out.
  client=${SSH_CONNECTION%% *}
  key_ok=0
  if [ -n "$client" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
    { $SUDO journalctl -u ssh -u sshd --since '-12h' --no-pager 2>/dev/null; $SUDO cat /var/log/auth.log 2>/dev/null; } \
      | grep -q "Accepted publickey for $(id -un) from $client" && key_ok=1
  fi
  if [ "$key_ok" = 1 ]; then
    if ask "This session logged in with an ssh key. Turn off password logins (key-only ssh)?"; then
      srun sh -c 'printf "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n" > /etc/ssh/sshd_config.d/99-pierce-skill-kit.conf'
      if srun sshd -t; then srun systemctl reload ssh 2>/dev/null || srun systemctl reload sshd; else
        srun rm -f /etc/ssh/sshd_config.d/99-pierce-skill-kit.conf; warn "sshd config check failed; change reverted"; fi
    fi
  else
    warn "Not turning off password logins: this run couldn't confirm you logged in with an ssh key."
    warn "Set up a key (docs/windows.md or 'ssh-copy-id'), log in with it, then run get.sh --vps again."
  fi
fi

# ---------- 5. next steps ----------
say "Done. Next:"
echo "  1. claude            # sign in once (opens a login link)"
echo "  2. lead              # start the lead session"
echo "  3. lead doctor       # check everything is set up"
echo "  Connecting from Windows: $REPO/blob/main/docs/windows.md · from a Mac: $REPO/blob/main/docs/macos.md"

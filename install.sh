#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GLOBALS
# ============================================================
USER_NAME="${SUDO_USER:-$USER}"
SUDO_FILE="/etc/sudoers.d/99_${USER_NAME}"
DOTFILES_REPO="https://github.com/z1rov/dotfiles"

BANNER="
            Made by: z1rov
          OSCP | OSCP+ | CRTO
Repo: https://github.com/z1rov/dotfiles
"

# ============================================================
# COLORS / LOG
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

log() {
  local level="$1"; shift
  case "$level" in
    ok)    echo -e "${GREEN}[OK]${RESET}    $*" ;;
    info)  echo -e "${CYAN}[INFO]${RESET}  $*" ;;
    warn)  echo -e "${YELLOW}[WARN]${RESET}  $*" ;;
    error) echo -e "${RED}[ERROR]${RESET} $*" ;;
  esac
}

# ============================================================
# UI
# ============================================================
banner() {
  clear
  echo -e "$BANNER\n"
}

step() {
  banner
  echo -e "➜ $1\n"
}

# ============================================================
# CHECKS
# ============================================================
[[ $EUID -eq 0 ]] && {
  echo "[!] Do not run as root"
  exit 1
}

# ============================================================
# SINGLE CONFIRM
# ============================================================
banner
read -rp "Continue installation? (Y/n): " ans
ans=${ans,,}
[[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && exit 0

# ============================================================
# SUDO (ONCE)
# ============================================================
step "Caching sudo credentials"
sudo -v

run_sudo() {
  sudo "$@"
}

# ============================================================
# SUDO NOPASSWD
# ============================================================
setup_sudo() {
  step "Configuring sudo NOPASSWD"

  run_sudo sh -c "echo '$USER_NAME ALL=(ALL) NOPASSWD: ALL' > '$SUDO_FILE'"
  run_sudo chmod 440 "$SUDO_FILE"

  run_sudo visudo -cf "$SUDO_FILE" || {
    run_sudo rm -f "$SUDO_FILE"
    log error "Invalid sudoers file, reverted"
    exit 1
  }
  log ok "sudo NOPASSWD configured"
}

# ============================================================
# PACKAGE INSTALL
# ============================================================
install_pacman() {
  for pkg in "$@"; do
    log info "Installing $pkg..."
    if pacman -Qi "$pkg" &>/dev/null; then
      log ok "$pkg already installed — skipping"
    elif run_sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
      log ok "$pkg installed"
    else
      log error "Failed to install $pkg"
    fi
  done
}

install_yay() {
  command -v yay &>/dev/null || {
    log warn "yay not found, skipping AUR packages"
    return
  }

  for pkg in "$@"; do
    log info "Installing AUR $pkg..."
    if yay -Qi "$pkg" &>/dev/null; then
      log ok "$pkg already installed — skipping"
    elif yay -S --needed --noconfirm "$pkg" &>/dev/null; then
      log ok "$pkg installed"
    else
      log error "Failed to install AUR $pkg"
    fi
  done
}

# ============================================================
# YAY
# ============================================================
setup_yay() {
  if command -v yay &>/dev/null; then
    step "yay already installed — skipping"
    log ok "yay present"
    return
  fi

  step "Installing yay"
  run_sudo pacman -S --needed --noconfirm git base-devel

  tmpdir="$(mktemp -d)"
  log info "Cloning yay AUR repo..."
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  cd "$tmpdir/yay"
  makepkg -si --noconfirm
  cd /
  rm -rf "$tmpdir"
  log ok "yay installed"
}

# ============================================================
# DOCKER
# ============================================================
setup_docker() {
  step "Docker"

  if command -v docker &>/dev/null; then
    log ok "docker already installed — skipping"
  else
    log info "Installing docker..."
    if run_sudo pacman -S --needed --noconfirm docker docker-compose &>/dev/null; then
      log ok "docker installed"
    else
      log error "Failed to install docker"
      return
    fi
  fi

  run_sudo systemctl enable --now docker
  log ok "docker service enabled"

  if ! getent group docker | grep -q "\b${USER_NAME}\b"; then
    run_sudo usermod -aG docker "$USER_NAME"
    log ok "$USER_NAME added to docker group"
  else
    log ok "$USER_NAME already in docker group — skipping"
  fi
}

# ============================================================
# EXEGOL + HTB-OPERATOR
# ============================================================
setup_exegol() {
  step "Exegol + htb-operator"

  # pipx dependency
  if ! command -v pipx &>/dev/null; then
    log info "Installing python-pipx..."
    run_sudo pacman -S --needed --noconfirm python-pipx &>/dev/null || {
      log error "Failed to install python-pipx"
      return
    }
    pipx ensurepath &>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
  fi

  # exegol wrapper
  if pipx list 2>/dev/null | grep -q "exegol"; then
    log ok "exegol wrapper already installed — skipping"
  else
    log info "Installing exegol wrapper via pipx..."
    if pipx install exegol &>/dev/null; then
      log ok "exegol wrapper installed"
    else
      log error "Failed to install exegol wrapper"
      return
    fi
  fi

  # htb-operator
  if pipx list 2>/dev/null | grep -q "htb-operator"; then
    log ok "htb-operator already installed — skipping"
  else
    log info "Installing htb-operator..."
    if pipx install htb-operator &>/dev/null; then
      log ok "htb-operator installed"
    else
      log error "Failed to install htb-operator"
    fi
  fi

  # pull image
  banner
  read -rp "Pull Exegol image now? This can be large (full ~25GB / light ~8GB). (Y/n): " ans
  ans=${ans,,}
  if [[ -z "$ans" || "$ans" == "y" || "$ans" == "yes" ]]; then
    echo -e "\nChoose Exegol image:\n  1) full   — all tools (~25 GB)\n  2) light  — common tools (~8 GB)\n  3) ad     — Active Directory focused\n  4) web    — Web pentesting focused\n  5) skip   — pull later manually"
    read -rp "Select [2]: " img_choice
    case "${img_choice:-2}" in
      1) EXEGOL_IMAGE="full" ;;
      3) EXEGOL_IMAGE="ad" ;;
      4) EXEGOL_IMAGE="web" ;;
      5) log info "Skipping image pull — run 'exegol install' later"; return ;;
      *) EXEGOL_IMAGE="light" ;;
    esac

    log info "Pulling exegol/$EXEGOL_IMAGE — this will take a while..."
    if exegol install "$EXEGOL_IMAGE"; then
      log ok "exegol/$EXEGOL_IMAGE ready"
    else
      log error "Failed to pull exegol/$EXEGOL_IMAGE"
      log warn "Run manually: exegol install $EXEGOL_IMAGE"
    fi
  else
    log info "Skipping image pull — run 'exegol install <image>' later"
  fi

  # aliases
  SHELL_RC="$HOME/.zshrc"
  [[ ! -f "$SHELL_RC" ]] && touch "$SHELL_RC"

  if ! grep -q "alias exegol=" "$SHELL_RC" 2>/dev/null; then
    {
      echo ""
      echo "# ── exegol ──"
      echo "alias exegol='sudo -E \$(which exegol)'"
    } >> "$SHELL_RC"
    log ok "exegol alias written to $SHELL_RC"
  else
    log ok "exegol alias already present — skipping"
  fi

  log ok "Exegol + htb-operator setup complete"
  log warn "Log out and back in (or 'newgrp docker') for docker group to take effect"
}

# ============================================================
# SERVICES
# ============================================================
setup_services() {
  step "Services"
  run_sudo systemctl enable NetworkManager lxdm
  run_sudo systemctl start NetworkManager
  echo "exec bspwm" > ~/.xinitrc
  run_sudo chsh -s /bin/zsh "$USER_NAME"
  log ok "Services configured"
}

# ============================================================
# ZSH
# ============================================================
setup_zsh() {
  step "ZSH"
  if [[ -d ~/.oh-my-zsh ]]; then
    log ok "oh-my-zsh already installed — skipping"
  else
    log info "Installing oh-my-zsh..."
    RUNZSH=no sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    log ok "oh-my-zsh installed"
  fi

  ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

  log info "Cloning zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || log ok "zsh-autosuggestions already present"

  log info "Cloning zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || log ok "zsh-syntax-highlighting already present"

  log ok "ZSH configured"
}

# ============================================================
# DOTFILES
# ============================================================
setup_dotfiles() {
  step "Dotfiles"

  DOTDIR="$HOME/dotfiles"

  if [[ -d "$DOTDIR/.git" ]]; then
    log info "Dotfiles already cloned — pulling updates"
    git -C "$DOTDIR" pull
  else
    log info "Cloning dotfiles..."
    git clone "$DOTFILES_REPO" "$DOTDIR"
  fi

  mkdir -p "$HOME/.config"

  [[ -d "$DOTDIR/config" ]] && {
    cp -r "$DOTDIR/config/"* "$HOME/.config/"
    log ok "config/ deployed to ~/.config/"
  }

  [[ -f "$DOTDIR/home/.zshrc" ]] && {
    cp "$DOTDIR/home/.zshrc" "$HOME/"
    log ok ".zshrc deployed"
  }
  [[ -d "$DOTDIR/home/.mozilla" ]] && {
    cp -r "$DOTDIR/home/.mozilla" "$HOME/"
    log ok ".mozilla deployed"
  }
  [[ -d "$DOTDIR/home/.local" ]] && {
    cp -r "$DOTDIR/home/.local" "$HOME/"
    log ok ".local deployed"
  }

  if [[ -d "$DOTDIR/bin" ]]; then
    log info "Deploying bin/ to /usr/bin/..."
    while IFS= read -r -d '' binfile; do
      bname=$(basename "$binfile")
      [[ "$bname" == .* || "$bname" == README* || "$bname" == LICENSE* ]] && continue
      [[ ! -f "$binfile" ]] && continue
      if run_sudo cp "$binfile" "/usr/bin/$bname" && run_sudo chmod +x "/usr/bin/$bname"; then
        log ok "$bname → /usr/bin/$bname"
      else
        log error "Failed to deploy $bname"
      fi
    done < <(find "$DOTDIR/bin" -maxdepth 1 -type f -print0)
  fi

  [[ -f "$HOME/.config/bspwm/bspwmrc" ]] && chmod +x "$HOME/.config/bspwm/bspwmrc"
  [[ -d "$HOME/.config/bspwm/scripts" ]] && find "$HOME/.config/bspwm/scripts" -type f -exec chmod 755 {} \;

  mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/CTF"
  log ok "Dotfiles deployed"
}

# ============================================================
# ROOT SYNC
# ============================================================
setup_root() {
  step "Root sync"
  run_sudo chsh -s /bin/zsh root
  run_sudo cp -r ~/.oh-my-zsh /root/
  run_sudo cp ~/.zshrc /root/
  run_sudo cp -r ~/.config /root/
  log ok "Root synced"
}

# ============================================================
# SSH
# ============================================================
setup_ssh() {
  banner
  read -rp "Generate SSH keys? (Y/n): " ans
  ans=${ans,,}
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && return

  step "SSH key setup"

  DEFAULT_USER="$USER_NAME"

  echo -e "Choose SSH key mode:\n  1) Default — no passphrase\n  2) Secure  — with passphrase (recommended)"
  read -rp "Select option [1]: " mode
  [[ "$mode" != "2" ]] && mode=1

  read -rp "SSH key label [${DEFAULT_USER}]: " SSH_USER
  SSH_USER="${SSH_USER:-$DEFAULT_USER}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  PASSPHRASE_RSA=""
  PASSPHRASE_ED25519=""

  if [[ "$mode" == "2" ]]; then
    while true; do
      echo "RSA passphrase:"
      read -s -p "Passphrase: " p1; echo
      read -s -p "Confirm: " p2; echo
      [[ "$p1" == "$p2" ]] && PASSPHRASE_RSA="$p1" && break
      log warn "Passphrases do not match"
    done

    read -s -p "ED25519 passphrase (ENTER = reuse RSA): " q1; echo
    if [[ -z "$q1" ]]; then
      PASSPHRASE_ED25519="$PASSPHRASE_RSA"
    else
      while true; do
        read -s -p "Confirm ED25519: " q2; echo
        [[ "$q1" == "$q2" ]] && PASSPHRASE_ED25519="$q1" && break
        log warn "Passphrases do not match"
      done
    fi
  fi

  generate_key() {
    local path="$1" type="$2" bits="$3" pass="$4"

    if [[ -f "$path" ]]; then
      read -rp "[!] $path exists — overwrite? (y/N): " ow
      [[ "${ow,,}" != "y" ]] && return
      cp "$path" "$path.bak" 2>/dev/null || true
      cp "$path.pub" "$path.pub.bak" 2>/dev/null || true
      rm -f "$path" "$path.pub"
    fi

    log info "Generating $type key..."
    if [[ "$type" == "rsa" ]]; then
      ssh-keygen -t rsa -b "$bits" -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    else
      ssh-keygen -t ed25519 -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    fi

    chmod 600 "$path"
    chmod 644 "$path.pub"
    log ok "$type key generated"
  }

  generate_key "$HOME/.ssh/id_rsa"     "rsa"     4096 "$PASSPHRASE_RSA"
  generate_key "$HOME/.ssh/id_ed25519" "ed25519" ""   "$PASSPHRASE_ED25519"

  banner
  [[ -f ~/.ssh/id_rsa.pub ]] && {
    echo "--- id_rsa.pub ---"
    cat ~/.ssh/id_rsa.pub
    echo
  }
  [[ -f ~/.ssh/id_ed25519.pub ]] && {
    echo "--- id_ed25519.pub ---"
    cat ~/.ssh/id_ed25519.pub
    echo
  }

  read -rp "Press ENTER to continue..."
}

# ============================================================
# VMWARE DETECTION
# ============================================================
setup_vmware() {
  if ! systemd-detect-virt --quiet --vm 2>/dev/null | grep -q vmware && \
     ! grep -qi "vmware" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    return
  fi

  step "VMware guest detected"
  log info "Installing open-vm-tools and gtkmm3..."

  if run_sudo pacman -S --needed --noconfirm open-vm-tools gtkmm3 &>/dev/null; then
    log ok "open-vm-tools + gtkmm3 installed"
  else
    log error "Failed to install open-vm-tools"
    return
  fi

  run_sudo systemctl enable vmtoolsd.service
  run_sudo systemctl start  vmtoolsd.service
  log ok "vmtoolsd enabled"

  run_sudo systemctl enable vmware-vmblock-fuse.service
  run_sudo systemctl start  vmware-vmblock-fuse.service
  log ok "vmware-vmblock-fuse enabled"

  BSPWMRC="$HOME/.config/bspwm/bspwmrc"
  if [[ -f "$BSPWMRC" ]]; then
    if ! grep -q "vmware-user" "$BSPWMRC"; then
      echo "" >> "$BSPWMRC"
      echo "# VMware clipboard & drag-drop" >> "$BSPWMRC"
      echo "pgrep vmware-user || vmware-user &" >> "$BSPWMRC"
      log ok "vmware-user added to bspwmrc"
    else
      log ok "vmware-user already in bspwmrc — skipping"
    fi
  else
    log warn "bspwmrc not found — will need to add 'pgrep vmware-user || vmware-user &' manually"
  fi
}

# ============================================================
# PACKAGES
# ============================================================
PACMAN_PKGS=(
  xorg xorg-xinit bspwm sxhkd picom feh lxdm
  kitty zsh tmux neovim rofi thunar gvfs ttf-jetbrains-mono
  bat eza xclip brightnessctl pamixer firefox
  pipewire pipewire-pulse wireplumber papirus-icon-theme
  dunst flameshot gnome-themes-extra
  linux linux-firmware mesa opencl-mesa xf86-video-amdgpu polybar nodejs npm
)

YAY_PKGS=( i3lock-color ttf-hack-nerd ttf-firacode-nerd )

# ============================================================
# MAIN
# ============================================================
setup_sudo
setup_yay
install_pacman "${PACMAN_PKGS[@]}"
install_yay "${YAY_PKGS[@]}"
setup_docker
setup_exegol
setup_services
setup_zsh
setup_dotfiles
setup_vmware
setup_root
setup_ssh

run_sudo dracut --regenerate-all --force

banner
log ok "OÑO"

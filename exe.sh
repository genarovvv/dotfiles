#!/usr/bin/env bash
# =============================================================================
#  exegol-install.sh — Instalador de Exegol para Arch/Debian/Fedora
#  Descarga por defecto: ad-3.1.6 + web-3.1.6 (sin licencia, docker pull directo)
# =============================================================================
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

log() { local l="$1"; shift
  case "$l" in
    ok)    echo -e "${GREEN}[OK]${RESET}    $*" ;;
    info)  echo -e "${CYAN}[INFO]${RESET}  $*" ;;
    warn)  echo -e "${YELLOW}[WARN]${RESET}  $*" ;;
    error) echo -e "${RED}[ERROR]${RESET} $*" ;;
    head)  echo -e "\n${BOLD}${CYAN}══════ $* ══════${RESET}" ;;
  esac
}

USER_NAME="${SUDO_USER:-$USER}"
SHELL_RC="$HOME/.zshrc"
[[ "$(basename "${SHELL:-bash}")" == "bash" ]] && SHELL_RC="$HOME/.bashrc"

# ── Detectar distro ───────────────────────────────────────────────────────────
detect_pkg_manager() {
  if   command -v pacman  &>/dev/null; then PKG_MGR="pacman"
  elif command -v apt-get &>/dev/null; then PKG_MGR="apt"
  elif command -v dnf     &>/dev/null; then PKG_MGR="dnf"
  else log error "Gestor de paquetes no soportado (pacman/apt/dnf)"; exit 1; fi
  log info "Distro: ${PKG_MGR} | Shell RC: ${SHELL_RC}"
}

# ── Docker ────────────────────────────────────────────────────────────────────
install_docker() {
  log head "Docker"
  if command -v docker &>/dev/null; then
    log ok "$(docker --version)"; return
  fi
  case "$PKG_MGR" in
    pacman) sudo pacman -S --needed --noconfirm docker ;;
    *)      curl -fsSL "https://get.docker.com/" | sh ;;
  esac
  sudo systemctl enable --now docker
  log ok "Docker instalado"
}

# ── Deps ──────────────────────────────────────────────────────────────────────
install_deps() {
  log head "Dependencias"
  case "$PKG_MGR" in
    pacman) sudo pacman -S --needed --noconfirm git python-pipx ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y git python3 pipx ;;
    dnf)    sudo dnf install -y git python3 pipx ;;
  esac
  pipx ensurepath
  export PATH="$HOME/.local/bin:$PATH"
  log ok "git + pipx OK"
}

# ── Wrapper ───────────────────────────────────────────────────────────────────
install_exegol_tool() {
  log head "Exegol wrapper"
  command -v exegol &>/dev/null || pipx install exegol
  export PATH="$HOME/.local/bin:$PATH"
  command -v exegol &>/dev/null && log ok "exegol: $(which exegol)" \
    || { log error "exegol no en PATH"; exit 1; }
}

# ── Alias sudo ────────────────────────────────────────────────────────────────
setup_alias() {
  log head "Alias"
  local alias_line="alias exegol='sudo -E $(echo ~/.local/bin/exegol)'"
  grep -q "alias exegol=" "${SHELL_RC}" 2>/dev/null \
    && log ok "Alias ya existe" \
    || { echo "${alias_line}" >> "${SHELL_RC}"; log ok "Alias añadido a ${SHELL_RC}"; }
}

# ── Imágenes: ad + web directo ────────────────────────────────────────────────
pull_images() {
  log head "Descargando imagen (full-3.1.6)"
  log warn "Esto tarda — ~20 GB"

  local failed=()
  for tag in "full-3.1.6"; do
    log info "→ nwodtuhs/exegol:${tag}"
    sudo docker pull "nwodtuhs/exegol:${tag}" \
      && log ok "${tag} OK" \
      || { log error "${tag} falló"; failed+=("$tag"); }
  done

  [[ ${#failed[@]} -gt 0 ]] \
    && log warn "Falló: ${failed[*]} — reintenta con: sudo docker pull nwodtuhs/exegol:<tag>"
}

# ── Verify ────────────────────────────────────────────────────────────────────
verify() {
  log head "Verificación"
  sudo docker info &>/dev/null && log ok "Docker daemon OK" || log error "Docker no responde"
  command -v exegol &>/dev/null && log ok "exegol en PATH" || log warn "Reinicia la terminal para aplicar PATH"
  echo ""
  sudo docker images | grep -E "REPOSITORY|exegol" || echo "  (sin imágenes)"
  echo ""
  log info "Primer contenedor:  sudo -E exegol start"
  log info "Menú de gestión:    ./exegol-manager.sh"
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
 _____                       _
| ____|_  _____  __ _  ___ | |
|  _| \ \/ / _ \/ _` |/ _ \| |
| |___ >  <  __/ (_| | (_) | |
|_____/_/\_\___|\__, |\___/|_|
                |___/  installer
BANNER
echo -e "${RESET}"

detect_pkg_manager
install_docker
install_deps
install_exegol_tool
setup_alias
pull_images
verify

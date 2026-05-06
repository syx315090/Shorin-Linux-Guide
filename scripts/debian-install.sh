#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

COPY_DOTFILES=1
COPY_WALLPAPERS=1
ENABLE_BACKPORTS=1
ENABLE_NONFREE=0
DRY_RUN=0
ASSUME_YES=0
TARGET_USER="${SUDO_USER:-${USER:-}}"
DISPLAY_MANAGER_SERVICE=""

log() {
  printf '\033[1;34m[shorin-debian]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[warning]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/debian-install.sh [options]

Options:
  --target-user USER   User that receives dotfiles and user-level settings
  --no-backports       Do not add Debian backports; not recommended for Niri
  --with-nonfree       Add contrib, non-free and non-free-firmware components when creating backports
  --no-dotfiles        Install packages only
  --no-wallpapers      Do not copy wallpapers; useful with sparse clone
  --dry-run            Print actions without changing the system
  -y, --yes            Non-interactive apt mode
  -h, --help           Show this help

Examples:
  bash scripts/debian-install.sh -y
  bash scripts/debian-install.sh --with-nonfree --no-wallpapers -y
  bash scripts/debian-install.sh --target-user shorin --with-nonfree -y
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --target-user)
        [[ $# -ge 2 ]] || die "--target-user requires a value"
        TARGET_USER="$2"
        shift 2
        ;;
      --with-backports)
        # Kept for old documentation and scripts. Backports are enabled by default.
        ENABLE_BACKPORTS=1
        shift
        ;;
      --no-backports)
        ENABLE_BACKPORTS=0
        shift
        ;;
      --with-nonfree)
        ENABLE_NONFREE=1
        shift
        ;;
      --no-dotfiles)
        COPY_DOTFILES=0
        shift
        ;;
      --no-wallpapers)
        COPY_WALLPAPERS=0
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

sudo_run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run "$@"
  else
    run sudo "$@"
  fi
}

require_debian() {
  [[ -r /etc/debian_version ]] || die "This installer is for Debian and Debian-based systems."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "This installer is for Debian. Detected: ${PRETTY_NAME:-unknown system}."
  command -v apt-get >/dev/null 2>&1 || die "apt-get was not found."
  if [[ "$(id -u)" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo was not found. Run this script as root or install sudo first."
  fi
}

target_home() {
  getent passwd "$TARGET_USER" | cut -d: -f6
}

apt_update() {
  sudo_run apt-get update
}

apt_has_package() {
  apt-cache show "$1" >/dev/null 2>&1
}

apt_install() {
  local requested=("$@")
  local available=()
  local missing=()
  local pkg

  for pkg in "${requested[@]}"; do
    if apt_has_package "$pkg"; then
      available+=("$pkg")
    else
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Skipped unavailable Debian packages: ${missing[*]}"
  fi

  [[ ${#available[@]} -gt 0 ]] || return 0

  local args=(apt-get install)
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    args+=(-y)
  fi
  sudo_run "${args[@]}" "${available[@]}"
}

apt_install_from_backports() {
  local suite="$1"
  shift

  if [[ "$ENABLE_BACKPORTS" -eq 1 ]]; then
    local args=(apt-get -t "$suite-backports" install)
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      args+=(-y)
    fi

    local available=()
    local missing=()
    local pkg
    for pkg in "$@"; do
      if apt_has_package "$pkg"; then
        available+=("$pkg")
      else
        missing+=("$pkg")
      fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
      warn "Skipped unavailable Debian packages: ${missing[*]}"
    fi

    [[ ${#available[@]} -gt 0 ]] || return 0
    sudo_run "${args[@]}" "${available[@]}"
  else
    apt_install "$@"
  fi
}

apt_install_required_from_backports() {
  local suite="$1"
  shift

  local missing=()
  local pkg
  for pkg in "$@"; do
    if ! apt_has_package "$pkg"; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Required Debian packages are unavailable: ${missing[*]}. Use Debian 13/trixie or newer with backports enabled."
  fi

  if [[ "$ENABLE_BACKPORTS" -eq 1 ]]; then
    local args=(apt-get -t "$suite-backports" install)
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      args+=(-y)
    fi
    sudo_run "${args[@]}" "$@"
  else
    apt_install "$@"
  fi
}

enable_backports() {
  [[ "$ENABLE_BACKPORTS" -eq 1 ]] || return 0

  # shellcheck disable=SC1091
  . /etc/os-release
  local suite="${VERSION_CODENAME:-}"
  [[ -n "$suite" ]] || die "Could not determine Debian codename from /etc/os-release."

  local components="main"
  if [[ "$ENABLE_NONFREE" -eq 1 ]]; then
    components="main contrib non-free non-free-firmware"
  fi

  local list="/etc/apt/sources.list.d/${suite}-backports.list"
  local entry="deb http://deb.debian.org/debian ${suite}-backports ${components}"

  if [[ -r "$list" ]] && grep -Fxq "$entry" "$list"; then
    log "Backports already configured: ${suite}-backports"
    return 0
  fi

  log "Adding Debian backports: ${suite}-backports"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] write %s: %s\n' "$list" "$entry"
  elif [[ "$(id -u)" -eq 0 ]]; then
    printf '%s\n' "$entry" >"$list"
  else
    printf '%s\n' "$entry" | sudo tee "$list" >/dev/null
  fi
}

install_base_packages() {
  log "Installing base desktop packages"
  apt_install \
    sudo curl wget git ca-certificates gnupg lsb-release locales \
    dbus-user-session xdg-user-dirs xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk \
    pipewire wireplumber pipewire-pulse pipewire-alsa alsa-utils rtkit \
    network-manager network-manager-gnome bluetooth bluez blueman cups flatpak \
    fonts-noto-core fonts-noto-cjk fonts-noto-cjk-extra fonts-noto-color-emoji fonts-liberation fonts-jetbrains-mono \
    fonts-font-awesome fonts-wqy-zenhei fonts-adobe-sourcesans3 fonts-adobe-sourcecodepro \
    vim neovim nano fish starship fzf zoxide jq ripgrep eza btop fastfetch yazi \
    firefox-esr thunar pavucontrol brightnessctl playerctl wl-clipboard grim slurp swappy satty \
    mako-notifier fuzzel waybar swaylock wlogout copyq kitty foot ghostty \
    fcitx5 fcitx5-chinese-addons fcitx5-rime fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
    fcitx5-frontend-qt5 kde-config-fcitx5 qt5ct qt6ct im-config
}

install_niri_packages() {
  log "Installing Niri desktop packages"
  # shellcheck disable=SC1091
  . /etc/os-release
  local suite="${VERSION_CODENAME:-stable}"
  apt_install_required_from_backports "$suite" niri
  apt_install_from_backports "$suite" xwayland-satellite swaybg swayidle

  if [[ "$DRY_RUN" -ne 1 ]] && ! command -v niri >/dev/null 2>&1; then
    die "Niri package installation finished, but the niri command was not found."
  fi
}

is_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

current_display_manager_service() {
  if [[ -r /etc/X11/default-display-manager ]]; then
    local configured
    configured="$(basename "$(cat /etc/X11/default-display-manager)" | sed 's/\.service$//')"
    if [[ -n "$configured" ]] && is_package_installed "$configured"; then
      printf '%s\n' "$configured"
      return 0
    fi
    warn "Ignoring stale display manager setting: ${configured:-unknown}"
  fi

  local candidate
  for candidate in gdm3 sddm lightdm; do
    if is_package_installed "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

install_display_manager() {
  DISPLAY_MANAGER_SERVICE="$(current_display_manager_service || true)"

  if [[ -n "$DISPLAY_MANAGER_SERVICE" ]]; then
    log "Keeping existing display manager: $DISPLAY_MANAGER_SERVICE"
    return 0
  fi

  log "Installing SDDM display manager"
  if [[ "$DRY_RUN" -ne 1 ]]; then
    printf 'sddm shared/default-x-display-manager select sddm\n' | sudo_run debconf-set-selections || true
  fi
  apt_install sddm
  DISPLAY_MANAGER_SERVICE="sddm"
}

configure_services() {
  log "Enabling system services"
  if command -v systemctl >/dev/null 2>&1; then
    sudo_run systemctl enable NetworkManager || warn "Could not enable NetworkManager."
    sudo_run systemctl enable bluetooth || warn "Could not enable bluetooth."
    sudo_run systemctl enable cups || warn "Could not enable cups."
    if [[ -n "$DISPLAY_MANAGER_SERVICE" ]]; then
      sudo_run systemctl enable "$DISPLAY_MANAGER_SERVICE" || warn "Could not enable $DISPLAY_MANAGER_SERVICE."
    else
      warn "No display manager service was selected."
    fi
  else
    warn "systemctl was not found; services were not enabled automatically."
  fi
}

install_niri_session_file() {
  local session_file="/usr/share/wayland-sessions/niri.desktop"
  local portals_file="/usr/share/xdg-desktop-portal/niri-portals.conf"
  local exec_line=""

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] write %s\n' "$session_file"
    printf '[dry-run] write %s\n' "$portals_file"
    return 0
  fi

  sudo_run mkdir -p /usr/share/wayland-sessions
  sudo_run mkdir -p /usr/share/xdg-desktop-portal

  if command -v niri-session >/dev/null 2>&1; then
    exec_line="niri-session"
  elif command -v niri >/dev/null 2>&1; then
    exec_line="dbus-run-session niri --session"
  else
    die "Cannot create Niri session file because neither niri-session nor niri was found."
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    cat >"$session_file" <<EOF
[Desktop Entry]
Name=Niri
Comment=A scrollable-tiling Wayland compositor
Exec=$exec_line
Type=Application
DesktopNames=niri
EOF
    cat >"$portals_file" <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.Access=gtk
org.freedesktop.impl.portal.Notification=gtk
EOF
  else
    sudo tee "$session_file" >/dev/null <<EOF
[Desktop Entry]
Name=Niri
Comment=A scrollable-tiling Wayland compositor
Exec=$exec_line
Type=Application
DesktopNames=niri
EOF
    sudo tee "$portals_file" >/dev/null <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.Access=gtk
org.freedesktop.impl.portal.Notification=gtk
EOF
  fi
}

configure_locale_and_input() {
  log "Configuring zh_CN.UTF-8 locale and Fcitx5 environment"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] enable zh_CN.UTF-8 and en_US.UTF-8 in /etc/locale.gen\n'
  else
    sudo_run sed -i \
      -e 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' \
      -e 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
      /etc/locale.gen
  fi
  sudo_run locale-gen
  sudo_run update-locale LANG=zh_CN.UTF-8 LC_MESSAGES=zh_CN.UTF-8

  local profile_script="/etc/profile.d/shorin-fcitx5.sh"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] write %s\n' "$profile_script"
  elif [[ "$(id -u)" -eq 0 ]]; then
    cat >"$profile_script" <<'EOF'
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus
EOF
  else
    sudo tee "$profile_script" >/dev/null <<'EOF'
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus
EOF
  fi
}

configure_flatpak() {
  command -v flatpak >/dev/null 2>&1 || return 0
  log "Configuring Flathub remote"
  sudo_run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || warn "Could not add Flathub remote."
}

backup_path() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  local backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
  warn "Backing up existing path: $path -> $backup"
  run mv "$path" "$backup"
}

copy_tree() {
  local src="$1"
  local dst="$2"
  [[ -d "$src" ]] || return 0
  backup_path "$dst"
  run mkdir -p "$dst"
  run cp -a "$src"/. "$dst"/
}

write_file() {
  local dst="$1"
  shift
  run mkdir -p "$(dirname -- "$dst")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] write %s\n' "$dst"
    return 0
  fi
  cat >"$dst" "$@"
}

install_niri_config() {
  local home="$1"
  local cfg="$home/.config/niri"
  run mkdir -p "$cfg"

  [[ -f "$cfg/config.kdl" ]] && backup_path "$cfg/config.kdl"

  write_file "$cfg/config.kdl" <<'EOF'
input {
    keyboard {
        xkb {
            layout "us"
        }
    }
    touchpad {
        tap
        natural-scroll
    }
}

prefer-no-csd

spawn-sh-at-startup "waybar -c ~/.config/waybar/config-niri -s ~/.config/waybar/style.css"
spawn-at-startup "mako"
spawn-at-startup "fcitx5"
spawn-at-startup "wl-paste" "--watch" "cliphist" "store"

layout {
    gaps 8
    center-focused-column "never"
    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
        proportion 1.0
    }
    default-column-width { proportion 0.5; }
    focus-ring {
        width 2
        active-color "#89b4fa"
        inactive-color "#45475a"
    }
    border {
        off
    }
}

binds {
    Mod+T { spawn "kitty" "-e" "fish"; }
    Mod+B { spawn "firefox"; }
    Mod+E { spawn "thunar"; }
    Mod+Z { spawn "fuzzel"; }
    Mod+Q { close-window; }
    Mod+Shift+E { quit; }
    Mod+Shift+S { spawn-sh "grim -g \"$(slurp)\" - | if command -v satty >/dev/null 2>&1; then satty -f -; else swappy -f -; fi"; }
    Mod+Alt+A { spawn-sh "grim -g \"$(slurp)\" - | wl-copy"; }
    Mod+Alt+L { spawn "swaylock"; }

    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }
    Mod+Left { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Down { focus-window-down; }
    Mod+Up { focus-window-up; }

    Mod+Ctrl+H { move-column-left; }
    Mod+Ctrl+L { move-column-right; }
    Mod+Ctrl+J { move-window-down; }
    Mod+Ctrl+K { move-window-up; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }
    Mod+Ctrl+1 { move-column-to-workspace 1; }
    Mod+Ctrl+2 { move-column-to-workspace 2; }
    Mod+Ctrl+3 { move-column-to-workspace 3; }
    Mod+Ctrl+4 { move-column-to-workspace 4; }
    Mod+Ctrl+5 { move-column-to-workspace 5; }
    Mod+Ctrl+6 { move-column-to-workspace 6; }
    Mod+Ctrl+7 { move-column-to-workspace 7; }
    Mod+Ctrl+8 { move-column-to-workspace 8; }
    Mod+Ctrl+9 { move-column-to-workspace 9; }

    Mod+F { maximize-column; }
    Mod+Alt+F { fullscreen-window; }
    Mod+V { toggle-window-floating; }
    Mod+R { switch-preset-column-width; }
    Mod+O { spawn "pkill" "-SIGUSR1" "waybar"; }
}
EOF
}

install_waybar_config() {
  local home="$1"
  local cfg="$home/.config/waybar"
  run mkdir -p "$cfg"

  [[ -f "$cfg/config" ]] && backup_path "$cfg/config"
  [[ -f "$cfg/config-niri" ]] && backup_path "$cfg/config-niri"
  [[ -f "$cfg/style.css" ]] && backup_path "$cfg/style.css"

  write_file "$cfg/config-niri" <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 34,
  "spacing": 8,
  "modules-left": ["custom/launcher", "niri/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["tray", "pulseaudio", "network", "battery"],
  "custom/launcher": {
    "format": "SHORiN",
    "on-click": "fuzzel"
  },
  "clock": {
    "format": "{:%Y-%m-%d %H:%M}"
  },
  "pulseaudio": {
    "format": "VOL {volume}%",
    "format-muted": "VOL muted"
  },
  "network": {
    "format-wifi": "NET {essid}",
    "format-ethernet": "NET wired",
    "format-disconnected": "NET off"
  },
  "battery": {
    "format": "BAT {capacity}%"
  }
}
EOF

  if [[ ! -f "$cfg/config" ]]; then
    run cp "$cfg/config-niri" "$cfg/config"
  fi

  write_file "$cfg/style.css" <<'EOF'
* {
  border: none;
  border-radius: 0;
  font-family: "JetBrains Mono", "Noto Sans CJK SC", sans-serif;
  font-size: 13px;
  min-height: 0;
}

window#waybar {
  background: rgba(24, 24, 37, 0.88);
  color: #cdd6f4;
}

#custom-launcher,
#workspaces,
#clock,
#tray,
#pulseaudio,
#network,
#battery {
  margin: 5px 4px;
  padding: 0 10px;
  border-radius: 8px;
  background: rgba(49, 50, 68, 0.85);
}

#workspaces button {
  padding: 0 8px;
  color: #cdd6f4;
}

#workspaces button.active,
#workspaces button.focused {
  color: #11111b;
  background: #89b4fa;
}
EOF
}

install_dotfiles() {
  [[ "$COPY_DOTFILES" -eq 1 ]] || return 0

  local home
  home="$(target_home)"
  [[ -n "$home" && -d "$home" ]] || die "Could not determine home directory for user: $TARGET_USER"

  log "Installing configuration files for $TARGET_USER"
  run mkdir -p "$home/.config" "$home/.local/share"

  copy_tree "$REPO_ROOT/legacy/.config/foot" "$home/.config/foot"
  copy_tree "$REPO_ROOT/legacy/.config/ghostty" "$home/.config/ghostty"
  copy_tree "$REPO_ROOT/legacy/.config/MangoHud" "$home/.config/MangoHud"
  copy_tree "$REPO_ROOT/legacy/.config/mango" "$home/.config/mango"
  copy_tree "$REPO_ROOT/legacy/.config/wlogout" "$home/.config/wlogout"
  copy_tree "$REPO_ROOT/legacy/.config/niriswitcher" "$home/.config/niriswitcher"
  copy_tree "$REPO_ROOT/legacy/.local/share/fcitx5" "$home/.local/share/fcitx5"
  if [[ "$COPY_WALLPAPERS" -eq 1 ]]; then
    run mkdir -p "$home/Pictures/Shorin-Wallpapers"
    copy_tree "$REPO_ROOT/wallpapers" "$home/Pictures/Shorin-Wallpapers"
  fi

  copy_tree "$REPO_ROOT/legacy/.config/niri" "$home/.config/niri"
  install_niri_config "$home"
  install_waybar_config "$home"

  if [[ -f "$REPO_ROOT/legacy/.zshrc" ]]; then
    backup_path "$home/.zshrc"
    run cp "$REPO_ROOT/legacy/.zshrc" "$home/.zshrc"
  fi

  run find "$home/.config" "$home/.local" -type f -name '*.sh' -exec chmod +x {} +

  if [[ "$(id -un)" == "root" ]]; then
    run chown -R "$TARGET_USER:$TARGET_USER" "$home/.config" "$home/.local"
    [[ -d "$home/Pictures/Shorin-Wallpapers" ]] && run chown -R "$TARGET_USER:$TARGET_USER" "$home/Pictures/Shorin-Wallpapers"
    [[ -f "$home/.zshrc" ]] && run chown "$TARGET_USER:$TARGET_USER" "$home/.zshrc"
  fi
}

main() {
  parse_args "$@"
  require_debian

  log "Desktop: Niri"
  log "Target user: $TARGET_USER"

  enable_backports
  apt_update

  install_base_packages
  install_niri_packages
  install_display_manager
  install_niri_session_file

  configure_locale_and_input
  configure_flatpak
  configure_services
  install_dotfiles

  log "Done. Reboot or log out, then choose Niri in the display manager."
}

main "$@"

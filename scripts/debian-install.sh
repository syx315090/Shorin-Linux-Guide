#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

PROFILES=()
COPY_DOTFILES=1
COPY_WALLPAPERS=1
ENABLE_BACKPORTS=0
ENABLE_NONFREE=0
DRY_RUN=0
ASSUME_YES=0
TARGET_USER="${SUDO_USER:-${USER:-}}"

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
  --profile LIST       Comma separated profiles: base,gnome,plasma,hyprland,niri,all
                       Default: base,gnome
  --target-user USER   User that receives dotfiles and user-level settings
  --with-backports     Add Debian backports and prefer it for Hyprland/Niri packages
  --with-nonfree       Add contrib, non-free and non-free-firmware components when creating backports
  --no-dotfiles        Install packages only
  --no-wallpapers      Do not copy wallpapers; useful with sparse clone
  --dry-run            Print actions without changing the system
  -y, --yes            Non-interactive apt mode
  -h, --help           Show this help

Examples:
  bash scripts/debian-install.sh --profile base,gnome
  bash scripts/debian-install.sh --profile hyprland,niri --with-backports
  bash scripts/debian-install.sh --profile all --with-backports --with-nonfree -y
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --profile)
        [[ $# -ge 2 ]] || die "--profile requires a value"
        IFS=',' read -r -a PROFILES <<<"$2"
        shift 2
        ;;
      --target-user)
        [[ $# -ge 2 ]] || die "--target-user requires a value"
        TARGET_USER="$2"
        shift 2
        ;;
      --with-backports)
        ENABLE_BACKPORTS=1
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

  if [[ ${#PROFILES[@]} -eq 0 ]]; then
    PROFILES=(base gnome)
  fi
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

normalize_profiles() {
  local expanded=()
  local profile

  for profile in "${PROFILES[@]}"; do
    case "$profile" in
      all)
        expanded+=(base gnome plasma hyprland niri)
        ;;
      base|gnome|plasma|hyprland|niri)
        expanded+=("$profile")
        ;;
      "")
        ;;
      *)
        die "Unsupported profile: $profile"
        ;;
    esac
  done

  PROFILES=()
  local seen=" "
  for profile in "${expanded[@]}"; do
    if [[ "$seen" != *" $profile "* ]]; then
      PROFILES+=("$profile")
      seen+="$profile "
    fi
  done

  if [[ "$seen" != *" base "* ]]; then
    PROFILES=(base "${PROFILES[@]}")
  fi
}

has_profile() {
  local needle="$1"
  local profile
  for profile in "${PROFILES[@]}"; do
    [[ "$profile" == "$needle" ]] && return 0
  done
  return 1
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

install_gnome_packages() {
  log "Installing GNOME profile"
  apt_install gnome-core gdm3 gnome-tweaks gnome-shell-extensions gnome-software-plugin-flatpak
}

install_plasma_packages() {
  log "Installing Plasma profile"
  apt_install kde-plasma-desktop plasma-pa plasma-nm sddm dolphin konsole systemsettings kde-config-gtk-style
}

install_hyprland_packages() {
  log "Installing Hyprland profile"
  # Hyprland availability depends on Debian release and backports state.
  # Missing packages are skipped with a warning, so the same script can run on bookworm, trixie and sid.
  # shellcheck disable=SC1091
  . /etc/os-release
  local suite="${VERSION_CODENAME:-stable}"
  apt_install_from_backports "$suite" \
    hyprland xdg-desktop-portal-hyprland hypridle hyprlock hyprpaper hyprland-guiutils \
    swww swaybg cliphist wev waypaper
}

install_niri_packages() {
  log "Installing Niri profile"
  # shellcheck disable=SC1091
  . /etc/os-release
  local suite="${VERSION_CODENAME:-stable}"
  apt_install_from_backports "$suite" niri xwayland-satellite swaybg swayidle
}

configure_services() {
  log "Enabling system services"
  if command -v systemctl >/dev/null 2>&1; then
    sudo_run systemctl enable NetworkManager || warn "Could not enable NetworkManager."
    sudo_run systemctl enable bluetooth || warn "Could not enable bluetooth."
    sudo_run systemctl enable cups || warn "Could not enable cups."

    if has_profile gnome; then
      sudo_run systemctl enable gdm3 || warn "Could not enable gdm3."
    elif has_profile plasma; then
      sudo_run systemctl enable sddm || warn "Could not enable sddm."
    fi
  else
    warn "systemctl was not found; services were not enabled automatically."
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

install_hyprland_config() {
  local home="$1"
  local cfg="$home/.config/hypr"
  run mkdir -p "$cfg"

  if [[ -f "$cfg/hyprland.conf" ]]; then
    run mv "$cfg/hyprland.conf" "$cfg/hyprland.legacy.conf"
  fi

  write_file "$cfg/hyprland.conf" <<'EOF'
monitor=,preferred,auto,1

$terminal = kitty -e fish
$fileManager = thunar
$menu = fuzzel
$browser = firefox
$mainMod = SUPER

exec-once = waybar -c ~/.config/waybar/config-hyprland -s ~/.config/waybar/style.css
exec-once = mako
exec-once = fcitx5
exec-once = copyq
exec-once = wl-paste --watch cliphist store
exec-once = swww-daemon

env = LC_MESSAGES,zh_CN.UTF-8
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt6ct

general {
    gaps_in = 6
    gaps_out = 8
    border_size = 2
    col.active_border = rgba(89b4faff) rgba(f5c2e7ff) 45deg
    col.inactive_border = rgba(45475aff)
    layout = dwindle
}

decoration {
    rounding = 10
    active_opacity = 0.98
    inactive_opacity = 0.98
    shadow {
        enabled = true
        range = 4
        render_power = 3
        color = rgba(11111bee)
    }
    blur {
        enabled = true
        size = 5
        passes = 2
        vibrancy = 0.16
    }
}

animations {
    enabled = true
    bezier = easeOutQuint, 0.23, 1, 0.32, 1
    animation = windows, 1, 4.8, easeOutQuint
    animation = windowsOut, 1, 1.5, default
    animation = fade, 1, 3, default
    animation = workspaces, 1, 2, default, slidevert
}

dwindle {
    pseudotile = true
    preserve_split = true
}

misc {
    force_default_wallpaper = 0
    disable_hyprland_logo = true
}

input {
    kb_layout = us
    follow_mouse = 1
    accel_profile = flat
    touchpad {
        natural_scroll = false
    }
}

bind = $mainMod, T, exec, $terminal
bind = $mainMod, Q, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating,
bind = $mainMod, Z, exec, $menu
bind = $mainMod, B, exec, $browser
bind = $mainMod ALT, F, fullscreen
bind = $mainMod, F, fullscreen, 1
bind = $mainMod, O, exec, pkill -SIGUSR1 waybar
bind = $mainMod, F2, exec, pkill waybar || true && waybar
bind = $mainMod ALT, L, exec, swaylock
bind = $mainMod SHIFT, S, exec, grim -g "$(slurp)" - | sh -c 'if command -v satty >/dev/null 2>&1; then satty -f -; else swappy -f -; fi'
bind = $mainMod ALT, A, exec, grim -g "$(slurp)" - | wl-copy

bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d
bind = $mainMod, H, movefocus, l
bind = $mainMod, L, movefocus, r
bind = $mainMod, J, movefocus, d
bind = $mainMod, K, movefocus, u
bind = $mainMod CTRL, H, movewindow, l
bind = $mainMod CTRL, L, movewindow, r
bind = $mainMod CTRL, J, movewindow, d
bind = $mainMod CTRL, K, movewindow, u

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod CTRL, 1, movetoworkspace, 1
bind = $mainMod CTRL, 2, movetoworkspace, 2
bind = $mainMod CTRL, 3, movetoworkspace, 3
bind = $mainMod CTRL, 4, movetoworkspace, 4
bind = $mainMod CTRL, 5, movetoworkspace, 5
bind = $mainMod CTRL, 6, movetoworkspace, 6
bind = $mainMod CTRL, 7, movetoworkspace, 7
bind = $mainMod CTRL, 8, movetoworkspace, 8
bind = $mainMod CTRL, 9, movetoworkspace, 9

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindel = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+
bindel = ,XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioPause, exec, playerctl play-pause
bindl = , XF86AudioPrev, exec, playerctl previous

windowrule = suppressevent maximize, class:.*
windowrule = float, class:com.github.hluk.copyq
windowrule = float, title:Select what to share
layerrule = blur, notifications
EOF
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
  [[ -f "$cfg/config-hyprland" ]] && backup_path "$cfg/config-hyprland"
  [[ -f "$cfg/config-niri" ]] && backup_path "$cfg/config-niri"
  [[ -f "$cfg/style.css" ]] && backup_path "$cfg/style.css"

  if has_profile hyprland; then
    write_file "$cfg/config-hyprland" <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 34,
  "spacing": 8,
  "modules-left": ["custom/launcher", "hyprland/workspaces"],
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
  fi

  if has_profile niri; then
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
  fi

  if [[ ! -f "$cfg/config" ]]; then
    if has_profile hyprland; then
      run cp "$cfg/config-hyprland" "$cfg/config"
    elif has_profile niri; then
      run cp "$cfg/config-niri" "$cfg/config"
    fi
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
  run mkdir -p "$home/.config" "$home/.local/share" "$home/Pictures/Shorin-Wallpapers"

  copy_tree "$REPO_ROOT/legacy/.config/foot" "$home/.config/foot"
  copy_tree "$REPO_ROOT/legacy/.config/ghostty" "$home/.config/ghostty"
  copy_tree "$REPO_ROOT/legacy/.config/MangoHud" "$home/.config/MangoHud"
  copy_tree "$REPO_ROOT/legacy/.config/mango" "$home/.config/mango"
  copy_tree "$REPO_ROOT/legacy/.config/wlogout" "$home/.config/wlogout"
  copy_tree "$REPO_ROOT/legacy/.config/niriswitcher" "$home/.config/niriswitcher"
  copy_tree "$REPO_ROOT/legacy/.local/share/fcitx5" "$home/.local/share/fcitx5"
  if [[ "$COPY_WALLPAPERS" -eq 1 ]]; then
    copy_tree "$REPO_ROOT/wallpapers" "$home/Pictures/Shorin-Wallpapers"
  fi

  if has_profile hyprland; then
    copy_tree "$REPO_ROOT/legacy/.config/hypr" "$home/.config/hypr"
    install_hyprland_config "$home"
  fi

  if has_profile niri; then
    copy_tree "$REPO_ROOT/legacy/.config/niri" "$home/.config/niri"
    install_niri_config "$home"
  fi

  if has_profile hyprland || has_profile niri; then
    install_waybar_config "$home"
  fi

  if [[ -f "$REPO_ROOT/legacy/.zshrc" ]]; then
    backup_path "$home/.zshrc"
    run cp "$REPO_ROOT/legacy/.zshrc" "$home/.zshrc"
  fi

  run find "$home/.config" "$home/.local" -type f -name '*.sh' -exec chmod +x {} +

  if [[ "$(id -un)" == "root" ]]; then
    run chown -R "$TARGET_USER:$TARGET_USER" "$home/.config" "$home/.local" "$home/Pictures/Shorin-Wallpapers"
    [[ -f "$home/.zshrc" ]] && run chown "$TARGET_USER:$TARGET_USER" "$home/.zshrc"
  fi
}

main() {
  parse_args "$@"
  require_debian
  normalize_profiles

  log "Profiles: ${PROFILES[*]}"
  log "Target user: $TARGET_USER"

  enable_backports
  apt_update

  has_profile base && install_base_packages
  has_profile gnome && install_gnome_packages
  has_profile plasma && install_plasma_packages
  has_profile hyprland && install_hyprland_packages
  has_profile niri && install_niri_packages

  configure_locale_and_input
  configure_flatpak
  configure_services
  install_dotfiles

  log "Done. Reboot or log out, then choose GNOME, Plasma, Hyprland or Niri in the display manager."
}

main "$@"

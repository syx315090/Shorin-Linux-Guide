# Debian 适配说明

本项目原本围绕 Arch Linux/AUR 工作流整理桌面环境配置。Debian 适配脚本位于：

```bash
scripts/debian-install.sh
```

从刚安装完成的 Debian 命令行系统开始，请优先阅读：[Debian 从零自动安装桌面环境教程](debian-auto-install-tutorial.md)。

脚本目标是在 Debian 上安装与项目相同方向的桌面体验：GNOME、Plasma、Hyprland、Niri、Waybar、Fcitx5/Rime、PipeWire、Flatpak、常用终端/文件管理器/截图/通知组件，并复用仓库里的 `legacy/.config` 与 `wallpapers` 资源。

## 快速使用

GNOME 日用桌面：

```bash
bash scripts/debian-install.sh --profile base,gnome -y
```

Plasma 日用桌面：

```bash
bash scripts/debian-install.sh --profile base,plasma -y
```

Hyprland/Niri Wayland 桌面：

```bash
bash scripts/debian-install.sh --profile hyprland,niri --with-backports -y
```

完整安装：

```bash
bash scripts/debian-install.sh --profile all --with-backports --with-nonfree -y
```

## 适配策略

- Debian 默认使用 `apt` 和官方软件源，不安装 AUR 工具。
- Debian 源中没有的 Arch/AUR 包会被自动跳过，并在终端输出 warning。
- Debian 包名和 Arch 不完全一致，例如通知服务使用 `mako-notifier`；截图标注优先用 `satty`，不可用时回退到 `swappy`。
- `--with-backports` 会为当前 Debian 代号添加 backports 源，适合安装 Hyprland/Niri 这类更新较快的 Wayland 组件。
- `--with-nonfree` 只影响脚本创建 backports 源时的组件列表，会加入 `contrib non-free non-free-firmware`。
- 脚本会配置 `zh_CN.UTF-8`、Fcitx5 环境变量、Flathub、NetworkManager、Bluetooth、CUPS。
- 用户配置默认安装给执行 sudo 的用户；需要指定时使用 `--target-user 用户名`。
- 可以用普通用户配合 sudo 运行，也可以直接用 root 运行；root 运行时建议显式传入 `--target-user 用户名`。

## 配置文件处理

仓库当前没有 `.gitignore` 中提到的完整 `dotfiles/` 目录，因此 Debian 脚本主要复用：

- `legacy/.config/foot`
- `legacy/.config/ghostty`
- `legacy/.config/hypr`
- `legacy/.config/niri`
- `legacy/.config/wlogout`
- `legacy/.config/niriswitcher`
- `legacy/.config/MangoHud`
- `legacy/.local/share/fcitx5`
- `wallpapers`

Hyprland 的旧配置依赖 Arch/AUR 中更常见的插件和工具。脚本复制旧配置后，会把旧 `hyprland.conf` 保存为 `hyprland.legacy.conf`，再写入一份 Debian 可启动的 `hyprland.conf`。

Niri 目录当前只有脚本资源，没有完整 `config.kdl`。脚本会生成一份基础 `config.kdl`，保留项目的键位风格和 Waybar/Fcitx5/Mako 自启动。

Waybar 会分别生成 `~/.config/waybar/config-hyprland` 和 `~/.config/waybar/config-niri`，避免两个合成器的 workspace 模块互相报错。

## 注意事项

- Debian 12/bookworm 的 Hyprland/Niri 包可用性有限，建议使用 Debian 13/trixie 或更新版本。
- Hyprland/Niri 更新很快，Debian stable 的版本可能落后于 Arch。
- 如果你已经有自己的 `~/.config` 配置，脚本会先备份为 `.bak.时间戳`。
- 脚本不会立即切换显示管理器，只会 enable 服务；安装后建议重启，在登录界面选择桌面会话。

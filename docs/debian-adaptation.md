# Debian Niri 适配说明

本项目的 Debian 脚本现在只做一件事：在刚安装好的 Debian 上自动安装 Niri 桌面环境和配套桌面组件。

脚本位置：

```bash
scripts/debian-install.sh
```

从刚安装完成的 Debian 命令行系统开始，请优先阅读：[Debian 从零自动安装 Niri 桌面教程](debian-auto-install-tutorial.md)。

## 快速使用

推荐使用 sparse clone，只拉脚本和配置，不下载图片和壁纸：

```bash
git clone --filter=blob:none --sparse https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
git sparse-checkout set scripts docs legacy README.md LICENSE .gitignore
bash scripts/debian-install.sh --with-nonfree --no-wallpapers -y
```

如果已经完整下载仓库：

```bash
bash scripts/debian-install.sh --with-nonfree -y
```

root 运行时指定目标用户：

```bash
bash scripts/debian-install.sh --target-user 你的用户名 --with-nonfree -y
```

## 脚本安装内容

- Niri
- SDDM 登录管理器
- Waybar
- Fcitx5/Rime
- PipeWire / WirePlumber
- Flatpak / Flathub
- NetworkManager、蓝牙、打印
- 终端、文件管理器、截图、通知、剪贴板等常用 Wayland 组件
- 仓库中的 `legacy/.config`、`legacy/.local/share/fcitx5`
- 可选复制 `wallpapers`

## 适配策略

- 默认启用 Debian backports，因为 Niri 这类 Wayland 组件更新较快。
- `--no-backports` 可以关闭 backports，但不推荐。
- `--with-nonfree` 会在创建 backports 源时加入 `contrib non-free non-free-firmware`。
- `--no-wallpapers` 会跳过壁纸复制，适合 sparse clone。
- Debian 源中没有的包会被跳过并输出 warning，脚本会尽量继续完成可安装部分。
- 脚本只接受 `ID=debian` 的系统，Ubuntu、Linux Mint、Kali 等不会运行。

## 配置文件处理

仓库当前没有 `.gitignore` 中提到的完整 `dotfiles/` 目录，因此 Debian 脚本主要复用：

- `legacy/.config/foot`
- `legacy/.config/ghostty`
- `legacy/.config/niri`
- `legacy/.config/wlogout`
- `legacy/.config/niriswitcher`
- `legacy/.config/MangoHud`
- `legacy/.local/share/fcitx5`
- `wallpapers`

脚本会生成一份基础 `~/.config/niri/config.kdl`，保留项目的键位风格和 Waybar/Fcitx5/Mako 自启动。

Waybar 会生成 `~/.config/waybar/config-niri` 和 `~/.config/waybar/style.css`。

已有配置会先备份为：

```text
原路径.bak.时间戳
```

## 注意事项

- 建议使用 Debian 13/trixie 或更新版本。
- Debian 12/bookworm 的 Niri 包可用性有限。
- 安装完成后重启，在 SDDM 登录界面选择 Niri 会话。

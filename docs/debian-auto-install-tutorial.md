# Debian 从零自动安装桌面环境教程

本文面向刚安装完成的 Debian 系统：没有桌面环境，只有命令行，可以登录 root 或普通用户。

截至 2026-05-06，Debian 当前 stable 是 Debian 13，代号 `trixie`。本脚本优先按 Debian 13 适配；Debian 12/bookworm 可以安装 GNOME/Plasma 等稳定组件，但 Hyprland/Niri 包可用性会明显差一些。

## 目标效果

运行脚本后，可以安装这些桌面环境和组件：

- GNOME
- KDE Plasma
- Hyprland
- Niri
- Waybar、Fcitx5/Rime、PipeWire、Flatpak
- 终端、文件管理器、截图、通知、剪贴板、蓝牙、打印等常用桌面组件
- 本仓库里的旧配置和壁纸资源

## 1. 确认系统版本

登录 Debian 后运行：

```bash
cat /etc/os-release
```

建议看到类似内容：

```text
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
VERSION_CODENAME=trixie
ID=debian
```

如果 `ID` 不是 `debian`，脚本会拒绝运行。Ubuntu、Linux Mint、Kali 等系统不要使用这个 Debian 脚本。

## 2. 准备网络

最简单的情况是有线网络已经可用。先测试：

```bash
ping -c 3 deb.debian.org
```

如果能收到回复，继续下一步。

如果网络不可用，优先回到 Debian 安装器确认已经配置网络。刚装完、没有桌面时，Wi-Fi 配置会比较麻烦；建议第一次安装时临时使用有线网络或手机 USB 共享网络。

## 3. 安装获取项目所需的最小工具

如果你现在是 root，直接运行：

```bash
apt update
apt install -y git ca-certificates bash sudo
```

如果你现在是普通用户，并且已经能用 sudo：

```bash
sudo apt update
sudo apt install -y git ca-certificates bash
```

如果普通用户不能用 sudo，切换到 root 后把用户加入 sudo 组：

```bash
su -
apt update
apt install -y sudo git ca-certificates bash
usermod -aG sudo 你的用户名
reboot
```

重启后再用普通用户登录。

## 4. 下载项目

### 推荐：只下载脚本和配置

国内直连 GitHub 慢时，不建议完整 clone。仓库里的图片和壁纸文件比较多，Debian 新装系统只需要脚本、文档和 `legacy` 配置目录即可。

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone --filter=blob:none --sparse https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
git sparse-checkout set scripts docs legacy README.md LICENSE .gitignore
```

这种方式不会下载 `pictures` 和 `wallpapers`，速度会快很多。运行脚本时加上 `--no-wallpapers`：

```bash
bash scripts/debian-install.sh --profile all --with-backports --with-nonfree --no-wallpapers -y
```

### 完整下载

如果网络正常，或者你需要项目里的图片和壁纸资源，可以完整 clone。

进入一个你习惯放源码的位置，例如：

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
```

如果你使用的是自己的 fork，把上面的 Git 地址换成你的仓库地址。

### 更快的离线办法

如果你有另一台网络更好的电脑，可以提前下载好项目压缩包或 clone 好仓库，然后用 U 盘复制到 Debian：

```bash
cd /path/to/Shorin-Linux-Guide
bash scripts/debian-install.sh --profile all --with-backports --with-nonfree -y
```

如果你维护了 Gitee、GitCode 或内网镜像，也可以把上面的 GitHub 地址换成镜像地址。脚本不依赖 GitHub，只要求目录里有 `scripts/debian-install.sh`、`legacy`，以及可选的 `wallpapers`。

## 5. 选择安装方案

推荐完整安装，适合“刚装完 Debian，想一次装好全部桌面选择”的场景：

```bash
bash scripts/debian-install.sh --profile all --with-backports --with-nonfree -y
```

只安装 GNOME 日用桌面：

```bash
bash scripts/debian-install.sh --profile base,gnome -y
```

只安装 KDE Plasma 日用桌面：

```bash
bash scripts/debian-install.sh --profile base,plasma -y
```

只安装 Hyprland 和 Niri：

```bash
bash scripts/debian-install.sh --profile hyprland,niri --with-backports -y
```

## 6. root 运行时指定目标用户

如果你直接用 root 执行脚本，必须告诉脚本把配置文件安装给哪个普通用户：

```bash
bash scripts/debian-install.sh --profile all --with-backports --with-nonfree --target-user 你的用户名 -y
```

如果你用普通用户加 sudo 运行，脚本会自动把配置安装给当前用户，一般不需要写 `--target-user`。

## 7. 脚本会做什么

脚本会自动执行这些工作：

- 安装基础桌面包、字体、输入法、声音、蓝牙、打印、Flatpak
- 安装所选 profile 对应的 GNOME、Plasma、Hyprland、Niri
- 可选添加 Debian backports 源，用于 Hyprland/Niri 等更新较快的软件
- 配置 `zh_CN.UTF-8` locale
- 写入 Fcitx5 输入法环境变量
- 添加 Flathub
- 启用 NetworkManager、bluetooth、cups、gdm3 或 sddm
- 复制 `legacy/.config`、`legacy/.local/share/fcitx5`、可选复制 `wallpapers`
- 为 Hyprland/Niri 生成 Debian 可启动的基础配置
- 备份已有配置到 `.bak.时间戳`

## 8. 安装完成后重启

脚本结束后运行：

```bash
reboot
```

重启进入登录界面后：

- GNOME：登录界面选择 GNOME
- Plasma：登录界面选择 Plasma
- Hyprland：登录界面选择 Hyprland
- Niri：登录界面选择 Niri

GDM 通常在输入密码前或选中用户后有齿轮按钮可以选择会话。SDDM 通常在左下角或顶部有会话选择菜单。

## 9. 推荐的一次性命令

普通用户 sudo 方式：

```bash
sudo apt update
sudo apt install -y git ca-certificates bash
mkdir -p ~/Projects
cd ~/Projects
git clone --filter=blob:none --sparse https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
git sparse-checkout set scripts docs legacy README.md LICENSE .gitignore
bash scripts/debian-install.sh --profile all --with-backports --with-nonfree --no-wallpapers -y
reboot
```

root 方式：

```bash
apt update
apt install -y git ca-certificates bash sudo
mkdir -p /opt
cd /opt
git clone --filter=blob:none --sparse https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
git sparse-checkout set scripts docs legacy README.md LICENSE .gitignore
bash scripts/debian-install.sh --profile all --with-backports --with-nonfree --no-wallpapers --target-user 你的用户名 -y
reboot
```

## 常见问题

### 提示某些包 skipped unavailable

这是正常的。Debian 和 Arch 包名、收录范围不同，脚本会跳过当前 Debian 源里没有的包，尽量继续完成可安装部分。

Hyprland/Niri 如果被跳过，优先确认你使用的是 Debian 13/trixie，并且运行时加了：

```bash
--with-backports
```

### 登录后没有 Hyprland 或 Niri 选项

先确认包是否安装成功：

```bash
command -v Hyprland
command -v niri
```

如果没有输出，说明 Debian 当前源没有安装到对应包。可以先使用 GNOME/Plasma，等 backports 或系统版本提供对应包后再运行：

```bash
bash scripts/debian-install.sh --profile hyprland,niri --with-backports -y
```

### 中文输入法不能用

重启后一般会生效。如果仍不可用，打开终端检查：

```bash
echo $XMODIFIERS
fcitx5 -d
```

正常应该看到 `@im=fcitx`。GNOME/Plasma 下也可以打开 Fcitx5 配置工具添加 Rime。

### 已经有自己的配置文件

脚本不会直接覆盖删除。已有路径会被移动为：

```text
原路径.bak.时间戳
```

需要恢复时，把对应 `.bak.时间戳` 目录改回原名即可。

## 参考

- [Debian Releases](https://www.debian.org/releases/)
- [Debian 13 trixie Release Information](https://www.debian.org/releases/trixie/)
- [Debian 13 "trixie" released](https://www.debian.org/News/2025/20250809)

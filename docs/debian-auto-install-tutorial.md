# Debian 从零自动安装 Niri 桌面教程

本文面向刚安装完成的 Debian 系统：没有桌面环境，只有命令行，可以登录 root 或普通用户。

截至 2026-05-06，Debian 当前 stable 是 Debian 13，代号 `trixie`。本脚本优先按 Debian 13 适配；Debian 12/bookworm 的 Niri 包可用性会差一些。

## 目标效果

运行脚本后安装一个 Niri Wayland 桌面：

- Niri
- SDDM 登录界面
- Waybar 顶栏
- Fcitx5/Rime 中文输入法
- PipeWire 声音服务
- Flatpak / Flathub
- 终端、文件管理器、截图、通知、剪贴板、蓝牙、打印等常用组件
- 本仓库里的 Niri 配置、Fcitx5 配置和可选壁纸

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
ping -c 3 mirrors.ustc.edu.cn
```

如果能收到回复，继续下一步。

如果网络不可用，优先回到 Debian 安装器确认已经配置网络。刚装完、没有桌面时，Wi-Fi 配置会比较麻烦；建议第一次安装时临时使用有线网络或手机 USB 共享网络。

## 3. 安装最小工具

如果你现在是 root：

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

## 4. 快速下载项目

国内直连 GitHub 慢时，不建议完整 clone。仓库里的图片和壁纸文件比较多，新装 Debian 只需要脚本、文档和 `legacy` 配置目录即可。

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone --filter=blob:none --sparse https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
git sparse-checkout set scripts docs legacy README.md LICENSE .gitignore
```

这种方式不会下载 `pictures` 和 `wallpapers`，速度会快很多。运行脚本时加上 `--no-wallpapers`。

如果你需要项目里的图片和壁纸资源，可以完整 clone：

```bash
git clone https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
```

更快的离线办法：在另一台网络更好的电脑提前下载仓库，然后用 U 盘复制到 Debian。脚本不依赖 GitHub，只要求目录里有 `scripts/debian-install.sh`、`legacy`，以及可选的 `wallpapers`。

## 5. 自动安装 Niri

普通用户 sudo 方式，推荐：

```bash
bash scripts/debian-install.sh --with-nonfree --no-wallpapers -y
```

脚本默认把 Debian APT 源切换为中科大镜像：

```text
http://mirrors.ustc.edu.cn/debian
http://mirrors.ustc.edu.cn/debian-security
```

如果你想换成其他国内镜像，可以指定：

```bash
bash scripts/debian-install.sh \
  --main-mirror https://mirrors.tuna.tsinghua.edu.cn/debian \
  --security-mirror https://mirrors.tuna.tsinghua.edu.cn/debian-security \
  --with-nonfree --no-wallpapers -y
```

如果你完整下载了仓库，并且想复制壁纸：

```bash
bash scripts/debian-install.sh --with-nonfree -y
```

root 方式必须指定目标用户：

```bash
bash scripts/debian-install.sh --target-user 你的用户名 --with-nonfree --no-wallpapers -y
```

## 6. 脚本会做什么

脚本会自动执行这些工作：

- 添加 Debian backports 源
- 默认把 Debian APT 源切换到国内镜像，并备份原源文件
- Debian 官方源没有 Niri 时，添加 OBS/DankLinux 的 Niri 仓库
- 安装基础桌面包、字体、输入法、声音、蓝牙、打印、Flatpak
- 安装 Niri、SDDM、Waybar 和常用 Wayland 组件
- 配置 `zh_CN.UTF-8` locale
- 写入 Fcitx5 输入法环境变量
- 添加 Flathub
- 启用 NetworkManager、bluetooth、cups、sddm
- 复制 `legacy/.config`、`legacy/.local/share/fcitx5`、可选复制 `wallpapers`
- 生成 Debian 可启动的 `~/.config/niri/config.kdl`
- 生成 `~/.config/waybar/config-niri`
- 生成 `/usr/share/wayland-sessions/niri.desktop`
- 备份已有配置到 `.bak.时间戳`

## 7. 重启并进入 Niri

脚本结束后运行：

```bash
reboot
```

重启进入 SDDM 登录界面后，选择 Niri 会话并登录。

## 8. 推荐的一次性命令

普通用户 sudo 方式：

```bash
sudo apt update
sudo apt install -y git ca-certificates bash
mkdir -p ~/Projects
cd ~/Projects
git clone --filter=blob:none --sparse https://github.com/syx315090/Shorin-Linux-Guide.git
cd Shorin-Linux-Guide
git sparse-checkout set scripts docs legacy README.md LICENSE .gitignore
bash scripts/debian-install.sh --with-nonfree --no-wallpapers -y
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
bash scripts/debian-install.sh --target-user 你的用户名 --with-nonfree --no-wallpapers -y
reboot
```

## 常见问题

### 提示某些包 skipped unavailable

这是正常的。Debian 和 Arch 包名、收录范围不同，脚本会跳过当前 Debian 源里没有的包，尽量继续完成可安装部分。

如果 Niri 安装失败，优先确认你使用的是 Debian 13/trixie 或更新版本，并且没有使用 `--no-obs-niri`。

### 登录界面没有 Niri 选项

先确认 Niri 是否安装成功：

```bash
command -v niri
ls /usr/share/wayland-sessions/
```

如果 `command -v niri` 没有输出，说明当前软件源没有安装到 Niri。新版脚本会在 Debian 官方源没有 `niri` 时自动添加 OBS/DankLinux 仓库；请 `git pull` 后重新运行脚本。

如果有 `niri` 命令，但 `/usr/share/wayland-sessions/` 里没有 `niri.desktop`，重新运行新版脚本：

```bash
bash scripts/debian-install.sh --with-nonfree --no-wallpapers -y
```

新版脚本会自动生成 Niri 登录会话文件。

### 安装时出现 gdm 和 sddm 相关错误

这通常是系统里已经有 `gdm3`，脚本又安装 `sddm` 时触发 display manager 选择冲突。

新版脚本会优先沿用已有的 `gdm3`、`sddm` 或 `lightdm`，只有没有显示管理器时才安装 `sddm`。更新脚本后重新运行即可：

```bash
git pull
bash scripts/debian-install.sh --with-nonfree --no-wallpapers -y
```

如果你明确想使用 SDDM，可以手动切换：

```bash
sudo apt install -y sddm
sudo dpkg-reconfigure sddm
sudo systemctl enable sddm
reboot
```

### 中文输入法不能用

重启后一般会生效。如果仍不可用，打开终端检查：

```bash
echo $XMODIFIERS
fcitx5 -d
```

正常应该看到 `@im=fcitx`。可以打开 Fcitx5 配置工具添加 Rime。

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

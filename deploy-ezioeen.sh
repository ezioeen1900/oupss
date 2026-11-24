#!/usr/bin/env bash
# ==============================================================================
# Ezioeen 专属 Nothing OS / Glyph 全栈一键部署脚本
# 用法：
#   ./deploy-ezioeen.sh               完整部署（依赖包 + 个人脚本 + 配置软链 + SDDM + Plymouth 开机动画）
#   ./deploy-ezioeen.sh --with-refind 完整部署 + 额外写入 rEFInd 2560x1600 引导主题
#   ./deploy-ezioeen.sh --links-only  仅部署用户态软链、默认状态与个人脚本（免 root）
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-full}"

say() { printf '\n\033[1;31m●\033[0m \033[1m%s\033[0m\n' "$*"; }

# 1. 安装核心运行依赖（仅在 Arch / CachyOS 且非 --links-only 时执行）
install_packages() {
    command -v pacman >/dev/null || return 0
    say "检查并补齐系统依赖包..."
    local pkgs=(
        hyprland quickshell xdg-desktop-portal-hyprland
        qt5-wayland qt6-wayland qt6-multimedia-ffmpeg qt6-svg qt6-5compat
        networkmanager bluez bluez-utils blueman
        pipewire pipewire-pulse wireplumber
        brightnessctl playerctl wl-clipboard cliphist
        grim slurp swappy flameshot hyprpicker hypridle hyprsunset
        libqalculate libvips jq
        kitty fish starship fastfetch btop cava eza zoxide direnv ydotool trash-cli
        dolphin pavucontrol papirus-icon-theme adw-gtk-theme
        noto-fonts-cjk noto-fonts-emoji fcitx5 fcitx5-im fcitx5-chinese-addons
    )
    sudo pacman -S --needed --noconfirm "${pkgs[@]}" || true
}

# 2. 部署个人辅助脚本与实时歌词二进制
install_helpers() {
    say "部署个人辅助脚本 (~/.local/bin)..."
    mkdir -p "$HOME/.local/bin"
    chmod +x "$REPO_DIR/ezioeen/bin/"* 2>/dev/null || true
    for f in "$REPO_DIR/ezioeen/bin/"*; do
        [ -f "$f" ] || continue
        local base
        base="$(basename "$f")"
        [ "$base" = "lyricsmpris" ] && continue
        if [ ! -e "$HOME/.local/bin/$base" ]; then
            cp -a "$f" "$HOME/.local/bin/$base"
            echo "  + ~/.local/bin/$base"
        fi
    done
    # float-size-persist 始终保持最新定制版（排除微信 280x380 登录框）
    cp -a "$REPO_DIR/ezioeen/bin/float-size-persist" "$HOME/.local/bin/float-size-persist"
    chmod +x "$HOME/.local/bin/float-size-persist"
}

# 3. 建立软链并写入初始状态（顶栏灵动岛 + 纯黑白红 + 1.25 缩放）
install_links_and_state() {
    # 确保仓库在 ~/.local/share/glyph（若克隆在其他目录则建立软链或同步指向）
    if [ "$REPO_DIR" != "$HOME/.local/share/glyph" ] && [ ! -e "$HOME/.local/share/glyph" ]; then
        mkdir -p "$HOME/.local/share"
        ln -s "$REPO_DIR" "$HOME/.local/share/glyph"
    fi

    bash "$REPO_DIR/install.sh" --links

    say "初始化 Ezioeen 默认主题与缩放状态..."
    mkdir -p "$HOME/.local/state/rice" "$HOME/.config/demonshot" "$HOME/.local/share/fcitx5/themes" "$HOME/.config/fcitx5/conf"
    [ -f "$HOME/.local/state/rice/glyph.json" ] || cp -a "$REPO_DIR/ezioeen/defaults/glyph.json" "$HOME/.local/state/rice/glyph.json"
    [ -f "$HOME/.config/demonshot/rules.json" ] || cp -a "$REPO_DIR/ezioeen/defaults/rules.json" "$HOME/.config/demonshot/rules.json"
    [ -f "$HOME/.Xresources" ] || cp -a "$REPO_DIR/ezioeen/defaults/Xresources" "$HOME/.Xresources"
    if [ -d "$REPO_DIR/extras/fcitx5/glyph-nothing" ]; then
        rm -rf "$HOME/.local/share/fcitx5/themes/glyph-nothing"
        cp -rT "$REPO_DIR/extras/fcitx5/glyph-nothing" "$HOME/.local/share/fcitx5/themes/glyph-nothing"
        cp -a "$REPO_DIR/ezioeen/defaults/classicui.conf" "$HOME/.config/fcitx5/conf/classicui.conf"
    fi
    systemctl --user disable --now awww-daemon.service >/dev/null 2>&1 || true
}

# 4. 部署 SDDM 登录主题 & Plymouth (WELCOME EZIOEEN) 开机动画
install_system_themes() {
    say "部署 SDDM 登录界面与 Plymouth 开机动画..."
    sudo bash -c "
        set -euo pipefail
        if [ -d /usr/share/sddm/themes ]; then
            rm -rf /usr/share/sddm/themes/glyph
            cp -rT '$REPO_DIR/config/sddm/glyph' /usr/share/sddm/themes/glyph
            rm -f /usr/share/sddm/themes/glyph/fonts
            cp -rT '$REPO_DIR/config/fonts' /usr/share/sddm/themes/glyph/fonts
            chmod -R a+rX /usr/share/sddm/themes/glyph
            mkdir -p /etc/sddm.conf.d
            printf '[Theme]\nCurrent=glyph\n' > /etc/sddm.conf
            printf '[Theme]\nCurrent=glyph\n\n[General]\nInputMethod=\n' > /etc/sddm.conf.d/zz-glyph.conf
        fi
        if [ -d /usr/share/plymouth/themes ]; then
            rm -rf /usr/share/plymouth/themes/glyph
            cp -rT '$REPO_DIR/ezioeen/plymouth/glyph' /usr/share/plymouth/themes/glyph
            chmod -R a+rX /usr/share/plymouth/themes/glyph
            plymouth-set-default-theme -R glyph
        fi
    "
}

# 5. 可选：部署 rEFInd 2560x1600 引导主题
install_refind_theme() {
    say "部署 rEFInd Nothing OS 引导主题..."
    sudo bash -c "
        set -euo pipefail
        REFIND_DIR=/boot/efi/EFI/refind
        [ -d \"\$REFIND_DIR\" ] || REFIND_DIR=/boot/EFI/refind
        if [ ! -f \"\$REFIND_DIR/refind.conf\" ]; then
            echo '未找到 refind.conf，跳过引导主题部署' >&2
            exit 0
        fi
        cp -a \"\$REFIND_DIR/refind.conf\" \"\$REFIND_DIR/refind.conf.bak-\$(date +%F_%H-%M-%S)\"
        mkdir -p \"\$REFIND_DIR/themes\"
        rm -rf \"\$REFIND_DIR/themes/glyph\"
        cp -rT '$REPO_DIR/ezioeen/refind/glyph' \"\$REFIND_DIR/themes/glyph\"
        grep -q 'themes/glyph/theme.conf' \"\$REFIND_DIR/refind.conf\" || printf '\ninclude themes/glyph/theme.conf\n' >> \"\$REFIND_DIR/refind.conf\"
    "
}

case "$MODE" in
    --links-only)
        install_helpers
        install_links_and_state
        ;;
    full|"")
        install_packages
        install_helpers
        install_links_and_state
        install_system_themes
        ;;
    --with-refind)
        install_packages
        install_helpers
        install_links_and_state
        install_system_themes
        install_refind_theme
        ;;
    *)
        sed -n '3,7s/^# //p' "$0"
        exit 1
        ;;
esac

say "部署完成！若已在 Hyprland 会话内，运行: ~/.local/bin/rice restart"

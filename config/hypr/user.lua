-- 个人 Hyprland 覆盖配置（由 Glyph 的 hyprland.lua 自动加载，已在 .gitignore 中）
local HOME = os.getenv("HOME")
local vars = require("variables")

-- ==================== 显示器：原生 2560x1600@120Hz，缩放同步设置里的 1.25 ====================
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1.25,
})

-- ==================== 环境变量 ====================
-- fcitx5 输入法
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")

-- Flatpak 应用 desktop / 图标
local dataDirs = os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
hl.env("XDG_DATA_DIRS", "/var/lib/flatpak/exports/share:" .. dataDirs)

-- 鼠标光标主题
hl.env("XCURSOR_THEME", "entis_cursors_x11_others")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- 键盘与触控板：彻底禁用俄语布局和 Alt+Shift 切布局（防止拦截 Alt+Shift 快捷键），恢复右下角右键
hl.config({
    input = {
        kb_layout = "us",
        kb_options = "",
        touchpad = {
            clickfinger_behavior = false,
            tap_button_map = "lrm",
        },
    },
    -- 未聚焦窗口半透明（与之前保持一致）
    decoration = {
        active_opacity = 1.0,
        inactive_opacity = 0.85,
        dim_inactive = false,
    },
    -- 登录进桌面首帧背景设为纯黑，无缝衔接 Glyph
    misc = {
        background_color = "rgb(000000)",
    },
})

-- ==================== 个人后台守护进程 ====================
hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1 &")
    hl.exec_cmd("fcitx5 -d --disable notificationitem")
    hl.exec_cmd("$HOME/.local/bin/float-size-persist &")
    hl.exec_cmd("$HOME/.local/bin/flatpak-desktop-sync")
    hl.exec_cmd("$HOME/.local/bin/clash-proxy-watch &")
    hl.exec_cmd("/usr/bin/kdeconnectd >/dev/null 2>&1 &")
    hl.exec_cmd("hyprctl setcursor entis_cursors_x11_others 24")
end)

-- ==================== 个人习惯键位（Alt 系完整迁移）====================
local fn = require("hyprland.functions")

local function rebind(key, action, opts)
    if hl.unbind then pcall(hl.unbind, key) end
    if opts then
        hl.bind(key, action, opts)
    else
        hl.bind(key, action)
    end
end

-- 清除 Glyph 默认在 Alt+Tab / Shift+Alt+Tab 上的大写组切换绑定
if hl.unbind then
    pcall(hl.unbind, "ALT + TAB")
    pcall(hl.unbind, "SHIFT + ALT + TAB")
end

-- 启动器 / 终端 / 浏览器 / 文件管理器 / 微信
local kittyCmd = "/usr/bin/kitty --config " .. HOME .. "/.config/kitty/kitty.conf"
rebind("SUPER + Return",  hl.dsp.exec_cmd(kittyCmd))
rebind("CTRL + ALT + T",  hl.dsp.exec_cmd(kittyCmd))
rebind("ALT + Return",    hl.dsp.exec_cmd(kittyCmd))
rebind("SUPER + W",       hl.dsp.exec_cmd(HOME .. "/.local/bin/chromium-zh --ozone-platform=wayland"))
rebind("ALT + grave",     hl.dsp.exec_cmd(HOME .. "/.local/bin/chromium-zh --ozone-platform=wayland"))
rebind("SUPER + E",       hl.dsp.exec_cmd(HOME .. "/.local/bin/dolphin"))
rebind("ALT + BackSpace", hl.dsp.exec_cmd("wechat"))
rebind("ALT + Space",     hl.dsp.global("shell:launcher"))
rebind("SUPER + R",       hl.dsp.global("shell:memo"))

-- 输入法切换（还原 Super+Space；Alt+Tab 打开窗口实时缩略图总览；Glyph 底部 Deck 保留在 Super+Tab 与底边悬停）
rebind("SUPER + Space",   hl.dsp.exec_cmd("fcitx5-remote -t"))
rebind("ALT + Tab",       hl.dsp.global("shell:overview"))
rebind("SUPER + Tab",     hl.dsp.global("shell:altar"))

-- 窗口操作（Alt 系 + 原有 Super 习惯补齐）
rebind("ALT + Q",              hl.dsp.exec_cmd(HOME .. "/.local/bin/close-window"))
rebind("ALT + F",              hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
rebind("ALT + D",              hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
rebind("ALT + T",              hl.dsp.window.float({ action = "toggle" }))
rebind("ALT + P",              hl.dsp.window.pseudo())
rebind("ALT + E",              hl.dsp.window.move({ workspace = "special:min" }))
rebind("ALT + SHIFT + E",      hl.dsp.workspace.toggle_special("min"))
-- 调换 Glyph 默认暂存区键位：Super+S 移入暂存区，Super+Alt+S 呼出/隐藏暂存区
rebind("SUPER + S",            hl.dsp.window.move({ workspace = "special:special" }))
rebind("SUPER + ALT + S",      fn.toggle_special("special"))
rebind("ALT + SHIFT + Return", hl.dsp.window.bring_to_top())
rebind("ALT + I",              hl.dsp.global("shell:settings"))
rebind("ALT + O",              hl.dsp.reload_config())
rebind("SUPER + Semicolon",    hl.dsp.layout("splitratio -0.1"), { repeating = true })
rebind("SUPER + Apostrophe",   hl.dsp.layout("splitratio +0.1"), { repeating = true })
rebind("SUPER + BracketLeft",  hl.dsp.focus({ direction = "left" }))
rebind("SUPER + BracketRight", hl.dsp.focus({ direction = "right" }))

-- 焦点 / 交换
rebind("ALT + left",        hl.dsp.focus({ direction = "left" }))
rebind("ALT + right",       hl.dsp.focus({ direction = "right" }))
rebind("ALT + up",          hl.dsp.focus({ direction = "up" }))
rebind("ALT + down",        hl.dsp.focus({ direction = "down" }))
rebind("ALT + H",           hl.dsp.focus({ direction = "left" }))
rebind("ALT + L",           hl.dsp.focus({ direction = "right" }))
rebind("ALT + K",           hl.dsp.focus({ direction = "up" }))
rebind("ALT + J",           hl.dsp.focus({ direction = "down" }))
rebind("ALT + SHIFT + left",  hl.dsp.window.swap({ direction = "left" }))
rebind("ALT + SHIFT + right", hl.dsp.window.swap({ direction = "right" }))
rebind("ALT + SHIFT + up",    hl.dsp.window.swap({ direction = "up" }))
rebind("ALT + SHIFT + down",  hl.dsp.window.swap({ direction = "down" }))

-- 窗口大小调整（兼容 =/- 与 Shift 后的 +/_）
rebind("ALT + equal",         hl.dsp.window.resize({ x = 40,  y = 0 }),  { repeating = true })
rebind("ALT + minus",         hl.dsp.window.resize({ x = -40, y = 0 }),  { repeating = true })
rebind("ALT + SHIFT + equal", hl.dsp.window.resize({ x = 0,   y = 40 }), { repeating = true })
rebind("ALT + SHIFT + plus",  hl.dsp.window.resize({ x = 0,   y = 40 }), { repeating = true })
rebind("ALT + SHIFT + minus", hl.dsp.window.resize({ x = 0,   y = -40 }),{ repeating = true })
rebind("ALT + SHIFT + underscore", hl.dsp.window.resize({ x = 0, y = -40 }), { repeating = true })

-- 工作区 1-10：同时绑定物理键码 code:10..19 + 小键盘键码，解决按住 Shift 时 1..0 变成 !@# 导致 Shift+Alt+数字 失效的问题
local numCodes    = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local numpadCodes = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
for i = 1, 10 do
    rebind("ALT + code:" .. numCodes[i],          hl.dsp.focus({ workspace = i }))
    rebind("ALT + code:" .. numpadCodes[i],       hl.dsp.focus({ workspace = i }))
    rebind("ALT + SHIFT + code:" .. numCodes[i],    hl.dsp.window.move({ workspace = i }))
    rebind("ALT + SHIFT + code:" .. numpadCodes[i], hl.dsp.window.move({ workspace = i }))
    -- 同时修复 Super+Shift+1..0 移动窗口到工作区（防止只按 Super+Shift+数字没反应）
    rebind("SUPER + SHIFT + code:" .. numCodes[i],  hl.dsp.window.move({ workspace = i }))
end

-- 鼠标拖动 / 缩放窗口（修正 Glyph 把 Super+左键设成缩放的反直觉默认）
rebind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
rebind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
rebind("ALT + mouse:272",   hl.dsp.window.drag(),   { mouse = true })
rebind("ALT + mouse:273",   hl.dsp.window.resize(), { mouse = true })

-- 锁屏 / 电源菜单 / Clash / 截图 / 录屏 / 截图目录 / 复制图片像素
rebind("ALT + SHIFT + L",  hl.dsp.exec_cmd(vars.lockCmd))
rebind("ALT + SHIFT + P",  hl.dsp.global("shell:power"))
rebind("ALT + SHIFT + C",  hl.dsp.exec_cmd(HOME .. "/.local/bin/clash-ui"))
rebind("ALT + SHIFT + D",  hl.dsp.exec_cmd(HOME .. "/.local/bin/dolphin " .. HOME .. "/Pictures/Screenshots"))
rebind("ALT + SHIFT + R",  fn.record(true, false), { locked = true })
rebind("ALT + SHIFT + S",  hl.dsp.global("shell:shot"))
rebind("CTRL + SHIFT + S", hl.dsp.global("shell:shot"))
rebind("mouse:274",        hl.dsp.global("shell:shot"))
rebind("ALT + C",          hl.dsp.exec_cmd(HOME .. "/.local/bin/copy-image-data"))

-- ==================== 个人窗口规则 ====================
-- 微信所有窗口默认浮动居中（不在静态 window_rule 写死尺寸，否则会把 280x380 登录框也强行拉大）
hl.window_rule({ match = { class = ".*([Ww]e[Cc]hat|[Ww]eixin).*" }, float = true, center = true })
hl.window_rule({ match = { class = ".*([Dd]ing[Tt]alk).*" }, float = true })

-- 仅针对已登录的微信主窗口（初始宽度 > 450，排除 280x380 登录框）固定为 1265x923
hl.on("window.open", function(win)
    if win and win.class == "wechat" and (win.title == "微信" or win.title == "Weixin") then
        if win.size and win.size.x > 450 then
            hl.dispatch(hl.dsp.window.resize({ x = 1265, y = 923, relative = false, window = win }))
            hl.dispatch(hl.dsp.window.move({ x = 250, y = 159, relative = false, window = win }))
        end
    end
end)
hl.window_rule({
    match = { class = "^Emulator$" },
    float = true,
})
hl.window_rule({
    match = { class = "^Emulator$", title = "^Android Emulator.*" },
    size = {549, 1220},
})
hl.window_rule({
    match = { class = "^(org\\.flameshot\\.Flameshot|flameshot)$" },
    float = true,
    no_anim = true,
    no_blur = true,
    pin = true,
    move = {0, 0},
})
hl.window_rule({
    match = { class = "^kcm_.*" },
    float = true,
    size = {1000, 760},
    center = true,
})
hl.window_rule({
    match = { class = "^(steam|Steam)$" },
    float = true,
    size = {"(monitor_w*0.62)", "(monitor_h*0.74)"},
    center = true,
})

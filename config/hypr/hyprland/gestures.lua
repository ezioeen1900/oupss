local vars = require("variables")

hl.config({
    gestures = {
        workspace_swipe_distance                 = 700,
        workspace_swipe_cancel_ratio             = 0.15,
        workspace_swipe_min_speed_to_force       = 5,
        workspace_swipe_direction_lock           = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new               = true,
    },
})

-- 4指上下滑智能暂存区（异步执行，避免在 Lua 回调内同步调 hyprctl 造成主线程死锁）
local function special_swipe(target)
    local cmd = string.format(
        [[sh -c 'cur=$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .specialWorkspace.name | ltrimstr(\"special:\")"); [ -n "$cur" ] || cur="%s"; hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$cur\")"']],
        target
    )
    return function()
        hl.exec_cmd(cmd)
    end
end

-- 3指拖动窗口，4指左右切工作区、上下智能暂存区，5指下滑休眠
hl.gesture({ fingers = 3, direction = "swipe", action = "move" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "up", action = special_swipe("special") })
hl.gesture({ fingers = 4, direction = "down", action = special_swipe("min") })
hl.gesture({
    fingers   = vars.gestureFingersMore,
    direction = "down",
    action    = function()
        hl.exec_cmd(vars.sleepGestureCmd)
    end,
})

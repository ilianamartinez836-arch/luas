local ffi = require("ffi")
ffi.cdef[[ short GetAsyncKeyState(int vKey); ]]

local function is_held(vk)
    if not vk or vk == 0 then return false end
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

local function rgba(r, g, b, a)
    return { r/255, g/255, b/255, (a or 255)/255 }
end

local function ca(col, scale)
    return col[1], col[2], col[3], col[4] * (scale or 1)
end

local function c(t, ...)
    return t[1], t[2], t[3], t[4], ...
end

local CFG = {
    x        = 14,
    y        = 300,
    w        = 195,
    pad_x    = 10,
    pad_y    = 7,
    row_h    = 17,
    gap      = 3,
    rounding = 8,
    hdr_h    = 24,
    spd      = 14,
}

local expanded  = true
local exp_frac  = 1.0
local drag      = { on=false, ox=0, oy=0, sx=0, sy=0, moved=false }
local mb_prev    = false
local last_t    = os.clock()

local C = {
    bg       = rgba(24, 20, 22, 230),
    hdr      = rgba(38, 30, 34, 255),
    hdr_txt  = rgba(255, 214, 224, 255),
    sep      = rgba(255, 214, 224, 25),
    border   = rgba(255, 182, 193, 40),
    active   = rgba(255, 182, 193, 255),
    held     = rgba(240, 150, 175, 255),
    both     = rgba(255, 225, 235, 255),
    dot      = rgba(255, 182, 193, 255),
    key      = rgba(185, 165, 170, 255),
    chev     = rgba(185, 165, 170, 255),
}

local VKN = {
    [1]="LMB",[2]="RMB",[4]="MMB",[5]="X1",[6]="X2",
    [8]="Bksp",[9]="Tab",[13]="Enter",[16]="Shift",[17]="Ctrl",[18]="Alt",
    [20]="Caps",[27]="Esc",[32]="Space",
    [33]="PgUp",[34]="PgDn",[35]="End",[36]="Home",
    [37]="Left",[38]="Up",[39]="Right",[40]="Down",
    [45]="Ins",[46]="Del",
    [112]="F1",[113]="F2",[114]="F3",[115]="F4",
    [116]="F5",[117]="F6",[118]="F7",[119]="F8",
    [120]="F9",[121]="F10",[122]="F11",[123]="F12",
}
for i=65,90 do VKN[i]=string.char(i) end
for i=48,57 do VKN[i]=string.char(i) end

local function vname(vk)
    if not vk or vk==0 then return nil end
    return VKN[vk] or ("#"..vk)
end

local function sv(id)  local ok,v=pcall(vars.get,id); return ok and v or nil end
local function svb(id) local v=sv(id); return v==true end
local function svi(id) local v=sv(id); return type(v)=="number" and math.floor(v) or 0 end

local entries = {
    {
        label   = "Third Person",
        visible = function() return svb("thirdperson.enable") end,
        key_vk  = function() return svi("thirdperson.key") end,
    },
    {
        label   = "Freelook",
        visible = function() return svb("freelook.is_active") end,
        held_fn = function() return is_held(svi("freelook.key")) end,
        key_vk  = function() return svi("freelook.key") end,
    },
    {
        label   = "Anti-Aim",
        visible = function() return svb("aa.enabled") end,
        key_vk  = function() return svi("aa.disable_key") end,
    },
    {
        label   = "Ragebot",
        visible = function()
            return svb("hitscan.toggled")
                or svb("hitscan.holding")
                or is_held(svi("hitscan.aim_key"))
        end,
        held_fn = function()
            return svb("hitscan.holding") or is_held(svi("hitscan.aim_key"))
        end,
        key_vk  = function() return svi("hitscan.aim_key") end,
        tog_vk  = function() return svi("hitscan.toggle_key") end,
    },
    {
        label   = "Legitbot",
        visible = function()
            return svb("legitbot.toggled")
               -- or svb("legitbot.holding")
                or is_held(svi("legitbot.aim_key"))
        end,
        held_fn = function()
            return svb("legitbot.holding") or is_held(svi("legitbot.aim_key"))
        end,
        key_vk  = function() return svi("legitbot.aim_key") end,
        tog_vk  = function() return svi("legitbot.toggle_key") end,
    },
    {
        label   = "Triggerbot",
        visible = function()
            if not (svb("legitbot.enable") and svb("legitbot.triggerbot")) then return false end
            if svb("legitbot.trigger_require_key") then
                return is_held(svi("legitbot.trigger_key"))
            end
            return true
        end,
        held_fn = function()
            return svb("legitbot.trigger_require_key") and is_held(svi("legitbot.trigger_key"))
        end,
        key_vk  = function()
            return svb("legitbot.trigger_require_key") and svi("legitbot.trigger_key") or 0
        end,
    },
    {
        label   = "Speedhack",
        visible = function()
            return svb("settings.tick_manipulation") and is_held(svi("settings.speedhack_key"))
        end,
        held_fn = function() return true end,
        key_vk  = function() return svi("settings.speedhack_key") end,
    },
    {
        label   = "Fakelag",
        visible = function() return svb("fakelag.enable") end,
    },
    {
        label   = "Prespeed",
        visible = function()
            return svb("misc.prespeed") and is_held(svi("misc.prespeed_key"))
        end,
        held_fn = function() return true end,
        key_vk  = function() return svi("misc.prespeed_key") end,
    },
    {
        label   = "Lag Exploit",
        visible = function()
            return svb("misc.sequence_freezing") and is_held(svi("misc.seq_key"))
        end,
        held_fn = function() return true end,
        key_vk  = function() return svi("misc.seq_key") end,
    },
}

local vis = {}
for i = 1, #entries do vis[i] = 0.0 end

local function draw()
    local now = os.clock()
    local dt  = math.min(now - last_t, 0.05)
    last_t    = now

    local k   = 1.0 - math.exp(-CFG.spd * dt)
    local dl = imgui.get_foreground_draw_list()
    local mx, my = imgui.GetMousePos()
    local mb = imgui.IsMouseDown(0)

    local just_dn = mb and not mb_prev
    local just_up = not mb and mb_prev
    mb_prev = mb

    local px, py = CFG.x, CFG.y

    if just_dn then
        if mx >= px and mx <= px+CFG.w and my >= py and my <= py+CFG.hdr_h then
            drag.on    = true
            drag.ox    = mx - CFG.x
            drag.oy    = my - CFG.y
            drag.sx    = mx
            drag.sy    = my
            drag.moved = false
        end
    end

    if drag.on and mb then
        if math.abs(mx-drag.sx)+math.abs(my-drag.sy) > 4 then drag.moved = true end
        if drag.moved then
            CFG.x = mx - drag.ox
            CFG.y = my - drag.oy
            px, py = CFG.x, CFG.y
        end
    end

    if just_up then
        if drag.on and not drag.moved then
            expanded = not expanded
        end
        drag.on = false
    end

    exp_frac = exp_frac + ((expanded and 1.0 or 0.0) - exp_frac) * k

    for i, e in ipairs(entries) do
        local tgt = (e.visible and e.visible()) and 1.0 or 0.0
        vis[i] = vis[i] + (tgt - vis[i]) * k
    end

    local raw_h = 0
    for i = 1, #entries do
        raw_h = raw_h + vis[i] * (CFG.row_h + CFG.gap)
    end
    if raw_h > CFG.gap then raw_h = raw_h - CFG.gap end
    local content_h = raw_h * exp_frac
    local has_content = content_h > 0.5

    local panel_h = CFG.hdr_h
                  + (has_content and (CFG.pad_y + content_h + CFG.pad_y) or 0)

    dl:add_rect_filled(px, py, px+CFG.w, py+panel_h, c(C.bg, CFG.rounding))

    dl:add_rect_filled(px, py, px+CFG.w, py+CFG.hdr_h, c(C.hdr, CFG.rounding))
    if has_content then
        local half = math.ceil(CFG.rounding)
        dl:add_rect_filled(px, py+CFG.hdr_h-half, px+CFG.w, py+CFG.hdr_h, c(C.hdr, 0))
    end

    local title = "Keybinds"
    local tw    = imgui.CalcTextSize(title)
    dl:add_text(px + (CFG.w-tw)*0.5, py + (CFG.hdr_h-13)*0.5, c(C.hdr_txt, title))

    if has_content then
        dl:add_line(px+6, py+CFG.hdr_h, px+CFG.w-6, py+CFG.hdr_h,
                    c(C.sep, 1.0))
    end

    local cy = py + CFG.hdr_h + CFG.pad_y
    for i, e in ipairs(entries) do
        local frac = vis[i] * exp_frac
        local row_contrib = frac * (CFG.row_h + CFG.gap)

        if frac > 0.005 then
            local is_h = e.held_fn and e.held_fn() or false
            local is_t = e.visible and e.visible() or false

            local base = (is_t and is_h) and C.both
                      or is_h            and C.held
                      or                     C.active

            local ty    = cy + (CFG.row_h - 13) * 0.5
            local dot_x = px + CFG.pad_x + 4
            local dot_y = cy + CFG.row_h * 0.5

            dl:add_circle_filled(dot_x, dot_y, 3.0, ca(C.dot, frac))

            dl:add_text(dot_x+9, ty, base[1], base[2], base[3], base[4]*frac, e.label)

            local bx = px + CFG.w - CFG.pad_x

            local function badge(vk, col)
                local name = vname(vk)
                if not name then return end
                local bw = imgui.CalcTextSize(name)
                bx = bx - bw
                dl:add_text(bx, ty, col[1], col[2], col[3], col[4]*frac, name)
                bx = bx - 5
            end

            if e.key_vk then
                local vk = e.key_vk()
                badge(vk, is_held(vk) and C.held or C.key)
            end

            if e.tog_vk then
                local tvk = e.tog_vk()
                local hvk = e.key_vk and e.key_vk() or 0
                if tvk ~= 0 and tvk ~= hvk then
                    badge(tvk, is_held(tvk) and C.active or C.key)
                end
            end
        end

        cy = cy + row_contrib
    end
    dl:add_rect(px, py, px+CFG.w, py+panel_h, c(C.border, 1.0, CFG.rounding))
end

function on_end_scene()
    draw()
end

function on_unload()
    drag.on = false
    mb_prev = false
end

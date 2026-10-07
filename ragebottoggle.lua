local ffi = require("ffi")
ffi.cdef[[ short GetAsyncKeyState(int vKey); ]]

local function is_held(vk)
    if not vk or vk == 0 then return false end
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

local function rgba(r, g, b, a)
    return { r/255, g/255, b/255, (a or 255)/255 }
end

local function ca(col, scale, ...)
    return col[1], col[2], col[3], col[4] * (scale or 1), ...
end

local function c(t, ...)
    return t[1], t[2], t[3], t[4], ...
end

local function svb(id)
    local ok, v = pcall(vars.get, id)
    return ok and v == true
end

local MM_CFG = {
    x        = 300,
    y        = 300,
    w        = 210,
    pad_x    = 12,
    pad_y    = 8,
    row_h    = 20,
    gap      = 4,
    rounding = 8,
    hdr_h    = 24,
    spd      = 14,
}

local C = {
    bg       = rgba(24, 20, 22, 230),
    hdr      = rgba(38, 30, 34, 255),
    hdr_txt  = rgba(255, 214, 224, 255),
    sep      = rgba(255, 214, 224, 25),
    border   = rgba(255, 182, 193, 40),
    active   = rgba(255, 182, 193, 255),
    both     = rgba(255, 225, 235, 255),
    text_dim = rgba(160, 145, 150, 255),
}

local ignore_options = {
    { id = "ignore.teammates",             label = "Ignore Teammates" },
    { id = "ignore.friends",               label = "Ignore Friends" },
    { id = "ignore.commons",               label = "Ignore Commons" },
    { id = "ignore.witch_until_startled",  label = "Ignore Unstartled Witch" },
}

local menu_open      = false
local menu_frac      = 0.0
local supr_was_down  = false
local mb_prev        = false
local mm_drag        = { on = false, ox = 0, oy = 0, sx = 0, sy = 0, moved = false }
local last_t         = os.clock()

local function draw()
    local now = os.clock()
    local dt  = math.min(now - last_t, 0.05)
    last_t    = now

    local k   = 1.0 - math.exp(-MM_CFG.spd * dt)
    local dl  = imgui.get_foreground_draw_list()
    local mx, my = imgui.GetMousePos()
    local mb  = imgui.IsMouseDown(0)

    local just_dn = mb and not mb_prev
    local just_up = not mb and mb_prev
    mb_prev = mb

    local supr_down = is_held(46)
    if supr_down and not supr_was_down then
        menu_open = not menu_open
        if client and client.set_input_blocked then
            client.set_input_blocked(menu_open)
        end
    end
    supr_was_down = supr_down

    menu_frac = menu_frac + ((menu_open and 1.0 or 0.0) - menu_frac) * k

    if menu_frac <= 0.005 then return end

    local mmx, mmy = MM_CFG.x, MM_CFG.y
    local item_cnt = #ignore_options
    local mm_content_h = item_cnt * MM_CFG.row_h + (item_cnt - 1) * MM_CFG.gap
    local mm_total_h = MM_CFG.hdr_h + MM_CFG.pad_y * 2 + mm_content_h

    if just_dn and menu_open then
        if mx >= mmx and mx <= mmx+MM_CFG.w and my >= mmy and my <= mmy+MM_CFG.hdr_h then
            mm_drag.on    = true
            mm_drag.ox    = mx - MM_CFG.x
            mm_drag.oy    = my - MM_CFG.y
            mm_drag.sx    = mx
            mm_drag.sy    = my
            mm_drag.moved = false
        end
    end

    if mm_drag.on and mb then
        if math.abs(mx-mm_drag.sx)+math.abs(my-mm_drag.sy) > 4 then mm_drag.moved = true end
        if mm_drag.moved then
            MM_CFG.x = mx - mm_drag.ox
            MM_CFG.y = my - mm_drag.oy
            mmx, mmy = MM_CFG.x, MM_CFG.y
        end
    end

    if just_up then mm_drag.on = false end

    dl:add_rect_filled(mmx, mmy, mmx+MM_CFG.w, mmy+mm_total_h, c(C.bg, MM_CFG.rounding))
    
    dl:add_rect_filled(mmx, mmy, mmx+MM_CFG.w, mmy+MM_CFG.hdr_h, c(C.hdr, MM_CFG.rounding))
    local half = math.ceil(MM_CFG.rounding)
    dl:add_rect_filled(mmx, mmy+MM_CFG.hdr_h-half, mmx+MM_CFG.w, mmy+MM_CFG.hdr_h, c(C.hdr, 0))
    dl:add_line(mmx+6, mmy+MM_CFG.hdr_h, mmx+MM_CFG.w-6, mmy+MM_CFG.hdr_h, ca(C.sep, menu_frac))

    local m_title = "Ragebot Ignore Filter"
    local m_tw = imgui.CalcTextSize(m_title)
    dl:add_text(mmx + (MM_CFG.w-m_tw)*0.5, mmy + (MM_CFG.hdr_h-13)*0.5, ca(C.hdr_txt, menu_frac, m_title))

    local m_cy = mmy + MM_CFG.hdr_h + MM_CFG.pad_y
    for i, opt in ipairs(ignore_options) do
        local opt_active = svb(opt.id)
        
        local row_x1, row_y1 = mmx + MM_CFG.pad_x, m_cy
        local row_x2, row_y2 = mmx + MM_CFG.w - MM_CFG.pad_x, m_cy + MM_CFG.row_h
        local is_hovered = (mx >= row_x1 and mx <= row_x2 and my >= row_y1 and my <= row_y2)

        if menu_open and is_hovered and just_dn then
            pcall(vars.set, opt.id, not opt_active)
            opt_active = not opt_active
        end

        local txt_y = m_cy + (MM_CFG.row_h - 13) * 0.5
        local label_col = opt_active and C.active or (is_hovered and C.both or C.text_dim)
        dl:add_text(row_x1, txt_y, ca(label_col, menu_frac, opt.label))

        local box_size = 10
        local box_x1 = row_x2 - box_size
        local box_y1 = m_cy + (MM_CFG.row_h - box_size) * 0.5
        local box_x2 = row_x2
        local box_y2 = box_y1 + box_size

        dl:add_rect(box_x1, box_y1, box_x2, box_y2, ca(C.border, menu_frac, 2))
        if opt_active then
            dl:add_rect_filled(box_x1+2, box_y1+2, box_x2-2, box_y2-2, ca(C.active, menu_frac, 1))
        elseif is_hovered then
            dl:add_rect_filled(box_x1+2, box_y1+2, box_x2-2, box_y2-2, ca(C.border, menu_frac * 0.5, 1))
        end

        m_cy = m_cy + MM_CFG.row_h + MM_CFG.gap
    end

    dl:add_rect(mmx, mmy, mmx+MM_CFG.w, mmy+mm_total_h, ca(C.border, menu_frac, MM_CFG.rounding))
end

function on_end_scene()
    draw()
end

function on_unload()
    mm_drag.on = false
    mb_prev = false
    if client and client.set_input_blocked then
        client.set_input_blocked(false)
    end
end

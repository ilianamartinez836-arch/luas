-- Script : wiwiwiw.lua
-- Author : yipee
-- Created: auto
local gif = dofile("C:\\Echidna-L4d2\\Scripts\\gif.lua")
gif.init("C:\\Echidna-L4d2\\gif_cache\\")

local ui = {
    show        = true,
    keep_aspect = true,
    show_top_bar = true,
    rounding    = 4,
}

local GIF_PATH = "C:\\Echidna-L4d2\\New folder\\anim2.gif"

function on_end_scene()
    if not ui.show then return end

    local window_flags = 0
    local menu_open = client.is_menu_open()

    if not menu_open and not ui.show_top_bar then
        window_flags = window_flags + imgui.ImGuiWindowFlags_NoTitleBar
    end

    imgui.SetNextWindowSize(320, 240, imgui.ImGuiCond_FirstUseEver)

    if imgui.Begin("Capella.lua", window_flags) then

        imgui.draw_window_blur(0.5)

        if menu_open then
            local aspect_val, aspect_changed = imgui.Checkbox("Keep Aspect Ratio", ui.keep_aspect)
            if aspect_changed then
                ui.keep_aspect = aspect_val
            end

            local bar_val, bar_changed = imgui.Checkbox("Show Top Bar when menu closed", ui.show_top_bar)
            if bar_changed then
                ui.show_top_bar = bar_val
            end

            imgui.Separator()
            imgui.Spacing()
        end

        local avail_w, avail_h = imgui.GetContentRegionAvail()
        local px, py           = imgui.GetCursorScreenPos()
        local draw_w, draw_h   = avail_w, avail_h

        if ui.keep_aspect then
            local img_w, img_h = gif.get_size(GIF_PATH)
            if img_w > 0 and img_h > 0 then
                local scale = math.min(avail_w / img_w, avail_h / img_h)
                draw_w = img_w * scale
                draw_h = img_h * scale
            end
        end

        gif.draw(GIF_PATH, px, py, draw_w, draw_h, ui.rounding)

        imgui.Dummy(draw_w, draw_h)
    end

    imgui.End()
end

function on_unload()
    if gif and gif.shutdown then
        gif.shutdown()
    end
end

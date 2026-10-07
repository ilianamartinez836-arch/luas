local gif = dofile("C:\\Echidna-L4d2\\Scripts\\gif.lua")
gif.init("C:\\Echidna-L4d2\\gif_cache\\")

local ui = {
    show = true,
    keep_aspect = true,
    show_top_bar = true,
    rounding = 4,
}

function on_end_scene()
    if not ui.show then
        return
    end

    local window_flags = imgui.ImGuiWindowFlags_None or 0

    if not client.is_menu_open() and not ui.show_top_bar then
        window_flags = window_flags + (imgui.ImGuiWindowFlags_NoTitleBar or 1)
    end

    imgui.SetNextWindowSize(320, 240, imgui.ImGuiCond_FirstUseEver)

    if imgui.Begin("Capella.lua", window_flags) then
        if imgui.draw_window_blur then
           -- imgui.draw_window_blur(0.8)
        end
  
        if client.is_menu_open() then
            local cb_aspect = imgui.Checkbox("Keep Aspect Ratio", ui.keep_aspect)
            if cb_aspect ~= nil then
                ui.keep_aspect = cb_aspect
            end
            
            local cb_bar = imgui.Checkbox("Show Top Bar when menu closed", ui.show_top_bar)
            if cb_bar ~= nil then
                ui.show_top_bar = cb_bar
            end
            
            imgui.Separator()
        end
        
        local avail_w, avail_h = imgui.GetContentRegionAvail()
        local px, py = imgui.GetCursorScreenPos()

        local draw_w, draw_h = avail_w, avail_h

        if ui.keep_aspect then
            local img_w, img_h = gif.get_size("C:\\Echidna-L4d2\\New folder\\anim3.gif")
            if img_w > 0 and img_h > 0 then
                local scale = math.min(avail_w / img_w, avail_h / img_h)
                draw_w = img_w * scale
                draw_h = img_h * scale
            end
        end

        gif.draw(
            "C:\\Echidna-L4d2\\New folder\\anim3.gif",
            px,
            py,
            draw_w,
            draw_h,
            ui.rounding
        )

        imgui.Dummy(draw_w, draw_h)
    end
    imgui.End()
end

function on_unload()
    if gif and gif.shutdown then
        gif.shutdown()
    end
end

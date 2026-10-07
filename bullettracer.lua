-- @author: Natsumi
-- @created: 27.06 10:08
-- Echidna Script
local cfg = {
    enabled          = true,

    tracer_enabled   = true,
    tracer_style     = 0,
    tracer_duration  = 0.8,
    tracer_thickness = 1.5,
    tracer_r         = 1.0,
    tracer_g         = 0.9,
    tracer_b         = 0.2,
    tracer_a         = 1.0,

    icon_enabled     = true,
    icon_size        = 14.0,
    icon_duration    = 3.5,
    icon_path        = "C:\\Echidna-L4d2\\New folder\\konata.png",

    effect_style     = 1,
    effect_size      = 24.0,
    effect_duration  = 0.5,
    effect_r         = 1.0,
    effect_g         = 0.4,
    effect_b         = 0.1,
    effect_a         = 1.0,

    fade_style       = 0,
    max_impacts      = 64,
}

local impacts    = {}
local icon_tex   = nil
local icon_dirty = false

local TRACER_STYLES = { "Line", "Beam", "Dashed", "Electric", "Rail" }
local EFFECT_STYLES = { "None", "Ring", "Cross", "Dot", "Splash", "Shockwave" }
local FADE_STYLES   = { "Quadratic", "Linear", "Hold + Drop" }

local function Combo(label, current, items)
    local preview = items[current + 1] or ""
    local result  = current
    if imgui.BeginCombo(label, preview) then
        for i = 1, #items do
            local is_sel = (i - 1) == current
            if imgui.Selectable(items[i], is_sel) then
                result = i - 1
            end
            if is_sel then imgui.SetItemDefaultFocus() end
        end
        imgui.EndCombo()
    end
    return result
end

local function ensure_texture()
    if not icon_tex or icon_dirty then
        icon_tex   = client.load_texture(cfg.icon_path)
        icon_dirty = false
    end
end

local function get_eye_pos(ent)
    if not (ent and ent:is_valid()) then return nil end
    local p = ent:as("CTerrorPlayer") or ent
    return (p.EyePosition    and p:EyePosition())
        or (p.get_abs_origin and p:get_abs_origin())
        or (p.GetAbsOrigin   and p:GetAbsOrigin())
end

local function compute_fade(elapsed, duration)
    local t = math.max(0, math.min(1, 1 - elapsed / duration))
    if cfg.fade_style == 0 then return t * t end
    if cfg.fade_style == 1 then return t      end
    return t > 0.3 and 1.0 or (t / 0.3)
end

local function drand(seed, i)
    local v = math.sin(seed * 127.1 + i * 311.7) * 43758.5453
    return v - math.floor(v)
end

local function draw_tracer(dl, ox, oy, dx, dy, alpha, seed)
    local s       = cfg.tracer_style
    local r, g, b = cfg.tracer_r, cfg.tracer_g, cfg.tracer_b
    local a       = alpha * cfg.tracer_a
    local th      = cfg.tracer_thickness

    if s == 0 then
        dl:add_line(ox, oy, dx, dy, r, g, b, a, th)

    elseif s == 1 then
        dl:add_line(ox, oy, dx, dy, r, g, b, a * 0.15, th * 6)
        dl:add_line(ox, oy, dx, dy, r, g, b, a * 0.40, th * 3)
        dl:add_line(ox, oy, dx, dy, r, g, b, a,         th)

    elseif s == 2 then
        local segs = 14
        for i = 0, segs - 1, 2 do
            local t0 = i / segs
            local t1 = (i + 0.65) / segs
            dl:add_line(
                ox + (dx-ox)*t0, oy + (dy-oy)*t0,
                ox + (dx-ox)*t1, oy + (dy-oy)*t1,
                r, g, b, a, th)
        end

    elseif s == 3 then
        local segs = 10
        local px   = -(dy - oy)
        local py   =  (dx - ox)
        local plen = math.sqrt(px*px + py*py)
        if plen > 0 then px = px/plen; py = py/plen end
        local prev_x, prev_y = ox, oy
        for i = 1, segs do
            local t  = i / segs
            local mx = ox + (dx-ox)*t
            local my = oy + (dy-oy)*t
            if i < segs then
                local off = (drand(seed, i) - 0.5) * 18
                mx = mx + px*off; my = my + py*off
            end
            dl:add_line(prev_x, prev_y, mx, my, r, g, b, a, th)
            prev_x, prev_y = mx, my
        end

    elseif s == 4 then
        dl:add_line(ox, oy, dx, dy, r, g, b, a * 0.20, th * 7)
        dl:add_line(ox, oy, dx, dy, r, g, b, a * 0.50, th * 3)
        dl:add_line(ox, oy, dx, dy, 1,  1,  1,  a,      th)
    end
end

local function draw_effect(dl, dx, dy, alpha, elapsed)
    local s   = cfg.effect_style
    if s == 0 then return end
    local r, g, b = cfg.effect_r, cfg.effect_g, cfg.effect_b
    local a   = alpha * cfg.effect_a
    local sz  = cfg.effect_size
    local pct = elapsed / cfg.effect_duration

    if s == 1 then
        dl:add_circle(dx, dy, sz * pct, r, g, b, a, 32, 1.5)

    elseif s == 2 then
        local h = sz * 0.5
        dl:add_line(dx-h, dy-h, dx+h, dy+h, r, g, b, a, 1.5)
        dl:add_line(dx+h, dy-h, dx-h, dy+h, r, g, b, a, 1.5)

    elseif s == 3 then
        local rad = math.max(1, sz * 0.35 * (1 - pct))
        dl:add_circle_filled(dx, dy, rad, r, g, b, a, 20)

    elseif s == 4 then
        local len = sz * pct
        for i = 0, 7 do
            local angle = (i / 8) * math.pi * 2
            dl:add_line(
                dx + math.cos(angle)*len*0.25,
                dy + math.sin(angle)*len*0.25,
                dx + math.cos(angle)*len,
                dy + math.sin(angle)*len,
                r, g, b, a, 1.5)
        end

    elseif s == 5 then
        local outer = sz * pct
        dl:add_circle(dx, dy, outer,       r, g, b, a,       48, 1.0)
        dl:add_circle(dx, dy, outer * 0.6, r, g, b, a * 0.4, 32, 1.0)
        if pct < 0.4 then
            dl:add_circle_filled(dx, dy, sz*0.15, 1, 1, 1, a*(1-pct/0.4), 16)
        end
    end
end

local bullet_impact_id = events.add_listener("bullet_impact", function(ev)
    if not cfg.enabled then return end
    local local_idx = EngineClient.GetLocalPlayer()
    if EngineClient.GetPlayerForUserID(ev:GetInt("userid")) ~= local_idx then return end

    if #impacts >= cfg.max_impacts then table.remove(impacts, 1) end

    local local_ent = ClientEntityList.GetClientEntity(local_idx)
    table.insert(impacts, {
        pos    = { x = ev:GetFloat("x"), y = ev:GetFloat("y"), z = ev:GetFloat("z") },
        origin = get_eye_pos(local_ent),
        time   = os.clock(),
        seed   = math.random(1, 9999),
    })
end)

function on_end_scene()
    if not cfg.enabled or not EngineClient.IsInGame() then return end
    if cfg.icon_enabled then ensure_texture() end
    if #impacts == 0 then return end

    local now      = os.clock()
    local vw, vh   = imgui.GetDisplaySize()
    local sw, sh   = EngineClient.GetScreenSize()
    local sx, sy   = vw/sw, vh/sh
    local dl       = imgui.get_foreground_draw_list()
    local max_life = math.max(cfg.tracer_duration, cfg.icon_duration, cfg.effect_duration)

    local local_ent = ClientEntityList.GetClientEntity(EngineClient.GetLocalPlayer())
    local eye_now   = get_eye_pos(local_ent)

    for i = #impacts, 1, -1 do
        local impact  = impacts[i]
        local elapsed = now - impact.time

        if elapsed > max_life then
            table.remove(impacts, i)
        else
            local ret, sp = DebugOverlay.ScreenPosition(impact.pos)
            if ret == 0 then
                local dx, dy = sp.x*sx, sp.y*sy

                if cfg.tracer_enabled and impact.origin and elapsed < cfg.tracer_duration then
                    local ret2, sp2 = DebugOverlay.ScreenPosition(impact.origin)
                    if ret2 == 0 then
                        draw_tracer(dl, sp2.x*sx, sp2.y*sy, dx, dy,
                            compute_fade(elapsed, cfg.tracer_duration), impact.seed)
                    end
                end

                if cfg.effect_style > 0 and elapsed < cfg.effect_duration then
                    draw_effect(dl, dx, dy,
                        compute_fade(elapsed, cfg.effect_duration), elapsed)
                end

                if cfg.icon_enabled and icon_tex and elapsed < cfg.icon_duration then
                    local dist = 400
                    if eye_now then
                        local lx = eye_now.x - impact.pos.x
                        local ly = eye_now.y - impact.pos.y
                        local lz = eye_now.z - impact.pos.z
                        dist = math.sqrt(lx*lx + ly*ly + lz*lz)
                    end
                    local sz = math.max(4, math.min(128, cfg.icon_size*(400/math.max(1,dist))))
                    dl:add_image_rounded(icon_tex,
                        dx-sz/2, dy-sz/2, dx+sz/2, dy+sz/2,
                        0, 0, 1, 1, 1, 1, 1,
                        compute_fade(elapsed, cfg.icon_duration), 0)
                end
            end
        end
    end
end

menu.add_main_tab("⊙", "Tracer", function()
    imgui.PushStyleColor(imgui.ImGuiCol_ChildBg, 0.06, 0.08, 0.15, 0.92)
    
    if imgui.BeginChild("##tracer_container", 0, 0, true) then
        if imgui.BeginTabBar("tracer_tabs") then

            if imgui.BeginTabItem("General") then
                cfg.enabled     = imgui.Checkbox("Master Enable", cfg.enabled)
                imgui.Separator()
                cfg.fade_style  = Combo("Fade Curve",    cfg.fade_style,  FADE_STYLES)
                cfg.max_impacts = imgui.SliderInt("Max Impacts", cfg.max_impacts, 8, 256)
                imgui.Separator()
                imgui.Text("Fade hint:")
                local hints = {
                    [0] = "Stays bright — sharp tail at the end",
                    [1] = "Fades evenly across full lifetime",
                    [2] = "Fully opaque — snaps out at the end",
                }
                imgui.TextDisabled(hints[cfg.fade_style] or "")
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("Tracer") then
                cfg.tracer_enabled   = imgui.Checkbox("Show Tracer", cfg.tracer_enabled)
                imgui.Separator()
                cfg.tracer_style     = Combo("Style##tr",      cfg.tracer_style,     TRACER_STYLES)
                cfg.tracer_duration  = imgui.SliderFloat("Duration (s)##tr",  cfg.tracer_duration,  0.05, 8.0)
                cfg.tracer_thickness = imgui.SliderFloat("Thickness##tr",     cfg.tracer_thickness, 0.5,  10.0)
                imgui.Separator()
                imgui.Text("Color")
                cfg.tracer_r = imgui.SliderFloat("R##tr", cfg.tracer_r, 0.0, 1.0)
                cfg.tracer_g = imgui.SliderFloat("G##tg", cfg.tracer_g, 0.0, 1.0)
                cfg.tracer_b = imgui.SliderFloat("B##tb", cfg.tracer_b, 0.0, 1.0)
                cfg.tracer_a = imgui.SliderFloat("A##ta", cfg.tracer_a, 0.0, 1.0)
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("Icon") then
                cfg.icon_enabled  = imgui.Checkbox("Show Icon", cfg.icon_enabled)
                imgui.Separator()
                cfg.icon_size     = imgui.SliderFloat("Base Size##ic",    cfg.icon_size,    4.0,  64.0)
                cfg.icon_duration = imgui.SliderFloat("Duration (s)##ic", cfg.icon_duration, 0.5, 15.0)
                imgui.Separator()
                imgui.Text("Path (edit in script):")
                imgui.TextDisabled(cfg.icon_path)
                imgui.Spacing()
                if imgui.Button("Reload Image") then
                    icon_tex   = nil
                    icon_dirty = true
                end
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("Effect") then
                cfg.effect_style    = Combo("Effect##ef",       cfg.effect_style,    EFFECT_STYLES)
                imgui.Separator()
                cfg.effect_size     = imgui.SliderFloat("Size##ef",          cfg.effect_size,     4.0, 120.0)
                cfg.effect_duration = imgui.SliderFloat("Duration (s)##ef", cfg.effect_duration, 0.05,  5.0)
                imgui.Separator()
                imgui.Text("Color")
                cfg.effect_r = imgui.SliderFloat("R##er", cfg.effect_r, 0.0, 1.0)
                cfg.effect_g = imgui.SliderFloat("G##eg", cfg.effect_g, 0.0, 1.0)
                cfg.effect_b = imgui.SliderFloat("B##eb", cfg.effect_b, 0.0, 1.0)
                cfg.effect_a = imgui.SliderFloat("A##ea", cfg.effect_a, 0.0, 1.0)
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end
        imgui.EndChild()
    end

    imgui.PopStyleColor()
end)

function on_unload()
    if bullet_impact_id then
        events.remove_listener("bullet_impact", bullet_impact_id)
    end
end

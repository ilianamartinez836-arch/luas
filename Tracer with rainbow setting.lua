-- ============================================================
--  Advanced 3D Impacts Script  |  HeavenHook / L4D2
--  Settings are saved to impacts_config.txt next to this file.                OG version made by by AddOutSeqNr
--  Config auto-loads on startup and auto-saves on every change.
-- ============================================================

local MODES = { "Local", "Enemy", "Team" }
local mode_idx = 0 

local function create_default_cfg(is_local)
    return {
        enabled          = is_local, 
        tracer_enabled   = true,
        tracer_style     = 4,
        tracer_duration  = 1.5,
        tracer_thickness = 2.5,
        tracer_r         = is_local and 0.2 or 1.0,
        tracer_g         = is_local and 0.8 or 0.2,
        tracer_b         = is_local and 1.0 or 0.2,
        tracer_a         = 1.0,
        tracer_rainbow   = false,
        tracer_rspeed    = 2.0,

        effect_style     = 1,
        effect_size      = 24.0,
        effect_duration  = 1.5,
        effect_r         = is_local and 0.2 or 1.0,
        effect_g         = is_local and 0.8 or 0.2,
        effect_b         = is_local and 1.0 or 0.2,
        effect_a         = 1.0,
        effect_rainbow   = false,
        effect_rspeed    = 2.0,
    }
end

local cfg = {
    ["Local"] = create_default_cfg(true),
    ["Enemy"] = create_default_cfg(false),
    ["Team"]  = create_default_cfg(false),
}

local global_cfg = {
    fade_style  = 0,
    max_impacts = 128,
}

-- ──────────────────────────────────────────────────────────────
--  CONFIG SAVE / LOAD SYSTEM
-- ──────────────────────────────────────────────────────────────

local CONFIG_PATH = "impacts_config.txt"

local function serialize_value(val, indent)
    indent = indent or ""
    local t = type(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "boolean" or t == "number" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local key_str
            if type(k) == "string" then
                key_str = string.format("[%q]", k)
            else
                key_str = string.format("[%s]", tostring(k))
            end
            local val_str = serialize_value(v, indent .. "  ")
            if val_str then
                table.insert(parts, string.format("%s  %s = %s", indent, key_str, val_str))
            end
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return nil
end

local function save_config()
    local ok, file = pcall(io.open, CONFIG_PATH, "w")
    if not ok or not file then return end

    local data = {
        cfg = cfg,
        global_cfg = global_cfg
    }

    local content = "return " .. serialize_value(data) .. "\n"
    file:write(content)
    file:close()
end

local function load_config()
    local ok, file = pcall(io.open, CONFIG_PATH, "r")
    if not ok or not file then return end

    local content = file:read("*a")
    file:close()

    local chunk, err = load(content)
    if not chunk then return end

    local success, loaded_data = pcall(chunk)
    if not success or type(loaded_data) ~= "table" then return end

    if loaded_data.global_cfg then
        for k, v in pairs(loaded_data.global_cfg) do
            global_cfg[k] = v
        end
    end

    if loaded_data.cfg then
        for mode, mode_cfg in pairs(loaded_data.cfg) do
            if cfg[mode] then
                for k, v in pairs(mode_cfg) do
                    cfg[mode][k] = v
                end
                
                -- SAFETY FALLBACK: If old config is missing rainbow settings, inject them so the script doesn't crash
                if cfg[mode].tracer_rainbow == nil then cfg[mode].tracer_rainbow = false end
                if cfg[mode].tracer_rspeed == nil then cfg[mode].tracer_rspeed = 2.0 end
                if cfg[mode].effect_rainbow == nil then cfg[mode].effect_rainbow = false end
                if cfg[mode].effect_rspeed == nil then cfg[mode].effect_rspeed = 2.0 end
            end
        end
    end
end

load_config()

-- ──────────────────────────────────────────────────────────────
--  IMPACT DRAWING & HELPERS
-- ──────────────────────────────────────────────────────────────

local impacts = {}
local TRACER_STYLES = { "Line", "Beam", "Dashed", "Electric", "Rail" }
local EFFECT_STYLES = { "None", "Ring", "Cross", "Dot", "Splash", "Shockwave" }
local FADE_STYLES   = { "Quadratic", "Linear", "Hold + Drop" }


local function get_screen_coords(world_pos)
    if not engine.world_to_screen_matrix then return nil end

    local mat_ptr = engine.world_to_screen_matrix()
    if not mat_ptr or mat_ptr == 0 then return nil end

    local function read_mat(idx)
        return memory.read_float(mat_ptr + (idx * 4))
    end

    local ok, m00 = pcall(read_mat, 0)
    if not ok then return nil end
    local m01 = read_mat(1); local m02 = read_mat(2); local m03 = read_mat(3)
    local m10 = read_mat(4); local m11 = read_mat(5); local m12 = read_mat(6); local m13 = read_mat(7)
    local m30 = read_mat(12); local m31 = read_mat(13); local m32 = read_mat(14); local m33 = read_mat(15)

    local w = m30 * world_pos.x + m31 * world_pos.y + m32 * world_pos.z + m33
    if w < 0.001 then return nil end 

    local inv_w = 1.0 / w
    local screen_x = (m00 * world_pos.x + m01 * world_pos.y + m02 * world_pos.z + m03) * inv_w
    local screen_y = (m10 * world_pos.x + m11 * world_pos.y + m12 * world_pos.z + m13) * inv_w

    local width, height = engine.get_screen_size()
    local x = (width / 2) + (screen_x * width / 2)
    local y = (height / 2) - (screen_y * height / 2)

    return { x = math.floor(x), y = math.floor(y) }
end

local function compute_fade(elapsed, duration)
    local t = math.max(0, math.min(1, 1 - elapsed / duration))
    if global_cfg.fade_style == 0 then return t * t end
    if global_cfg.fade_style == 1 then return t      end
    return t > 0.3 and 1.0 or (t / 0.3)
end

local function drand(seed, i)
    local v = math.sin(seed * 127.1 + i * 311.7) * 43758.5453
    return v - math.floor(v)
end

-- Rainbow Color Generator
local function get_rainbow_color(speed)
    local s = speed or 2.0
    local time = os.clock() * s
    local r = (math.sin(time) * 0.5) + 0.5
    local g = (math.sin(time + 2.09439) * 0.5) + 0.5 -- 120 deg offset
    local b = (math.sin(time + 4.18879) * 0.5) + 0.5 -- 240 deg offset
    return r, g, b
end

local function safe_line(x1, y1, x2, y2, r, g, b, a)
    pcall(function() draw.line(math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2), r, g, b, a) end)
end
local function safe_circle(x, y, rad, segs, r, g, b, a)
    pcall(function() draw.circle(math.floor(x), math.floor(y), rad, segs, r, g, b, a) end)
end
local function safe_outlined_circle(x, y, rad, segs, r, g, b, a)
    pcall(function() draw.outlined_circle(math.floor(x), math.floor(y), rad, segs, r, g, b, a) end)
end

local function safe_thick_line(x1, y1, x2, y2, r, g, b, a, thickness)
    if thickness <= 1.0 then safe_line(x1, y1, x2, y2, r, g, b, a); return end
    local dx = x2 - x1; local dy = y2 - y1
    local len = math.sqrt(dx*dx + dy*dy)
    if len == 0 then return end
    local px = -dy / len; local py = dx / len
    local half = thickness / 2
    for i = -half, half, 0.5 do
        safe_line(x1 + px * i, y1 + py * i, x2 + px * i, y2 + py * i, r, g, b, a)
    end
end

local function draw_tracer(ox, oy, dx, dy, elapsed, seed, c)
    local s = c.tracer_style
    local r, g, b = c.tracer_r, c.tracer_g, c.tracer_b
    
    if c.tracer_rainbow then
        r, g, b = get_rainbow_color(c.tracer_rspeed)
    end

    local a  = compute_fade(elapsed, c.tracer_duration) * c.tracer_a
    local th = c.tracer_thickness

    if s == 0 then
        safe_thick_line(ox, oy, dx, dy, r, g, b, a, th)
    elseif s == 1 then
        safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.15, th * 2.5)
        safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.40, th * 1.5)
        safe_thick_line(ox, oy, dx, dy, r, g, b, a, th)
    elseif s == 2 then
        local segs = 14
        for i = 0, segs - 1, 2 do
            local t0 = i / segs; local t1 = (i + 0.65) / segs
            safe_thick_line(ox + (dx-ox)*t0, oy + (dy-oy)*t0, ox + (dx-ox)*t1, oy + (dy-oy)*t1, r, g, b, a, th)
        end
    elseif s == 3 then
        local segs = 10
        local px = -(dy - oy); local py = (dx - ox)
        local plen = math.sqrt(px*px + py*py)
        if plen > 0 then px = px/plen; py = py/plen end
        local prev_x, prev_y = ox, oy
        for i = 1, segs do
            local t  = i / segs
            local mx = ox + (dx-ox)*t; local my = oy + (dy-oy)*t
            if i < segs then
                local off = (drand(seed, i) - 0.5) * 18
                mx = mx + px*off; my = my + py*off
            end
            safe_thick_line(prev_x, prev_y, mx, my, r, g, b, a, th)
            prev_x, prev_y = mx, my
        end
    elseif s == 4 then
        safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.20, th * 3.5)
        safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.60, th * 1.5)
        safe_thick_line(ox, oy, dx, dy, 1, 1, 1, a, th * 0.5)
    end
end

local function draw_effect(dx, dy, elapsed, c)
    local s = c.effect_style
    if s == 0 then return end
    
    local r, g, b = c.effect_r, c.effect_g, c.effect_b
    if c.effect_rainbow then
        r, g, b = get_rainbow_color(c.effect_rspeed)
    end

    local a   = compute_fade(elapsed, c.effect_duration) * c.effect_a
    local sz  = c.effect_size
    local pct = elapsed / c.effect_duration

    if s == 1 then
        safe_outlined_circle(dx, dy, sz * pct, 32, r, g, b, a)
    elseif s == 2 then
        local h = sz * 0.5
        safe_line(dx-h, dy-h, dx+h, dy+h, r, g, b, a)
        safe_line(dx+h, dy-h, dx-h, dy+h, r, g, b, a)
    elseif s == 3 then
        local rad = math.max(1, sz * 0.35 * (1 - pct))
        safe_circle(dx, dy, rad, 20, r, g, b, a)
    elseif s == 4 then
        local len = sz * pct
        for i = 0, 7 do
            local angle = (i / 8) * math.pi * 2
            safe_line(dx + math.cos(angle)*len*0.25, dy + math.sin(angle)*len*0.25, dx + math.cos(angle)*len, dy + math.sin(angle)*len, r, g, b, a)
        end
    elseif s == 5 then
        local outer = sz * pct
        safe_outlined_circle(dx, dy, outer, 48, r, g, b, a)
        safe_outlined_circle(dx, dy, outer * 0.6, 32, r, g, b, a * 0.4)
        if pct < 0.4 then safe_circle(dx, dy, sz*0.15, 16, 1, 1, 1, a*(1-pct/0.4)) end
    end
end


events.register("bullet_impact")

function on_game_event(name, event)
    if name == "bullet_impact" then
        local local_player = client.get_local_player()
        if not local_player then return end
        
        local userid = event:get_int("userid")
        local player_idx = engine.get_player_for_userid(userid)
        if not player_idx or player_idx == 0 then return end
        
        local mode = "None"
        if player_idx == local_player:get_index() then
            mode = "Local"
        else
            local shooter = entity.get_by_index(player_idx)
            if shooter then
                if shooter:get_team() == local_player:get_team() then
                    mode = "Team"
                else
                    mode = "Enemy"
                end
            end
        end

        if mode ~= "None" and cfg[mode].enabled then
            if #impacts >= global_cfg.max_impacts then table.remove(impacts, 1) end
            
            local start_pos
            if mode == "Local" then
                local eye_pos = local_player:get_eye_position()
                local angles  = engine.get_view_angles()
                local fwd, right, up = utils.angle_vectors(angles)
                start_pos = vector.new(
                    eye_pos.x + (fwd.x * 30) + (right.x * 8) - (up.x * 10),
                    eye_pos.y + (fwd.y * 30) + (right.y * 8) - (up.y * 10),
                    eye_pos.z + (fwd.z * 30) + (right.z * 8) - (up.z * 10)
                )
            else
                local shooter = entity.get_by_index(player_idx)
                start_pos = shooter:get_eye_position()
            end

            if start_pos then
                table.insert(impacts, {
                    target_pos = vector.new(event:get_float("x"), event:get_float("y"), event:get_float("z")),
                    start_pos  = start_pos,
                    time       = os.clock(),
                    seed       = math.random(1, 9999),
                    mode       = mode
                })
            end
        end
    end
end


function on_paint()
    if not engine.is_in_game() then return end
    if #impacts == 0 then return end

    local now = os.clock()

    for i = #impacts, 1, -1 do
        local impact  = impacts[i]
        local elapsed = now - impact.time
        local c       = cfg[impact.mode]

        local max_life = math.max(c.tracer_duration, c.effect_duration)

        if elapsed > max_life or not c.enabled then
            table.remove(impacts, i)
        else
            local target_2d = get_screen_coords(impact.target_pos)
            local start_2d  = get_screen_coords(impact.start_pos)
            
            if target_2d and start_2d then
                if c.tracer_enabled and elapsed < c.tracer_duration then
                    draw_tracer(start_2d.x, start_2d.y, target_2d.x, target_2d.y, elapsed, impact.seed, c)
                end

                if c.effect_style > 0 and elapsed < c.effect_duration then
                    draw_effect(target_2d.x, target_2d.y, elapsed, c)
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────────
--  AUTO-SAVE ON SHUTDOWN
-- ──────────────────────────────────────────────────────────────

pcall(function()
    local _orig_shutdown = on_shutdown
    on_shutdown = function()
        save_config()
        if _orig_shutdown then _orig_shutdown() end
    end
end)

-- ──────────────────────────────────────────────────────────────
--  MENU
-- ──────────────────────────────────────────────────────────────

menu.add_main_tab("Impacts", function()
    imgui.text("Advanced 3D Impacts")
    imgui.separator()
    imgui.spacing()

    local changed, val
    changed, val = imgui.combo("Global Fade Curve", global_cfg.fade_style, FADE_STYLES)
    if changed then
        global_cfg.fade_style = val
        save_config()
    end

    changed, val = imgui.slider_int("Global Max Impacts", global_cfg.max_impacts, 8, 256)
    if changed then
        global_cfg.max_impacts = val
        save_config()
    end

    imgui.spacing()
    imgui.separator()
    imgui.spacing()

    changed, val = imgui.combo("Target Mode (Edit)", mode_idx, MODES)
    if changed then mode_idx = val end

    local current_mode_str = MODES[mode_idx + 1]
    local c = cfg[current_mode_str]

    imgui.spacing()
    changed, val = imgui.checkbox("Enable " .. current_mode_str .. " Impacts", c.enabled)
    if changed then
        c.enabled = val
        save_config()
    end

    imgui.spacing()
    if imgui.button("Save Config Now") then
        save_config()
    end

    if not c.enabled then return end 
    imgui.spacing()

    -- Tracer Box (Height increased to 330 to fit everything cleanly)
    if imgui.begin_child("TracerBox", 0, 330, true, 0) then
        imgui.text("Tracer Settings (" .. current_mode_str .. ")")
        imgui.separator()
        
        changed, val = imgui.checkbox("Show Tracer", c.tracer_enabled)
        if changed then c.tracer_enabled = val; save_config() end
        
        changed, val = imgui.combo("Style##tr", c.tracer_style, TRACER_STYLES)
        if changed then c.tracer_style = val; save_config() end
        
        changed, val = imgui.slider_float("Duration (s)##tr", c.tracer_duration, 0.05, 8.0)
        if changed then c.tracer_duration = val; save_config() end

        changed, val = imgui.slider_float("Thickness##tr", c.tracer_thickness, 1.0, 10.0)
        if changed then c.tracer_thickness = val; save_config() end
        
        imgui.spacing()
        imgui.text("Color (RGBA) & Rainbow:")
        
        changed, val = imgui.checkbox("Rainbow Mode##tr_rb", c.tracer_rainbow)
        if changed then c.tracer_rainbow = val; save_config() end

        changed, val = imgui.slider_float("Rainbow Speed##tr_rs", c.tracer_rspeed, 0.1, 10.0)
        if changed then c.tracer_rspeed = val; save_config() end

        changed, val = imgui.slider_float("R##tr", c.tracer_r, 0.0, 1.0)
        if changed then c.tracer_r = val; save_config() end
        
        changed, val = imgui.slider_float("G##tg", c.tracer_g, 0.0, 1.0)
        if changed then c.tracer_g = val; save_config() end
        
        changed, val = imgui.slider_float("B##tb", c.tracer_b, 0.0, 1.0)
        if changed then c.tracer_b = val; save_config() end
        
        changed, val = imgui.slider_float("A##ta", c.tracer_a, 0.0, 1.0)
        if changed then c.tracer_a = val; save_config() end

        imgui.end_child()
    end

    imgui.spacing()

    -- Effect Box (Height increased to 300 to fit everything cleanly)
    if imgui.begin_child("EffectBox", 0, 300, true, 0) then
        imgui.text("Impact Effect Settings (" .. current_mode_str .. ") ")
        imgui.separator()

        changed, val = imgui.combo("Effect##ef", c.effect_style, EFFECT_STYLES)
        if changed then c.effect_style = val; save_config() end

        changed, val = imgui.slider_float("Size##ef", c.effect_size, 4.0, 120.0)
        if changed then c.effect_size = val; save_config() end

        changed, val = imgui.slider_float("Duration (s)##ef", c.effect_duration, 0.05, 5.0)
        if changed then c.effect_duration = val; save_config() end

        imgui.spacing()
        imgui.text("Color (RGBA) & Rainbow:")

        changed, val = imgui.checkbox("Rainbow Mode##ef_rb", c.effect_rainbow)
        if changed then c.effect_rainbow = val; save_config() end

        changed, val = imgui.slider_float("Rainbow Speed##ef_rs", c.effect_rspeed, 0.1, 10.0)
        if changed then c.effect_rspeed = val; save_config() end

        changed, val = imgui.slider_float("R##er", c.effect_r, 0.0, 1.0)
        if changed then c.effect_r = val; save_config() end
        
        changed, val = imgui.slider_float("G##eg", c.effect_g, 0.0, 1.0)
        if changed then c.effect_g = val; save_config() end
        
        changed, val = imgui.slider_float("B##eb", c.effect_b, 0.0, 1.0)
        if changed then c.effect_b = val; save_config() end
        
        changed, val = imgui.slider_float("A##ea", c.effect_a, 0.0, 1.0)
        if changed then c.effect_a = val; save_config() end

        imgui.end_child()
    end
end)
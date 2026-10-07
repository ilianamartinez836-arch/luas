local ENABLE_BONES = false
local USE_CLASS_COLORS = false
local BOX_R, BOX_G, BOX_B = 0.68, 0.22, 0.22

local NETWORKED_HEALTH = {
    CTerrorPlayer = true, SurvivorBot = true,
    Boomer = true, Smoker = true, Hunter = true,
    Jockey = true, Charger = true, Spitter = true, Tank = true,
}

local UNNETWORKED_HEALTH = {
    Infected = true, Witch = true,
}

local BONE_COLOR = {
    CTerrorPlayer = { 0.31, 0.78, 1.0 }, SurvivorBot = { 0.31, 0.78, 1.0 },
    Boomer  = { 0.78, 0.31, 0.31 }, Smoker   = { 0.71, 0.39, 0.86 },
    Hunter  = { 0.86, 0.39, 0.39 }, Jockey   = { 0.86, 0.71, 0.24 },
    Charger = { 0.71, 0.24, 0.24 }, Spitter  = { 0.39, 0.86, 0.39 },
    Tank    = { 0.68, 0.22, 0.22 }, Infected = { 0.63, 0.63, 0.63 },
    Witch   = { 0.86, 0.47, 0.86 },
}

local function is_target(cls)
    return NETWORKED_HEALTH[cls] or UNNETWORKED_HEALTH[cls]
end

local function check_alive(p, cls)
    local sf = p:GetSolidFlags()
    if sf == nil or bit.band(sf, 4) ~= 0 then return false end
    if UNNETWORKED_HEALTH[cls] then return true end
    local hp = p:GetHealth()
    return hp ~= nil and hp > 0
end

function on_end_scene()
    if not EngineClient.IsInGame() then return end

    local vw, vh = imgui.GetDisplaySize()
    local sw, sh = EngineClient.GetScreenSize()
    local sx = vw / sw
    local sy = vh / sh

    local max_ents  = ClientEntityList.GetMaxEntities()
    local local_idx = EngineClient.GetLocalPlayer()

    local target_num = 0

    for i = 1, max_ents do
        if i == local_idx then goto continue end

        local ent = ClientEntityList.GetClientEntity(i)
        if not (ent and ent:is_valid() and not ent:is_dormant()) then goto continue end

        local cls = ent:get_class_name()
        if not is_target(cls) then goto continue end

        local p = ent:as("CTerrorPlayer")
        if not p then goto continue end
        if not check_alive(p, cls) then goto continue end

        local model = p:GetModel()
        if not model then goto continue end

        local hdr = ModelInfo.GetStudiomodel(model)
        if not hdr then goto continue end

        local bones = p:setup_bones()
        if not bones then goto continue end

        local cr, cg, cb = BOX_R, BOX_G, BOX_B
        if USE_CLASS_COLORS then
            local col = BONE_COLOR[cls] or { 1.0, 1.0, 1.0 }
            cr, cg, cb = col[1], col[2], col[3]
        end
        
        local num = hdr:numbones()
        local min_x, min_y =  math.huge,  math.huge
        local max_x, max_y = -math.huge, -math.huge
        local has_pts = false

        for b = 0, num - 1 do
            local bone = hdr:GetBone(b)
            if not bone then goto next_bone end
            if bit.band(bone:flags(), 256) == 0 then goto next_bone end

            local wpos = client.get_bone_pos(bones, b)
            if not wpos then goto next_bone end

            local ret1, sp1 = DebugOverlay.ScreenPosition(wpos)
            if ret1 ~= 0 then goto next_bone end

            local ix, iy = sp1.x * sx, sp1.y * sy

            if ix < min_x then min_x = ix end
            if ix > max_x then max_x = ix end
            if iy < min_y then min_y = iy end
            if iy > max_y then max_y = iy end
            has_pts = true

            if ENABLE_BONES then
                local par = bone:parent()
                if par ~= -1 then
                    local wpar = client.get_bone_pos(bones, par)
                    if wpar then
                        local ret2, sp2 = DebugOverlay.ScreenPosition(wpar)
                        if ret2 == 0 then
                            imgui.fg_draw_line(ix, iy, sp2.x * sx, sp2.y * sy, cr, cg, cb, 0.55, 1.0)
                        end
                    end
                end
            end

            ::next_bone::
        end

        if not has_pts then goto continue end

     --   target_num = target_num + 1
      --  local pad = 8
      --  local bx1 = min_x - pad
      --  local by1 = min_y - pad
      --  local bx2 = max_x + pad
      --  local by2 = max_y + pad
        target_num = target_num + 1
        -- The fixed padding of 8 pixels was keeping the box large at a distance.
        -- This changes it to dynamically scale down based on the player's screen height.
        --before it was like, ffucked as shit
        local raw_h = max_y - min_y
        local pad = math.max(1, math.min(8, math.floor(raw_h * 0.03)))
        local bx1 = min_x - pad
        local by1 = min_y - pad
        local bx2 = max_x + pad
        local by2 = max_y + pad
        imgui.fg_draw_rect(bx1, by1, bx2, by2, BOX_R, BOX_G, BOX_B, 0.55, 1.0, 0.0)

        local label   = string.format("Look_%02d", target_num)
        local box_h   = by2 - by1
        local font_sz = math.max(6, math.min(13, math.floor(box_h * 0.055)))
        local lbl_pad = math.max(1, math.floor(font_sz * 0.20))
        local lbl_h   = font_sz + lbl_pad * 2
        local lbl_w   = #label * (font_sz * 0.55) + lbl_pad * 2

        imgui.fg_draw_rect_filled(bx1, by1 - lbl_h, bx1 + lbl_w, by1, BOX_R, BOX_G, BOX_B, 0.55, 0.0)
        imgui.fg_draw_text(bx1 + lbl_pad, by1 - lbl_h + lbl_pad, 1.0, 1.0, 1.0, 1.0, label, font_sz)

        if NETWORKED_HEALTH[cls] then
            local hp     = p:GetHealth() or 0
            local max_hp = p:GetMaxHealth() or 100
            if max_hp <= 0 then max_hp = 100 end
            local frac   = math.max(0, math.min(1, hp / max_hp))
            local bar_h  = math.max(1, math.min(3, math.floor(box_h * 0.008)))
            local bar_w  = bx2 - bx1

            imgui.fg_draw_rect_filled(bx1, by2 + 2, bx2, by2 + 2 + bar_h, 0.06, 0.06, 0.06, 0.6, 0.0)
            imgui.fg_draw_rect_filled(bx1, by2 + 2, bx1 + bar_w * frac, by2 + 2 + bar_h, 0.75, 0.65, 0.85, 0.7, 0.0)
        end

        ::continue::
    end
end

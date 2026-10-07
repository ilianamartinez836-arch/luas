-- @author: Hiraeth
-- @created: 26.07 22:03
-- Echidna Script
local ffi = require("ffi")

local CFG_PATH = "C:\\Echidna-L4d2\\Scripts\\mute_cfg.lua"

local cfg = {
    enabled = true,
    muted   = {},
}

local function cfg_save()
    local f = io.open(CFG_PATH, "w")
    if not f then return end
    f:write("return {\n")
    f:write(("  enabled = %s,\n"):format(tostring(cfg.enabled)))
    f:write("  muted = {\n")
    for k, v in pairs(cfg.muted) do
        f:write(("    [%q] = { name=%q, enabled=%s },\n")
            :format(k, v.name or "?", tostring(v.enabled ~= false)))
    end
    f:write("  },\n}\n")
    f:close()
end

do
    local ok, data = pcall(dofile, CFG_PATH)
    if ok and type(data) == "table" then
        if type(data.enabled) == "boolean" then cfg.enabled = data.enabled end
        if type(data.muted)   == "table"   then
            for k, v in pairs(data.muted) do
                if type(k) == "string" and type(v) == "table" then
                    cfg.muted[k] = v
                end
            end
        end
    end
end

local mute_rt = {}

local function rebuild()
    mute_rt = {}
    for k, v in pairs(cfg.muted) do
        local n = tonumber(k)
        if n and v.enabled ~= false then
            mute_rt[n] = true
        end
    end
end
rebuild()

local cp_addr = memory.find_pattern("client.dll",
    "55 8B EC B8 E4 10 00 00 E8 ? ? ? ? A1 ? ? ? ? 33 C5 89 45 FC 8B 4D 14")
assert(cp_addr, "[Mute] ChatPrintF pattern not found")

local chat_hook = hooks.create(cp_addr,
    "int(__cdecl*)(void*, int, int, const char*, const char*)",
    function(orig, ctx, player_ref, flags, fmt, msg)
        if not cfg.enabled or player_ref == 0 then
            return orig(ctx, player_ref, flags, fmt, msg)
        end

        local fid = nil

        local ok, info = pcall(EngineClient.GetPlayerInfo, player_ref)
        if ok and info then
            fid = info:friendsid()
        else
            local ent = EngineClient.GetPlayerForUserID(player_ref)
            if ent and ent > 0 then
                local ok2, info2 = pcall(EngineClient.GetPlayerInfo, ent)
                if ok2 and info2 then fid = info2:friendsid() end
            end
        end

        if fid and mute_rt[fid] then
            return 0
        end

        return orig(ctx, player_ref, flags, fmt, msg)
    end)

assert(chat_hook, "[Mute] hook failed")

local function get_players()
    local out = {}
    local me  = EngineClient.GetLocalPlayer()
    for i = 1, 32 do
        local ok, info = pcall(EngineClient.GetPlayerInfo, i)
        if ok and info then
            local fid = info:friendsid()
            if fid and fid ~= 0 then
                out[#out + 1] = {
                    ent   = i,
                    name  = info:name()   or "?",
                    fid   = fid,
                    uid   = info:userid() or 0,
                    is_me = (i == me),
                }
            end
        end
    end
    return out
end

menu.add_main_tab("M", "ChatMute", function()

    imgui.PushStyleColor(imgui.ImGuiCol_ChildBg, 0.06, 0.08, 0.16, 0.93)
    if imgui.BeginChild("##cm_hdr", 0, 40, true) then
        local prev  = cfg.enabled
        cfg.enabled = select(1, imgui.Checkbox("Mute Active", cfg.enabled))
        if cfg.enabled ~= prev then cfg_save() end
        imgui.SameLine()
        imgui.TextColored(0.38, 0.42, 0.60, 1.0,
            ("  %d muted"):format((function()
                local c = 0; for _ in pairs(cfg.muted) do c = c + 1 end; return c
            end)()))
        imgui.EndChild()
    end
    imgui.PopStyleColor()

    imgui.Spacing()
    imgui.TextColored(0.45, 0.50, 0.65, 1.0, "Players in server:")
    imgui.Spacing()

    local players = get_players()

    imgui.PushStyleColor(imgui.ImGuiCol_ChildBg, 0.04, 0.05, 0.10, 0.88)
    if imgui.BeginChild("##cm_list", 0, math.max(#players * 56, 40), false) then

        if #players == 0 then
            imgui.TextColored(0.40, 0.40, 0.50, 1.0, "Not connected to a server.")
        else
            for _, p in ipairs(players) do
                if not p.is_me then
                    local k        = tostring(p.fid)
                    local entry    = cfg.muted[k]
                    local is_muted = entry ~= nil and entry.enabled ~= false

                    imgui.PushStyleColor(imgui.ImGuiCol_ChildBg,
                        is_muted and 0.20 or 0.06,
                        is_muted and 0.06 or 0.07,
                        is_muted and 0.06 or 0.14,
                        0.90)

                    if imgui.BeginChild("##cm_row_" .. k, 0, 50, true) then
                        local rx, ry = imgui.GetCursorScreenPos()

                        imgui.SetCursorScreenPos(rx + 6, ry + 5)
                        local nc = is_muted
                            and {1.0, 0.36, 0.36, 1.0}
                            or  {0.85, 0.92, 1.0,  1.0}
                        imgui.TextColored(nc[1], nc[2], nc[3], nc[4],
                            is_muted and ("[MUTED]  " .. p.name) or p.name)

                        imgui.SetCursorScreenPos(rx + 6, ry + 25)
                        imgui.TextColored(0.34, 0.40, 0.58, 1.0,
                            ("steamid: %d  |  uid: %d  |  ent: %d")
                            :format(p.fid, p.uid, p.ent))

                        imgui.SetCursorScreenPos(rx + 310, ry + 13)
                        if is_muted then
                            imgui.PushStyleColor(imgui.ImGuiCol_Button, 0.30, 0.08, 0.08, 0.90)
                            if imgui.SmallButton("Unmute##" .. k) then
                                cfg.muted[k] = nil
                                rebuild(); cfg_save()
                            end
                            imgui.PopStyleColor()
                        else
                            imgui.PushStyleColor(imgui.ImGuiCol_Button, 0.08, 0.10, 0.30, 0.90)
                            if imgui.SmallButton("Mute##" .. k) then
                                cfg.muted[k] = { name = p.name, enabled = true }
                                rebuild(); cfg_save()
                            end
                            imgui.PopStyleColor()
                        end

                        imgui.EndChild()
                    end
                    imgui.PopStyleColor()
                    imgui.Spacing()
                end
            end
        end
        imgui.EndChild()
    end
    imgui.PopStyleColor()

    local offline = {}
    for k, v in pairs(cfg.muted) do
        local found = false
        for _, p in ipairs(players) do
            if tostring(p.fid) == k then found = true; break end
        end
        if not found then offline[k] = v end
    end

    if next(offline) then
        imgui.Spacing()
        imgui.TextColored(0.45, 0.50, 0.65, 1.0, "Saved mutes (not in server):")
        imgui.Spacing()

        imgui.PushStyleColor(imgui.ImGuiCol_ChildBg, 0.04, 0.05, 0.10, 0.88)
        if imgui.BeginChild("##cm_off", 0, 0, false) then
            for k, v in pairs(offline) do
                imgui.PushStyleColor(imgui.ImGuiCol_ChildBg, 0.14, 0.05, 0.05, 0.88)
                if imgui.BeginChild("##off_" .. k, 0, 36, true) then
                    local ox, oy = imgui.GetCursorScreenPos()

                    imgui.SetCursorScreenPos(ox + 6, oy + 7)
                    imgui.TextColored(0.72, 0.32, 0.32, 1.0,
                        (v.name or "?") .. "   [" .. k .. "]")

                    imgui.SetCursorScreenPos(ox + 310, oy + 7)
                    imgui.PushStyleColor(imgui.ImGuiCol_Button, 0.30, 0.08, 0.08, 0.90)
                    if imgui.SmallButton("Remove##off_" .. k) then
                        cfg.muted[k] = nil
                        rebuild(); cfg_save()
                    end
                    imgui.PopStyleColor()
                    imgui.EndChild()
                end
                imgui.PopStyleColor()
                imgui.Spacing()
            end
            imgui.EndChild()
        end
        imgui.PopStyleColor()
    end
end)

function on_unload()
    if chat_hook then chat_hook:destroy(); chat_hook = nil end
    memory.restore_all()
end

--DLL Internal tested only
--Simple anime bullshit, optimized with cache thumbnails, subtitles and focused on .mkv files 
--Page used for Content and rezero:
--https://beatrice-raws.org/
--you can update path like this:
--local base_dir = [[F:! ! ! !\Movies[Beatrice-Raws] Re Zero - Season 2 - Starting Life in Another World [BDRip 1920x1080 HEVC TrueHD]]]
--To the proper one, same goes for:
--local function get_ep_path(ep)
--    local path = string.format("%s[Beatrice-Raws] ReZero kara Hajimeru Isekai Seikatsu 2nd Season %d [BDRip 1920x1080 HEVC TrueHD].mkv", base_dir, ep)
--    return path:gsub("\\", "/")
--end
--local function get_sub_path(ep, lang)
--    local path = string.format("%sSub\\%s\\[Beatrice-Raws] ReZero kara Hajimeru Isekai Seikatsu 2nd Season %d [BDRip 1920x1080 HEVC TrueHD].ass", base_dir, lang, ep)
--    return path:gsub("\\", "/")
--end
--
--Dependencies:
--anime_player.dll
--libmpv-2.dll
--Thumbs content will play a random frame from the video and then save it as png for thumbnails
--Changing the resolution to your taste is recommended, current config is meant for playing + watching anime so it has little to no effect on gameplay 
--Reloading subtitles just go back and play the video again, as simple as that
-- @author: Capella
-- @created: 30.05 10:08
-- Echidna Script
local ffi = require("ffi")
ffi.cdef[[
    int   SetDllDirectoryA(const char* lpPathName);
    bool  init_video_player (void* dev, const char* path, int rw, int rh);
    bool  is_frame_ready    (void);
    void  update_video_frame(void);
    void* get_video_texture_ptr(void);
    void  shutdown_video_player(void);
    void    player_seek             (double s);
    void    player_seek_relative    (double s);
    void    player_toggle_pause     (void);
    void    player_set_pause        (bool p);
    double  player_get_time         (void);
    double  player_get_duration     (void);
    bool    player_is_paused        (void);
    int     player_get_chapter      (void);
    int     player_get_chapter_count(void);
    void    player_set_chapter      (int idx);
    int     player_get_track_count  (void);
    int     player_get_volume       (void);
    void    player_set_volume       (int vol);
    const char* player_get_property_string  (const char* name);
    void        player_set_property_string  (const char* name, const char* val);
    void        player_command_string       (const char* cmd);
]]
local BASE = "C:\\Echidna-L4d2\\"
ffi.C.SetDllDirectoryA(BASE)
local player = ffi.load(BASE .. "anime_player.dll")
local VW, VH        = 640, 360
local WW, WH        = 968, 598
local FRAME_INTERVAL = 1 / 25
local base_dir = [[F:\! ! ! !\Movies\[Beatrice-Raws] Re Zero - Season 2 - Starting Life in Another World [BDRip 1920x1080 HEVC TrueHD]\]]
local anime_path = ""
local inited        = false
local last_tex      = nil
local is_seeking    = false
local seek_val      = 0.0
local vol           = 100
local chapters      = {}
local sub_tr        = {}
local aud_tr        = {}
local meta_loaded   = false
local view_mode      = "dashboard"
local current_ep     = 14
local selected_sub   = "None"
local locked         = false
local keep_aspect    = true
local last_frame_t   = 0
local sub_languages = {
    "Arabic", "English", "French", "German", "Italian", "Portuguese", "Russian", "Spanish", "Spanish (Latin American)"
}
local THUMB_DIR      = BASE .. "thumbs\\"
local THUMB_SEEK     = 45.0
local THUMB_W, THUMB_H = 320, 180
local thumb_tex    = {}
local thumb_queue  = {}
local thumb_queued = false
local thumb_active = nil
local thumb_phase  = 0
local thumb_frames = 0
local function get_ep_path(ep)
    local path = string.format("%s[Beatrice-Raws] ReZero kara Hajimeru Isekai Seikatsu 2nd Season %d [BDRip 1920x1080 HEVC TrueHD].mkv", base_dir, ep)
    return path:gsub("\\", "/")
end
local function get_sub_path(ep, lang)
    local path = string.format("%sSub\\%s\\[Beatrice-Raws] ReZero kara Hajimeru Isekai Seikatsu 2nd Season %d [BDRip 1920x1080 HEVC TrueHD].ass", base_dir, lang, ep)
    return path:gsub("\\", "/")
end
local function IC(r, g, b, a)
    a = a or 255
    return { r / 255, g / 255, b / 255, a / 255 }
end
local CG   = IC( 88,178,118)
local CGH  = IC(110,210,148)
local CGL  = IC( 50,110, 72, 180)
local CGold= IC(200,165, 70)
local CPN  = IC( 13, 13, 21, 250)
local CBR  = IC( 38, 38, 54)
local CWH  = IC(255,255,255)
local CTX  = IC(225,225,235)
local CTD  = IC(140,140,156, 200)
local CBL  = IC(  8,  8, 14)
local CDB  = IC( 26, 26, 26)
local CDA  = IC( 13, 13, 13)
local CDF  = IC( 51, 51, 51)
local CTB  = IC(  0, 191, 255)
local function pstr(k)
    local p = player.player_get_property_string(k)
    return p ~= nil and ffi.string(p) or ""
end
local function ftime(s)
    s = math.max(0, math.floor(s + 0.5))
    local h = math.floor(s / 3600); s = s - h * 3600
    local m = math.floor(s /   60); s = s - m * 60
    return h > 0 and ("%d:%02d:%02d"):format(h, m, s)
               or   ("%d:%02d"):format(m, s)
end
local function thumb_file(ep)
    return string.format("%sep%02d.png", THUMB_DIR, ep)
end
local function queue_thumbs()
    if thumb_queued then return end
    thumb_queued = true
    os.execute('if not exist "' .. THUMB_DIR .. '" mkdir "' .. THUMB_DIR .. '"')
    for ep = 14, 25 do
        local f = io.open(thumb_file(ep), "rb")
        if f then
            f:close()
            if client and client.load_texture then
                thumb_tex[ep] = client.load_texture(thumb_file(ep))
            end
        else
            table.insert(thumb_queue, ep)
        end
    end
end
local function process_thumb_gen()
    if thumb_active then
        if player.is_frame_ready() then player.update_video_frame() end
        thumb_frames = thumb_frames + 1
        if thumb_phase == 1 and thumb_frames >= 45 then
            player.player_seek(THUMB_SEEK)
            thumb_phase = 2; thumb_frames = 0
        elseif thumb_phase == 2 and thumb_frames >= 90 then
            local f = thumb_file(thumb_active):gsub("\\", "/")
            player.player_command_string("screenshot-to-file " .. f .. " video")
            thumb_phase = 3; thumb_frames = 0
        elseif thumb_phase == 3 and thumb_frames >= 20 then
            local ep = thumb_active
            local fcheck = io.open(thumb_file(ep), "rb")
            if fcheck then
                fcheck:close()
                if client and client.load_texture then
                    thumb_tex[ep] = client.load_texture(thumb_file(ep))
                end
            else
                thumb_tex[ep] = false
            end
            player.shutdown_video_player()
            thumb_active = nil; thumb_phase = 0; thumb_frames = 0
        end
        return
    end
    if #thumb_queue == 0 then return end
    local ep  = table.remove(thumb_queue, 1)
    local dev = client.get_d3d9_device()
    if not dev then table.insert(thumb_queue, 1, ep); return end
    if player.init_video_player(dev, get_ep_path(ep), THUMB_W, THUMB_H) then
        thumb_active = ep; thumb_phase = 1; thumb_frames = 0
    else
        thumb_tex[ep] = false
    end
end
local function start()
    local dev = client.get_d3d9_device()
    if not dev then return end
    if player.init_video_player(dev, anime_path, VW, VH) then
        inited = true; meta_loaded = false
        chapters = {}; sub_tr = {}; aud_tr = {}
        vol = player.player_get_volume()
        print("[Crusch-AnimeMedia] ready")
    else
        print("[Crusch-AnimeMedia] init_video_player failed")
    end
end
local function change_episode(ep)
    if ep < 14 or ep > 25 then return end
    if thumb_active then
        player.shutdown_video_player()
        table.insert(thumb_queue, 1, thumb_active)
        thumb_active = nil; thumb_phase = 0; thumb_frames = 0
    end
    current_ep = ep
    anime_path = get_ep_path(ep)
    inited = false
    start()
    if selected_sub ~= "None" then
        local path = get_sub_path(current_ep, selected_sub)
        player.player_set_property_string("sub-files", path)
        player.player_set_property_string("sid", "ext1")
    end
end
function on_key_down(key)
    if not inited or view_mode ~= "player" or not client.is_menu_open() then return end
    if key == 32 then
        if not locked then player.player_toggle_pause() end
    elseif key == 37 then
        player.player_seek_relative(-10)
    elseif key == 39 then
        player.player_seek_relative(10)
    elseif key == 38 then
        vol = math.min(150, vol + 5)
        player.player_set_volume(vol)
    elseif key == 40 then
        vol = math.max(0, vol - 5)
        player.player_set_volume(vol)
    end
end
function on_key_up(key)
end
local function load_meta()
    if meta_loaded or player.player_get_duration() <= 0 then return end
    local nc = player.player_get_chapter_count()
    for i = 0, nc - 1 do
        local t  = tonumber(pstr("chapter-list/"..i.."/time")) or 0
        local tl = pstr("chapter-list/"..i.."/title")
        table.insert(chapters, { title = tl ~= "" and tl or ("Ch "..(i+1)),
                                 time  = t, idx = i })
    end
    local nt = player.player_get_track_count()
    for i = 0, nt - 1 do
        local tp = pstr("track-list/"..i.."/type")
        local id = tonumber(pstr("track-list/"..i.."/id")) or 0
        local lg = pstr("track-list/"..i.."/lang")
        local tt = pstr("track-list/"..i.."/title")
        local sl = pstr("track-list/"..i.."/selected") == "yes"
        local lb = (tt ~= "" and tt) or (lg ~= "" and lg) or ("Track "..id)
        if     tp == "sub"   then table.insert(sub_tr, {id=id,label=lb,sel=sl})
        elseif tp == "audio" then table.insert(aud_tr, {id=id,label=lb,sel=sl})
        end
    end
    meta_loaded = true
end
local function refresh_sel()
    local nt = player.player_get_track_count()
    for i = 0, nt - 1 do
        local tp = pstr("track-list/"..i.."/type")
        local id = tonumber(pstr("track-list/"..i.."/id")) or 0
        local sl = pstr("track-list/"..i.."/selected") == "yes"
        local tbl = (tp == "sub" and sub_tr) or (tp == "audio" and aud_tr)
        if tbl then
            for _, tr in ipairs(tbl) do
                if tr.id == id then tr.sel = sl end
            end
        end
    end
end
function on_end_scene()
    local menu_open = client.is_menu_open()
    if view_mode == "dashboard" then
        queue_thumbs()
        if menu_open then
            process_thumb_gen()
        else
            return
        end
    else
        if not inited then start(); return end
        local now = client.get_time()
        if (now - last_frame_t) >= FRAME_INTERVAL then
            if player.is_frame_ready() then
                player.update_video_frame()
                local raw = player.get_video_texture_ptr()
                last_tex  = (raw ~= nil) and client.tex_from_ptr(raw) or nil
            end
            last_frame_t = now
        end
        if not meta_loaded then load_meta() end
    end
    imgui.SetNextWindowSize(WW, WH, 4)
    local wflags = 0
    if locked or not menu_open then
        wflags = wflags + 0x20
        wflags = wflags + 0x40
    end
    if not menu_open then
        wflags = wflags + 0x01
        wflags = wflags + 0x08
    end
    if not imgui.Begin("Crusch-AnimeMedia", nil, wflags) then imgui.End(); return end
    local dl = imgui.get_window_draw_list()
    local wx, wy = imgui.GetWindowPos()
    local ww, wh = imgui.GetWindowSize()
    local fh     = menu_open and imgui.GetFrameHeight() or 0
    dl:add_rect_filled(wx, wy + fh, wx + ww, wy + wh, CPN[1], CPN[2], CPN[3], CPN[4])
    if view_mode == "dashboard" then
        imgui.SetCursorScreenPos(wx + 20, wy + fh + 15)
        imgui.TextColored(CGold[1], CGold[2], CGold[3], CGold[4], "SELECT EPISODE")
        imgui.Separator()
        imgui.SetCursorScreenPos(wx + 20, wy + fh + 45)
        imgui.BeginChild("##ep_grid", ww - 40, wh - fh - 65, false)
        local start_x, start_y = imgui.GetCursorScreenPos()
        local columns = 3
        local card_w = math.floor((ww - 80) / columns)
        local card_h = 135
        local gap_x  = 20
        local gap_y  = 20
        for idx = 0, 11 do
            local ep = 14 + idx
            imgui.PushID(ep)
            local col = idx % columns
            local row = math.floor(idx / columns)
            local cx  = start_x + col * (card_w + gap_x)
            local cy  = start_y + row * (card_h + gap_y)
     local info_h = 28
            local img_h  = (card_h - 25) - info_h
            dl:add_rect_filled(cx, cy, cx + card_w, cy + card_h - 25, CDB[1], CDB[2], CDB[3], CDB[4], 6)
            local tex = thumb_tex[ep]
            if tex and tex ~= false then
                dl:add_image_rounded(tex, cx + 1, cy + 1, cx + card_w - 1, cy + img_h, 0, 0, 1, 1, 1, 1, 1, 1, 4)
            else
                dl:add_rect_filled(cx + 1, cy + 1, cx + card_w - 1, cy + img_h,
                    CDA[1], CDA[2], CDA[3], CDA[4], 0)
                local status = (thumb_active == ep) and "generating..." or "..."
                dl:add_text(cx + 8, cy + img_h * 0.5 - 6,
                    CTD[1], CTD[2], CTD[3], CTD[4], status)
            end
            dl:add_rect_filled(cx, cy + img_h, cx + card_w, cy + card_h - 25,
                CDA[1], CDA[2], CDA[3], CDA[4], 0)
            dl:add_rect(cx, cy, cx + card_w, cy + card_h - 25, CDF[1], CDF[2], CDF[3], CDF[4], 6)
            dl:add_text(cx + 8, cy + img_h + 6,
                CTB[1], CTB[2], CTB[3], CTB[4], string.format("RE:ZERO S2  Ep %d", ep))
            dl:add_text(cx + card_w - 50, cy + img_h + 6,
                CTD[1], CTD[2], CTD[3], CTD[4], "▶ PLAY")
            imgui.SetCursorScreenPos(cx, cy)
            if imgui.Selectable("##click" .. ep, false, 0, card_w, card_h - 25) then
                change_episode(ep)
                view_mode = "player"
            end
            imgui.SetCursorScreenPos(cx + 2, cy + card_h - 20)
            imgui.TextDisabled(string.format("Season 2 · 1080p BD · Ep %d", ep))
            imgui.PopID()
        end
        imgui.EndChild()
        imgui.End()
        return
    end
    if menu_open then
        imgui.SetCursorScreenPos(wx + 14, wy + fh + 4)
        if imgui.Button("< Dashboard", 90, 22) then
            player.shutdown_video_player()
            inited   = false
            last_tex = nil
            view_mode = "dashboard"
        end
        imgui.SetCursorScreenPos(wx + 112, wy + fh + 4)
        if imgui.Button(locked and "[ LOCKED ]" or "[  LOCK  ]", 80, 22) then
            locked = not locked
        end
        imgui.SetCursorScreenPos(wx + 200, wy + fh + 4)
        if imgui.Button(keep_aspect and "AR: ON" or "AR:OFF", 54, 22) then
            keep_aspect = not keep_aspect
        end
    end
    local CTRL_H  = menu_open and 88 or 0
    local top_off = menu_open and (fh + 32) or 0
    local vy      = wy + top_off
    local avail_w = ww - (menu_open and 28 or 0)
    local avail_h = wh - top_off - CTRL_H
    local disp_w, disp_h
    if keep_aspect then
        local scale = math.min(avail_w / VW, avail_h / VH)
        disp_w = math.floor(VW * scale)
        disp_h = math.floor(VH * scale)
    else
        disp_w = avail_w
        disp_h = avail_h
    end
    local vx = wx + math.floor((ww - disp_w) * 0.5)
    local vb = vy + disp_h
    if last_tex then
        dl:add_image(last_tex, vx, vy, vx + disp_w, vb)
    else
        dl:add_rect_filled(vx, vy, vx + disp_w, vb, CBL[1], CBL[2], CBL[3], CBL[4], 3)
        imgui.SetCursorScreenPos(vx + disp_w * 0.5 - 36, vy + disp_h * 0.5 - 8)
        imgui.TextDisabled("Buffering...")
    end
    if menu_open then
        dl:add_rect_filled(wx, vb + 5, wx + ww, vb + 6, CGL[1], CGL[2], CGL[3], CGL[4])
    end
    if menu_open then
    local dur   = player.player_get_duration()
    local cur   = is_seeking and seek_val or player.player_get_time()
    local prog  = (dur > 0) and math.max(0, math.min(1, cur / dur)) or 0
    local sk_x  = wx + 14
    local sk_y  = vb + 14
    local sk_w  = ww - 28
    local sk_h  = 5
    dl:add_rect_filled(sk_x, sk_y, sk_x + sk_w, sk_y + sk_h, CBR[1], CBR[2], CBR[3], CBR[4], sk_h)
    if prog > 0 then
        dl:add_rect_filled(sk_x, sk_y, sk_x + sk_w * prog, sk_y + sk_h, CG[1], CG[2], CG[3], CG[4], sk_h)
    end
    dl:add_circle_filled(sk_x + sk_w * prog, sk_y + sk_h * 0.5, 7, CWH[1], CWH[2], CWH[3], CWH[4], 14)
    imgui.SetCursorScreenPos(sk_x, sk_y - 6)
    if locked then
        imgui.Dummy(sk_w, sk_h + 12)
    else
        imgui.InvisibleButton("##seek", sk_w, sk_h + 12)
        if imgui.IsItemActive() then
            local mx, _ = imgui.GetMousePos()
            seek_val    = math.max(0, math.min(1, (mx - sk_x) / sk_w)) * dur
            is_seeking  = true
        end
        if is_seeking and not imgui.IsMouseDown(0) then
            player.player_seek(seek_val)
            is_seeking = false
        end
    end
    local tl_y = sk_y + sk_h + 5
    imgui.SetCursorScreenPos(sk_x, tl_y)
    imgui.TextDisabled(ftime(cur))
    local dur_s = ftime(dur)
    imgui.SetCursorScreenPos(sk_x + sk_w - #dur_s * 6, tl_y)
    imgui.TextDisabled(dur_s)
    local btn_y = tl_y + 18
    local mid   = wx + math.floor(ww * 0.5)
    local bh    = 22
    local function btn(label, ox, bw, fn)
        imgui.SetCursorScreenPos(mid + ox, btn_y)
        if imgui.Button(label, bw, bh) then fn() end
    end
    btn("|<",  -185, 32, function()
        player.player_set_chapter(math.max(0, player.player_get_chapter() - 1))
    end)
    btn("-30", -148, 38, function() player.player_seek_relative(-30) end)
    btn("-10", -105, 38, function() player.player_seek_relative(-10) end)
    imgui.SetCursorScreenPos(mid - 62, btn_y)
    local plbl = player.player_is_paused() and "   >   " or " || "
    if imgui.Button(plbl, 48, bh) and not locked then
        player.player_toggle_pause()
    end
    btn("+10",  19, 38, function() player.player_seek_relative(10) end)
    btn("+30",  62, 38, function() player.player_seek_relative(30) end)
    btn(">|",  105, 32, function()
        local cc = player.player_get_chapter_count()
        local ch = player.player_get_chapter()
        if ch < cc - 1 then player.player_set_chapter(ch + 1) end
    end)
    imgui.SetCursorScreenPos(wx + 14, btn_y)
    if imgui.Button("CC", 32, bh)  then imgui.OpenPopup("##subs") end
    imgui.SetCursorScreenPos(wx + 52, btn_y)
    if imgui.Button("AU", 32, bh)  then imgui.OpenPopup("##auds") end
    imgui.SetCursorScreenPos(wx + 90, btn_y)
    if imgui.Button("CH", 32, bh)  then imgui.OpenPopup("##chs")  end
    imgui.SetCursorScreenPos(wx + 132, btn_y)
    if imgui.Button("EP-", 32, bh) then
        if current_ep > 14 then change_episode(current_ep - 1) end
    end
    imgui.SetCursorScreenPos(wx + 168, btn_y)
    if imgui.Button("EP+", 32, bh) then
        if current_ep < 25 then change_episode(current_ep + 1) end
    end
    imgui.SetCursorScreenPos(wx + ww - 152, btn_y)
    imgui.TextDisabled(string.format("VOL %d%%", vol))
    imgui.SetCursorScreenPos(wx + ww - 92, btn_y)
    imgui.SetNextItemWidth(72)
    local nv = imgui.SliderInt("##vol", vol, 0, 150)
    if type(nv) == "number" and nv ~= vol then
        vol = nv; player.player_set_volume(vol)
    end
    if imgui.BeginPopup("##chs") then
        imgui.Text("Chapters")
        imgui.Separator()
        local cur_ch = player.player_get_chapter()
        for _, ch in ipairs(chapters) do
            local label = string.format("[%s]  %s", ftime(ch.time), ch.title)
            if imgui.Selectable(label, ch.idx == cur_ch) then
                player.player_set_chapter(ch.idx)
                imgui.CloseCurrentPopup()
            end
        end
        if #chapters == 0 then imgui.TextDisabled("(no chapters)") end
        imgui.EndPopup()
    end
    if imgui.BeginPopup("##subs") then
        imgui.Text("External Subtitles (.ass)")
        imgui.Separator()
        if imgui.Selectable("[ Off ]", selected_sub == "None") then
            player.player_set_property_string("sid", "no")
            selected_sub = "None"
            imgui.CloseCurrentPopup()
        end
        for _, lang in ipairs(sub_languages) do
            if imgui.Selectable(lang, selected_sub == lang) then
                selected_sub = lang
                local path = get_sub_path(current_ep, lang)
                player.player_set_property_string("sub-files", path)
                player.player_set_property_string("sid", "ext1")
                imgui.CloseCurrentPopup()
            end
        end
        imgui.EndPopup()
    end
    if imgui.BeginPopup("##auds") then
        imgui.Text("Audio Tracks")
        imgui.Separator()
        for _, tr in ipairs(aud_tr) do
            if imgui.Selectable(tr.label, tr.sel) then
                player.player_set_property_string("aid", tostring(tr.id))
                refresh_sel()
                imgui.CloseCurrentPopup()
            end
        end
        if #aud_tr == 0 then imgui.TextDisabled("(none)") end
        imgui.EndPopup()
    end
    imgui.SetCursorScreenPos(wx, btn_y + bh + 6)
    imgui.Dummy(1, 1)
    end
    imgui.End()
end
function on_unload()
    if inited or thumb_active then
        player.shutdown_video_player()
    end
    inited       = false
    last_tex     = nil
    thumb_active = nil
end

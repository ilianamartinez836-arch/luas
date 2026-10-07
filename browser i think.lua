-- @author: Capella
-- @created: 30.05 10:08
-- Echidna Script
--DLL Internal tested only
--browser beta (no cache or main input implemented)--
--Dependencies:
--C:\Echidna-L4d2
--browser.dll
--WebView2Loader.dll
--Optimization will come after update of the main cheat
local ffi = require("ffi")
ffi.cdef[[
    int  SetDllDirectoryA(const char* p);
    bool init_browser         (void* dev, const char* url, int w, int h);
    bool browser_is_frame_ready();
    void browser_update_frame ();
    void* browser_get_texture ();
    void browser_navigate     (const char* url);
    void browser_back         ();
    void browser_forward      ();
    void browser_reload       ();
    void browser_capture_now  ();
    bool browser_is_loading   ();
    const char* browser_get_url();
    void browser_send_mouse   (int x, int y, int btn);
    void browser_send_scroll  (int delta);
    void browser_send_char    (unsigned int cp);
    void browser_send_key     (int vk, bool down);
    void shutdown_browser     ();
]]
local BASE = "C:\\Echidna-L4d2\\"
ffi.C.SetDllDirectoryA(BASE)
if not ffi.abi("32bit") then
    error("[browser.lua] Architecture mismatch: Game is running in 64-bit, but 32-bit is required.")
end
local status, br = pcall(ffi.load, BASE .. "browser.dll")
if not status then
    error("[browser.lua] Failed to load 32-bit browser.dll. Ensure it was compiled for x86: " .. tostring(br))
end
local BW, BH     = 1280, 720
local WW, WH     = 1320, 800
local START_URL  = "https://www.google.com"
local inited      = false
local last_tex    = nil
local url_input   = START_URL
local focus       = "none"
local last_frame  = 0
local FRAME_INTV  = 1 / 15
local function IC(r,g,b,a) a=a or 255; return {r/255,g/255,b/255,a/255} end
local CBAR  = IC( 28, 28, 36, 245)
local CBTN  = IC( 45, 45, 60)
local CBTNL = IC( 60, 60, 85)
local CLOAD = IC( 80,160,255)
local CTXT  = IC(220,220,230)
local CTXD  = IC(130,130,148)
local CBDR  = IC( 55, 55, 75)
local CBKG  = IC(  8,  8, 14)
local function start()
    local dev = client.get_d3d9_device()
    if not dev then return end
    if br.init_browser(dev, START_URL, BW, BH) then
        inited = true
        print("[browser] WebView2 ready")
    else
        print("[browser] init failed — is WebView2Loader.dll present?")
    end
end
local function normalize_url(s)
    s = s:match("^%s*(.-)%s*$")
    if s == "" then return s end
    if not s:match("^https?://") and not s:match("^file://") then
        if s:find(" ") or not s:find("%.") then
            return "https://www.google.com/search?q=" .. s:gsub(" ", "+")
        end
        return "https://" .. s
    end
    return s
end
local function draw_loading_bar(dl, x, y, w, t)
    local pos = (t % 1.5) / 1.5
    local bw  = w * 0.35
    local bx  = x + (w + bw) * pos - bw
    bx = math.max(x, math.min(bx, x + w - 1))
    local ex = math.min(bx + bw, x + w)
    dl:add_rect_filled(bx, y, ex, y + 2,
        CLOAD[1], CLOAD[2], CLOAD[3], CLOAD[4])
end
function on_end_scene()
    if not client.is_menu_open() then return end
    if not inited then start(); return end
    local now = client.get_time()
    if (now - last_frame) >= FRAME_INTV then
        if br.browser_is_frame_ready() then
            br.browser_update_frame()
            local raw = br.browser_get_texture()
            last_tex = raw ~= nil and client.tex_from_ptr(raw) or nil
        end
        last_frame = now
    end
    imgui.SetNextWindowSize(WW, WH, 4)
    local wf = 0
    if not imgui.Begin("Felix-Fox", nil, wf) then imgui.End(); return end
    local dl          = imgui.get_window_draw_list()
    local wx, wy      = imgui.GetWindowPos()
    local ww, wh      = imgui.GetWindowSize()
    local fh          = imgui.GetFrameHeight()
    local TOOLBAR_H   = 34
    dl:add_rect_filled(wx, wy + fh, wx + ww, wy + fh + TOOLBAR_H,
        CBAR[1], CBAR[2], CBAR[3], CBAR[4])
    local bar_y = wy + fh + 6
    local cx    = wx + 8
    local function tbtn(label, bw, fn)
        imgui.SetCursorScreenPos(cx, bar_y)
        if imgui.Button(label, bw, 22) then fn() end
        cx = cx + bw + 4
    end
    tbtn("<",  22, function() br.browser_back();    br.browser_capture_now() end)
    tbtn(">",  22, function() br.browser_forward();  br.browser_capture_now() end)
    tbtn("R",  22, function() br.browser_reload();   br.browser_capture_now() end)
    local url_w = ww - (cx - wx) - 16
    imgui.SetCursorScreenPos(cx, bar_y)
    imgui.SetNextItemWidth(url_w)
    local new_url = imgui.InputText("##url", url_input)
    if new_url ~= nil then
        url_input = new_url
        focus = "urlbar"
    end
    if focus == "urlbar" and imgui.IsItemFocused() then
        if imgui.IsKeyPressed(13) then
            local nav = normalize_url(url_input)
            br.browser_navigate(nav)
            focus = "page"
        end
    end
    if imgui.IsItemClicked() then focus = "urlbar" end
    if focus ~= "urlbar" then
        local live = ffi.string(br.browser_get_url())
        if live ~= "" then url_input = live end
    end
    if br.browser_is_loading() then
        draw_loading_bar(dl, wx, wy + fh + TOOLBAR_H - 2, ww, now)
    else
        dl:add_rect_filled(wx, wy + fh + TOOLBAR_H - 1, wx + ww, wy + fh + TOOLBAR_H,
            CBDR[1], CBDR[2], CBDR[3], CBDR[4])
    end
    local vx = wx
    local vy = wy + fh + TOOLBAR_H
    local vw = ww
    local vh = wh - fh - TOOLBAR_H
    local scale  = math.min(vw / BW, vh / BH)
    local dw     = math.floor(BW * scale)
    local dh     = math.floor(BH * scale)
    local img_x  = vx + math.floor((vw - dw) * 0.5)
    local img_y  = vy + math.floor((vh - dh) * 0.5)
    dl:add_rect_filled(vx, vy, vx + vw, vy + vh, CBKG[1], CBKG[2], CBKG[3], CBKG[4])
    if last_tex then
        dl:add_image(last_tex, img_x, img_y, img_x + dw, img_y + dh)
    else
        local mid_x = vx + vw * 0.5 - 30
        local mid_y = vy + vh * 0.5 - 7
        imgui.SetCursorScreenPos(mid_x, mid_y)
        imgui.TextDisabled(br.browser_is_loading() and "Loading..." or "Waiting for WebView2...")
    end
    imgui.SetCursorScreenPos(img_x, img_y)
    imgui.InvisibleButton("##viewport", dw, dh)
    if imgui.IsItemHovered() then
        local mx, my = imgui.GetMousePos()
        local bx = math.floor((mx - img_x) / scale)
        local by = math.floor((my - img_y) / scale)
        br.browser_send_mouse(bx, by, 0)
        if imgui.IsMouseClicked(0) then
            br.browser_send_mouse(bx, by, 1)
            br.browser_send_mouse(bx, by, 2)
            focus = "page"
            br.browser_capture_now()
        end
        if imgui.IsMouseClicked(1) then
            br.browser_send_mouse(bx, by, 3)
            br.browser_send_mouse(bx, by, 4)
        end
         local wheel = imgui.GetMouseWheel and imgui.GetMouseWheel() or 0
        if wheel ~= 0 then
            br.browser_send_scroll(wheel > 0 and 3 or -3)
            br.browser_capture_now()
        end
    end
    if focus == "page" then
        local io_chars = imgui.GetInputCharacters and imgui.GetInputCharacters()
        if io_chars then
            for i = 1, #io_chars do
                br.browser_send_char(io_chars:byte(i))
            end
        end
        local function fwd_key(vk)
            if imgui.IsKeyPressed(vk) then
                br.browser_send_key(vk, true)
                br.browser_send_key(vk, false)
                br.browser_capture_now()
            end
        end
        fwd_key(8)
        fwd_key(13)
        fwd_key(9)
        fwd_key(27)
        fwd_key(37)
        fwd_key(39)
        fwd_key(38)
        fwd_key(40)
        fwd_key(46)
    end
    imgui.End()
end
function on_unload()
    if inited then
        br.shutdown_browser()
        inited   = false
        last_tex = nil
    end
end

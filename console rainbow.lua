local ffi = require("ffi")

ffi.cdef[[
    typedef struct {
        float console[3];
        float hud[3];
        int console_rainbow;
        float console_speed;
        float console_strength;
        int hud_rainbow;
        float hud_speed;
        float hud_strength;
    } config_t;
    void* fopen(const char* filename, const char* mode);
    size_t fwrite(const void* ptr, size_t size, size_t count, void* stream);
    size_t fread(void* ptr, size_t size, size_t count, void* stream);
    int fclose(void* stream);
]]

local libc = ffi.os == "Windows" and ffi.load("msvcrt") or ffi.C

local console_color = {0.0, 0.0, 1.0}
local hud_color = {0.0, 0.0, 1.0}
local console_rainbow = false
local console_speed = 1.0
local console_strength = 1.0
local hud_rainbow = false
local hud_speed = 1.0
local hud_strength = 1.0

local config_filename = "console_hud_modulate.bin"

local function hsv_to_rgb(h, s, v)
    if s == 0 then return v, v, v end
    local i = math.floor(h * 6)
    local f = (h * 6) - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    elseif i == 5 then return v, p, q
    end
end

local function save_config()
    local cfg = ffi.new("config_t")
    cfg.console[0] = console_color[1]
    cfg.console[1] = console_color[2]
    cfg.console[2] = console_color[3]
    cfg.hud[0] = hud_color[1]
    cfg.hud[1] = hud_color[2]
    cfg.hud[2] = hud_color[3]
    cfg.console_rainbow = console_rainbow and 1 or 0
    cfg.console_speed = console_speed
    cfg.console_strength = console_strength
    cfg.hud_rainbow = hud_rainbow and 1 or 0
    cfg.hud_speed = hud_speed
    cfg.hud_strength = hud_strength

    local file = libc.fopen(config_filename, "wb")
    if file ~= nil then
        libc.fwrite(cfg, ffi.sizeof("config_t"), 1, file)
        libc.fclose(file)
    end
end

local function load_config()
    local file = libc.fopen(config_filename, "rb")
    if file ~= nil then
        local cfg = ffi.new("config_t")
        if libc.fread(cfg, ffi.sizeof("config_t"), 1, file) == 1 then
            console_color[1] = cfg.console[0]
            console_color[2] = cfg.console[1]
            console_color[3] = cfg.console[2]
            hud_color[1] = cfg.hud[0]
            hud_color[2] = cfg.hud[1]
            hud_color[3] = cfg.hud[2]
            console_rainbow = cfg.console_rainbow == 1
            console_speed = cfg.console_speed
            console_strength = cfg.console_strength
            hud_rainbow = cfg.hud_rainbow == 1
            hud_speed = cfg.hud_speed
            hud_strength = cfg.hud_strength
        end
        libc.fclose(file)
    end
end

load_config()

menu.add_main_tab("Q", "ConsoleModulate", function()
    if imgui.BeginTabBar("ConsoleSubTabBar") then
        if imgui.BeginTabItem("Console") then
            imgui.Spacing()

            local r, g, b = imgui.ColorEdit3(
                "Console Tint",
                console_color[1],
                console_color[2],
                console_color[3]
            )

            local rb = imgui.Checkbox("Rainbow Mode", console_rainbow)
            local speed = imgui.SliderFloat("Rainbow Speed", console_speed, 0.0, 5.0)
            local strength = imgui.SliderFloat("Rainbow Strength", console_strength, 0.0, 1.0)

            if r ~= console_color[1] or g ~= console_color[2] or b ~= console_color[3] or
               rb ~= console_rainbow or speed ~= console_speed or strength ~= console_strength then
                console_color[1] = r
                console_color[2] = g
                console_color[3] = b
                console_rainbow = rb
                console_speed = speed
                console_strength = strength
                save_config()
            end

            imgui.EndTabItem()
        end

        if imgui.BeginTabItem("HUD") then
            imgui.Spacing()

            local r, g, b = imgui.ColorEdit3(
                "HUD Tint",
                hud_color[1],
                hud_color[2],
                hud_color[3]
            )

            local rb = imgui.Checkbox("HUD Rainbow Mode", hud_rainbow)
            local speed = imgui.SliderFloat("HUD Rainbow Speed", hud_speed, 0.0, 5.0)
            local strength = imgui.SliderFloat("HUD Rainbow Strength", hud_strength, 0.0, 1.0)

            if r ~= hud_color[1] or g ~= hud_color[2] or b ~= hud_color[3] or
               rb ~= hud_rainbow or speed ~= hud_speed or strength ~= hud_strength then
                hud_color[1] = r
                hud_color[2] = g
                hud_color[3] = b
                hud_rainbow = rb
                hud_speed = speed
                hud_strength = strength
                save_config()
            end

            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
end)

local console_targets = {
    ["console/background04_widescreen"] = true,
    ["vgui/../console/background04_widescreen"] = true,
    ["vgui_white"] = true,
    ["engine/modulatesinglecolor"] = true,
    ["vgui/hud/800corner1"] = true,
    ["vgui/hud/800corner2"] = true,
    ["vgui/hud/800corner3"] = true,
    ["vgui/hud/800corner4"] = true,
}

local hud_targets = {
    ["vgui/hud/iconsheet"] = true,
    ["vgui/hud/iconsheet2"] = true,
    ["vgui/hud/iconsheet3"] = true,
    ["vgui/hud/healthbar_bg_1"] = true,
    ["vgui/hud/healthbar_bg_2"] = true,
    ["vgui/hud/healthbar_bg_3"] = true,
    ["vgui/hud/healthbar_withglow_green"] = true,
    ["vgui/hud/healthbar_withglow_orange"] = true,
    ["vgui/hud/healthbar_withglow_red"] = true,
    ["vgui/hud/healthbar_withglow_white"] = true,
}

local console_mats = {}
local hud_mats = {}
local cached = false

local function build_material_cache()
    if cached or not MaterialSystem then
        return
    end

    cached = true

    local invalid = MaterialSystem.InvalidMaterial()
    local h = MaterialSystem.FirstMaterial()

    while h ~= invalid do
        local mat = MaterialSystem.GetMaterial(h)

        if mat and not mat:IsErrorMaterial() then
            local name = mat:GetName()

            if console_targets[name] then
                console_mats[#console_mats + 1] = mat
            elseif hud_targets[name] or string.find(name, "^vgui/hud/icon_") then
                hud_mats[#hud_mats + 1] = mat
            end
        end

        h = MaterialSystem.NextMaterial(h)
    end
end

local function apply_modulation()
    local cr, cg, cb
    if console_rainbow then
        local hue = (os.clock() * console_speed) % 1.0
        cr, cg, cb = hsv_to_rgb(hue, console_strength, 1.0)
    else
        cr, cg, cb = console_color[1], console_color[2], console_color[3]
    end

    for _, mat in ipairs(console_mats) do
        pcall(function()
            mat:ColorModulate(cr, cg, cb)
        end)
    end

    local hr, hg, hb
    if hud_rainbow then
        local hue = (os.clock() * hud_speed) % 1.0
        hr, hg, hb = hsv_to_rgb(hue, hud_strength, 1.0)
    else
        hr, hg, hb = hud_color[1], hud_color[2], hud_color[3]
    end

    for _, mat in ipairs(hud_mats) do
        pcall(function()
            mat:ColorModulate(hr, hg, hb)
        end)
    end
end

function on_paint_traverse(panel_name)
    build_material_cache()
    apply_modulation()
end

function on_unload()
    for _, mat in ipairs(console_mats) do
        pcall(function()
            mat:ColorModulate(1.0, 1.0, 1.0)
        end)
    end

    for _, mat in ipairs(hud_mats) do
        pcall(function()
            mat:ColorModulate(1.0, 1.0, 1.0)
        end)
    end
end

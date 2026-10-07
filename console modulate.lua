local console_color = {0.0, 0.0, 1.0}

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

            console_color[1] = r
            console_color[2] = g
            console_color[3] = b

            imgui.EndTabItem()
        end
        imgui.EndTabBar()
    end
end)

local target_names = {
    ["console/background04_widescreen"] = true,
    ["vgui/../console/background04_widescreen"] = true,
    ["vgui/white"] = true,
    ["vgui_white"] = true,
    ["engine/modulatesinglecolor"] = true,
    ["vgui/hud/800corner1"] = true,
    ["vgui/hud/800corner2"] = true,
    ["vgui/hud/800corner3"] = true,
    ["vgui/hud/800corner4"] = true,
}

local target_mats = {}
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

            if target_names[name] then
                target_mats[#target_mats + 1] = mat
            end
        end

        h = MaterialSystem.NextMaterial(h)
    end
end

local function apply_modulation()
    local r, g, b = console_color[1], console_color[2], console_color[3]

    for _, mat in ipairs(target_mats) do
        pcall(function()
            mat:ColorModulate(r, g, b)
        end)
    end
end

function on_paint_traverse(panel_name)
    build_material_cache()

    if panel_name == "GameConsole" then
        apply_modulation()
    end
end

function on_unload()
    for _, mat in ipairs(target_mats) do
        pcall(function()
            mat:ColorModulate(1.0, 1.0, 1.0)
        end)
    end
end

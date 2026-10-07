-- @author: Natsumi
-- @created: 26.06 09:45
-- Echidna Script
local ffi = require("ffi")
echidna_features.disable("Feature_EnginePrediction")
echidna_features.disable("Feature_ESP")
echidna_hooks.remove("CL_CopyCommand")
echidna_hooks.remove("CL_RunCommand")

local CONFIG = {
    bg_red          = 11,       
    bg_green        = 11,       
    bg_blue         = 13,       

    bg_opacity      = 255,

    blur_strength   = 0,        

    padding         = 12,
    rounding        = 6,
}

if not _G._storm_api_loaded then
    ffi.cdef[[
        int  Storm_EnableHook(const char* name);
        int  Storm_DisableHook(const char* name);
        int  Storm_RemoveHook(const char* name);
        int  Storm_IsHookEnabled(const char* name);
        int  Storm_EnablePatch(const char* name);
        int  Storm_DisablePatch(const char* name);
        int  Storm_IsPatchApplied(const char* name);
        int  Storm_ListHooks(char* buf, int buf_size);
        int  Storm_ListPatches(char* buf, int buf_size);
        void Storm_ListCommands(char* buf, int buf_size);
        void Storm_SetInterfaceValue(const char* name, float value);
        short GetAsyncKeyState(int vKey);
    ]]
    _G._storm_api_loaded = true
end

local user32 = ffi.load("user32")
local menu_visible = false
local last_key_state = false

local interfaces = {
    "Interface_Extra_Commands", "Interface_Extra_Commands_Action", 
    "Interface_Extra_Commands_Key",
    "Interface_Interpolate_Extra_Commands", "Interface_Target_On_Simulation", 
    "Interface_Shotgun_Shove", "Interface_Riot_Deprioritize", 
    "Interface_Penetrate_Teammates", "Interface_Aim_Intersection", 
    "Interface_Penetration_Damage", "Interface_Equipment_Distance", 
    "Interface_Storm_Rotation_Radius", "Interface_Storm_Radius", 
    "Interface_Storm_Segments", "Interface_Storm_Iterations", 
    "Interface_Storm_Speed", "Interface_Auto_Shoot", "Interface_Ignore_Common"
}
local extra_commands_key = 0x10 -- VK_SHIFT
local waiting_for_key = false
local extra_commands_value = 5.0

local VK_NAMES = {
    [0x01]="Mouse1",[0x02]="Mouse2",[0x04]="Mouse3",[0x05]="Mouse4",[0x06]="Mouse5",
    [0x08]="Backspace",[0x09]="Tab",[0x0D]="Enter",[0x10]="Shift",[0x11]="Ctrl",[0x12]="Alt",
    [0x14]="Caps",[0x1B]="Escape",[0x20]="Space",
    [0x25]="Left",[0x26]="Up",[0x27]="Right",[0x28]="Down",
    [0x2D]="Insert",[0x2E]="Delete",
    [0x70]="F1",[0x71]="F2",[0x72]="F3",[0x73]="F4",[0x74]="F5",[0x75]="F6",
    [0x76]="F7",[0x77]="F8",[0x78]="F9",[0x79]="F10",[0x7A]="F11",[0x7B]="F12",
}

for i=0x30,0x39 do
    VK_NAMES[i]=string.char(i)
end

for i=0x41,0x5A do
    VK_NAMES[i]=string.char(i)
end

local function vk_name(vk)
    return VK_NAMES[vk] or ("VK_"..tostring(vk))
end

local storm = ffi.load("Storm.cpl")
local function poll_keybind()
    if not waiting_for_key then
        return
    end

    for vk=1,255 do
        if bit.band(user32.GetAsyncKeyState(vk),0x8000)~=0 then
            extra_commands_key = vk
            storm.Storm_SetInterfaceValue("Interface_Extra_Commands_Key", vk)
            waiting_for_key = false
            break
        end
    end
end
for _, name in ipairs(interfaces) do
    local cmd_name = "storm_" .. name:gsub("^Interface_", ""):lower()
    local cmd_ok = client.register_command(cmd_name, function(arg)
        local input = string.lower(arg or "")
        local val = tonumber(input)
        
        if input == "on" or input == "enable" or input == "1" then
            val = 1
        elseif input == "off" or input == "disable" or input == "0" then
            val = 0
        end
        
        if val then
            storm.Storm_SetInterfaceValue(name, val)
            print("[" .. cmd_name .. "] Status is now: " .. val)
        else
            print("[" .. cmd_name .. "] Invalid value. Expected a number or toggle statement.")
        end
    end)

    if not cmd_ok then
        print("[" .. cmd_name .. "] Failed to register command. (Name collision)")
    end
end

local HOOKS = {
    { name = "copy_command"              },
    { name = "run_command"               },
    { name = "post_network_data_received"},
    { name = "interpolate"               },
    { name = "update_animations"         },
    { name = "estimate_velocity"         },
    { name = "spawn_grenade"             },
    { name = "update"                    },
    { name = "process_movement"          },
    { name = "play_footstep_sound"       },
    { name = "finish_move"               },
    { name = "item_post_frame"           },
    { name = "perform_trace"             },
    { name = "read_packets"              },
    { name = "move"                      },
    { name = "send_move"                 },
    { name = "calculate_view"            },
    { name = "draw_effect"               },
    { name = "write_texture"             },
    { name = "paint"                     },
    { name = "get_glow_color"            },
    { name = "draw_crosshair_hud"        },
    { name = "draw_crosshair_scope"      },
    { name = "calc_viewmodel"      },
}

local PATCHES = {
    { name = "delimit_interface"           },
    { name = "block_316816"                },
    { name = "engine_350575"               },
    { name = "engine_521741"               },
    { name = "maintain_sequence_transitions" },
    { name = "anim_3244278"                },
    { name = "pred_1554528"                },
    { name = "pred_1557776"                },
    { name = "input_nop_1250629"           },
    { name = "input_417204"                },
    { name = "input_2538675"               },
    { name = "effects_407384"              },
    { name = "effects_133424"              },
    { name = "effects_2881566"             },
    { name = "effects_1868237"             },
    { name = "effects_2655546"             },
    { name = "paint_3244715"               },
    { name = "paint_2930985"               },
}

local hook_state  = {}
local patch_state = {}
local auto_shoot_enabled = true

local function refresh_states()
    for _, h in ipairs(HOOKS) do
        hook_state[h.name] = storm.Storm_IsHookEnabled(h.name) == 1
    end
    for _, p in ipairs(PATCHES) do
        patch_state[p.name] = storm.Storm_IsPatchApplied(p.name) == 1
    end
end

refresh_states()

local seq_shift_value = 20000
local bg_tex = nil

menu.add_main_tab("S", "Storm.cpl", function()
    poll_keybind()
    if not bg_tex and client.load_texture then
        bg_tex = client.load_texture("1136091.png")
    end

    local x1, y1 = imgui.GetWindowPos()
    local w, h = imgui.GetWindowSize()
    local x2, y2 = x1 + w, y1 + h

    local r_float     = CONFIG.bg_red / 255.0
    local g_float     = CONFIG.bg_green / 255.0
    local b_float     = CONFIG.bg_blue / 255.0
    local alpha_float = CONFIG.bg_opacity / 255.0
    
    local pad_float   = CONFIG.padding * 1.0
    local round_float = CONFIG.rounding * 1.0
    local blur_float  = CONFIG.blur_strength * 1.0

    local rx1 = x1 + pad_float
    local ry1 = y1 + pad_float
    local rx2 = x2 - pad_float
    local ry2 = y2 - pad_float

    imgui.win_draw_rect_filled(rx1, ry1, rx2, ry2, r_float, g_float, b_float, alpha_float, round_float)

    if bg_tex and imgui.win_draw_image then
    --    imgui.win_draw_image(bg_tex, rx1, ry1, rx2, ry2)
    end


    if imgui.draw_window_blur and blur_float > 0 then
        imgui.draw_window_blur(blur_float, 0)
    end

    imgui.SetCursorPosY(pad_float + 4.0) 
    imgui.Indent(pad_float) 

    imgui.Spacing()

    imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
    imgui.TextColored(0.85, 0.85, 1.0, 1.0, "Pandora.lua") 
    
    imgui.Spacing()
    imgui.Separator()

    imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
    imgui.TextColored(0.2, 0.8, 1, 1, "Storm  //  Hook Manager")
    
    imgui.Separator()
    imgui.Spacing()

    if imgui.BeginTabBar("storm_tabs") then
        if imgui.BeginTabItem("General") then
            imgui.Spacing()

            imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
            imgui.TextColored(1, 0.6, 0.2, 1, "Auto Shoot")
            imgui.SameLine()
            if imgui.Button(auto_shoot_enabled and "Disable##auto_shoot" or "Enable##auto_shoot") then
                auto_shoot_enabled = not auto_shoot_enabled
                storm.Storm_SetInterfaceValue("Interface_Auto_Shoot", auto_shoot_enabled and 1 or 0)
            end
            imgui.SameLine()
            if auto_shoot_enabled then
                imgui.TextColored(0, 1, 0, 1, "[ON]")
            else
                imgui.TextColored(1, 0, 0, 1, "[OFF]")
            end
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
            imgui.TextColored(0, 1, 0.5, 1, "Sequence Shift")

            imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
            local new_ss, ss_changed = imgui.SliderInt("##seq_shift", seq_shift_value, 1000, 100000)
            if ss_changed then
                seq_shift_value = new_ss
                _G.storm_seq_shift = seq_shift_value
            end
            imgui.SameLine()
            imgui.TextColored(0.5, 0.5, 0.5, 1, "out seq offset")
            imgui.Spacing()
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
            imgui.TextColored(1,0.75,0.2,1,"Extra Commands Key")

            imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)

            local label
            if waiting_for_key then
                label = "[ Press any key... ]"
            else
                label = vk_name(extra_commands_key)
            end

            if imgui.Button(label .. "##extra_commands_key") then
                waiting_for_key = true
            end
            imgui.Spacing()
            imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
            imgui.TextColored(0.6, 1.0, 0.6, 1, "Extra Commands Strength")

            imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
            local new_val, changed = imgui.SliderInt("##extra_commands_val", extra_commands_value, 0, 80)
            if changed then
                extra_commands_value = new_val
                storm.Storm_SetInterfaceValue("Interface_Extra_Commands", new_val)
            end

            imgui.SameLine()
            imgui.TextColored(0.5, 0.5, 0.5, 1, tostring(extra_commands_value))

            imgui.EndTabItem()
        end

        if imgui.BeginTabItem("Hooks") then
            imgui.Spacing()
            if imgui.Button("Enable All##hooks") then
                for _, h in ipairs(HOOKS) do
                    storm.Storm_EnableHook(h.name)
                    hook_state[h.name] = true
                end
            end
            imgui.SameLine()
            if imgui.Button("Disable All##hooks") then
                for _, h in ipairs(HOOKS) do
                    storm.Storm_DisableHook(h.name)
                    hook_state[h.name] = false
                end
            end
            imgui.SameLine()
            if imgui.Button("Refresh##hooks") then
                refresh_states()
            end

            imgui.Spacing()

            imgui.BeginChild("##hooks_scroll", 540, 380, true)
            for _, h in ipairs(HOOKS) do
                local active = hook_state[h.name]


                imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
                if active then
                    imgui.TextColored(0, 1, 0, 1, "[ON] ")
                else
                    imgui.TextColored(1, 0, 0, 1, "[OFF]")
                end
                imgui.SameLine()
                imgui.Text(h.name)
                imgui.SameLine()

                local btn_label = active and ("Disable##h_" .. h.name) or ("Enable##h_"  .. h.name)

                if imgui.Button(btn_label) then
                    if active then
                        storm.Storm_DisableHook(h.name)
                        hook_state[h.name] = false
                    else
                        storm.Storm_EnableHook(h.name)
                        hook_state[h.name] = true
                    end
                end

                imgui.SameLine()

                if imgui.Button("Remove##h_" .. h.name) then
                    storm.Storm_RemoveHook(h.name)
                    hook_state[h.name] = false
                end
            end
            imgui.EndChild()
            imgui.Spacing()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem("Byte Patches") then
            imgui.Spacing()
            if imgui.Button("Enable All##patches") then
                for _, p in ipairs(PATCHES) do
                    storm.Storm_EnablePatch(p.name)
                    patch_state[p.name] = true
                end
            end
            imgui.SameLine()
            if imgui.Button("Restore All##patches") then
                for _, p in ipairs(PATCHES) do
                    storm.Storm_DisablePatch(p.name)
                    patch_state[p.name] = false
                end
            end
            imgui.SameLine()
            if imgui.Button("Refresh##patches") then
                refresh_states()
            end

            imgui.Spacing()

            imgui.BeginChild("##patches_scroll", 540, 380, true)
            for _, p in ipairs(PATCHES) do
                local active = patch_state[p.name]


                imgui.SetCursorPosX(imgui.GetCursorPosX() + 8.0)
                if active then
                    imgui.TextColored(0, 1, 0, 1, "[ON] ")
                else
                    imgui.TextColored(1, 0.4, 0, 1, "[OFF]")
                end
                imgui.SameLine()
                imgui.Text(p.name)
                imgui.SameLine()

                local btn_label = active and ("Restore##p_" .. p.name) or ("Re-apply##p_" .. p.name)

                if imgui.Button(btn_label) then
                    if active then
                        storm.Storm_DisablePatch(p.name)
                        patch_state[p.name] = false
                    else
                        storm.Storm_EnablePatch(p.name)
                        patch_state[p.name] = true
                    end
                end
            end
            imgui.EndChild()
            imgui.Spacing()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem("Diagnostics") then
            imgui.Spacing()
            if imgui.Button("Print API to console") then
                local buf = ffi.new("char[4096]")
                storm.Storm_ListCommands(buf, 4096)
                print(ffi.string(buf))
            end
            imgui.Spacing()
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
    
    imgui.Unindent(pad_float)
end)

_G.Storm = _G.Storm or {}

_G.Storm.SetInterface = function(name, value)
    if storm then
        storm.Storm_SetInterfaceValue(name, value)
    end
end

_G.Storm.GetHookEnabled = function(name)
    if storm then
        return storm.Storm_IsHookEnabled(name) == 1
    end
    return false
end

_G.Storm.EnableHook  = function(name) if storm then storm.Storm_EnableHook(name)  end end
_G.Storm.DisableHook = function(name) if storm then storm.Storm_DisableHook(name) end end

function on_unload()
    _G.Storm = nil
    storm = nil
    bg_tex = nil
end

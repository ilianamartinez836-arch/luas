-- @author: Capella
-- @created: 18.05 15:18
-- Echidna Script

-- This uncaps the 14 limit at the speedhack
-- and NO, this is not only uncapping the 14 problem
-- this also UNCAPS THE 14 TICK IN-GAME LIMIT
-- SO, instead of using over 14 and getting teleported back without the fix
-- u can use storm speedhack without any trouble along with echidna, enjoy!
local ffi = require("ffi")
ffi.cdef[[
    void* GetModuleHandleA(const char* lpModuleName);
    int VirtualProtect(void* lpAddress, unsigned long dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]]

local PAGE_RWX  = 0x40
local old_prot  = ffi.new("unsigned long[1]")

local function poke8(addr, val)
    local p = ffi.cast("unsigned char*", addr)
    ffi.C.VirtualProtect(p, 1, PAGE_RWX, old_prot)
    p[0] = val
    ffi.C.VirtualProtect(p, 1, old_prot[0], old_prot)
end

local function poke32(addr, val)
    local p = ffi.cast("int*", addr)
    ffi.C.VirtualProtect(p, 4, PAGE_RWX, old_prot)
    p[0] = val
    ffi.C.VirtualProtect(p, 4, old_prot[0], old_prot)
end

local storm = tonumber(ffi.cast("unsigned int", ffi.C.GetModuleHandleA("Storm.cpl")))

local PATCH_ADDR     = storm + 0x2F4F
local EC_ADDR        = storm + 0xE194   -- Interface_Extra_Commands.Integer btw
local LIMIT_CMP_ADDR = storm + 0x2F8F
local LIMIT_CAP_ADDR = storm + 0x2F98
local FORCE_VAR_ADDR = storm + 0x4A2D

poke8(LIMIT_CMP_ADDR, 0x64)
poke8(LIMIT_CAP_ADDR, 0x63)

poke8(FORCE_VAR_ADDR, 0xB0)
poke8(FORCE_VAR_ADDR + 1, 0x01)
poke8(FORCE_VAR_ADDR + 2, 0x90)

local EXTRA_CMDS     = 3
local master_enabled = false 
local speedhack_on   = false

local function enable()
    poke8(PATCH_ADDR, 0xEB)
    poke32(EC_ADDR, EXTRA_CMDS)
    speedhack_on = true
end

local function disable()
    poke8(PATCH_ADDR, 0x75)
    poke32(EC_ADDR, 0)
    speedhack_on = false
end

function on_end_scene()
    if master_enabled then
        local shift_down = ffi.C.GetAsyncKeyState(0x10) < 0 -- SHIFT KEY, u can change it using this hex codes: https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
        
        if shift_down and not speedhack_on then
            enable()
        elseif not shift_down and speedhack_on then
            disable()
        end
    else
        if speedhack_on then disable() end
    end

    if not client.is_menu_open() then return end

    imgui.SetNextWindowPos(40, 40, 4)
    imgui.SetNextWindowSize(260, 115, 4)

    if imgui.Begin("Storm speed stuff", 0) then
        imgui.draw_window_blur(1.0)

        local is_active = master_enabled and speedhack_on
        local r, g = is_active and 0 or 1, is_active and 1 or 0
        imgui.TextColored(r, g, 0, 1, is_active and "Speed:  ON" or "Speed:  OFF")
        imgui.Spacing()
        imgui.SetCursorPosX(12)

        local toggled
        master_enabled, toggled = imgui.Checkbox("Master Enable", master_enabled)
        if toggled and not master_enabled then
            if speedhack_on then disable() end
        end

        imgui.SetCursorPosX(12)
        imgui.SetNextItemWidth(200)
        
        local new_val, changed = imgui.SliderInt("##ec", EXTRA_CMDS, 1, 99)
        if changed then
            EXTRA_CMDS = new_val
            if speedhack_on then poke32(EC_ADDR, EXTRA_CMDS) end
        end
        imgui.SameLine()
        imgui.TextColored(0.5, 0.5, 0.5, 1, "cmds")

        imgui.End()
    end
end

function on_unload()
    if speedhack_on then disable() end
    
    poke8(LIMIT_CMP_ADDR, 0x0F)
    poke8(LIMIT_CAP_ADDR, 0x0E)

    poke8(FORCE_VAR_ADDR, 0x0F)
    poke8(FORCE_VAR_ADDR + 1, 0x9E)
    poke8(FORCE_VAR_ADDR + 2, 0xC0)
end

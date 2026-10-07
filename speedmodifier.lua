-- Echidna Loader Script
-- Name   : External speed modifier
-- Author : Hakoz (Daniel)
-- Date   : 27.05.2026 16:47
local ffi = require("ffi")
--Mini desc: storm cpl from server used for random shit, ported from internal to external
local function def(s) pcall(ffi.cdef, s) end

def "typedef unsigned long    DWORD;"
def "typedef int              BOOL;"
def "typedef void* HANDLE;"
def "typedef unsigned short   WCHAR;"
def "typedef const void* LPCVOID;"
def "typedef void* LPVOID;"
def "typedef size_t           SIZE_T;"
def "typedef intptr_t         LONG_PTR;"

def [[
    typedef struct tagPROCESSENTRY32W {
        DWORD dwSize;
        DWORD cntUsage;
        DWORD th32ProcessID;
        LONG_PTR th32DefaultHeapID;
        DWORD th32ModuleID;
        DWORD cntThreads;
        DWORD th32ParentProcessID;
        long  pcPriClassBase;
        DWORD dwFlags;
        WCHAR szExeFile[260];
    } PROCESSENTRY32W;
]]
def [[
    typedef struct tagMODULEENTRY32W {
        DWORD dwSize;
        DWORD th32ModuleID;
        DWORD th32ProcessID;
        DWORD GlblcntUsage;
        DWORD ProccntUsage;
        unsigned char* modBaseAddr;
        DWORD modBaseSize;
        HANDLE hModule;
        WCHAR szModule[256];
        WCHAR szExePath[260];
    } MODULEENTRY32W;
]]

def "HANDLE CreateToolhelp32Snapshot(DWORD dwFlags, DWORD th32ProcessID);"
def "BOOL   Process32FirstW(HANDLE hSnapshot, PROCESSENTRY32W* lppe);"
def "BOOL   Process32NextW(HANDLE hSnapshot, PROCESSENTRY32W* lppe);"
def "BOOL   Module32FirstW(HANDLE hSnapshot, MODULEENTRY32W* lpme);"
def "BOOL   Module32NextW(HANDLE hSnapshot, MODULEENTRY32W* lpme);"
def "HANDLE OpenProcess(DWORD dwDesiredAccess, BOOL bInheritHandle, DWORD dwProcessId);"
def "BOOL   CloseHandle(HANDLE hObject);"
def "BOOL   ReadProcessMemory(HANDLE hProcess, LPCVOID lpBaseAddress, LPVOID lpBuffer, SIZE_T nSize, SIZE_T* lpNumberOfBytesRead);"
def "BOOL   WriteProcessMemory(HANDLE hProcess, LPVOID lpBaseAddress, LPCVOID lpBuffer, SIZE_T nSize, SIZE_T* lpNumberOfBytesWritten);"
def "BOOL   VirtualProtectEx(HANDLE hProcess, LPVOID lpAddress, SIZE_T dwSize, DWORD flNewProtect, DWORD* lpflOldProtect);"
def "BOOL   GetExitCodeProcess(HANDLE hProcess, DWORD* lpExitCode);"
def "short  GetAsyncKeyState(int vKey);"

local kernel32 = ffi.load("kernel32")
local user32 = ffi.load("user32")

local process_handle    = nil
local storm_base        = 0
local current_pid        = 0
local initial_patched   = false

local EXTRA_CMDS        = 3
local master_enabled    = false 
local speedhack_on       = false

local function wcs_equal(wchar_arr, lua_str)
    for i = 1, #lua_str do
        if wchar_arr[i-1] ~= string.byte(lua_str, i) then return false end
    end
    return wchar_arr[#lua_str] == 0
end

local function get_process_id(name)
    local snap = kernel32.CreateToolhelp32Snapshot(0x00000002, 0)
    if ffi.cast("intptr_t", snap) == -1 then return 0 end
    local pe = ffi.new("PROCESSENTRY32W")
    pe.dwSize = ffi.sizeof(pe)
    if kernel32.Process32FirstW(snap, pe) ~= 0 then
        repeat
            if wcs_equal(pe.szExeFile, name) then
                kernel32.CloseHandle(snap)
                return pe.th32ProcessID
            end
        until kernel32.Process32NextW(snap, pe) == 0
    end
    kernel32.CloseHandle(snap)
    return 0
end

local function get_module_base(pid, name)
    local snap = kernel32.CreateToolhelp32Snapshot(0x00000018, pid)
    if ffi.cast("intptr_t", snap) == -1 then return 0 end
    local me = ffi.new("MODULEENTRY32W")
    me.dwSize = ffi.sizeof(me)
    if kernel32.Module32FirstW(snap, me) ~= 0 then
        repeat
            if wcs_equal(me.szModule, name) then
                kernel32.CloseHandle(snap)
                return tonumber(ffi.cast("DWORD", me.modBaseAddr))
            end
        until kernel32.Module32NextW(snap, me) == 0
    end
    kernel32.CloseHandle(snap)
    return 0
end

local function write_bytes_ext(handle, address, bytes)
    if handle == nil or address == 0 then return false end
    local ptr = ffi.cast("LPVOID", address)
    local old_prot = ffi.new("DWORD[1]")
    
    if kernel32.VirtualProtectEx(handle, ptr, #bytes, 0x40, old_prot) == 0 then
        return false
    end

    local buf = ffi.new("uint8_t[?]", #bytes)
    for i = 1, #bytes do buf[i - 1] = bytes[i] end
    local result = kernel32.WriteProcessMemory(handle, ptr, buf, #bytes, nil)
    
    kernel32.VirtualProtectEx(handle, ptr, #bytes, old_prot[0], old_prot)
    return result ~= 0
end

local function poke8(handle, addr, val)
    return write_bytes_ext(handle, addr, { val })
end

local function poke32(handle, addr, val)
    local b1 = bit.band(val, 0xFF)
    local b2 = bit.band(bit.rshift(val, 8), 0xFF)
    local b3 = bit.band(bit.rshift(val, 16), 0xFF)
    local b4 = bit.band(bit.rshift(val, 24), 0xFF)
    return write_bytes_ext(handle, addr, { b1, b2, b3, b4 })
end

local function apply_initial_patches()
    if process_handle == nil or storm_base == 0 then return end
    
    poke8(process_handle, storm_base + 0x2F8F, 0x64)
    poke8(process_handle, storm_base + 0x2F98, 0x63)

    write_bytes_ext(process_handle, storm_base + 0x4A2D, { 0xB0, 0x01, 0x90 })
    initial_patched = true
end

local function enable()
    if process_handle == nil or storm_base == 0 then return end
    poke8(process_handle, storm_base + 0x2F4F, 0xEB)
    poke32(process_handle, storm_base + 0xE194, EXTRA_CMDS)
    speedhack_on = true
end

local function disable()
    if process_handle == nil or storm_base == 0 then return end
    poke8(process_handle, storm_base + 0x2F4F, 0x75)
    poke32(process_handle, storm_base + 0xE194, 0)
    speedhack_on = false
end

local function run_cheat_tick()
    if process_handle ~= nil then
        local exit_code = ffi.new("DWORD[1]")
        if kernel32.GetExitCodeProcess(process_handle, exit_code) == 0 or exit_code[0] ~= 259 then
            kernel32.CloseHandle(process_handle)
            process_handle = nil
            storm_base = 0
            current_pid = 0
            initial_patched = false
            speedhack_on = false
        end
    end

    if process_handle == nil then
        local pid = get_process_id("left4dead2.exe")
        if pid ~= 0 then
            process_handle = kernel32.OpenProcess(0x001F0FFF, false, pid)
            if process_handle ~= nil then
                storm_base = get_module_base(pid, "Storm.cpl")
                current_pid = pid
                if storm_base == 0 then
                    kernel32.CloseHandle(process_handle)
                    process_handle = nil
                    current_pid = 0
                end
            end
        end
    end

    if process_handle == nil or storm_base == 0 then return end

    -- Run optimization constraints patch once on link
    if not initial_patched then
        apply_initial_patches()
    end

    if master_enabled then
        local shift_down = bit.band(user32.GetAsyncKeyState(0x10), 0x8000) ~= 0 -- Shift Key
        if shift_down and not speedhack_on then
            enable()
        elseif not shift_down and speedhack_on then
            disable()
        end
    else
        if speedhack_on then disable() end
    end
end

menu.add_tab("storm_speed_tab", "Storm Speed", "S", function()
    run_cheat_tick()

    if process_handle ~= nil and storm_base ~= 0 then
        imgui.TextColored(0.2, 1.0, 0.2, 1, string.format("Connected | Storm.cpl: 0x%X", storm_base))
    else
        imgui.TextColored(1.0, 0.2, 0.2, 1, "Waiting for Storm.cpl inside left4dead2.exe...")
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    local is_active = master_enabled and speedhack_on
    local r, g = is_active and 0 or 1, is_active and 1 or 0
    imgui.TextColored(r, g, 0, 1, is_active and "Speedhack Status: RUNNING" or "Speedhack Status: IDLE")
    imgui.Spacing()

    imgui.SetCursorPosX(12)
    local toggled
    master_enabled, toggled = imgui.Checkbox("Master Enable Speed Override", master_enabled)
    if toggled and not master_enabled then
        if speedhack_on then disable() end
    end

    imgui.Spacing()
    imgui.SetCursorPosX(12)
    imgui.SetNextItemWidth(200)
    
    local new_val, changed = imgui.SliderInt("##ec_slider", EXTRA_CMDS, 1, 99)
    if changed then
        EXTRA_CMDS = new_val
        if speedhack_on then poke32(process_handle, storm_base + 0xE194, EXTRA_CMDS) end
    end
    imgui.SameLine()
    imgui.TextColored(0.5, 0.5, 0.5, 1, "cmds")
end)

function on_unload()
    if process_handle ~= nil and storm_base ~= 0 then
        -- Safely reverse speed states externally
        poke8(process_handle, storm_base + 0x2F4F, 0x75)
        poke32(process_handle, storm_base + 0xE194, 0) 

        poke8(process_handle, storm_base + 0x2F8F, 0x0F)
        poke8(process_handle, storm_base + 0x2F98, 0x0E)

        write_bytes_ext(process_handle, storm_base + 0x4A2D, { 0x0F, 0x9E, 0xC0 })
        
        kernel32.CloseHandle(process_handle)
    end
end

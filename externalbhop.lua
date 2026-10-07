-- Echidna Loader Script
-- Name   : meaw.lua
-- Author : idk
-- Date   : 22.05.2026 07:46
local ffi = require("ffi")
local function def(s) pcall(ffi.cdef, s) end

def "typedef unsigned long      DWORD;"
def "typedef int                BOOL;"
def "typedef void*              HANDLE;"
def "typedef unsigned short     WCHAR;"
def "typedef const void*        LPCVOID;"
def "typedef void*              LPVOID;"
def "typedef size_t             SIZE_T;"
def "typedef intptr_t           LONG_PTR;"


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
def "BOOL   GetExitCodeProcess(HANDLE hProcess, DWORD* lpExitCode);"
def "short  GetAsyncKeyState(int vKey);"
def "DWORD  GetTickCount();"

local kernel32 = ffi.load("kernel32")
local user32 = ffi.load("user32")

local LOCALPLAYER_OFFSET = 0x0726BD8
local FORCE_JUMP         = 0x759E70
local M_FLAGS            = 0xF0

local bhop_enabled = false

local process_handle = nil
local client_base    = 0
local jump_state     = 0
local next_state_time = 0

local dbg_local_player = 0
local dbg_flags = 0
local dbg_spacebar = false

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

local function read_dword(handle, address)
    local buf = ffi.new("DWORD[1]")
    kernel32.ReadProcessMemory(handle, ffi.cast("LPCVOID", address), buf, ffi.sizeof(buf), nil)
    return buf[0]
end

local function read_int(handle, address)
    local buf = ffi.new("int[1]")
    kernel32.ReadProcessMemory(handle, ffi.cast("LPCVOID", address), buf, ffi.sizeof(buf), nil)
    return buf[0]
end

local function write_int(handle, address, value)
    local buf = ffi.new("int[1]", value)
    kernel32.WriteProcessMemory(handle, ffi.cast("LPVOID", address), buf, ffi.sizeof(buf), nil)
end

local function run_bhop_tick()
    if process_handle ~= nil then
        local exit_code = ffi.new("DWORD[1]")
        if kernel32.GetExitCodeProcess(process_handle, exit_code) == 0 or exit_code[0] ~= 259 then
            kernel32.CloseHandle(process_handle)
            process_handle = nil
            client_base = 0
            jump_state = 0
        end
    end

    if process_handle == nil then
        local pid = get_process_id("left4dead2.exe")
        if pid ~= 0 then
            process_handle = kernel32.OpenProcess(0x001F0FFF, ffi.cast("BOOL", false), pid)
            if process_handle ~= nil then
                client_base = get_module_base(pid, "client.dll")
                if client_base == 0 then
                    kernel32.CloseHandle(process_handle)
                    process_handle = nil
                end
            end
        end
    end

    dbg_spacebar = false
    if process_handle ~= nil and client_base ~= 0 then
        local current_time = kernel32.GetTickCount()

        local local_player = read_dword(process_handle, client_base + LOCALPLAYER_OFFSET)
        dbg_local_player = local_player
        
        if local_player ~= 0 then
            local flags = read_int(process_handle, local_player + M_FLAGS)
            dbg_flags = flags

            local key_state = user32.GetAsyncKeyState(0x20)
            if bit.band(key_state, 0x8000) ~= 0 then
                dbg_spacebar = true

                if bhop_enabled then
                    if jump_state == 1 then
                        if current_time >= next_state_time then
                            write_int(process_handle, client_base + FORCE_JUMP, 4)
                            jump_state = 0
                        end
                    else
                        if bit.band(flags, 1) ~= 0 then
                            write_int(process_handle, client_base + FORCE_JUMP, 5)
                            next_state_time = current_time + 35
                            jump_state = 1
                        end
                    end
                end
            end
        else
            dbg_flags = 0
        end
    end
end

menu.add_tab("bhopLuashit", "External bhop", "I", function()

    run_bhop_tick()

    if imgui.BeginTabBar("randomfeaturestabbar") then
        
        if imgui.BeginTabItem("Movement") then
            imgui.Spacing()
            
            if process_handle ~= nil and client_base ~= 0 then
                imgui.TextColored(0.2, 1.0, 0.2, 1, string.format("Connected | Client.dll: 0x%X", client_base))
            else
                imgui.TextColored(1.0, 0.2, 0.2, 1, "Waiting for left4dead2.exe...")
            end
            imgui.Spacing()

            local btn_label = bhop_enabled and "Disable Bhop" or "Enable Bhop"
            if imgui.Button(btn_label, 120, 28) then
                bhop_enabled = not bhop_enabled
            end
            
            imgui.SameLine()
            if bhop_enabled then
                imgui.TextColored(0.2, 1.0, 0.2, 1, "[ ACTIVE ]")
            else
                imgui.TextColored(0.5, 0.5, 0.5, 1, "[ OFF ]")
            end

            imgui.Spacing()
            imgui.EndTabItem()
        end


        imgui.EndTabBar()
    end
end)

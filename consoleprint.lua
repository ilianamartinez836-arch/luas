-- @author: Natsumi
-- @created: 06.06 13:43
-- Echidna Script
local ffi = require("ffi")

ffi.cdef[[
    void* GetModuleHandleA(const char* lpModuleName);
    void* GetProcAddress(void* hModule, const char* lpProcName);

    typedef struct {
        unsigned char r, g, b, a;
    } SourceColor_t;

    typedef void(__cdecl* ConColorMsgFn)(const SourceColor_t* clr, const char* format, ...);
]]
-- unlikely to happen but better guard it than nothing
local tier0_base = ffi.C.GetModuleHandleA("tier0.dll")
if tier0_base == nil then
    print("[Error] Failed to get handle for tier0.dll")
    return
end

local mangled_name = "?ConColorMsg@@YAXABVColor@@PBDZZ"
local proc_addr = ffi.C.GetProcAddress(tier0_base, mangled_name)

if proc_addr == nil then
    print("[Error] Failed to find ConColorMsg export address")
    return
end

local ffi_ConColorMsg = ffi.cast("ConColorMsgFn", proc_addr)

function PrintConsoleColor(r, g, b, msg)
    local color_struct = ffi.new("SourceColor_t", r, g, b, 255)
    
    ffi_ConColorMsg(color_struct, msg .. "\n")
end

PrintConsoleColor(0, 255, 128, "Penis")

local ffi = require("ffi")

ffi.cdef[[
    typedef struct {
        uint16_t e_magic;
        uint8_t  pad[58];
        uint32_t e_lfanew;
    } IMAGE_DOS_HEADER;
    typedef struct {
        uint32_t BaseOfCode;
        uint32_t SizeOfCode;
    } IMAGE_OPTIONAL_HEADER_PARTIAL;
    typedef struct {
        uint32_t Signature;
        uint8_t  FileHeader[20];
        IMAGE_OPTIONAL_HEADER_PARTIAL OptionalHeader;
    } IMAGE_NT_HEADERS32_PARTIAL;
]]

local IN_ATTACK       = 1
local IN_USE          = 32
local IN_ATTACK2      = 2048
local MOVETYPE_NOCLIP = 8
local MOVETYPE_LADDER = 9

local hitscan_disabled_by_script = false
local aa_disabled_by_script = false

local client_base = ffi.cast("uintptr_t", memory.get_module_base("client.dll"))

local function get_movetype()
    local lp_ptr = ffi.cast("void**", client_base + 7498712)[0]
    if lp_ptr == nil then return 0 end
    local lp = tonumber(ffi.cast("uintptr_t", lp_ptr))
    return memory.read_u8(lp + 0x144)
end

local function should_disable_rage(cmd, movetype)
    if cmd:has_button(IN_USE)     then return true end
    if cmd:has_button(IN_ATTACK2) then return true end
    if movetype == MOVETYPE_LADDER or movetype == MOVETYPE_NOCLIP then return true end
    return false
end

function on_create_move(cmd, local_player)
    local_player = local_player or EntityCache.GetLocal()
    if not local_player then return end

    local current_movetype = get_movetype()

    if should_disable_rage(cmd, current_movetype) then
        if vars.get("hitscan.enable") == true then
            vars.set("hitscan.enable", false)
            hitscan_disabled_by_script = true
        end
    else
        if hitscan_disabled_by_script then
            vars.set("hitscan.enable", true)
            hitscan_disabled_by_script = false
        end
    end

    if current_movetype == MOVETYPE_LADDER or current_movetype == MOVETYPE_NOCLIP then
        if vars.get("aa.enabled") == true then
            vars.set("aa.enabled", false)
            aa_disabled_by_script = true
        end
    else
        if aa_disabled_by_script then
            vars.set("aa.enabled", true)
            aa_disabled_by_script = false
        end
    end
end

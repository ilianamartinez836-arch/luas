-- @author: Capella
-- @created: 17.05 14:51
-- Echidna Script
local ffi = require("ffi")

ffi.cdef[[
    void* GetModuleHandleA(const char* lpModuleName);
    void* GetProcAddress(void* hModule, const char* lpProcName);

    typedef struct {
        char __pad00[0x8];
        char name[32];
        int userid;
        char guid[33];
        unsigned int friendsid;
        char __pad01[0x150];
    } player_info_t;
]]

local client_base = ffi.C.GetModuleHandleA("client.dll")
local chatPtrAddr = ffi.cast("void***", ffi.cast("uintptr_t", client_base) + 0x757920)
local c_hud_chat = chatPtrAddr[0]
local ffi_print_chat = ffi.cast("void(__cdecl*)(void*, int, int, const char*, ...)", ffi.cast("void***", c_hud_chat)[0][23])

local function PrintChat(msg, ent_idx)
    local target_idx = ent_idx or 0
    ffi_print_chat(c_hud_chat, target_idx, 0, " " .. msg)
end

local function get_engine_client()
    local engine_mod = ffi.C.GetModuleHandleA("engine.dll")
    if engine_mod == nil then return nil end

    local create_interface = ffi.cast(
        "void* (__cdecl*)(const char*, int*)",
        ffi.C.GetProcAddress(engine_mod, "CreateInterface")
    )
    if create_interface == nil then return nil end

    return create_interface("VEngineClient013", nil)
end

local engine_client = get_engine_client()
if not engine_client then return end

local engine_vtbl = ffi.cast("void***", engine_client)
local vfunc_GetPlayerInfo = ffi.cast(
    "bool(__thiscall*)(void*, int, player_info_t*)",
    engine_vtbl[0][8]
)

local function DumpPlayerSteamIDs()
    if not EngineClient.IsInGame or not EngineClient.IsInGame() then
        return
    end

    local max_ent = ClientEntityList.GetHighestEntityIndex()

    for i = 1, max_ent do
        local ent = ClientEntityList.GetClientEntity(i)

        if ent and ent:is_valid() then
            local class_name = ent:get_class_name() or ""

            if class_name == "CTerrorPlayer" or class_name == "SurvivorBot" then
                local info = ffi.new("player_info_t[1]")
                
                if vfunc_GetPlayerInfo(engine_client, i, info) then
                    local name = ffi.string(info[0].name)
                    local steam_id = ffi.string(info[0].guid)
                    
                    if steam_id == "" or steam_id == "STEAM_ID_LAN" then
                        steam_id = "BOT/LAN"
                    end

                    PrintChat(string.format("[%d] %s -> %s", i, name, steam_id), i)
                end
            end
        end
    end
end

DumpPlayerSteamIDs()

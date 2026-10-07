-- @author: Aika
-- @created: 07.07 18:34
-- Echidna Script
-- when grabbed by a jockey it will airstuck and wont let the jockey move you around
-- if u are retarded and dont know what it does
local ffi = require("ffi")
ffi.cdef[[
    typedef struct {
        float x;
        float y;
        float z;
    } qangle_t;

    typedef struct {
        void* vmt;
        int   command_number;
        int   tick_count;
        qangle_t viewangles;
    } c_user_cmd_t;
]]

function on_create_move(cmd, lp)
    if not lp then return end
    if not EngineClient.IsInGame() then return end

    local cmd_pointer = ffi.cast("void**", cmd)[0]
    local raw_cmd = ffi.cast("c_user_cmd_t*", cmd_pointer)
    if raw_cmd == nil then return end

    local team = lp:get_prop_int("CBaseEntity", "m_iTeamNum")
    if team == 2 then
        local jockey_attacker = lp:get_prop_int("CTerrorPlayer", "m_jockeyAttacker")
        local is_jockeyed = (jockey_attacker > 0 and jockey_attacker ~= 0xFFFFFFFF and jockey_attacker ~= 2047)

        if is_jockeyed then
            raw_cmd.tick_count = 0xFFFFFF
        end
    end
end

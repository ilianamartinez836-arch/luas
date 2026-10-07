-- @author: HaruUrara
-- @created: 17.06 11:45
-- Echidna Script
local ffi = require("ffi")

if not _G._fm_loaded then
    ffi.cdef[[
        void* GetModuleHandleA(const char* lpModuleName);
        void* GetProcAddress(void* hModule, const char* lpProcName);
        typedef void* (*CreateInterfaceFn)(const char* name, int* ret);
        typedef struct CmdBase_s {
            void* vtable;
            struct CmdBase_s* pNext;
            char              bRegistered;
            char              _pad[3];
            const char* pszName;
            const char* pszHelpString;
            int               nFlags;
        } CmdBase_t;
        typedef void       (__thiscall *IterVoidFn)(void* self);
        typedef bool       (__thiscall *IterBoolFn)(void* self);
        typedef CmdBase_t* (__thiscall *IterGetFn )(void* self);
        typedef struct {
            void* dtor;
            IterVoidFn SetFirst;
            IterVoidFn Next;
            IterBoolFn IsValid;
            IterGetFn  Get;
        } IterVtbl_t;
        typedef struct { IterVtbl_t* vtbl; } ICVarIter_t;
        typedef ICVarIter_t* (__thiscall *FactoryIterFn)(void* icvar);
        short GetAsyncKeyState(int vKey);
    ]]
    _G._fm_loaded = true
end

local FACTORY_SLOT                = 38
local FCVAR_CLIENTCMD_CAN_EXECUTE = bit.lshift(1, 30)
local VK_M4                        = 0x05
local IN_ATTACK                    = 1

local WAIT_HIT    = 0.220
local WAIT_SWAP   = 0.150
local WAIT_CYCLE  = 0.550

local function patch_slots()
    local vstdlib = ffi.C.GetModuleHandleA("vstdlib.dll")
    if not vstdlib or ffi.cast("uintptr_t", vstdlib) == 0 then return end
    local ci_raw = ffi.C.GetProcAddress(vstdlib, "CreateInterface")
    if not ci_raw then return end
    local icvar = ffi.cast("CreateInterfaceFn", ci_raw)("VEngineCvar007", nil)
    if not icvar or ffi.cast("uintptr_t", icvar) < 0x10000 then return end
    local vtbl = ffi.cast("void***", icvar)[0]
    local ok, iter = pcall(function()
        return ffi.cast("FactoryIterFn", vtbl[FACTORY_SLOT])(icvar)
    end)
    if not ok or not iter or ffi.cast("uintptr_t", iter) < 0x10000 then return end
    iter.vtbl.SetFirst(iter)
    local count = 0
    while iter.vtbl.IsValid(iter) do
        count = count + 1
        if count > 8000 then break end
        local cmd = iter.vtbl.Get(iter)
        if cmd ~= nil and ffi.cast("uintptr_t", cmd) > 0x10000 then
            local ok2, name = pcall(ffi.string, cmd.pszName)
            if ok2 and (name == "slot1" or name == "slot2") then
                cmd.nFlags = bit.bor(cmd.nFlags, FCVAR_CLIENTCMD_CAN_EXECUTE)
            end
        end
        iter.vtbl.Next(iter)
    end
end

patch_slots()

local state    = "idle"
local timer    = 0
local key_prev = false

local function key_down()
    return bit.band(ffi.C.GetAsyncKeyState(VK_M4), 0x8000) ~= 0
end

function on_create_move(cmd, local_player)
    if not local_player then return end
    if not EngineClient.IsInGame() then return end

    local now     = os.clock()
    local holding = key_down()
    local pressed = holding and not key_prev
    key_prev      = holding

    if state == "idle" then
        if pressed then
            EngineClient.ClientCmd("slot2")
            timer = now
            state = "wait_hit"
        end

    elseif state == "wait_hit" then
        if not holding then
            EngineClient.ClientCmd("slot1")
            state = "idle"
        elseif now - timer >= WAIT_HIT then
            EngineClient.ClientCmd("slot1")
            timer = now
            state = "swap_back"
        else
            cmd:add_button(IN_ATTACK)
        end

    elseif state == "swap_back" then
        if not holding then
            state = "idle"
        elseif now - timer >= WAIT_SWAP then
            EngineClient.ClientCmd("slot2")
            timer = now
            state = "wait_cycle"
        end

    elseif state == "wait_cycle" then
        if not holding then
            state = "idle"
        elseif now - timer >= WAIT_CYCLE then
            timer = now
            state = "wait_hit"
            cmd:add_button(IN_ATTACK)
        end
    end
end

function on_unload()
    pcall(function()
        EngineClient.ClientCmd("slot1")
    end)
end

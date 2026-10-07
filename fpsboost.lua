local ffi = require("ffi")
_G._fpsboost_types_loaded = nil

if not _G._fpsboost_types_loaded then
    ffi.cdef[[
        void*  GetModuleHandleA(const char* lpModuleName);
        void*  GetProcAddress(void* hModule, const char* lpProcName);

        typedef struct { unsigned char r, g, b, a; } SourceColor_t;
        typedef void(__cdecl* ConColorMsgFn)(const SourceColor_t* clr, const char* fmt, ...);
        typedef void* (*CreateInterfaceFn)(const char* name, int* ret);

        typedef struct CmdBase_s {
            void*              vtable;
            struct CmdBase_s*  pNext;
            char               bRegistered;
            char               _pad[3];
            const char*        pszName;
            const char*        pszHelpString;
            int                nFlags;
        } CmdBase_t;

        typedef void        (__thiscall *IterVoidFn)(void* self);
        typedef bool        (__thiscall *IterBoolFn)(void* self);
        typedef CmdBase_t*  (__thiscall *IterGetFn )(void* self);
        typedef struct {
            void*      dtor;
            IterVoidFn SetFirst;
            IterVoidFn Next;
            IterBoolFn IsValid;
            IterGetFn  Get;
        } IterVtbl_t;
        typedef struct { IterVtbl_t* vtbl; } ICVarIter_t;

        typedef ICVarIter_t* (__thiscall *FactoryIterFn)(void* icvar);
        typedef CmdBase_t*   (__thiscall *FindVarFn   )(void* icvar, const char* name);

        typedef struct ConVar_s {
            void*             vtable;
            struct ConVar_s*  pNext;
            uint8_t           bRegistered;
            uint8_t           _pad0[3];
            const char*       pszName;
            const char*       pszHelpString;
            int               nFlags;
            void*             iConVarVtbl;
            struct ConVar_s*  pParent;
            const char*       pszDefaultValue;
            char*             pszString;
            int               nStringLength;
            float             fValue;
            int               nValue;
            uint8_t           bHasMin;
            uint8_t           _pad1[3];
            float             fMinVal;
            uint8_t           bHasMax;
            uint8_t           _pad2[3];
            float             fMaxVal;
        } ConVar_t;
    ]]
    _G._fpsboost_types_loaded = true
end

local _t0  = ffi.C.GetModuleHandleA("tier0.dll")
local _ccm = _t0 and ffi.C.GetProcAddress(_t0, "?ConColorMsg@@YAXABVColor@@PBDZZ")
_ccm = _ccm and ffi.cast("ConColorMsgFn", _ccm)
local function PrintColor(r, g, b, msg)
    if _ccm then _ccm(ffi.new("SourceColor_t", r, g, b, 255), msg .. "\n") end
end
local original_cvars = {}
local function SetI(n, v) 
    local c = Cvars.FindVar(n)
    if c then 
        if original_cvars[n] == nil then
            original_cvars[n] = { type = "int", val = c:GetInt() }
        end
        c:SetInt(v)   
    end 
end

local function SetF(n, v) 
    local c = Cvars.FindVar(n)
    if c then 
        if original_cvars[n] == nil then
            original_cvars[n] = { type = "float", val = c:GetFloat() }
        end
        c:SetFloat(v) 
    end 
end

local function SetS(n, v) 
    local c = Cvars.FindVar(n)
    if c then 
        if original_cvars[n] == nil then
            original_cvars[n] = { type = "string", val = c:GetString() }
        end
        c:SetString(v) 
    end 
end

local function getRawPtr(cv)
    if not cv then return nil end
    local hex = tostring(cv):match("0x(%x+)")
    if not hex then return nil end
    local payload = ffi.cast("uintptr_t", tonumber("0x" .. hex))
    if payload < 0x10000 then return nil end
    local pConVar = ffi.cast("uintptr_t*", payload)[0]
    if pConVar < 0x10000 then return nil end
    local ptr = ffi.cast("CmdBase_t*", pConVar)
    local ok  = pcall(ffi.string, ptr.pszName)
    return ok and ptr or nil
end

local FCVAR_DEVELOPMENTONLY = 2
local FCVAR_HIDDEN          = 16
local FCVAR_PROTECTED       = 32
local FCVAR_CHEAT           = 16384
local FLAG_STRIP_MASK = bit.bor(FCVAR_DEVELOPMENTONLY, FCVAR_HIDDEN, FCVAR_PROTECTED, FCVAR_CHEAT)

local FINDVAR_SLOT = 12
local FACTORY_SLOT = 38
local g_icvar      = nil

local function getConVarRawPtr(name)
    if not g_icvar then return nil end
    local vtbl = ffi.cast("void***", g_icvar)[0]
    local ok, result = pcall(ffi.cast("FindVarFn", vtbl[FINDVAR_SLOT]), g_icvar, name)
    if not ok or result == nil or ffi.cast("uintptr_t", result) < 0x10000 then return nil end
    return ffi.cast("CmdBase_t*", result)
end

local function rawRemoveFlag(nameOrCV, flag)
    if type(nameOrCV) == "string" then
        local ptr = getConVarRawPtr(nameOrCV)
        if ptr then ptr.nFlags = bit.band(ptr.nFlags, bit.bnot(flag)); return true end
    end
    local cv  = type(nameOrCV) == "string" and Cvars.FindVar(nameOrCV) or nameOrCV
    local ptr = getRawPtr(cv)
    if not ptr then return false end
    ptr.nFlags = bit.band(ptr.nFlags, bit.bnot(flag))
    return true
end

local function patchConVarBounds(name, removeMin, removeMax)
    local base = getConVarRawPtr(name)
    if not base then return false end
    local cv  = ffi.cast("ConVar_t*", base)
    local par = cv.pParent
    if par ~= nil and ffi.cast("uintptr_t", par) > 0x10000 then cv = par end
    cv.nFlags = bit.band(cv.nFlags, bit.bnot(FLAG_STRIP_MASK))
    if removeMin then cv.bHasMin = 0 end
    if removeMax then cv.bHasMax = 0 end
    return true
end

local function patchConVarMeta()
    local probe = Cvars.FindVar("sv_cheats")
    if not probe then return false end
    local mt  = getmetatable(probe)
    if not mt then return false end
    local idx = rawget(mt, "__index")
    if type(idx) ~= "table" then return false end
    idx.RemoveFlags = function(self, flags)
        local p = getRawPtr(self)
        if p then p.nFlags = bit.band(p.nFlags, bit.bnot(flags)) end
    end
    idx.GetRawPtr   = function(self) return getRawPtr(self) end
    idx.GetRawFlags = function(self) local p = getRawPtr(self); return p and p.nFlags end
    return true
end

local function unlockViaIterator(icvar)
    local vtbl = ffi.cast("void***", icvar)[0]
    g_icvar = icvar

    local ok, iter = pcall(function()
        return ffi.cast("FactoryIterFn", vtbl[FACTORY_SLOT])(icvar)
    end)
    if not ok or not iter or ffi.cast("uintptr_t", iter) < 0x10000 then
        return false
    end

    iter.vtbl.SetFirst(iter)
    local total = 0
    while iter.vtbl.IsValid(iter) do
        total = total + 1
        if total > 8000 then break end
        local cmd = iter.vtbl.Get(iter)
        if cmd ~= nil and ffi.cast("uintptr_t", cmd) > 0x10000 then
            if bit.band(cmd.nFlags, FLAG_STRIP_MASK) ~= 0 then
                cmd.nFlags = bit.band(cmd.nFlags, bit.bnot(FLAG_STRIP_MASK))
            end
        end
        iter.vtbl.Next(iter)
    end
    return true
end

local function stripPerCvar()
    local targets = {
        "mat_fullbright","mat_picmip","mat_filtertextures","mat_filterlightmaps",
        "mat_fastnobump","mat_fastspecular","mat_reducefillrate","mat_antialias",
        "mat_bumpmap","mat_specular","mat_phong",
        "r_rootlod","r_lod","r_staticprop_lod",
        "r_shadows","r_dynamic","r_maxdlights",
        "r_waterdrawreflection","r_waterdrawrefraction","r_drawflecks","r_drawdetailprops",
    }
    for _, name in ipairs(targets) do rawRemoveFlag(name, FLAG_STRIP_MASK) end
end

local function UnlockCheats()
    local vstdlib = ffi.C.GetModuleHandleA("vstdlib.dll")
    if vstdlib and ffi.cast("uintptr_t", vstdlib) > 0 then
        local ci_raw = ffi.C.GetProcAddress(vstdlib, "CreateInterface")
        if ci_raw then
            local icvar = ffi.cast("CreateInterfaceFn", ci_raw)("VEngineCvar007", nil)
            if icvar and ffi.cast("uintptr_t", icvar) > 0x10000 then
                if unlockViaIterator(icvar) then return end
            end
        end
    end
    stripPerCvar()
end

local _cv_picmip     = nil
local _cv_fullbright = nil

local function EnforceVolatile()
    _cv_picmip     = _cv_picmip     or Cvars.FindVar("mat_picmip")
    _cv_fullbright = _cv_fullbright or Cvars.FindVar("mat_fullbright")

    if _cv_picmip and _cv_picmip:GetInt() ~= 4 then
        patchConVarBounds("mat_picmip", false, true)
        SetI("mat_picmip", 4)
    end

    if _cv_fullbright and _cv_fullbright:GetInt() ~= 0 then
        SetI("mat_fullbright", 0)
    end
end

local function ApplyFPSBoost()
    SetI("sv_cheats", 1)
    SetI("sv_consistency", 0)
    patchConVarMeta()
    UnlockCheats()


    patchConVarBounds("mat_picmip", false, true)
    SetI("mat_picmip", 4)
    SetI("mat_filtertextures", 0)
    SetI("mat_filterlightmaps", 0)
    SetI("mat_mipmaptextures", 1)
    SetI("mat_compressedtextures", 1)
    SetI("mat_reducefillrate", 1)
    SetI("mat_antialias", 0)
    SetI("mat_forceaniso", 0)
    SetI("mat_bumpmap", 0)
    SetI("mat_fastnobump", 1)
    SetI("mat_specular", 0)
    SetI("mat_fastspecular", 1)
    SetI("mat_phong", 0)

    SetI("r_rootlod", 1)
    SetI("r_lod", 1)
    SetI("r_staticprop_lod", 1)

    SetI("cl_threaded_client_leaf_system", 0)
    SetI("r_threaded_client_shadow_manager", 0)
    SetI("r_threaded_particles", 0)

    SetI("mat_hdr_level", 2)
    SetI("mat_disable_bloom", 1)
    SetI("mat_bloom_scalefactor_scalar", 0)
    SetI("mat_colorcorrection", 0)
    SetI("mat_motion_blur_enabled", 0)
    SetI("r_shadowrendertotexture", 0)
    SetI("r_flashlightdepthtexture", 0)
    SetI("r_ambientboost", 0)
    SetI("r_rimlight", 0)
    SetI("r_3dsky", 1)

    SetI("r_waterdrawreflection", 0)
    SetI("r_waterdrawrefraction", 0)
    SetI("r_waterforceexpensive", 0)
    SetI("r_waterforcereflectentities", 0)

    SetI("r_decals", 0)
    SetI("mp_decals", 0)
    SetI("r_drawmodeldecals", 0)
    SetI("r_queued_decals", 0)
    SetI("r_decal_cullsize", 15)
    SetI("cl_playerspraydisable", 1)
    SetI("r_spray_lifetime", 0)

    SetI("props_break_max_pieces", 0)
    SetI("r_drawflecks", 0)
    SetI("cl_show_splashes", 0)
    SetI("r_renderoverlayfragment", 1)

    SetI("r_drawdetailprops", 0)
    SetI("cl_detaildist", 0)
    SetI("cl_detailfade", 0)
    SetI("cl_detail_avoid_force", 0)
    SetI("cl_detail_avoid_recover_speed", 0)
    SetI("cl_detail_max_sway", 0)

    SetI("r_ropetranslucent", 0)
    SetI("rope_smooth", 0)
    SetI("rope_subdiv", 0)
    SetI("rope_averagelight", 0)
    SetI("rope_collide", 0)
    SetI("rope_rendersolid", 0)
    SetI("rope_shake", 0)
    SetI("rope_wind_dist", 0)
    SetI("r_queued_ropes", 1)

    SetI("cl_ragdoll_limit", 0)
    SetI("cl_ragdoll_collide", 0)
    SetI("cl_phys_props_enable", 0)
    SetI("cl_phys_props_max", 0)
    SetI("g_ragdoll_fadespeed", 9999)
    SetI("g_ragdoll_lvfadespeed", 9999)


    SetI("fps_max", 0)
    SetI("mat_vsync", 0)
    SetI("r_fastzreject", -1)
    SetI("r_occlusion", 1)
    SetI("cl_forcepreload", 1)
    SetI("sv_forcepreload", 1)
    SetI("cl_allowdownload", 0)
    SetI("cl_allowupload", 0)
    SetS("cl_downloadfilter", "none")
    SetI("dsp_slow_cpu", 1)
    SetI("cl_ejectbrass", 0)
    SetI("violence_hblood", 0)
    SetI("violence_ablood", 0)
    SetI("violence_hgibs", 0)
    SetI("violence_agibs", 0)

    -- SetI("r_drawviewmodel", 0)
    -- SetI("cl_drawhud", 0)
    -- SetI("r_drawparticles", 0)
    -- SetI("r_drawsprites", 0)
    -- SetF("mat_viewportscale", 0.75)
    -- SetI("r_drawstaticprops", 0)
    -- SetI("r_flex", 0)
    -- SetI("r_eyes", 0)
    -- SetI("r_teeth", 0)
    -- SetI("mat_queue_mode", -1)
    -- SetI("cl_threaded_bone_setup", 0)
    -- SetI("r_threaded_renderables", 0)
    -- SetI("r_queued_post_processing", 0)
    -- SetI("studio_queue_mode", 0)

    PrintColor(255, 200, 0, " FPS boost applied")
end
function on_create_move(cmd, local_player)
    EnforceVolatile()
end

function on_level_init_pre(mapname)
    _cv_picmip     = nil
    _cv_fullbright = nil
    
    ApplyFPSBoost()
end
ApplyFPSBoost()
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠤⢲⣦⡀⠀⣠⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣠⠖⠚⠓⠒⠒⠲⠿⣍⣛⣻⣦⣷⢠⣻⣀⠤⠤⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠔⡿⠓⠲⠬⢥⡤⠤⠤⠤⠤⣤⣀⣀⣈⣻⣿⣿⠓⠉⣀⡤⠔⢶⣻⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⢤⠞⠁⣼⠀⠀⠀⠀⠀⠀⠰⠶⢌⣽⡶⠟⢏⡁⢈⣉⣭⣷⡯⣝⠒⢦⣄⠙⠷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡾⣵⠿⣳⡟⠉⠉⠿⠀⠀⡀⠀⠀⣀⣀⣢⣾⣿⡚⠓⠒⠒⠒⠻⢿⣟⣧⡀⢠⣢⡻⠙⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡀⢿⣟⣲⢿⣷⢀⣤⣠⣄⣈⢿⣷⣤⣷⣻⡓⠒⠻⠭⢷⡄⠒⠲⢶⣦⣬⣻⣏⢦⡈⢿⣆⠘⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⢖⣩⠷⢎⣙⣿⣿⣼⡼⣿⣟⣽⣻⢯⢿⠞⣌⠙⢳⡕⠀⠙⠲⣶⠤⢄⡠⣄⡈⠛⣿⣿⣧⢳⣌⢻⡆⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠰⠗⠉⢀⣾⠟⠒⡿⣫⡿⡾⢫⢟⡏⠉⢸⡀⠑⢾⡆⢤⣻⣶⣤⣘⣲⣿⣶⡽⠿⣯⠲⣌⣇⢹⣷⣿⣆⠸⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⡼⠀⣿⢣⣧⠋⣸⠀⣰⢀⣿⣆⠀⠰⣄⠙⣧⣨⣿⣿⣿⣯⣿⣦⠘⣷⡌⢻⡄⠿⣆⠟⣆⢇⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠀⠀⠀⠀⠀⠀⠀⠀⡇⡼⣹⠈⢣⠆⡇⣰⣻⣼⣿⣽⣷⣦⣹⣿⣟⣯⠉⠘⣿⠏⠃⠀⣷⣽⡿⣾⡹⣷⣹⣧⡈⢺⡀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⢾⠟⠉⠀⠀⠀⠀⠀⠀⠀⠀⣷⣱⣽⡀⢸⣆⢳⣿⣇⣷⡿⠖⠿⠷⢦⣙⣆⠩⡗⠀⠀⠀⠀⠀⡯⠿⠳⣟⠻⣽⣄⢧⠈⠳⣷⡀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⡇⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣿⣿⣷⣸⣿⡀⣿⣅⠛⠇⠀⠀⠀⠀⢈⠙⠂⠀⠀⠀⠀⠀⣸⣿⠀⢠⣜⢦⠘⢿⣮⣷⡀⠀⠙⢦⡀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⢯⣇⠙⢄⣀⠀⠀⠀⢀⣀⡠⣴⣾⣫⠵⠛⣿⣻⠿⣷⣹⣾⣷⡠⡀⠀⠀⠀⠻⠦⠀⣀⠔⠀⠀⣴⣿⣸⣧⡀⠳⣝⠳⢴⡙⢞⣏⠢⡀⠀⠹⡄⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⢀⣀⣀⣈⣻⣤⣀⠈⠉⠻⠿⢿⣺⣿⡵⣶⢶⣦⠀⠘⣿⢷⣾⢿⣿⡋⢙⣮⣄⡀⠀⠀⠉⠈⠀⠀⢀⢞⣿⣼⣿⣿⣿⣆⡀⠙⢦⣝⣮⠛⢷⡙⢆⠀⣷⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⢠⡴⢟⣫⠤⠖⠒⠛⢛⣲⣿⣿⣿⠟⠋⢱⣿⣴⣷⣿⣹⢃⣀⣘⠃⢩⢿⣫⣥⣿⠧⢿⣿⣗⡶⣤⣄⣀⣴⣷⣻⣿⣿⠻⠘⣏⠛⢿⣦⣀⠱⢤⣉⡑⠛⠮⢿⣹⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⢠⢖⠵⠊⠁⢀⡤⠖⣲⣿⣿⣟⣻⣿⣋⠀⠀⠈⢿⣿⡿⠟⣵⣿⣿⣿⣷⡏⠈⢿⡿⣷⣤⣼⢿⣿⣿⢶⣯⣭⣵⣾⢿⣿⠿⢦⡀⢹⠀⠈⣏⠉⠉⢻⣶⣯⡑⠦⣄⠈⠳⣄⠀⠀")
PrintColor(255, 120, 255, "⠀⠹⠁⠀⠀⣞⢁⡾⢽⣯⣝⣛⣛⣯⣭⣽⣿⣷⣶⣤⣤⣴⣿⣿⣿⣿⣿⣿⡀⣀⣼⣀⠈⠙⠛⠷⣾⡿⢿⡟⣿⠟⠁⣈⣥⡴⠾⠷⢾⡄⠀⣿⠀⠀⠈⢇⠘⣿⣤⣀⠑⢦⡘⢧⠀")
PrintColor(255, 120, 255, "⠄⠀⠀⠀⠀⠈⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⢿⡿⠛⣻⢏⡽⣯⡄⠘⣏⣿⡏⠈⠙⠓⠶⣤⣀⠀⠙⢿⣿⡇⢀⡿⠋⠁⠀⢀⣀⣸⡇⠀⣟⣀⠀⠀⠀⠙⠃⣿⡎⠑⣤⡙⣌⡇")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⣿⣿⣿⣿⣿⣿⡥⣖⡯⠖⢋⣡⡞⣼⣿⠀⠀⢹⣿⣷⠀⠀⣀⡀⠀⠉⠻⣦⠀⢿⣿⡿⠁⣠⡶⠟⠋⠉⠹⣆⣸⣿⣿⠀⣀⡤⣤⡀⣿⠇⠀⢸⠳⡜⡇")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⣈⣿⣿⣿⣿⣿⣿⣏⢿⣗⠒⠊⠉⢸⠁⡿⡏⠀⢀⣿⡿⣁⠤⢶⣿⣽⡆⠀⠀⠘⢷⡈⠉⣡⠾⠋⠀⠀⣠⣆⢠⣿⣿⣿⡟⢀⣷⠒⢺⣧⡏⠀⠀⢸⠀⢹⣹")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⡠⢪⠟⡽⠙⢶⣾⣿⣿⣿⣷⡻⣦⡀⠀⠀⢣⣇⡇⢀⡞⣸⠏⠁⠀⠀⡇⢻⡀⠀⠀⣾⣶⡟⣿⣥⡄⠀⠀⢠⣇⣼⡶⣿⣿⠋⣸⣾⣷⣚⣽⡟⠀⠀⠀⣏⠀⡼⣿")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⢀⠎⡴⣣⣾⠟⣡⠞⢹⡿⣿⢿⣿⣿⣿⣷⣄⠀⠈⠻⡹⣼⠀⣿⡄⠀⠀⠀⠉⠻⣷⡀⠀⠙⠿⠇⣿⠿⠇⠀⠀⢠⡿⠋⢇⢹⣟⢷⠫⣿⣟⡿⠋⠀⠀⣠⣾⢞⡜⠁⡿")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⡼⡼⣵⠏⡏⣰⠃⠀⢾⡇⠈⠻⣿⣮⡉⠹⣿⣧⣄⡀⠙⣇⠀⠸⣿⣄⡀⠀⠀⠀⠈⢉⣧⡴⠀⠠⡄⣀⡤⠤⠴⠋⠁⠀⠈⢻⣿⣾⣤⡿⠋⠀⠀⠀⣉⣽⠿⠋⠀⣰⠃")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⣿⣽⠋⠀⡇⡇⠀⠀⠘⣷⢠⣶⢮⣻⣿⣦⠈⠛⠙⠹⣷⠘⢦⣤⣿⣳⣭⣑⣒⣒⣺⣿⢿⣀⣀⣀⣿⣧⣀⣀⣀⡤⠴⠒⣶⣿⣏⣾⡿⠁⠀⠀⠀⠉⠉⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⢻⡏⠀⠀⢳⣇⠀⠀⠀⠈⠈⣿⣾⣿⣿⣮⣿⣦⠀⠀⢿⣶⡫⣿⣿⣿⣿⣿⡹⣯⣊⠁⠉⠉⠉⠉⢙⣮⣷⣶⡤⣤⣶⣿⣿⣟⣾⢿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠸⣿⣦⡀⠀⠙⠦⠀⠀⢀⣼⠿⣽⣿⣯⣷⣼⡷⢾⣻⣾⣿⠞⢿⢻⡷⠻⣿⣏⡙⢝⣻⡾⡖⠒⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⣎⠣⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠈⠁⠀⠀⠀⠀⣴⣋⣉⣩⣿⣿⢿⣟⣷⣾⣯⡟⢱⡇⠀⠘⣿⠣⡀⣈⣻⣿⣿⣿⣷⣷⣶⣿⣿⣟⠋⡿⣹⣿⣿⣿⣿⢟⣏⠺⠿⠶⠭⠷⠂⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⣿⣿⣿⣿⣿⣿⣿⢹⣮⣾⣿⡿⢋⣶⢸⡇⠀⠀⠈⢷⡑⠈⢻⣟⠛⠛⠿⠋⠙⠓⣭⣿⣹⣵⣿⣿⣿⣿⣿⠈⠻⣷⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⢟⣛⡭⠶⢾⡿⠃⠀⠀⢸⢹⣾⣇⠀⠀⠀⠀⠻⣟⣿⡏⠀⠀⠀⠀⢰⣿⣿⢿⡇⣿⣿⣿⣿⣟⡏⠀⠀⠀⠉⠙⠓⠒⠂⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡟⠀⠀⠀⢰⣿⢸⣿⢿⡀⠀⠀⠀⠀⢸⣿⣣⠀⠀⠀⢠⣿⡟⣷⣾⣿⢿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⠁⠀⠀⠀⠘⡿⡿⢿⣏⣧⠀⠀⠀⢀⣾⣿⠿⠀⢀⣴⣿⣿⢿⡹⡇⣿⠈⣿⣿⡟⣾⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡇⠀⠀⠀⠀⢳⢧⠈⢿⣿⠀⠀⢀⣼⣿⠕⠁⣠⣾⡿⣻⠏⠀⢹⣹⣿⣆⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⣷⠀⠀⠀⠀⠈⣏⢧⠀⢻⣧⠶⣋⠿⠋⣀⣾⣟⣿⠞⠁⠀⠀⠀⢯⣿⣿⣿⣿⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⣇⠀⠀⠀⠀⠸⡜⣆⠈⢷⣿⠀⢠⣾⣿⠟⢻⡏⠀⠀⠀⠀⠀⠘⣿⣿⠏⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡻⣿⣿⣦⡀⠀⠀⠀⢧⠘⣆⠈⢷⠒⠛⢻⡿⠄⠘⣧⠀⠀⠀⠀⠀⢰⣷⣹⠀⠙⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣷⣝⣿⣿⣷⣄⠀⠀⠈⢇⠸⡄⠈⣇⠀⠀⢻⣆⠀⠘⣇⠀⠀⣠⣾⣽⢹⡟⠀⢰⣷⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣾⢻⠙⢿⣿⡇⠀⠀⠈⢧⢳⠀⢸⡀⠀⠀⢻⣆⠀⢻⡄⢠⣿⣯⣽⣓⣧⣤⠾⢹⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣼⡇⠀⠙⣿⠀⠀⠀⠈⢏⢧⠀⣇⠀⠀⠀⢻⣆⠀⢷⠘⣿⣮⡻⣿⠁⠀⢀⣯⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⣧⡀⠀⠀⠀⠀⠀⠀⠘⡾⡄⢸⠀⠀⠀⠈⢻⣆⠈⢷⣷⣾⣟⣻⣶⣿⡿⠛⢿⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣿⣿⣿⣦⣀⠀⠀⠀⠀⠀⢳⣇⠘⡆⠀⠀⠀⠀⠻⣶⢺⡏⢹⡟⠀⠉⠁⠀⠀⠀⢩⣍⠙⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣟⣿⣿⣿⣧⠀⢀⣤⣤⡸⣸⠀⡇⠀⠀⠀⠀⠀⠙⣿⣷⢡⣿⣶⣄⠀⠀⣄⠀⣦⣍⠙⢳⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⡿⢿⡙⠿⠀⢸⡟⢲⣷⡿⡄⢿⠀⠀⠀⠀⠀⠀⠘⣏⢸⣇⣍⢻⣷⣀⢻⣦⣤⣌⡙⣦⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣯⢷⠀⠀⠸⡇⠀⢿⣧⡇⢸⠀⠀⠀⠀⠀⠀⠀⣼⢸⣿⣯⠀⣿⣿⣷⣝⣿⣻⣿⣼⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣎⣧⠀⠐⣇⠀⠘⣽⣿⡸⡆⠀⠀⠀⠀⠀⠀⠈⠋⠈⠻⣼⣿⢶⢿⣿⣯⡻⣿⣿⣾⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⡼⡆⠀⣿⡀⠀⣿⢿⡇⢷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣾⢧⠈⠙⠿⣮⠟⠉⠙⢦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢿⢻⢠⣿⡇⠀⠹⣄⢳⣜⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⡏⠪⠳⢤⣄⣀⠀⠀⠀⠈⢣⠀⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣎⣿⡟⡇⠀⠀⠈⢻⣿⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢳⡄⠀⠀⠀⠙⢧⡀⢀⡄⠈⡇⠀⠀⠀⠀⠀⠀⠀⠀")
PrintColor(255, 120, 255, "FPS OPTIMIZER BY NATSUMI/AIKA -- mat_picmip = 1 (Normal) mat_picmip = 4 (Potato)")
Cvars.FindVar("mat_picmip"):SetInt(4) --forcer on top of the other ones, just double check and blabalblablabl
function on_unload()
    local restored_count = 0

    for name, data in pairs(original_cvars) do
        local c = Cvars.FindVar(name)
        if c then
            if data.type == "int" then
                c:SetInt(data.val)
            elseif data.type == "float" then
                c:SetFloat(data.val)
            elseif data.type == "string" then
                c:SetString(data.val)
            end
            restored_count = restored_count + 1
        end
    end

    PrintColor(255, 100, 100, string.format(" FPS boost disabled. Successfully restored %d original CVars.", restored_count))
end

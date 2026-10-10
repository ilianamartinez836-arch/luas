-- ============================================================
-- FMC All-in-One: 自瞄 + 自动推搡 + 无下坠保护 + 快速近战 + 网络监控
-- 合并自: firebullaim.lua (FMC自瞄) + 666688nofall.lua (twilight自动推++) + FastMelee (HaruUrara快速近战)
-- 优先级: 推搡 > 快速近战 > 自瞄 (特感贴脸时先推再瞄, 近战循环时不自瞄)
-- ============================================================

-- ============================================================
-- FFI Shoot Position (firebullaim)
-- ============================================================
local client_base = modules.get_client_base()

local _shootPosFn = ffi.cast("void(__thiscall*)(void*, float[3])", client_base + 108512)
local _shootBuf   = ffi.new("float[3]")
local function getShootPosition(rawPlayer)
    local ok, err = pcall(_shootPosFn, ffi.cast("void*", rawPlayer), _shootBuf)
    if not ok then
        client.print("[FBAim] getShootPosition crash: " .. tostring(err))
        return nil
    end
    return vector.new(_shootBuf[0], _shootBuf[1], _shootBuf[2])
end

-- ============================================================
-- 重复加载保护
-- ============================================================
if _G.__fb_aim_guard then
    client.print("[FBAim] Already loaded — duplicate blocked")
    return
end
_G.__fb_aim_guard = true
_G.__autoshove_guard = true

-- ============================================================
-- Anti-Cheat Bypass Parameters (LILAC v1.7.11 + SMAC v0.8.6.4)
-- ============================================================
-- SNAP检测: 击杀前0.5s内任一单帧角度变化>5.0°(SNAP2)或>10.0°(SNAP1)
--   → 绝对上限: DELTA_CAP + JITTER_MAX < 5.0°
--
-- REPEAT检测: 射击帧delta(N-1→N) > 前后帧tdelta(N-1→N+1) * 5.0
--   → 射击帧锚定: 按下攻击键的帧角度变化量受限，与前后帧连续
--
-- AIMLOCK检测: aimdist<5.0°持续>0.1s + 单帧>20.0°才触发
--   → 定期lock-break + 抖动保证不会长时间完美锁头
--
-- AUTOSHOOT: 3帧窗口内恰好1帧IN_ATTACK → 单发武器强制2-3帧攻击
-- TOTAL_DELTA: 0.5s内累计<450° → 远低于阈值
-- SMAC: 45°/帧阈值 → 完全不构成威胁
-- ============================================================
local DELTA_CLOSE     = 300.0
local DELTA_FAR       = 800.0
local DELTA_CAP_NEAR  = 1.8
local DELTA_CAP_MID   = 1.5
local DELTA_CAP_FAR   = 1.2
local DELTA_CAP       = DELTA_CAP_MID
local JITTER_MIN      = 0.20
local JITTER_MAX      = 0.35
local SMOOTH          = 4.5
local LOCK_BREAK_MIN  = 100
local LOCK_BREAK_MAX  = 180
local AIMLOCK_JITTER  = 0.60

local SHOOT_ANCHOR_CAP = 1.0

-- 拟人化: 平滑速度每10-18帧微调±25%, 避免匀速跟踪
local smooth_variation = 1.0
local smooth_var_timer = 0
local SMOOTH_VAR_INTERVAL_MIN = 10
local SMOOTH_VAR_INTERVAL_MAX = 18

local IN_ATTACK_BIT = 1
local prev_attack_state = false
local attack_frame_count = 0
local SEMIAUTO_AUTO_HOLD_TICKS = 2
local SEMIAUTO_AUTO_RELEASE_TICKS = 1
local SEMIAUTO_AIM_READY_FOV = 1.25
local semiauto_hold_ticks = 0
local semiauto_release_ticks = 0

local jitter_cur_x = 0.0
local jitter_cur_y = 0.0
local jitter_target_x = 0.0
local jitter_target_y = 0.0
local jitter_smooth_factor = 0.35
local jitter_reseed_interval = 6
local jitter_reseed_counter = 0

-- ============================================================
-- 无下坠保护参数 (from twilight)
-- ============================================================
local NOFALL_THRESHOLD = 320.0
local NOFALL_SEQUENCE_SHIFT = 180000

-- ============================================================
-- Anti-Jockey 参数 (from antijockarreglaoxd)
-- ============================================================
local AJ_TEAM_OFFSET = 228
local AJ_JOCKEY_ATTACKER_OFFSET = 10060
local is_jockeyed = false
local aj_raw_handle = 0

-- ============================================================
-- CID 映射表
-- ============================================================
local CID = {
    CTerrorPlayer = 232,
    SurvivorBot   = 275,
    Smoker        = 270,
    Boomer        = 0,
    Hunter        = 263,
    Spitter       = 272,
    Jockey        = 265,
    Charger       = 99,
    Tank          = 276,
    Witch         = 277,
}

local ZC_TO_CID = {
    [1] = 270, [2] = 0, [3] = 263, [4] = 272,
    [5] = 265, [6] = 99, [7] = 277, [8] = 276,
}

local SHOVE_TARGET_KEYS = {
    [1] = "autoshove_target_smoker",
    [2] = "autoshove_target_boomer",
    [3] = "autoshove_target_hunter",
    [4] = "autoshove_target_spitter",
    [5] = "autoshove_target_jockey",
}

-- ============================================================
-- 感染者玩家锁定 共享状态 (from Target Based Aim Infected)
-- ============================================================
if client.get_shared_bool("aim_player_lock_enabled", nil) == nil then
    client.set_shared_bool("aim_player_lock_enabled", true)
    client.set_shared_int("aim_selected_player_idx", 0)
end
if client.get_shared_bool("aim_player_lock_bypass", nil) == nil then
    client.set_shared_bool("aim_player_lock_bypass", false)
end

-- ============================================================
-- 配置默认值 (自瞄 + 推搡)
-- ============================================================
local DEFAULTS = {
    -- 自瞄配置
    { "fbaim_enabled",   "bool",  true  },
    { "fbaim_survivors", "bool",  false  },
    { "fbaim_smoker",    "bool",  true   },
    { "fbaim_boomer",    "bool",  true   },
    { "fbaim_hunter",    "bool",  true   },
    { "fbaim_spitter",   "bool",  true   },
    { "fbaim_jockey",    "bool",  true   },
    { "fbaim_charger",   "bool",  true   },
    { "fbaim_tank",      "bool",  true   },
    { "fbaim_witch",     "bool",  true   },
    { "fbaim_fov",       "float", 8.0   },
    { "fbaim_draw_fov",  "bool",  true  },
    { "fbaim_lock_radius", "float", 120.0 },
    { "fbaim_always_on", "bool",  false },
    { "fbaim_breath_circle", "bool", false },
    { "fbaim_hide_net_overlay", "bool", false },
    { "fbaim_target_line", "bool", false },
    { "fbaim_max_dist",  "float", 1580.0 },
    { "fbaim_aimkey",    "int",   keys.MOUSE4 },
    { "fbaim_semiauto_rapid", "bool", false },
    { "fbaim_sticky",    "bool",  true  },
    { "fbaim_debug",     "bool",  false  },
    { "fbaim_vertical_offset", "float", 0.0 },
    { "fbaim_silent",    "bool",  true  },
    { "fbaim_deadzone",  "bool",  true  },
    { "fbaim_dbg_has_target", "int", 0 },
    { "fbaim_dbg_target_index", "int", -1 },
    { "fbaim_dbg_dist", "float", 0.0 },
    { "fbaim_dbg_dist_2d", "float", 0.0 },
    { "fbaim_dbg_pixel_dist", "float", 0.0 },
    { "fbaim_dbg_pred_pitch", "float", 0.0 },
    { "fbaim_dbg_pred_yaw", "float", 0.0 },
    { "fbaim_dbg_final_pitch", "float", 0.0 },
    { "fbaim_dbg_final_yaw", "float", 0.0 },
    { "fbaim_dbg_cid", "int", 0 },
    { "fbaim_dbg_is_ghost", "int", 0 },
    { "fbaim_dbg_is_sticky", "int", 0 },
    { "fbaim_anti_spectate", "bool", true },
    -- 推搡/无下坠配置 (from twilight)
    { "nofall_enabled",      "bool",  true   },
    { "antijockey_enabled",  "bool",  true   },
    { "autoshove_enabled",   "bool",  true   },
    { "autoshove_range",     "float", 86.0   },
    { "autoshove_delay",     "float", 0.075  },
    { "autoshove_silent",    "bool",  true   },
    { "autoshove_legit",     "bool",  false  },
    { "autoshove_target_hunter",  "bool", true  },
    { "autoshove_target_jockey",  "bool", true  },
    { "autoshove_target_boomer",  "bool", true  },
    -- FastMelee快速近战配置
    { "fastmelee_enabled",     "bool",  false  },
    { "fastmelee_key",         "int",   keys.MOUSE5 },
    { "fastmelee_wait_hit",    "float", 0.150  },
    { "fastmelee_wait_swap",   "float", 0.050  },
    { "fastmelee_wait_cycle",  "float", 0.560  },
    -- AWP速射配置
    { "awprapid_enabled",      "bool",  false  },
    { "awprapid_key",          "int",   keys.MOUSE5 },
    { "awprapid_wait_shoot",   "float", 0.055 },
    { "awprapid_wait_shove",   "float", 0.050  },
    { "awprapid_wait_cooldown","float", 0.110  },
    -- 快捷发言配置 (8个槽位)
    { "quicksay_1_enabled", "bool",  false  },
    { "quicksay_1_key",     "int",   keys.KEY_F },
    { "quicksay_2_enabled", "bool",  false  },
    { "quicksay_2_key",     "int",   keys.KEY_G },
    { "quicksay_3_enabled", "bool",  false  },
    { "quicksay_3_key",     "int",   keys.KEY_H },
    { "quicksay_4_enabled", "bool",  false  },
    { "quicksay_4_key",     "int",   keys.KEY_V },
    { "quicksay_5_enabled", "bool",  false  },
    { "quicksay_5_key",     "int",   keys.KEY_B },
    { "quicksay_6_enabled", "bool",  false  },
    { "quicksay_6_key",     "int",   keys.KEY_N },
    { "quicksay_7_enabled", "bool",  false  },
    { "quicksay_7_key",     "int",   keys.KEY_Z },
    { "quicksay_8_enabled", "bool",  false  },
    { "quicksay_8_key",     "int",   keys.KEY_X },
}

local CFG_GETTERS = {
    bool = client.get_shared_bool,
    int = client.get_shared_int,
    float = client.get_shared_float,
}

local CFG_SETTERS = {
    bool = client.set_shared_bool,
    int = client.set_shared_int,
    float = client.set_shared_float,
}

for _, d in ipairs(DEFAULTS) do
    local key, typ, val = d[1], d[2], d[3]
    CFG_SETTERS[typ](key, val)
end

local function cfg(key, typ)      return CFG_GETTERS[typ](key) end
local function setcfg(key, typ, v) CFG_SETTERS[typ](key, v)   end

local function resetSemiautoRapid()
    semiauto_hold_ticks = 0
    semiauto_release_ticks = 0
end

local function applySemiautoRapid(cmd, enabled, has_target, aim_ready)
    if not enabled or not has_target or not aim_ready then
        resetSemiautoRapid()
        return false
    end

    if semiauto_release_ticks > 0 then
        semiauto_release_ticks = semiauto_release_ticks - 1
        return false
    end

    cmd:set_buttons(cmd:get_buttons() | IN_ATTACK_BIT)
    semiauto_hold_ticks = semiauto_hold_ticks + 1

    if semiauto_hold_ticks >= SEMIAUTO_AUTO_HOLD_TICKS then
        semiauto_hold_ticks = 0
        semiauto_release_ticks = SEMIAUTO_AUTO_RELEASE_TICKS
    end

    return true
end

-- ============================================================
-- 通用数学函数
-- ============================================================
local function normAngle(a)
    a = a % 360
    if a >  180 then a = a - 360 end
    if a < -180 then a = a + 360 end
    return a
end

local function calcAngle(src, dst)
    local dx = dst.x - src.x
    local dy = dst.y - src.y
    local dz = dst.z - src.z
    local hyp = math.sqrt(dx * dx + dy * dy)
    return vector.new(
        math.deg(math.atan2(-dz, hyp)),
        math.deg(math.atan2(dy, dx)),
        0
    )
end

local function getFov(va, aa)
    local dp = normAngle(aa.x - va.x)
    local dy = normAngle(aa.y - va.y)
    return math.sqrt(dp * dp + dy * dy)
end

-- ============================================================
-- 推搡专用函数 (from twilight/AutoShove++)
-- ============================================================
local last_shove_time = 0
local last_server_ip = ""
local last_connection_reset_time = 0

-- 网络状态数据
local netdata = {
    last_update = 0,
    cached_stats = {},
    connected = false,
    address = nil,
    time_connected = nil
}
local DEFAULT_NETWORK_LINES = { "正在获取数据..." }
local returning = false

-- Render callbacks run on a different thread. Keep host objects out of this
-- snapshot and replace the whole table when the game thread refreshes it.
local render_cache = {
    spectators = {},
    spectator_update = 0,
    network_lines = { "正在获取数据..." },
    connected = false,
    address = nil,
    time_connected = nil,
    debug_target_name = "无",
    returning = false
}
local debug_target_name = "无"

-- 格式化时间
local function format_time(seconds)
    if seconds < 60 then
        return string.format("%.1f秒", seconds)
    elseif seconds < 3600 then
        local minutes = math.floor(seconds / 60)
        local secs = seconds % 60
        return string.format("%d分%.1f秒", minutes, secs)
    else
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        local secs = seconds % 60
        return string.format("%d时%d分%.1f秒", hours, minutes, secs)
    end
end

-- 判断实体是否在玩家背后
local function is_entity_behind_player(local_player, entity)
    local local_angles = local_player:get_eye_angles()
    local eye_pos = local_player:get_eye_position()
    local target_pos = entity:get_origin()
    local to_target = calcAngle(eye_pos, target_pos)
    local yaw_diff = normAngle(to_target.y - local_angles.y)
    return math.abs(yaw_diff) > 90
end

-- 推搡冷却检查
local function can_shove_now()
    local gv = get_global_vars()
    if not gv then return false end
    local current_time = gv.curtime
    local delay = client.get_shared_float("autoshove_delay", 0.075)
    if current_time - last_shove_time >= delay then
        last_shove_time = current_time
        return true
    end
    return false
end

-- 检查指定zombie_class是否启用推搡
local function is_shove_target_enabled(z_class)
    local key = SHOVE_TARGET_KEYS[z_class]
    if not key then return false end
    return client.get_shared_bool(key, false)
end

-- 智能推搡判断
local function should_shove_entity(local_player, entity, range)
    local eye_pos = local_player:get_eye_position()
    local target_pos = entity:get_origin()
    local dist = vector.distance(eye_pos, target_pos)
    local z_class = entity:get_zombie_class()
    if not is_shove_target_enabled(z_class) then return false end
    local effective_range = range
    if z_class == 2 then effective_range = 105 end  -- Boomer范围更大
    if dist > effective_range then return false end
    local legit_mode = client.get_shared_bool("autoshove_legit", false)
    if legit_mode and is_entity_behind_player(local_player, entity) then return false end
    return true
end

-- ============================================================
-- FastMelee 快速近战 (from HaruUrara, Echidna→Heaven移植)
-- 按住自定义热键(默认MOUSE5/上侧键)自动: 切近战→攻击→切回主武器→循环
-- ============================================================

-- FFI patch slot1/slot2 允许客户端执行武器切换命令
local FM_FACTORY_SLOT = 38
local FM_FCVAR_CLIENTCMD_CAN_EXECUTE = 1 << 30

pcall(function()
    ffi.cdef[[
        void* GetModuleHandleA(const char* lpModuleName);
        void* GetProcAddress(void* hModule, const char* lpProcName);
        typedef void* (*FM_CreateInterfaceFn)(const char* name, int* ret);
        typedef struct FM_CmdBase_s {
            void* vtable;
            struct FM_CmdBase_s* pNext;
            char              bRegistered;
            char              _pad[3];
            const char* pszName;
            const char* pszHelpString;
            int               nFlags;
        } FM_CmdBase_t;
        typedef void       (__thiscall *FM_IterVoidFn)(void* self);
        typedef bool       (__thiscall *FM_IterBoolFn)(void* self);
        typedef FM_CmdBase_t* (__thiscall *FM_IterGetFn)(void* self);
        typedef struct {
            void* dtor;
            FM_IterVoidFn SetFirst;
            FM_IterVoidFn Next;
            FM_IterBoolFn IsValid;
            FM_IterGetFn  Get;
        } FM_IterVtbl_t;
        typedef struct { FM_IterVtbl_t* vtbl; } FM_ICVarIter_t;
        typedef FM_ICVarIter_t* (__thiscall *FM_FactoryIterFn)(void* icvar);
    ]]
end)

local function fm_patch_slots()
    local ok, err = pcall(function()
        local vstdlib = ffi.C.GetModuleHandleA("vstdlib.dll")
        if not vstdlib or ffi.cast("uintptr_t", vstdlib) == 0 then return end
        local ci_raw = ffi.C.GetProcAddress(vstdlib, "CreateInterface")
        if not ci_raw then return end
        local icvar = ffi.cast("FM_CreateInterfaceFn", ci_raw)("VEngineCvar007", nil)
        if not icvar or ffi.cast("uintptr_t", icvar) < 0x10000 then return end
        local vtbl = ffi.cast("void***", icvar)[0]
        local ok2, iter = pcall(function()
            return ffi.cast("FM_FactoryIterFn", vtbl[FM_FACTORY_SLOT])(icvar)
        end)
        if not ok2 or not iter or ffi.cast("uintptr_t", iter) < 0x10000 then return end
        iter.vtbl.SetFirst(iter)
        local count = 0
        while iter.vtbl.IsValid(iter) do
            count = count + 1
            if count > 8000 then break end
            local cmd = iter.vtbl.Get(iter)
            if cmd ~= nil and ffi.cast("uintptr_t", cmd) > 0x10000 then
                local ok3, name = pcall(ffi.string, cmd.pszName)
                if ok3 and (name == "slot1" or name == "slot2") then
                    cmd.nFlags = cmd.nFlags | FM_FCVAR_CLIENTCMD_CAN_EXECUTE
                end
            end
            iter.vtbl.Next(iter)
        end
    end)
    if ok then
        client.print("[FastMelee] slot1/slot2 patch 成功")
    else
        client.print("[FastMelee] slot patch 失败: " .. tostring(err))
    end
end

fm_patch_slots()

local fm_state     = "idle"
local fm_timer     = 0
local fm_key_prev  = false

local function fastmelee_update(cmd)
    if not cfg("fastmelee_enabled", "bool") then
        if fm_state ~= "idle" then
            client.execnormal("slot1")
            fm_state = "idle"
        end
        return
    end

    local fm_hotkey = cfg("fastmelee_key", "int")
    local now     = os.clock()
    local holding = input.is_key_down(fm_hotkey)
    local pressed = holding and not fm_key_prev
    fm_key_prev   = holding

    local wait_hit   = cfg("fastmelee_wait_hit",   "float")
    local wait_swap  = cfg("fastmelee_wait_swap",  "float")
    local wait_cycle = cfg("fastmelee_wait_cycle", "float")

    if fm_state == "idle" then
        if pressed then
            client.execnormal("slot2")
            fm_timer = now
            fm_state = "wait_hit"
        end
    elseif fm_state == "wait_hit" then
        if not holding then
            client.execnormal("slot1")
            fm_state = "idle"
        elseif now - fm_timer >= wait_hit then
            client.execnormal("slot1")
            fm_timer = now
            fm_state = "swap_back"
        else
            cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK)
        end
    elseif fm_state == "swap_back" then
        if not holding then
            fm_state = "idle"
        elseif now - fm_timer >= wait_swap then
            client.execnormal("slot2")
            fm_timer = now
            fm_state = "wait_cycle"
        end
    elseif fm_state == "wait_cycle" then
        if not holding then
            fm_state = "idle"
        elseif now - fm_timer >= wait_cycle then
            fm_timer = now
            fm_state = "wait_hit"
            cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK)
        end
    end
end

-- ============================================================
-- AWP速射: 射击→推搡取消拉栓→循环
-- ============================================================
local awp_state     = "idle"
local awp_timer     = 0
local awp_key_prev  = false

local QUICKSAY_SLOTS = 8
local quicksay_key_prev = {}
local quicksay_cooldown = {}
local quicksay_config = {}
local quicksay_texts = {
    "!vip",
    "!admintime",
    "!admin",
    "!rygive",
    "!tail",
    "!tails",
    "!kx",
    "!bosstank",
}
for i = 1, QUICKSAY_SLOTS do
    quicksay_key_prev[i] = false
    quicksay_cooldown[i] = 0
    local enabled_key = "quicksay_" .. i .. "_enabled"
    local hotkey_key = "quicksay_" .. i .. "_key"
    quicksay_config[i] = {
        enabled = enabled_key,
        key = hotkey_key,
        target = hotkey_key,
        button_id = "##qsbtn_" .. i,
        input_id = "##qstxt_" .. i,
    }
end

local function quicksay_update()
    local now = os.clock()
    for i = 1, QUICKSAY_SLOTS do
        local q = quicksay_config[i]
        if not cfg(q.enabled, "bool") then
            quicksay_key_prev[i] = false
        else
            local qs_hotkey = cfg(q.key, "int")
            local holding = input.is_key_down(qs_hotkey)
            local pressed = holding and not quicksay_key_prev[i]
            quicksay_key_prev[i] = holding
            if pressed and now >= quicksay_cooldown[i] then
                local text = quicksay_texts[i]
                if text and text ~= "" then
                    client.execnormal("say " .. text)
                    quicksay_cooldown[i] = now + 0.3
                end
            end
        end
    end
end

local function awprapid_update(cmd)
    if not cfg("awprapid_enabled", "bool") then
        awp_state = "idle"
        return
    end

    local awp_hotkey = cfg("awprapid_key", "int")
    local now     = os.clock()
    local holding = input.is_key_down(awp_hotkey)
    local pressed = holding and not awp_key_prev
    awp_key_prev   = holding

    local wait_shoot    = cfg("awprapid_wait_shoot",    "float")
    local wait_shove    = cfg("awprapid_wait_shove",    "float")
    local wait_cooldown = cfg("awprapid_wait_cooldown", "float")

    if awp_state == "idle" then
        if pressed then
            cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK)
            awp_timer = now
            awp_state = "shooting"
        end
    elseif awp_state == "shooting" then
        if not holding then
            awp_state = "idle"
        elseif now - awp_timer >= wait_shoot then
            cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK2)
            awp_timer = now
            awp_state = "shoving"
        else
            cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK)
        end
    elseif awp_state == "shoving" then
        if not holding then
            awp_state = "idle"
        elseif now - awp_timer >= wait_shove then
            awp_timer = now
            awp_state = "cooldown"
        else
            cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK2)
        end
    elseif awp_state == "cooldown" then
        if not holding then
            awp_state = "idle"
        elseif now - awp_timer >= wait_cooldown then
            cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK)
            awp_timer = now
            awp_state = "shooting"
        end
    end
end

-- ============================================================
-- 网络状态更新 (from twilight)
-- ============================================================
local function update_network_stats()
    if not engine.is_connected() then
        netdata.connected = false
        netdata.address = nil
        netdata.time_connected = nil
        netdata.cached_stats = { "未连接到服务器" }
        return
    end
    local net = engine.get_net_channel_info()
    if not net then
        netdata.connected = false
        netdata.address = nil
        netdata.time_connected = nil
        netdata.cached_stats = { "无法获取网络信息" }
        return
    end
    local serverAddress = net.address or "未知"
    local timeConnected = tonumber(net.time_connected) or 0
    netdata.connected = true
    netdata.address = serverAddress
    netdata.time_connected = timeConnected
    netdata.cached_stats = {
        string.format("服务器: %s", serverAddress),
        string.format("延迟 发送/接收: %.1f / %.1f 毫秒", (tonumber(net.latency_out) or 0) * 1000, (tonumber(net.latency_in) or 0) * 1000),
        string.format("丢包: %.2f%% | 阻塞: %.2f%%", (tonumber(net.loss_out) or 0) * 100, (tonumber(net.choke_out) or 0) * 100),
        string.format("速度: %.1f KB/s 发送 | %.1f KB/s 接收", (tonumber(net.data_out) or 0) / 1024, (tonumber(net.data_in) or 0) / 1024),
        string.format("数据包: %.1f/秒 发送 | %.1f/秒 接收", tonumber(net.packets_out) or 0, tonumber(net.packets_in) or 0),
        string.format("总流量: %.2f MB 发送 | %.2f MB 接收", (tonumber(net.total_data_out) or 0) / 1024 / 1024, (tonumber(net.total_data_in) or 0) / 1024 / 1024),
        string.format("已连接: %.1f 秒", timeConnected),
        string.format("超时时间: %.1f秒 | 正在超时: %s", tonumber(net.timeout_seconds) or 0, tostring(net.is_timing_out))
    }
end

-- ============================================================
-- 观战检测 (from firebullaim)
-- ============================================================
local function get_spectator_list(local_player)
    local spectators = {}
    if not engine.is_in_game() then return spectators end
    if not local_player then return spectators end
    local local_index = local_player:get_index()

    for i = 1, engine.get_max_clients() do
        if i == local_index then goto continue_spec end
        local player = entity.get_by_index(i)
        if not player then goto continue_spec end

        local observer_mode = player:get_observer_mode()
        local observer_target = player:get_observer_target()
        local is_dead = not player:is_alive()
        local team_num = player:get_team()

        local is_spectating = false
        local is_playing_team = (team_num == team.SURVIVOR or team_num == team.INFECTED)
        if observer_mode >= 4 and observer_mode <= 6 then
            is_spectating = true
        elseif is_dead and observer_mode > 0 and not is_playing_team then
            is_spectating = true
        end
        if team_num == team.SPECTATOR then
            is_spectating = true
        end

        if is_spectating and observer_target then
            if observer_target:get_index() == local_index then
                local player_info = engine.get_player_info(i)
                local name = player_info and player_info.name or "Unknown"
                local raw = entity.get_by_index_raw(i)
                if raw and raw ~= 0 and team_num == team.INFECTED then
                    local ok_z, is_zombie = pcall(function() return entity.is_zombie_from_ptr(raw) end)
                    if ok_z and is_zombie then
                        goto continue_spec
                    end
                end
                table.insert(spectators, { name = name, is_dead = is_dead })
            end
        end
        ::continue_spec::
    end
    return spectators
end

local function refresh_render_cache(local_player)
    local now = os.clock()
    local spectators = render_cache.spectators
    local spectator_update = render_cache.spectator_update

    if not cfg("fbaim_anti_spectate", "bool") then
        spectators = {}
        client.set_shared_bool("fbaim_has_spectator", false)
    elseif now - spectator_update >= 0.20 then
        local ok, result = pcall(get_spectator_list, local_player)
        spectators = ok and result or {}
        spectator_update = now
        client.set_shared_bool("fbaim_has_spectator", #spectators > 0)
    end

    if now - netdata.last_update >= 1.0 then
        local ok = pcall(update_network_stats)
        if not ok then
            netdata.connected = false
            netdata.address = nil
            netdata.time_connected = nil
            netdata.cached_stats = { "网络状态暂时不可用" }
        end
        netdata.last_update = now
    end

    local network_lines = netdata.cached_stats
    if #network_lines == 0 then
        network_lines = DEFAULT_NETWORK_LINES
    end

    render_cache = {
        spectators = spectators,
        spectator_update = spectator_update,
        network_lines = network_lines,
        connected = netdata.connected,
        address = netdata.address,
        time_connected = netdata.time_connected,
        debug_target_name = debug_target_name,
        returning = returning
    }
end

-- ============================================================
-- 瞄准位置 (from firebullaim)
-- ============================================================
local AIM_BODY_OFFSET = {
    [CID.Tank]    = 52,
    [CID.Charger] = 48,
    [CID.Smoker]  = 50,
    [CID.Spitter] = 50,
    [CID.Hunter]  = 46,
    [CID.Jockey]  = 28,
    [CID.Boomer]  = 44,
}
local DEFAULT_BODY_OFFSET = 48

local RIDE_EYE_DOWN = {
    [CID.Hunter] = 20,
    [CID.Jockey] = 18,
}

local function getAimPosition(origin, ent, cid)
    local ok_ep, ep = pcall(function() return ent:get_eye_position() end)
    if ok_ep and ep and (cid == CID.Hunter or cid == CID.Jockey) then
        if (ep.z - origin.z) > 20 then
            local eye_down = RIDE_EYE_DOWN[cid] or 20
            return { x = origin.x, y = origin.y, z = ep.z - eye_down }
        end
    end
    local z_off = AIM_BODY_OFFSET[cid] or DEFAULT_BODY_OFFSET
    return { x = origin.x, y = origin.y, z = origin.z + z_off }
end

-- ============================================================
-- Anti-Cheat Bypass Functions (from firebullaim)
-- ============================================================
local function get_world_to_screen_frame()
    if not engine.world_to_screen_matrix then return nil end
    local mat_ptr = engine.world_to_screen_matrix()
    if not mat_ptr or mat_ptr == 0 then return nil end

    local function rm(idx) return memory.read_float(mat_ptr + idx * 4) end
    local sw, sh = engine.get_screen_size()
    return {
        m00 = rm(0), m01 = rm(1), m02 = rm(2), m03 = rm(3),
        m10 = rm(4), m11 = rm(5), m12 = rm(6), m13 = rm(7),
        m30 = rm(12), m31 = rm(13), m32 = rm(14), m33 = rm(15),
        sw = sw,
        sh = sh,
    }
end

local function project_world_to_screen(pos, frame)
    if not frame then return nil end

    local w = frame.m30 * pos.x + frame.m31 * pos.y + frame.m32 * pos.z + frame.m33
    if w < 0.001 then return nil end

    local inv = 1.0 / w
    local sx = (frame.m00 * pos.x + frame.m01 * pos.y + frame.m02 * pos.z + frame.m03) * inv
    local sy = (frame.m10 * pos.x + frame.m11 * pos.y + frame.m12 * pos.z + frame.m13) * inv

    return {
        x = (frame.sw / 2) + (sx * frame.sw / 2),
        y = (frame.sh / 2) - (sy * frame.sh / 2),
    }
end

local function world_to_screen(pos)
    return project_world_to_screen(pos, get_world_to_screen_frame())
end

local function smoothAngle(cur, tar, f)
    if f <= 0 then return tar end
    local s = 1.0 / f
    return vector.new(
        cur.x + normAngle(tar.x - cur.x) * s,
        cur.y + normAngle(tar.y - cur.y) * s,
        0
    )
end

local function capDelta(cur, target, max_d)
    local dx = normAngle(target.x - cur.x)
    local dy = normAngle(target.y - cur.y)
    local d = math.sqrt(dx*dx + dy*dy)
    if d <= max_d then return target end
    local sc = max_d / d
    return vector.new(
        normAngle(cur.x + dx * sc),
        normAngle(cur.y + dy * sc),
        0
    )
end

local function updateSmoothJitter()
    jitter_reseed_counter = jitter_reseed_counter + 1
    if jitter_reseed_counter >= jitter_reseed_interval then
        jitter_reseed_counter = 0
        local mag_x = JITTER_MIN + math.random() * (JITTER_MAX - JITTER_MIN)
        local mag_y = JITTER_MIN + math.random() * (JITTER_MAX - JITTER_MIN)
        local sign_x = (math.random() < 0.5) and 1 or -1
        local sign_y = (math.random() < 0.5) and 1 or -1
        jitter_target_x = sign_x * mag_x
        jitter_target_y = sign_y * mag_y
    end
    jitter_cur_x = jitter_cur_x + (jitter_target_x - jitter_cur_x) * jitter_smooth_factor
    jitter_cur_y = jitter_cur_y + (jitter_target_y - jitter_cur_y) * jitter_smooth_factor
end

local function jitterAngle(ang)
    return vector.new(normAngle(ang.x + jitter_cur_x), normAngle(ang.y + jitter_cur_y), 0)
end

local function lockBreak(ang)
    return jitterAngle(ang)
end

local function fixMovement(cmd, oldAngles, newAngles)
    if not cmd then return end
    local yawDelta = normAngle(newAngles.y - oldAngles.y)
    local rad = math.rad(yawDelta)
    local cosA = math.cos(rad)
    local sinA = math.sin(rad)
    local forward = cmd:get_forwardmove()
    local side     = cmd:get_sidemove()
    cmd:set_forwardmove(forward * cosA - side * sinA)
    cmd:set_sidemove(side * cosA + forward * sinA)
end

local function get_vertical_offset()
    return client.get_shared_float("fbaim_vertical_offset", 0.0)
end

-- ============================================================
-- 目标状态变量
-- ============================================================
local g_best_target = nil
local last_angles   = nil
local lock_ticks    = 0
local next_break_at = LOCK_BREAK_MIN
local target_idx    = nil
local last_target_idx = nil
local prev_target_idx = nil
local lost_ticks     = 0
local LOST_RETAIN    = 30
local SWITCH_HYST    = 50
local MIN_LOCK_FRAMES = 8
local switch_timer   = 0
local RETURN_SPEED   = 1.5
local current_vert_off = 0.0
local VERT_SPEED     = 1.5
local DIST_WEIGHT_3D = 0.7
local DIST_WEIGHT_PX = 0.3

-- 待机动画死区: 过滤特感小范围呼吸/待机浮动
local AIM_DEADZONE       = 2.5   -- 目标移动<2.5单位视为待机动画
local DEADZONE_BLEND     = 0.12  -- 待机动画时的混合系数(越小越稳)
local last_stable_aimPos = nil

-- ============================================================
-- 子菜单Tab状态
-- ============================================================
local main_tab_index = 0  -- 0=自瞄, 1=弹道, 2=感染者锁定

-- ============================================================
-- Bullet Tracers and Impacts 弹道追踪 (from AddOutSeqNr)
-- ============================================================
local BT_MODES = { "Local", "Enemy", "Team" }
local bt_mode_idx = 0

local bt_cfg = {}
local function bt_create_default_cfg(is_local)
    return {
        enabled          = is_local,
        tracer_enabled   = true,
        tracer_style     = 4,
        tracer_duration  = 1.5,
        tracer_thickness = 2.5,
        tracer_r         = is_local and 0.2 or 1.0,
        tracer_g         = is_local and 0.8 or 0.2,
        tracer_b         = is_local and 1.0 or 0.2,
        tracer_a         = 1.0,
        effect_style     = 1,
        effect_size      = 24.0,
        effect_duration  = 1.5,
        effect_r         = is_local and 0.2 or 1.0,
        effect_g         = is_local and 0.8 or 0.2,
        effect_b         = is_local and 1.0 or 0.2,
        effect_a         = 1.0,
    }
end
bt_cfg["Local"] = bt_create_default_cfg(true)
bt_cfg["Enemy"] = bt_create_default_cfg(false)
bt_cfg["Team"]  = bt_create_default_cfg(false)

local bt_global = {
    fade_style  = 0,
    max_impacts = 128,
}
local bt_impacts = {}
local BT_TRACER_STYLES = { "Line", "Beam", "Dashed", "Electric", "Rail" }
local BT_EFFECT_STYLES = { "None", "Ring", "Cross", "Dot", "Splash", "Shockwave" }
local BT_FADE_STYLES   = { "Quadratic", "Linear", "Hold + Drop" }

local function bt_get_screen_coords(world_pos)
    if not engine.world_to_screen_matrix then return nil end
    local mat_ptr = engine.world_to_screen_matrix()
    if not mat_ptr or mat_ptr == 0 then return nil end
    local function rm(idx) return memory.read_float(mat_ptr + (idx * 4)) end
    local ok, m00 = pcall(rm, 0)
    if not ok then return nil end
    local m01, m02, m03 = rm(1), rm(2), rm(3)
    local m10, m11, m12, m13 = rm(4), rm(5), rm(6), rm(7)
    local m30, m31, m32, m33 = rm(12), rm(13), rm(14), rm(15)
    local w = m30 * world_pos.x + m31 * world_pos.y + m32 * world_pos.z + m33
    if w < 0.001 then return nil end
    local inv_w = 1.0 / w
    local sx = (m00 * world_pos.x + m01 * world_pos.y + m02 * world_pos.z + m03) * inv_w
    local sy = (m10 * world_pos.x + m11 * world_pos.y + m12 * world_pos.z + m13) * inv_w
    local sw, sh = engine.get_screen_size()
    return { x = math.floor((sw / 2) + (sx * sw / 2)), y = math.floor((sh / 2) - (sy * sh / 2)) }
end

local function bt_compute_fade(elapsed, duration)
    local t = math.max(0, math.min(1, 1 - elapsed / duration))
    if bt_global.fade_style == 0 then return t * t end
    if bt_global.fade_style == 1 then return t end
    return t > 0.3 and 1.0 or (t / 0.3)
end

local function bt_drand(seed, i)
    local v = math.sin(seed * 127.1 + i * 311.7) * 43758.5453
    return v - math.floor(v)
end

local function bt_safe_line(x1, y1, x2, y2, r, g, b, a)
    pcall(function() draw.line(math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2), r, g, b, a) end)
end
local function bt_safe_circle(x, y, rad, segs, r, g, b, a)
    pcall(function() draw.circle(math.floor(x), math.floor(y), rad, segs, r, g, b, a) end)
end
local function bt_safe_outlined_circle(x, y, rad, segs, r, g, b, a)
    pcall(function() draw.outlined_circle(math.floor(x), math.floor(y), rad, segs, r, g, b, a) end)
end

local function bt_safe_thick_line(x1, y1, x2, y2, r, g, b, a, thickness)
    if thickness <= 1.0 then bt_safe_line(x1, y1, x2, y2, r, g, b, a); return end
    local dx = x2 - x1; local dy = y2 - y1
    local len = math.sqrt(dx*dx + dy*dy)
    if len == 0 then return end
    local px = -dy / len; local py = dx / len
    local half = thickness / 2
    for i = -half, half, 0.5 do
        bt_safe_line(x1 + px * i, y1 + py * i, x2 + px * i, y2 + py * i, r, g, b, a)
    end
end

local function bt_draw_tracer(ox, oy, dx, dy, elapsed, seed, c)
    local s = c.tracer_style
    local r, g, b = c.tracer_r, c.tracer_g, c.tracer_b
    local a = bt_compute_fade(elapsed, c.tracer_duration) * c.tracer_a
    local th = c.tracer_thickness
    if s == 0 then
        bt_safe_thick_line(ox, oy, dx, dy, r, g, b, a, th)
    elseif s == 1 then
        bt_safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.15, th * 2.5)
        bt_safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.40, th * 1.5)
        bt_safe_thick_line(ox, oy, dx, dy, r, g, b, a, th)
    elseif s == 2 then
        local segs = 14
        for i = 0, segs - 1, 2 do
            local t0 = i / segs; local t1 = (i + 0.65) / segs
            bt_safe_thick_line(ox + (dx-ox)*t0, oy + (dy-oy)*t0, ox + (dx-ox)*t1, oy + (dy-oy)*t1, r, g, b, a, th)
        end
    elseif s == 3 then
        local segs = 10
        local px = -(dy - oy); local py = (dx - ox)
        local plen = math.sqrt(px*px + py*py)
        if plen > 0 then px = px/plen; py = py/plen end
        local prev_x, prev_y = ox, oy
        for i = 1, segs do
            local t = i / segs
            local mx = ox + (dx-ox)*t; local my = oy + (dy-oy)*t
            if i < segs then
                local off = (bt_drand(seed, i) - 0.5) * 18
                mx = mx + px*off; my = my + py*off
            end
            bt_safe_thick_line(prev_x, prev_y, mx, my, r, g, b, a, th)
            prev_x, prev_y = mx, my
        end
    elseif s == 4 then
        bt_safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.20, th * 3.5)
        bt_safe_thick_line(ox, oy, dx, dy, r, g, b, a * 0.60, th * 1.5)
        bt_safe_thick_line(ox, oy, dx, dy, 1, 1, 1, a, th * 0.5)
    end
end

local function bt_draw_effect(dx, dy, elapsed, c)
    local s = c.effect_style
    if s == 0 then return end
    local r, g, b = c.effect_r, c.effect_g, c.effect_b
    local a = bt_compute_fade(elapsed, c.effect_duration) * c.effect_a
    local sz = c.effect_size
    local pct = elapsed / c.effect_duration
    if s == 1 then
        bt_safe_outlined_circle(dx, dy, sz * pct, 32, r, g, b, a)
    elseif s == 2 then
        local h = sz * 0.5
        bt_safe_line(dx-h, dy-h, dx+h, dy+h, r, g, b, a)
        bt_safe_line(dx+h, dy-h, dx-h, dy+h, r, g, b, a)
    elseif s == 3 then
        local rad = math.max(1, sz * 0.35 * (1 - pct))
        bt_safe_circle(dx, dy, rad, 20, r, g, b, a)
    elseif s == 4 then
        local len = sz * pct
        for i = 0, 7 do
            local angle = (i / 8) * math.pi * 2
            bt_safe_line(dx + math.cos(angle)*len*0.25, dy + math.sin(angle)*len*0.25, dx + math.cos(angle)*len, dy + math.sin(angle)*len, r, g, b, a)
        end
    elseif s == 5 then
        local outer = sz * pct
        bt_safe_outlined_circle(dx, dy, outer, 48, r, g, b, a)
        bt_safe_outlined_circle(dx, dy, outer * 0.6, 32, r, g, b, a * 0.4)
        if pct < 0.4 then bt_safe_circle(dx, dy, sz*0.15, 16, 1, 1, 1, a*(1-pct/0.4)) end
    end
end

events.register("bullet_impact")

function on_game_event(name, event)
    if name == "bullet_impact" then
        local local_player = client.get_local_player()
        if not local_player then return end
        local userid = event:get_int("userid")
        local player_idx = engine.get_player_for_userid(userid)
        if not player_idx or player_idx == 0 then return end
        local mode = "None"
        if player_idx == local_player:get_index() then
            mode = "Local"
        else
            local shooter = entity.get_by_index(player_idx)
            if shooter then
                if shooter:get_team() == local_player:get_team() then
                    mode = "Team"
                else
                    mode = "Enemy"
                end
            end
        end
        if mode ~= "None" and bt_cfg[mode].enabled then
            if #bt_impacts >= bt_global.max_impacts then table.remove(bt_impacts, 1) end
            local start_pos
            if mode == "Local" then
                local eye_pos = local_player:get_eye_position()
                local angles = engine.get_view_angles()
                local fwd, right, up = utils.angle_vectors(angles)
                start_pos = vector.new(
                    eye_pos.x + (fwd.x * 30) + (right.x * 8) - (up.x * 10),
                    eye_pos.y + (fwd.y * 30) + (right.y * 8) - (up.y * 10),
                    eye_pos.z + (fwd.z * 30) + (right.z * 8) - (up.z * 10)
                )
            else
                local shooter = entity.get_by_index(player_idx)
                if shooter then start_pos = shooter:get_eye_position() end
            end
            if start_pos then
                table.insert(bt_impacts, {
                    target_pos = vector.new(event:get_float("x"), event:get_float("y"), event:get_float("z")),
                    start_pos  = start_pos,
                    time       = os.clock(),
                    seed       = math.random(1, 9999),
                    mode       = mode
                })
            end
        end
    end
end

local function combinedScore(dist3d, distPx, maxDist, lockR)
    local norm3d = (maxDist > 0) and (dist3d / maxDist) or 0
    local normPx = (lockR > 0) and (distPx / lockR) or 0
    return norm3d * DIST_WEIGHT_3D + normPx * DIST_WEIGHT_PX
end

local CID_NAMES = {
    [270] = "Smoker", [0] = "Boomer", [263] = "Hunter", [272] = "Spitter",
    [265] = "Jockey", [99] = "Charger", [276] = "Tank", [277] = "Witch",
}

local function get_cid_name(cid)
    return CID_NAMES[cid] or ("CID:" .. tostring(cid))
end

local function isZcEnabled(zc)
    if zc == 1 then return cfg("fbaim_smoker",  "bool") end
    if zc == 2 then return cfg("fbaim_boomer",  "bool") end
    if zc == 3 then return cfg("fbaim_hunter",  "bool") end
    if zc == 4 then return cfg("fbaim_spitter", "bool") end
    if zc == 5 then return cfg("fbaim_jockey",  "bool") end
    if zc == 6 then return cfg("fbaim_charger", "bool") end
    if zc == 7 then return cfg("fbaim_witch",   "bool") end
    if zc == 8 then return cfg("fbaim_tank",    "bool") end
    return false
end

-- ============================================================
-- 速度预测 (from firebullaim, 优化适配感染者视角)
-- ============================================================
local PREDICT_SPEED_THRESHOLD = 200.0
local PREDICT_NEAR = 0.08
local PREDICT_FAR  = 0.18
local PREDICT_NEAR_DIST = 400.0
local PREDICT_FAR_DIST  = 2500.0

local PREDICT_MULT = {
    [CID.Hunter]       = 0.04,
    [CID.Charger]      = 0.04,
    [CID.Jockey]       = 0.04,
    [CID.Tank]         = 0.05,
    [CID.Smoker]       = 0.05,
    [CID.Spitter]      = 0.05,
    [CID.Boomer]       = 0.05,
    [CID.CTerrorPlayer] = 0.06,
    [CID.SurvivorBot]   = 0.05,
}

local function applyVelocityPrediction(aimPos, ent, eyePos, cid)
    local ok_v, vel = pcall(function() return ent:get_velocity() end)
    if not ok_v or not vel then return aimPos end
    local speed = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)
    if speed < PREDICT_SPEED_THRESHOLD then return aimPos end

    local dx = aimPos.x - eyePos.x
    local dy = aimPos.y - eyePos.y
    local dz = aimPos.z - eyePos.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

    local t
    if dist <= PREDICT_NEAR_DIST then
        t = PREDICT_NEAR
    elseif dist >= PREDICT_FAR_DIST then
        t = PREDICT_FAR
    else
        local ratio = (dist - PREDICT_NEAR_DIST) / (PREDICT_FAR_DIST - PREDICT_NEAR_DIST)
        t = PREDICT_NEAR + (PREDICT_FAR - PREDICT_NEAR) * ratio
    end

    local mult = PREDICT_MULT[cid] or 1.0
    local predict_time = t * mult
    return {
        x = aimPos.x + vel.x * predict_time,
        y = aimPos.y + vel.y * predict_time,
        z = aimPos.z + vel.z * predict_time,
    }
end

-- ============================================================
-- 目标排序 (from firebullaim)
-- ============================================================
local function buildSortedTargets(local_player, cached_eyePos)
    g_best_target = nil
    local localIdx = local_player:get_index()
    local eyePos = cached_eyePos
    local maxDist = cfg("fbaim_max_dist", "float")
    local lockR = cfg("fbaim_lock_radius", "float")
    local sticky_enabled = cfg("fbaim_sticky", "bool")
    local allow_survivors = cfg("fbaim_survivors", "bool")
    local maxEnts = engine.get_max_clients()
    local localTeam = local_player:get_team()
    local localZc = 0
    if localTeam == 3 then
        localZc = local_player:get_zombie_class() or 0
    end
    local w2s = nil
    local ok_w2s, w2s_frame = pcall(get_world_to_screen_frame)
    if ok_w2s then w2s = w2s_frame end
    local screen_cx = w2s and (w2s.sw / 2) or 0
    local screen_cy = w2s and (w2s.sh / 2) or 0

    if switch_timer > 0 then switch_timer = switch_timer - 1 end

    local best, best_idx, best_score = nil, nil, nil
    local stick_ent, stick_fov, stick_ok = nil, nil, false

    if target_idx and sticky_enabled then
        local raw = entity.get_by_index_raw(target_idx)
        if raw and raw ~= 0 and not entity.is_dormant(raw) then
            local ent = entity.get_by_index(target_idx)
            if ent and ent:is_alive() then
                local ok_gh2, is_ghost2 = pcall(function() return ent:is_ghost() end)
                if ok_gh2 and is_ghost2 then
                    -- ghost, skip sticky
                else
                    local team = ent:get_team()
                    local is_valid_target = (team ~= localTeam) or (team == 2 and allow_survivors)
                    if is_valid_target then
                        local ok = false
                        if team == 2 then ok = (localTeam == 3) or allow_survivors
                        elseif team == 3 then
                            local zc = ent:get_zombie_class() or 0
                            ok = isZcEnabled(zc)
                        end
                        if ok then
                            local origin = ent:get_origin()
                            local dist = vector.distance(eyePos, origin)
                            if dist <= maxDist then
                                local cid = entity.get_class_id_from_ptr(raw) or 0
                                if team == 3 and cid == CID.CTerrorPlayer then
                                    cid = ZC_TO_CID[ent:get_zombie_class() or 0] or cid
                                end
                                local aimPos = getAimPosition(origin, ent, cid)
                                aimPos = applyVelocityPrediction(aimPos, ent, eyePos, cid)
                                local aimAng = calcAngle(eyePos, aimPos)
                                stick_ent = { cid=cid, dist=dist, aimPos=aimPos, aimAngle=aimAng, ent=ent }
                                local ok_sc, sc = pcall(project_world_to_screen, aimPos, w2s)
                                if ok_sc and sc then
                                    local px = math.sqrt((sc.x - screen_cx)^2 + (sc.y - screen_cy)^2)
                                    if px <= lockR then
                                        stick_fov = combinedScore(dist, px, maxDist, lockR)
                                        stick_ent.px = px
                                    else
                                        stick_fov = nil
                                    end
                                else
                                    stick_fov = nil
                                end
                                if stick_fov then stick_ok = true end
                            end
                        end
                    end
                end
            end
        end
        if not stick_ok then
            last_target_idx = target_idx
            target_idx = nil
            lost_ticks = LOST_RETAIN
        end
    elseif lost_ticks > 0 then
        lost_ticks = lost_ticks - 1
    end

    for i = 1, maxEnts do
        if i == localIdx then goto continue end
        local raw = entity.get_by_index_raw(i)
        if not raw or raw == 0 then goto continue end
        local cid = entity.get_class_id_from_ptr(raw)
        if not cid then goto continue end
        if entity.is_dormant(raw) then goto continue end
        local ent = entity.get_by_index(i)
        if not ent or not ent:is_alive() then goto continue end
        local ok_gh, is_ghost = pcall(function() return ent:is_ghost() end)
        if ok_gh and is_ghost then goto continue end

        local team = ent:get_team()
        local lt = localTeam
        if team == lt then
            if not (team == 2 and allow_survivors) then goto continue end
        end
        if team == 2 then
            if lt ~= 3 and not allow_survivors then goto continue end
        elseif team == 3 then
            local zc = ent:get_zombie_class() or 0
            if not isZcEnabled(zc) then goto continue end
        else
            goto continue
        end

        local aim_cid = cid
        if team == 3 and cid == CID.CTerrorPlayer then
            local zc_remap = ent:get_zombie_class() or 0
            aim_cid = ZC_TO_CID[zc_remap] or cid
        end

        local origin = ent:get_origin()
        local dist = vector.distance(eyePos, origin)
        if dist > maxDist then goto continue end

        local aimPos = getAimPosition(origin, ent, aim_cid)
        aimPos = applyVelocityPrediction(aimPos, ent, eyePos, aim_cid)
        local aimAng = calcAngle(eyePos, aimPos)

        local score
        local ok_sc, sc = pcall(project_world_to_screen, aimPos, w2s)
        if ok_sc and sc then
            local px = math.sqrt((sc.x - screen_cx)^2 + (sc.y - screen_cy)^2)
            if px > lockR then goto continue end
            score = combinedScore(dist, px, maxDist, lockR)
        else
            goto continue
        end

        if not best_score or score < best_score then
            best_score = score
            best = { cid=aim_cid, dist=dist, aimPos=aimPos, aimAngle=aimAng, ent=ent, px=px }
            best_idx = i
        end
        ::continue::
    end

    if stick_ok and stick_fov then
        if best_score and sticky_enabled then
            local hyst_score = (lockR > 0) and (SWITCH_HYST / lockR * DIST_WEIGHT_PX) or 0
            if stick_fov <= best_score + hyst_score then
                best = stick_ent; best_idx = target_idx; best_score = stick_fov
            elseif switch_timer > 0 then
                best = stick_ent; best_idx = target_idx; best_score = stick_fov
            end
        else
            best = stick_ent; best_idx = target_idx
        end
    end

    if best_idx then
        if best_idx ~= target_idx then switch_timer = MIN_LOCK_FRAMES end
        target_idx = best_idx
        lost_ticks = 0
        last_target_idx = best_idx
        g_best_target = { cid=best.cid, dist=best.dist, aimPos=best.aimPos, aimAngle=best.aimAngle, ent=best.ent }
    end
end

local function resetAimState()
    g_best_target = nil
    target_idx = nil
    last_target_idx = nil
    prev_target_idx = nil
    lost_ticks = 0
    last_angles = nil
    lock_ticks = 0
    next_break_at = LOCK_BREAK_MIN
    current_vert_off = 0.0
    returning = false
    attack_frame_count = 0
    prev_attack_state = false
    resetSemiautoRapid()
    jitter_cur_x = 0.0
    jitter_cur_y = 0.0
    jitter_target_x = 0.0
    jitter_target_y = 0.0
    jitter_reseed_counter = 0
    last_stable_aimPos = nil
    smooth_variation = 1.0
    smooth_var_timer = 0
    is_jockeyed = false
    aj_raw_handle = 0
    client.set_shared_int("fbaim_dbg_has_target", 0)
end

-- ============================================================
-- on_create_move: 自瞄主逻辑
-- 优先级: 推搡 > 自瞄 — 本tick要推搡时自瞄让出角度控制权
-- ============================================================
function on_create_move(cmd, local_player)
    -- Entity and net-channel reads belong to the game thread. The render hook
    -- consumes only the plain Lua snapshot produced here.
    pcall(refresh_render_cache, local_player)

    -- ========== 无下坠保护 ==========
    if cfg("nofall_enabled", "bool") and local_player and local_player:is_alive() and engine.is_in_game() and local_player:get_team() == 2 then
        local pAddr = entity.get_by_index_raw(local_player:get_index())
        local eb = modules.get_engine_base()
        local ptr1 = memory.read_int(eb + 4352236)
        local netChannel = (ptr1 ~= 0) and memory.read_int(ptr1 + 24) or 0
        if pAddr ~= 0 and netChannel ~= 0 then
            local tickbase = memory.read_float(pAddr + 0x11FC)
            local cond1 = memory.read_int(pAddr + 0x1F84)
            if (tickbase > NOFALL_THRESHOLD) or (cond1 ~= 0) then
                local currentSeq = memory.read_int(netChannel + 8)
                memory.write_int(netChannel + 8, currentSeq + NOFALL_SEQUENCE_SHIFT, false)
            end
        end
    end

    -- ========== Anti-Jockey ==========
    if cfg("antijockey_enabled", "bool") and local_player and local_player:is_alive() and engine.is_in_game() then
        local aj_ptr = entity.get_by_index_raw(local_player:get_index())
        if aj_ptr == 0 then
            is_jockeyed = false
        else
            local team = memory.read_int(aj_ptr + AJ_TEAM_OFFSET)
            if team ~= 2 then
                is_jockeyed = false
            else
                aj_raw_handle = memory.read_int(aj_ptr + AJ_JOCKEY_ATTACKER_OFFSET)
                local new_state = (aj_raw_handle > 0 and aj_raw_handle ~= 0xFFFFFFFF and aj_raw_handle ~= 2047)
                is_jockeyed = new_state
            end
        end
    else
        is_jockeyed = false
    end

    if is_jockeyed then
        client.set_send_packet(false)
    end

    -- 改键超时保护
    if waiting_key then
        key_wait_tick = key_wait_tick + 1
        if key_wait_tick > 300 or input.is_key_pressed(keys.ESCAPE) then
            waiting_key = false; key_target = nil; key_wait_tick = 0
        end
        return
    end

    -- 基础安全检查 (推搡和自瞄共用)
    if not local_player or not local_player:is_alive() then
        resetAimState(); return
    end
    if not engine.is_in_game() then return end

    -- ========== 连接重置检测 (from twilight) ==========
    -- 服务器IP变化/重连/每1分钟重置推搡冷却, 确保换服后立即可推
    if engine.is_connected() then
        local net = engine.get_net_channel_info()
        if net and net.address then
            local server_ip = net.address
            local current_time_connected = net.time_connected or 0

            if server_ip ~= last_server_ip then
                last_server_ip = server_ip
                last_connection_reset_time = current_time_connected
                last_shove_time = -9999
                client.print("服务器变化，自动推功能已重置")
            elseif current_time_connected < last_connection_reset_time then
                last_connection_reset_time = current_time_connected
                last_shove_time = -9999
                client.print("重新连接，自动推功能已重置")
            elseif current_time_connected > 0 then
                local current_minute = math.floor(current_time_connected / 60)
                local last_reset_minute = math.floor(last_connection_reset_time / 60)
                if current_minute > last_reset_minute then
                    last_connection_reset_time = current_time_connected
                    last_shove_time = -9999
                    client.print("自动推功能已重置（连接时间：" .. format_time(current_time_connected) .. "）")
                end
            end
        end
    end

    -- ============================================================
    -- 推搡优先执行: 独立于自瞄开关, 只要启用就执行
    -- 有人观战时自动降级为Legit模式(不转视角, 只推正面)
    -- ============================================================
    if local_player:get_team() == 2 and client.get_shared_bool("autoshove_enabled", false) and can_shove_now() and awp_state == "idle" then
        local is_spectated = cfg("fbaim_anti_spectate", "bool") and client.get_shared_bool("fbaim_has_spectator", false)
        local shove_range = client.get_shared_float("autoshove_range", 86.0)
        local shove_silent = client.get_shared_bool("autoshove_silent", true)
        local shove_legit = client.get_shared_bool("autoshove_legit", false) or is_spectated  -- 观战时强制Legit
        local shove_eye = local_player:get_eye_position()
        local shove_max = engine.get_max_clients()
        for si = 1, shove_max do
            local se = entity.get_by_index(si)
            if se and se:is_alive() and se:get_team() == 3 and not se:is_ghost() then
                local szc = se:get_zombie_class()
                if is_shove_target_enabled(szc) then
                    -- 观战时强制legit背后检查, 否则用用户设置
                    local effective_range = shove_range
                    if szc == 2 then effective_range = 105 end
                    local dist = vector.distance(shove_eye, se:get_origin())
                    if dist <= effective_range then
                        local is_behind = is_entity_behind_player(local_player, se)
                        if shove_legit and is_behind then
                            -- Legit/观战模式 + 特感在背后: 不推(等它绕到正面)
                        else
                            if shove_legit then
                                -- Legit/观战模式: 不转视角, 仅IN_ATTACK2
                                cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK2)
                            else
                                local shove_ang = calcAngle(shove_eye, se:get_eye_position())
                                cmd:set_viewangles(shove_ang)
                                if not shove_silent then
                                    engine.set_view_angles(shove_ang)
                                end
                                cmd:set_buttons(cmd:get_buttons() | buttons.IN_ATTACK2)
                            end
                            last_angles = nil
                            returning = false
                            awp_state = "idle"
                            fastmelee_update(cmd)  -- 推搡tick也要跑FastMelee
                            return  -- 推搡完成, 跳过自瞄
                        end
                    end
                end
            end
        end
    end

    -- ========== AWP速射 (推搡之后、FastMelee之前) ==========
    awprapid_update(cmd)

    -- ========== 快捷发言 ==========
    quicksay_update()

    -- ========== FastMelee (推搡之后、自瞄之前) ==========
    if awp_state == "idle" then
        fastmelee_update(cmd)
        if fm_state ~= "idle" then
            return  -- 近战循环中, 跳过自瞄
        end
    end

    -- ========== 以下为自瞄逻辑 (推搡未触发时才执行) ==========
    if not cfg("fbaim_enabled", "bool") then
        client.set_shared_int("fbaim_dbg_has_target", 0)
        force_attack_next = false
        resetSemiautoRapid()
        return
    end

    -- 观战检测 (仅停自瞄, 不阻止推搡)
    if cfg("fbaim_anti_spectate", "bool") and client.get_shared_bool("fbaim_has_spectator", false) then
        resetAimState(); return
    end

    -- 缓存eyePos
    local myRaw = entity.get_by_index_raw(local_player:get_index())
    local cached_eyePos = nil
    if myRaw and myRaw ~= 0 then
        cached_eyePos = getShootPosition(myRaw)
    end
    if not cached_eyePos then
        local o = local_player:get_origin()
        cached_eyePos = vector.new(o.x, o.y, o.z + 64)
    end

    local always_on = cfg("fbaim_always_on", "bool")
    local aimkey = cfg("fbaim_aimkey", "int")
    if not always_on then
        if aimkey == 0 or not input.is_key_down(aimkey) then
            resetAimState(); return
        end
    end

    buildSortedTargets(local_player, cached_eyePos)

    -- 待机动画死区: 过滤特感小范围呼吸浮动
    if cfg("fbaim_deadzone", "bool") and g_best_target and target_idx == prev_target_idx and last_stable_aimPos then
        local dx = g_best_target.aimPos.x - last_stable_aimPos.x
        local dy = g_best_target.aimPos.y - last_stable_aimPos.y
        local dz = g_best_target.aimPos.z - last_stable_aimPos.z
        local move_dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if move_dist < AIM_DEADZONE then
            local blend = (move_dist / AIM_DEADZONE) * DEADZONE_BLEND
            g_best_target.aimPos = {
                x = last_stable_aimPos.x + dx * blend,
                y = last_stable_aimPos.y + dy * blend,
                z = last_stable_aimPos.z + dz * blend,
            }
            g_best_target.aimAngle = calcAngle(cached_eyePos, g_best_target.aimPos)
        end
    end
    if g_best_target then
        last_stable_aimPos = {
            x = g_best_target.aimPos.x,
            y = g_best_target.aimPos.y,
            z = g_best_target.aimPos.z,
        }
    end

    if not g_best_target then
        client.set_shared_int("fbaim_dbg_has_target", 0)
        resetSemiautoRapid()
        if last_angles then
            returning = true
            local natural = cmd:get_viewangles()
            local returned = capDelta(last_angles, natural, RETURN_SPEED)
            fixMovement(cmd, cmd:get_viewangles(), returned)
            cmd:set_viewangles(returned)
            local dx = normAngle(returned.x - natural.x)
            local dy = normAngle(returned.y - natural.y)
            if math.sqrt(dx*dx + dy*dy) < 0.5 then
                returning = false; last_angles = nil; lock_ticks = 0
            else
                last_angles = returned
            end
        end
        return
    end

    returning = false
    if target_idx and target_idx ~= prev_target_idx then
        last_angles = nil
    end
    prev_target_idx = target_idx

    updateSmoothJitter()

    local baseAngles = (last_angles or cmd:get_viewangles())

    -- 拟人化: 平滑速度微调
    smooth_var_timer = smooth_var_timer + 1
    if smooth_var_timer >= SMOOTH_VAR_INTERVAL_MIN + math.random(0, SMOOTH_VAR_INTERVAL_MAX - SMOOTH_VAR_INTERVAL_MIN) then
        smooth_var_timer = 0
        smooth_variation = 0.75 + math.random() * 0.50
    end
    local effective_smooth = SMOOTH * smooth_variation

    local smoothed  = smoothAngle(baseAngles, g_best_target.aimAngle, effective_smooth)

    -- 距离自适应DELTA_CAP
    local active_cap
    if g_best_target.dist < DELTA_CLOSE then
        active_cap = DELTA_CAP_NEAR
    elseif g_best_target.dist < DELTA_FAR then
        active_cap = DELTA_CAP_MID
    else
        active_cap = DELTA_CAP_FAR
    end
    local capped = capDelta(baseAngles, smoothed, active_cap)

    lock_ticks = lock_ticks + 1
    local finalAng
    if lock_ticks >= next_break_at then
        finalAng = lockBreak(capped)
        if lock_ticks >= next_break_at + math.random(1, 3) then
            lock_ticks = 0
            next_break_at = LOCK_BREAK_MIN + math.random(0, LOCK_BREAK_MAX - LOCK_BREAK_MIN)
        end
    else
        finalAng = jitterAngle(capped)
    end

    -- 垂直偏移
    local target_vert = get_vertical_offset()
    local vert_diff = target_vert - current_vert_off
    if math.abs(vert_diff) > 0.01 then
        local vert_step = math.max(-VERT_SPEED, math.min(VERT_SPEED, vert_diff))
        current_vert_off = current_vert_off + vert_step
    else
        current_vert_off = target_vert
    end
    if current_vert_off ~= 0 then
        finalAng = vector.new(normAngle(finalAng.x + current_vert_off), finalAng.y, 0)
    end

    client.set_shared_float("fbaim_dbg_active_cap", active_cap)

    finalAng = vector.new(
        math.max(-89, math.min(89, normAngle(finalAng.x))),
        math.max(-180, math.min(180, normAngle(finalAng.y))),
        0
    )

    local semiauto_rapid = cfg("fbaim_semiauto_rapid", "bool")
    local semiauto_blocked = cfg("fbaim_anti_spectate", "bool") and client.get_shared_bool("fbaim_has_spectator", false)
    local semiauto_ready = getFov(finalAng, g_best_target.aimAngle) <= SEMIAUTO_AIM_READY_FOV
    applySemiautoRapid(cmd, semiauto_rapid and not semiauto_blocked, g_best_target ~= nil, semiauto_ready)

    local player_attacking = (cmd:get_buttons() & IN_ATTACK_BIT) ~= 0
    local just_pressed_attack = player_attacking and not prev_attack_state

    if just_pressed_attack and g_best_target then
        attack_frame_count = 0
    end

    if player_attacking then
        attack_frame_count = attack_frame_count + 1
    else
        if not semiauto_rapid and attack_frame_count > 0 and attack_frame_count <= 2 and g_best_target then
            cmd:set_buttons(cmd:get_buttons() | IN_ATTACK_BIT)
            attack_frame_count = attack_frame_count + 1
        else
            attack_frame_count = 0
        end
    end

    if just_pressed_attack and last_angles then
        local shot_delta = getFov(last_angles, finalAng)
        if shot_delta > SHOOT_ANCHOR_CAP then
            finalAng = capDelta(last_angles, finalAng, SHOOT_ANCHOR_CAP)
        end
    end

    fixMovement(cmd, cmd:get_viewangles(), finalAng)
    cmd:set_viewangles(finalAng)
    if not cfg("fbaim_silent", "bool") then
        engine.set_view_angles(finalAng)
    end

    prev_attack_state = player_attacking
    last_angles = finalAng

    -- 调试数据
    if cfg("fbaim_debug", "bool") and g_best_target then
        client.set_shared_int("fbaim_dbg_has_target", 1)
        local debug_target_index = g_best_target.ent and g_best_target.ent:get_index() or -1
        client.set_shared_int("fbaim_dbg_target_index", debug_target_index)
        local player_info = debug_target_index > 0 and engine.get_player_info(debug_target_index) or nil
        debug_target_name = player_info and player_info.name or "无"
        client.set_shared_float("fbaim_dbg_dist", g_best_target.dist)
        local ok_sc, sc = pcall(function() return world_to_screen(g_best_target.aimPos) end)
        local pixel_dist = 0
        if ok_sc and sc then
            local w, h = engine.get_screen_size()
            pixel_dist = math.sqrt((sc.x - w/2)^2 + (sc.y - h/2)^2)
        end
        client.set_shared_float("fbaim_dbg_pixel_dist", pixel_dist)
        client.set_shared_float("fbaim_dbg_pred_pitch", g_best_target.aimAngle and g_best_target.aimAngle.x or 0)
        client.set_shared_float("fbaim_dbg_pred_yaw", g_best_target.aimAngle and g_best_target.aimAngle.y or 0)
        client.set_shared_int("fbaim_dbg_cid", g_best_target.cid or 0)
        local is_sticky = (target_idx == prev_target_idx)
        client.set_shared_int("fbaim_dbg_is_sticky", is_sticky and 1 or 0)
        if g_best_target.ent then
            local ok_gh, gh_val = pcall(function() return g_best_target.ent:is_ghost() end)
            client.set_shared_int("fbaim_dbg_is_ghost", ok_gh and gh_val and 1 or 0)
        else
            client.set_shared_int("fbaim_dbg_is_ghost", 0)
        end
        if g_best_target.aimPos and cached_eyePos then
            local dx2d = g_best_target.aimPos.x - cached_eyePos.x
            local dy2d = g_best_target.aimPos.y - cached_eyePos.y
            client.set_shared_float("fbaim_dbg_dist_2d", math.sqrt(dx2d*dx2d + dy2d*dy2d))
        end
        client.set_shared_float("fbaim_dbg_final_pitch", finalAng.x)
        client.set_shared_float("fbaim_dbg_final_yaw", finalAng.y)
    elseif cfg("fbaim_debug", "bool") then
        client.set_shared_int("fbaim_dbg_has_target", 0)
        debug_target_name = "无"
    end
end

-- ============================================================
-- 改键状态
-- ============================================================
local key_names = {
    [keys.MOUSE1]="MOUSE1",[keys.MOUSE2]="MOUSE2",[keys.MOUSE3]="MOUSE3",
    [keys.MOUSE4]="MOUSE4",[keys.MOUSE5]="MOUSE5",
    [keys.KEY_A]="A",[keys.KEY_B]="B",[keys.KEY_C]="C",[keys.KEY_D]="D",
    [keys.KEY_E]="E",[keys.KEY_F]="F",[keys.KEY_G]="G",[keys.KEY_H]="H",
    [keys.KEY_I]="I",[keys.KEY_J]="J",[keys.KEY_K]="K",[keys.KEY_L]="L",
    [keys.KEY_M]="M",[keys.KEY_N]="N",[keys.KEY_O]="O",[keys.KEY_P]="P",
    [keys.KEY_Q]="Q",[keys.KEY_R]="R",[keys.KEY_S]="S",[keys.KEY_T]="T",
    [keys.KEY_U]="U",[keys.KEY_V]="V",[keys.KEY_W]="W",[keys.KEY_X]="X",
    [keys.KEY_Y]="Y",[keys.KEY_Z]="Z",
    [keys.SPACE]="SPACE",[keys.SHIFT]="SHIFT",[keys.CTRL]="CTRL",[keys.ALT]="ALT",
    [keys.ESCAPE]="ESC"
}

local waiting_key   = false
local key_target    = nil
local key_wait_tick = 0

-- ============================================================
-- on_end_scene: only render immutable data prepared by on_create_move
-- ============================================================
local function draw_imgui_window(name, flags, body)
    local ok_begin, visible = pcall(imgui.begin, name, flags)
    if not ok_begin or not visible then return end

    -- Always close a successfully opened window, even if one widget rejects
    -- stale cached data during a map or device transition.
    pcall(body)
    pcall(imgui["end"])
end

function on_end_scene()
    local snapshot = render_cache
    local specs = snapshot.spectators or {}

    if cfg("fbaim_anti_spectate", "bool") and #specs > 0 then
        draw_imgui_window("##fbaim_spectator_list", 0, function()
            imgui.text_colored(1.0, 0.6, 0.3, 1.0, "=== 观战列表 [" .. #specs .. "] ===")
            imgui.separator()
            for _, spec in ipairs(specs) do
                if spec.is_dead then
                    imgui.text_colored(1.0, 0.471, 0.471, 1.0, spec.name .. " [DEAD]")
                else
                    imgui.text(spec.name)
                end
            end
        end)
    end

    if not cfg("fbaim_hide_net_overlay", "bool") then
        draw_imgui_window("视奸状态", 0, function()
            for _, line in ipairs(snapshot.network_lines or {}) do
                imgui.text(line)
            end

            imgui.separator()
            imgui.text_colored(0.7, 1.0, 0.7, 1.0, "自动推重置机制")
            if snapshot.connected then
                if snapshot.address then
                    imgui.text(string.format("当前IP: %s", snapshot.address))
                end
                if snapshot.time_connected then
                    imgui.text(string.format("连接时间: %s", format_time(snapshot.time_connected)))
                    local time_to_reset = 60 - (snapshot.time_connected % 60)
                    imgui.text(string.format("下次重置: %s", format_time(time_to_reset)))
                end
            else
                imgui.text("未连接到服务器，重置机制未激活")
            end
            imgui.text("基于连接时间，每1分钟重置一次")
        end)
    end

    if not cfg("fbaim_debug", "bool") then return end
    if cfg("fbaim_dbg_has_target", "int") == 0 then return end
    local enabled = cfg("fbaim_enabled", "bool")

    draw_imgui_window("FBAim 调试面板", 0, function()
        imgui.set_window_size(340, 380, 0)
        imgui.text_colored(1.0, 0.5, 0.2, 1.0, "=== FBAim 调试面板 ===")
        local status = enabled and "运行中" or "已关闭"
        if enabled then
            imgui.text_colored(0.2, 1.0, 0.2, 1.0, "状态: " .. status)
        else
            imgui.text_colored(1.0, 0.3, 0.3, 1.0, "状态: " .. status)
        end
        imgui.separator()

        local target_idx_val = cfg("fbaim_dbg_target_index", "int")
        local cid_val = cfg("fbaim_dbg_cid", "int")
        local cid_name = get_cid_name(cid_val)

        imgui.text("目标: #" .. target_idx_val .. " " .. (snapshot.debug_target_name or "无"))
        imgui.text("类型: " .. cid_name)
        imgui.text(string.format("三维距离: %.0f 单位", cfg("fbaim_dbg_dist", "float")))
        imgui.text(string.format("二维距离: %.0f 单位", cfg("fbaim_dbg_dist_2d", "float")))
        imgui.text(string.format("像素距离: %.1f px", cfg("fbaim_dbg_pixel_dist", "float")))
        imgui.text_colored(0.5, 0.8, 0.5, 1.0, string.format("评分权重: 3D=%.0f%% 像素=%.0f%%",
            DIST_WEIGHT_3D * 100, DIST_WEIGHT_PX * 100))

        imgui.separator()
        imgui.text_colored(1.0, 1.0, 0.5, 1.0, "角度信息:")
        imgui.text(string.format("预测俯仰: %.2f 度", cfg("fbaim_dbg_pred_pitch", "float")))
        imgui.text(string.format("最终俯仰: %.2f 度", cfg("fbaim_dbg_final_pitch", "float")))
        imgui.text(string.format("预测偏航: %.2f 度", cfg("fbaim_dbg_pred_yaw", "float")))
        imgui.text(string.format("最终偏航: %.2f 度", cfg("fbaim_dbg_final_yaw", "float")))

        imgui.separator()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "状态标志:")
        local is_sticky = cfg("fbaim_dbg_is_sticky", "int") == 1
        local is_ghost = cfg("fbaim_dbg_is_ghost", "int") == 1
        imgui.text(string.format("粘性锁定: %s | 幽灵模式: %s | 回正: %s",
            is_sticky and "是" or "否", is_ghost and "是" or "否", snapshot.returning and "是" or "否"))

        imgui.separator()
        imgui.text_colored(0.7, 0.7, 1.0, 1.0, "当前设置:")
        imgui.text(string.format("锁定半径: %.0f px", cfg("fbaim_lock_radius", "float")))
        imgui.text(string.format("最大距离: %.0f 单位", cfg("fbaim_max_dist", "float")))
        imgui.text(string.format("粘性锁定: %s", cfg("fbaim_sticky", "bool") and "开启" or "关闭"))

        imgui.separator()
        imgui.text_colored(1.0, 0.7, 0.7, 1.0, "反作弊参数:")
        imgui.text(string.format("限幅: <=%.1f° (自适应)", client.get_shared_float("fbaim_dbg_active_cap", DELTA_CAP)))
        imgui.text(string.format("抖动: %.2f - %.2f°", JITTER_MIN, JITTER_MAX))
        imgui.text(string.format("平滑: %.1f | 打断: %d~%d帧", SMOOTH, LOCK_BREAK_MIN, LOCK_BREAK_MAX))
        imgui.text(string.format("断锁计数: %d/%d", lock_ticks, next_break_at))

        local vert_manual = cfg("fbaim_vertical_offset", "float")
        if vert_manual ~= 0 then
            imgui.separator()
            imgui.text_colored(0.6, 1.0, 0.8, 1.0, "垂直偏移:")
            imgui.text(string.format("偏移: %+.2f 度", vert_manual))
        end
    end)
end

-- ============================================================
-- on_paint: FOV圈 + 观战警告 (from firebullaim)
-- ============================================================
function on_paint()
    if cfg("fbaim_anti_spectate", "bool") and client.get_shared_bool("fbaim_has_spectator", false) then
        local w, h = engine.get_screen_size()
        if w > 0 and h > 0 then
            draw.string(fonts.ESP_NAME, w / 2, h * 0.15, 1.0, 0.2, 0.2, 1.0, text_align.CENTERX, "SPECTATING - AIM PAUSED")
        end
    end

    if cfg("fbaim_target_line", "bool") and cfg("fbaim_enabled", "bool") and g_best_target and g_best_target.aimPos then
        local lp = client.get_local_player()
        if lp and lp:is_alive() then
            local ok, scr = pcall(world_to_screen, g_best_target.aimPos)
            if ok and scr and scr.x and scr.y then
                local w, h = engine.get_screen_size()
                local cx, cy = math.floor(w / 2), math.floor(h / 2)
                draw.line(cx, cy, math.floor(scr.x), math.floor(scr.y), 0.0, 1.0, 0.0, 0.8)
            end
        end
    end

    if not cfg("fbaim_draw_fov", "bool") then return end
    if not cfg("fbaim_enabled", "bool") then return end
    local lp = client.get_local_player()
    if not lp or not lp:is_alive() then return end
    local w, h = engine.get_screen_size()
    if w <= 0 or h <= 0 then return end
    local lockR = cfg("fbaim_lock_radius", "float")
    local r = math.max(5, lockR)
    local cx, cy = math.floor(w / 2), math.floor(h / 2)
    local segs = 64
    if cfg("fbaim_breath_circle", "bool") then
        local t = os.clock() * 1.5
        local breath = math.sin(t * 0.6) * 0.2 + 0.8
        local rr = math.sin(t) * 0.3 + 0.7
        local gg = math.sin(t + 2.094) * 0.3 + 0.7
        local bb = math.sin(t + 4.189) * 0.3 + 0.7
        for i = 1, segs do
            local a1 = (i - 1) / segs * math.pi * 2
            local a2 = i / segs * math.pi * 2
            draw.line(
                math.floor(cx + r * math.cos(a1)), math.floor(cy + r * math.sin(a1)),
                math.floor(cx + r * math.cos(a2)), math.floor(cy + r * math.sin(a2)),
                rr * breath, gg * breath, bb * breath, breath
            )
        end
    else
        for i = 1, segs do
            local a1 = (i - 1) / segs * math.pi * 2
            local a2 = i / segs * math.pi * 2
            draw.line(
                math.floor(cx + r * math.cos(a1)), math.floor(cy + r * math.sin(a1)),
                math.floor(cx + r * math.cos(a2)), math.floor(cy + r * math.sin(a2)),
                1.0, 0.3, 0.3, 0.5
            )
        end
    end

    -- ============================================================
    -- Bullet Tracers and Impacts 渲染
    -- ============================================================
    if #bt_impacts == 0 then return end
    local now = os.clock()
    for i = #bt_impacts, 1, -1 do
        local impact = bt_impacts[i]
        local elapsed = now - impact.time
        local c = bt_cfg[impact.mode]
        local max_life = math.max(c.tracer_duration, c.effect_duration)
        if elapsed > max_life or not c.enabled then
            table.remove(bt_impacts, i)
        else
            local target_2d = bt_get_screen_coords(impact.target_pos)
            local start_2d = bt_get_screen_coords(impact.start_pos)
            if target_2d and start_2d then
                if c.tracer_enabled and elapsed < c.tracer_duration then
                    bt_draw_tracer(start_2d.x, start_2d.y, target_2d.x, target_2d.y, elapsed, impact.seed, c)
                end
                if c.effect_style > 0 and elapsed < c.effect_duration then
                    bt_draw_effect(target_2d.x, target_2d.y, elapsed, c)
                end
            end
        end
    end
end

-- ============================================================
-- 菜单: FMC All-in-One 主面板 (Tab式结构参考DarkSideTools)
-- ============================================================
local function colored_tab_button(label, is_active, r, g, b, width)
    if type(imgui.push_item_width) == "function" then
        imgui.push_item_width(width)
    end

    -- 索引对齐 DarkSideTools: 0=Text, 21=Button, 22=ButtonHovered, 23=ButtonActive
    if is_active then
        imgui.push_style_color(21, 0.10, 0.10, 0.10, 1.0)
        imgui.push_style_color(22, 0.14, 0.14, 0.14, 1.0)
        imgui.push_style_color(23, 0.10, 0.10, 0.10, 1.0)
    else
        imgui.push_style_color(21, 0.20, 0.20, 0.22, 1.0)
        imgui.push_style_color(22, 0.28, 0.28, 0.32, 1.0)
        imgui.push_style_color(23, 0.24, 0.24, 0.28, 1.0)
    end
    imgui.push_style_color(0, 1.0, 1.0, 1.0, 1.0)

    local clicked = imgui.button(label)

    imgui.pop_style_color(4)
    if type(imgui.pop_item_width) == "function" then
        imgui.pop_item_width()
    end

    if is_active then
        local ok_dl, dl = pcall(imgui.get_window_draw_list)
        if ok_dl and dl and type(dl.add_rect_filled) == "function" then
            local ok_min, min_first, min_second = pcall(imgui.get_item_rect_min)
            local ok_max, max_first, max_second = pcall(imgui.get_item_rect_max)
            if ok_min and ok_max then
                local min_x, min_y, max_x, max_y
                if type(min_first) == "table" then
                    min_x, min_y = tonumber(min_first.x) or tonumber(min_first[1]), tonumber(min_first.y) or tonumber(min_first[2])
                    max_x, max_y = tonumber(max_first.x) or tonumber(max_first[1]), tonumber(max_first.y) or tonumber(max_first[2])
                else
                    min_x, min_y = tonumber(min_first), tonumber(min_second)
                    max_x, max_y = tonumber(max_first), tonumber(max_second)
                end
                if min_x and min_y and max_x and max_y then
                    local col
                    if type(imgui.color_u32) == "function" then
                        col = imgui.color_u32(r, g, b, 1.0)
                    else
                        local function to_byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
                        col = to_byte(1.0) * 0x1000000 + to_byte(b) * 0x10000 + to_byte(g) * 0x100 + to_byte(r)
                    end
                    dl:add_rect_filled(min_x, max_y - 3, max_x, max_y, col)
                end
            end
        end
    end

    return clicked
end

menu.add_main_tab("FMC的自瞄",function()
    local c,v

    -- ============================================================
    -- Tab按钮行
    -- ============================================================
    local t = os.clock() * 0.8
    local rr = math.sin(t) * 0.35 + 0.65
    local gg = math.sin(t + 2.094) * 0.35 + 0.65
    local bb = math.sin(t + 4.189) * 0.35 + 0.65

    local avail_w = 0
    if type(imgui.get_window_width) == "function" then
        local ok, value = pcall(imgui.get_window_width)
        if ok and value then avail_w = tonumber(value) or 0 end
    end
    if avail_w <= 0 and type(imgui.get_content_region_avail) == "function" then
        local ok, ax, ay = pcall(imgui.get_content_region_avail)
        if ok and ax then
            avail_w = tonumber(ax) or 0
        end
    end
    local gap = 8
    local margin = 16
    local btn_w = (avail_w > margin + gap) and ((avail_w - margin - gap) / 2) or 120

    if colored_tab_button("自瞄", main_tab_index == 0, rr, gg, bb, btn_w) then main_tab_index = 0 end
    imgui.same_line(0, gap)
    if colored_tab_button("弹道显示", main_tab_index == 1, 0.3, 0.8, 1.0, btn_w) then main_tab_index = 1 end

    imgui.spacing()
    imgui.separator()

    -- ============================================================
    -- Tab 0: 自瞄 (原全部功能)
    -- ============================================================
    if main_tab_index == 0 then
        c,v=imgui.checkbox("启用", cfg("fbaim_enabled","bool"))
        if c then setcfg("fbaim_enabled","bool",v) end

        imgui.push_style_color(0, rr, gg, bb, 1.0)
        imgui.same_line()
        if imgui.button("Bilibili-一只小微凉鸭 闲鱼01电竞") then
            os.execute("start https://space.bilibili.com/2132149975")
        end
        imgui.pop_style_color(1)

        c,v=imgui.checkbox("常开模式", cfg("fbaim_always_on","bool"))
        if c then setcfg("fbaim_always_on","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("呼吸锁定圈", cfg("fbaim_breath_circle","bool"))
        if c then setcfg("fbaim_breath_circle","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("关闭网络状态悬浮窗", cfg("fbaim_hide_net_overlay","bool"))
        if c then setcfg("fbaim_hide_net_overlay","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("锁定目标线", cfg("fbaim_target_line","bool"))
        if c then setcfg("fbaim_target_line","bool",v) end

        if not cfg("fbaim_always_on","bool") then
            local ck=cfg("fbaim_aimkey","int")
            local kn = key_names[ck] or "MOUSE4"
            local bt=(waiting_key and key_target=="fbaim_aimkey") and "..." or kn
            if imgui.button(bt .. "##fbaim_aimkey") then waiting_key=true;key_target="fbaim_aimkey" end
            imgui.same_line();imgui.text("自瞄热键")
            imgui.same_line()
            c,v=imgui.checkbox("单发武器全自动", cfg("fbaim_semiauto_rapid","bool"))
            if c then setcfg("fbaim_semiauto_rapid","bool",v) end

            if waiting_key and key_target=="fbaim_aimkey" then
                for k,n in pairs(key_names) do
                    if input.is_key_pressed(k) then
                        if k==keys.ESCAPE then waiting_key=false;key_target=nil
                        else setcfg("fbaim_aimkey","int",k);waiting_key=false;key_target=nil end
                        break
                    end
                end
            end
        else
            c,v=imgui.checkbox("单发武器全自动", cfg("fbaim_semiauto_rapid","bool"))
            if c then setcfg("fbaim_semiauto_rapid","bool",v) end
        end

        imgui.spacing();imgui.separator()

        -- 特感目标
        imgui.text_colored(0.3,1,0.3,1,"[幸存者] 特感目标")
        imgui.spacing()

        c,v=imgui.checkbox("Smoker", cfg("fbaim_smoker","bool"))
        if c then setcfg("fbaim_smoker","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("Boomer", cfg("fbaim_boomer","bool"))
        if c then setcfg("fbaim_boomer","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("Hunter", cfg("fbaim_hunter","bool"))
        if c then setcfg("fbaim_hunter","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("Spitter", cfg("fbaim_spitter","bool"))
        if c then setcfg("fbaim_spitter","bool",v) end

        c,v=imgui.checkbox("Jockey", cfg("fbaim_jockey","bool"))
        if c then setcfg("fbaim_jockey","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("Charger", cfg("fbaim_charger","bool"))
        if c then setcfg("fbaim_charger","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("Tank", cfg("fbaim_tank","bool"))
        if c then setcfg("fbaim_tank","bool",v) end

        imgui.spacing();imgui.separator()

        -- 自瞄参数
        c,v=imgui.slider_float("锁定半径 (像素)", cfg("fbaim_lock_radius","float"), 10.0, 1000.0)
        if c then setcfg("fbaim_lock_radius","float",v) end
        imgui.same_line()
        c,v=imgui.checkbox("显示圈", cfg("fbaim_draw_fov","bool"))
        if c then setcfg("fbaim_draw_fov","bool",v) end

        c,v=imgui.slider_float("最大距离", cfg("fbaim_max_dist","float"), 200.0, 8192.0)
        if c then setcfg("fbaim_max_dist","float",v) end

        c,v=imgui.slider_float("垂直偏移 (度)", cfg("fbaim_vertical_offset","float"), -10.0, 10.0)
        if c then setcfg("fbaim_vertical_offset","float",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(+=偏低, -=偏高)")

        c,v=imgui.checkbox("粘性锁定", cfg("fbaim_sticky","bool"))
        if c then setcfg("fbaim_sticky","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("观战检测", cfg("fbaim_anti_spectate","bool"))
        if c then setcfg("fbaim_anti_spectate","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("幸存者/机器人", cfg("fbaim_survivors","bool"))
        if c then setcfg("fbaim_survivors","bool",v) end

        c,v=imgui.checkbox("静默瞄准", cfg("fbaim_silent","bool"))
        if c then setcfg("fbaim_silent","bool",v) end

        c,v=imgui.checkbox("待机动画死区", cfg("fbaim_deadzone","bool"))
        if c then setcfg("fbaim_deadzone","bool",v) end

        imgui.spacing();imgui.separator()

        -- 自动推搡
        imgui.text_colored(1.0, 0.4, 0.4, 1.0, "自动推搡")
        imgui.same_line()
        imgui.text_colored(0.3, 1.0, 0.3, 1.0, "(无绕过逻辑)")
        imgui.spacing()

        c,v=imgui.checkbox("启用自动推", client.get_shared_bool("autoshove_enabled", false))
        if c then client.set_shared_bool("autoshove_enabled", v) end
        imgui.same_line()
        c,v=imgui.checkbox("静默推搡", client.get_shared_bool("autoshove_silent", true))
        if c then client.set_shared_bool("autoshove_silent", v) end

        c,v=imgui.checkbox("Legit模式", client.get_shared_bool("autoshove_legit", false))
        if c then client.set_shared_bool("autoshove_legit", v) end
        imgui.same_line()
        c,v=imgui.checkbox("无下坠保护", cfg("nofall_enabled","bool"))
        if c then setcfg("nofall_enabled","bool",v) end
        imgui.same_line()
        c,v=imgui.checkbox("防止猴子", cfg("antijockey_enabled","bool"))
        if c then setcfg("antijockey_enabled","bool",v) end

        c,v=imgui.slider_float("推搡范围", client.get_shared_float("autoshove_range", 86.0), 78.0, 92.0)
        if c then client.set_shared_float("autoshove_range", v) end

        c,v=imgui.slider_float("推搡延迟", client.get_shared_float("autoshove_delay", 0.075), 0.0, 2.0)
        if c then client.set_shared_float("autoshove_delay", v) end

        imgui.text_colored(1.0, 1.0, 0.7, 1.0, "推搡目标:")
        imgui.same_line()
        c,v=imgui.checkbox("推Hunter", client.get_shared_bool("autoshove_target_hunter", false))
        if c then client.set_shared_bool("autoshove_target_hunter", v) end
        imgui.same_line()
        c,v=imgui.checkbox("推Jockey", client.get_shared_bool("autoshove_target_jockey", false))
        if c then client.set_shared_bool("autoshove_target_jockey", v) end
        imgui.same_line()
        c,v=imgui.checkbox("推Boomer", client.get_shared_bool("autoshove_target_boomer", false))
        if c then client.set_shared_bool("autoshove_target_boomer", v) end

        imgui.spacing();imgui.separator()
        imgui.text_colored(1.0, 0.8, 0.4, 1.0, "FastMelee 快速近战")
        c,v=imgui.checkbox("启用快速近战", cfg("fastmelee_enabled","bool"))
        if c then setcfg("fastmelee_enabled","bool",v) end

        local fmk=cfg("fastmelee_key","int")
        local fkn = key_names[fmk] or "MOUSE5"
        local fmbt=(waiting_key and key_target=="fastmelee_key") and "..." or fkn
        if imgui.button(fmbt .. "##fastmelee_key") then waiting_key=true;key_target="fastmelee_key" end
        imgui.same_line();imgui.text("近战热键")
        imgui.same_line()
        imgui.text_colored(1.0, 0.5, 0.5, 1.0, "(不要设置为MOUSE4)")

        if waiting_key and key_target=="fastmelee_key" then
            for k,n in pairs(key_names) do
                if input.is_key_pressed(k) then
                    if k==keys.ESCAPE then waiting_key=false;key_target=nil
                    else setcfg("fastmelee_key","int",k);waiting_key=false;key_target=nil end
                    break
                end
            end
        end

        c,v=imgui.slider_float("攻击等待", cfg("fastmelee_wait_hit","float"), 0.01, 0.30)
        if c then setcfg("fastmelee_wait_hit","float",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(攻击键按下时长)")

        c,v=imgui.slider_float("切回等待", cfg("fastmelee_wait_swap","float"), 0.01, 0.20)
        if c then setcfg("fastmelee_wait_swap","float",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(切回主武器冷却)")

        c,v=imgui.slider_float("循环等待", cfg("fastmelee_wait_cycle","float"), 0.30, 1.50)
        if c then setcfg("fastmelee_wait_cycle","float",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(斧头部署冷却,无伤害就调高)")

        imgui.spacing();imgui.separator()
        imgui.text_colored(0.6, 1.0, 0.6, 1.0, "AWP速射 取消拉栓")
        imgui.same_line()
        imgui.text_colored(1.0, 0.5, 0.5, 1.0, "(尽量不要搭配自瞄热键一起使用会检测到)")
        c,v=imgui.checkbox("启用AWP速射", cfg("awprapid_enabled","bool"))
        if c then setcfg("awprapid_enabled","bool",v) end

        local ak=cfg("awprapid_key","int")
        local akn = key_names[ak] or "MOUSE5"
        local abt=(waiting_key and key_target=="awprapid_key") and "..." or akn
        if imgui.button(abt .. "##awprapid_key") then waiting_key=true;key_target="awprapid_key" end
        imgui.same_line();imgui.text("速射热键")
        imgui.same_line()
        imgui.text_colored(1.0, 0.5, 0.5, 1.0, "(不要设置为MOUSE4)")

        if waiting_key and key_target=="awprapid_key" then
            for k,n in pairs(key_names) do
                if input.is_key_pressed(k) then
                    if k==keys.ESCAPE then waiting_key=false;key_target=nil
                    else setcfg("awprapid_key","int",k);waiting_key=false;key_target=nil end
                    break
                end
            end
        end

        c,v=imgui.slider_float("射击延迟", cfg("awprapid_wait_shoot","float"), 0.02, 0.15)
        if c then setcfg("awprapid_wait_shoot","float",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(子弹射出后等多久推)")

        c,v=imgui.slider_float("推搡时长", cfg("awprapid_wait_shove","float"), 0.05, 0.30)
        if c then setcfg("awprapid_wait_shove","float",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(推搡取消拉栓动画)")

        c,v=imgui.slider_float("冷却间隔", cfg("awprapid_wait_cooldown","float"), 0.10, 0.80)
        if c then setcfg("awprapid_wait_cooldown","float",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(推完后等多久下一枪,无伤害就调高)")

        imgui.spacing();imgui.separator()
        imgui.text_colored(1.0, 0.8, 1.0, 1.0, "快捷发言 (" .. QUICKSAY_SLOTS .. " 槽位)")

        for i = 1, QUICKSAY_SLOTS do
            local q = quicksay_config[i]
            local en = cfg(q.enabled, "bool")
            c,v=imgui.checkbox("槽位" .. i .. " 启用", en)
            if c then setcfg(q.enabled, "bool", v) end
            imgui.same_line()

            local k=cfg(q.key, "int")
            local kn = key_names[k] or "?"
            local bt=(waiting_key and key_target==q.target) and "..." or kn
            if imgui.button(bt .. q.button_id) then waiting_key=true;key_target=q.target end
            imgui.same_line();imgui.text("热键")

            if waiting_key and key_target==q.target then
                for kk,nn in pairs(key_names) do
                    if input.is_key_pressed(kk) then
                        if kk==keys.ESCAPE then waiting_key=false;key_target=nil
                        else setcfg(q.key, "int", kk);waiting_key=false;key_target=nil end
                        break
                    end
                end
            end

            c,v=imgui.input_text(q.input_id, quicksay_texts[i], 64)
            if c then quicksay_texts[i] = v end
        end

        imgui.spacing();imgui.separator()

        -- 调试功能
        imgui.text_colored(0.5, 0.8, 1.0, 1.0, "调试功能")
        c,v=imgui.checkbox("调试叠加层", cfg("fbaim_debug","bool"))
        if c then setcfg("fbaim_debug","bool",v) end
        imgui.same_line()
        imgui.text_colored(0.6, 0.6, 0.6, 1.0, "(实时显示瞄准数据)")

    -- ============================================================
    -- Tab 1: 弹道追踪
    -- ============================================================
    elseif main_tab_index == 1 then
        imgui.text_colored(0.3, 0.8, 1.0, 1.0, "Bullet Tracers and Impacts 弹道追踪")
        imgui.separator()
        imgui.spacing()

        local changed, val
        changed, val = imgui.combo("全局渐变曲线", bt_global.fade_style, BT_FADE_STYLES)
        if changed then bt_global.fade_style = val end

        changed, val = imgui.slider_int("最大弹道缓存", bt_global.max_impacts, 8, 256)
        if changed then bt_global.max_impacts = val end

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        changed, val = imgui.combo("编辑模式", bt_mode_idx, BT_MODES)
        if changed then bt_mode_idx = val end

        local bt_cur = BT_MODES[bt_mode_idx + 1]
        local bc = bt_cfg[bt_cur]

        imgui.spacing()
        changed, val = imgui.checkbox("启用 " .. bt_cur .. " 弹道", bc.enabled)
        if changed then bc.enabled = val end

        if not bc.enabled then
            -- skip
        else
            imgui.spacing()

            if imgui.begin_child("TracerBox", 0, 230, true, 0) then
                imgui.text("弹道设置 (" .. bt_cur .. ")")
                imgui.separator()

                changed, val = imgui.checkbox("显示弹道", bc.tracer_enabled)
                if changed then bc.tracer_enabled = val end

                changed, val = imgui.combo("样式##tr", bc.tracer_style, BT_TRACER_STYLES)
                if changed then bc.tracer_style = val end

                changed, val = imgui.slider_float("持续时间 (秒)##tr", bc.tracer_duration, 0.05, 8.0)
                if changed then bc.tracer_duration = val end

                changed, val = imgui.slider_float("粗细##tr", bc.tracer_thickness, 1.0, 10.0)
                if changed then bc.tracer_thickness = val end

                imgui.spacing()
                imgui.text("颜色 (RGBA):")
                changed, val = imgui.slider_float("R##tr", bc.tracer_r, 0.0, 1.0)
                if changed then bc.tracer_r = val end
                changed, val = imgui.slider_float("G##tg", bc.tracer_g, 0.0, 1.0)
                if changed then bc.tracer_g = val end
                changed, val = imgui.slider_float("B##tb", bc.tracer_b, 0.0, 1.0)
                if changed then bc.tracer_b = val end
                changed, val = imgui.slider_float("A##ta", bc.tracer_a, 0.0, 1.0)
                if changed then bc.tracer_a = val end

                imgui.end_child()
            end

            imgui.spacing()

            if imgui.begin_child("EffectBox", 0, 210, true, 0) then
                imgui.text("命中特效设置 (" .. bt_cur .. ")")
                imgui.separator()

                changed, val = imgui.combo("特效##ef", bc.effect_style, BT_EFFECT_STYLES)
                if changed then bc.effect_style = val end

                changed, val = imgui.slider_float("大小##ef", bc.effect_size, 4.0, 120.0)
                if changed then bc.effect_size = val end

                changed, val = imgui.slider_float("持续时间 (秒)##ef", bc.effect_duration, 0.05, 5.0)
                if changed then bc.effect_duration = val end

                imgui.spacing()
                imgui.text("颜色 (RGBA):")
                changed, val = imgui.slider_float("R##er", bc.effect_r, 0.0, 1.0)
                if changed then bc.effect_r = val end
                changed, val = imgui.slider_float("G##eg", bc.effect_g, 0.0, 1.0)
                if changed then bc.effect_g = val end
                changed, val = imgui.slider_float("B##eb", bc.effect_b, 0.0, 1.0)
                if changed then bc.effect_b = val end
                changed, val = imgui.slider_float("A##ea", bc.effect_a, 0.0, 1.0)
                if changed then bc.effect_a = val end

                imgui.end_child()
            end
        end

    end
end)

-- ============================================================
-- on_unload: 清理所有状态
-- ============================================================
function on_unload()
    _G.__fb_aim_guard = nil
    _G.__autoshove_guard = nil
    g_best_target = nil
    target_idx = nil
    last_target_idx = nil
    prev_target_idx = nil
    lost_ticks = 0
    last_angles = nil
    lock_ticks = 0
    next_break_at = LOCK_BREAK_MIN
    current_vert_off = 0.0
    returning = false
    attack_frame_count = 0
    prev_attack_state = false
    resetSemiautoRapid()
    jitter_cur_x = 0.0
    jitter_cur_y = 0.0
    jitter_target_x = 0.0
    jitter_target_y = 0.0
    jitter_reseed_counter = 0
    if fm_state ~= "idle" then
        pcall(function() client.execnormal("slot1") end)
        fm_state = "idle"
    end
    is_jockeyed = false
    aj_raw_handle = 0
    client.print("[FMC All-in-One] Unloaded")
end

client.print("[FMC All-in-One] Loaded — 自瞄 + 推搡(优先) + 无下坠 + 快速近战 + 网络监控")


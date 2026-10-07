-- @author: v1b3C0oD3r
-- @created: 07.22 2026
-- Echidna Script
-- Hunter Pounce Landing Prediction
-- When local player is Hunter:
--   Phase 1 (crouch): predict using eye angles + z_lunge_power(600) + z_lunge_up(200)
--   Phase 2 (air): real-time trajectory using actual velocity

-- ============================================================================
-- Constants
-- ============================================================================

local FL_ONGROUND         = 1
local SPEED_THRESHOLD     = 50.0
local TRACE_MASK_VISIBLE  = 0x1FFFFFF

local SIM_STEPS  = 300
local SIM_DT     = 0.012
local DEFAULT_GRAVITY = 800.0

local DRAW_TRAJECTORY = true  -- true = full arc, false = landing point only
local DOT_INTERVAL = 15
local LINE_THICK   = 4.0

-- Pounce launch constants (from server.dll convars)
local LUNGE_POWER   = 600.0  -- z_lunge_power: forward velocity
local LUNGE_UP      = 200.0  -- z_lunge_up: upward velocity

-- ============================================================================
-- Utility
-- ============================================================================

local function vx(v) return v.x or v[1] or 0 end
local function vy(v) return v.y or v[2] or 0 end
local function vz(v) return v.z or v[3] or 0 end

local function vec_speed(v)
    local x, y, z = vx(v), vy(v), vz(v)
    return math.sqrt(x * x + y * y + z * z)
end

local function lerp(a, b, t) return a + (b - a) * t end

local function grad_color(frac)
    frac = math.max(0, math.min(1, frac))
    if frac < 0.33 then
        local t = frac / 0.33
        return lerp(0, 255, t) / 255, 1.0, 0.0
    elseif frac < 0.66 then
        local t = (frac - 0.33) / 0.33
        return 1.0, lerp(255, 160, t) / 255, 0.0
    else
        local t = (frac - 0.66) / 0.34
        return 1.0, lerp(160, 0, t) / 255, 0.0
    end
end

local function grad_color_int(frac)
    local r, g, b = grad_color(frac)
    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

-- ============================================================================
-- Debug
-- ============================================================================

local DEBUG = false
local last_diag = 0

-- ============================================================================
-- Entity helpers
-- ============================================================================

local function get_local_player()
    local ok, player = pcall(EntityCache.GetLocal)
    if ok and player then return player end
    return nil
end

local function is_hunter(player)
    if not player then return false end
    local ok, cls = pcall(player.get_zombie_class, player)
    return ok and cls == 3
end

local function is_alive(player)
    local ok, alive = pcall(player.is_alive, player)
    return ok and alive
end

local function is_ghost(player)
    local ok, ghost = pcall(player.is_ghost, player)
    return ok and ghost
end

-- ============================================================================
-- Trajectory simulation: P(t) = P0 + V0*t + 0.5*G*t^2
-- ============================================================================

local function simulate(ox, oy, oz, velx, vely, velz, gravity)
    local points = {}
    local landing = nil
    local prev_x, prev_y, prev_z = ox, oy, oz

    for i = 1, SIM_STEPS do
        local t = i * SIM_DT
        local x = ox + velx * t
        local y = oy + vely * t
        local z = oz + velz * t - 0.5 * gravity * t * t

        local ok, result = pcall(gameutil.trace,
            { x = prev_x, y = prev_y, z = prev_z },
            { x = x, y = y, z = z },
            TRACE_MASK_VISIBLE
        )

        if ok and result and result.did_hit then
            local frac = result.fraction or 0
            landing = {
                x = prev_x + (x - prev_x) * frac,
                y = prev_y + (y - prev_y) * frac,
                z = prev_z + (z - prev_z) * frac,
            }
            points[#points + 1] = landing
            break
        end

        points[#points + 1] = { x = x, y = y, z = z }
        prev_x, prev_y, prev_z = x, y, z

        if z < oz - 2000 then break end
    end

    return points, landing
end

-- ============================================================================
-- 3D World overlay
-- ============================================================================

local function draw_3d_world(points, landing, ox, oy, oz)
    if DRAW_TRAJECTORY then
        local n = #points
        if n < 2 then return end

        local prev_x, prev_y, prev_z = ox, oy, oz

        for i, pt in ipairs(points) do
            local frac = i / n
            local r, g, b = grad_color_int(frac)

            pcall(DebugOverlay.AddLineOverlayAlpha,
                { x = prev_x, y = prev_y, z = prev_z },
                { x = pt.x, y = pt.y, z = pt.z },
                r, g, b, 180,
                true, 0
            )

            prev_x, prev_y, prev_z = pt.x, pt.y, pt.z
        end
    end

    if landing then
        local h = 10
        pcall(DebugOverlay.AddBoxOverlay,
            { x = landing.x, y = landing.y, z = landing.z },
            { x = -h, y = -h, z = -h },
            { x = h,  y = h,  z = h },
            { x = 0, y = 0, z = 0 },
            255, 0, 0, 255,
            0
        )
    end
end

-- ============================================================================
-- 2D Screen overlay
-- ============================================================================

local function w2s(x, y, z)
    return visual.world_to_screen(x, y, z)
end

local function draw_2d_thick_parabola(points, landing, ox, oy, oz, is_prediction)
    local n = #points
    if n < 2 then return end

    local screen = {}
    screen[0] = w2s(ox, oy, oz)
    for i = 1, n do
        screen[i] = w2s(points[i].x, points[i].y, points[i].z)
    end

    -- Prediction = dashed/dimmer, real = solid/bright
    local alpha = is_prediction and 0.6 or 0.95
    local thick = is_prediction and LINE_THICK * 0.7 or LINE_THICK

    if DRAW_TRAJECTORY then
        for i = 0, n - 1 do
            local s1 = screen[i]
            local s2 = screen[i + 1]
            if s1 and s2 then
                local frac = (i + 1) / n
                local r, g, b = grad_color(frac)
                -- Dashed effect for prediction: skip every other segment
                if not is_prediction or (i % 3 < 2) then
                    imgui.fg_draw_line(s1.x, s1.y, s2.x, s2.y, r, g, b, alpha, thick)
                end
            end
        end

        -- Dots at intervals
        for i = 0, n, DOT_INTERVAL do
            local s = screen[i]
            if s then
                local frac = i / n
                local r, g, b = grad_color(frac)
                imgui.fg_draw_circle_filled(s.x, s.y, r, g, b, alpha, 5, 10)
            end
        end

        -- Start marker
        local s0 = screen[0]
        if s0 then
            local col = is_prediction and {0.2, 0.8, 1.0} or {0.0, 1.0, 0.0}
            imgui.fg_draw_circle_filled(s0.x, s0.y, col[1], col[2], col[3], 0.9, 6, 12)
            imgui.fg_draw_circle(s0.x, s0.y, col[1], col[2], col[3], 0.7, 10, 16, 2.0)
        end
    end

    -- Landing marker
    if landing and screen[n] then
        local sx, sy = screen[n].x, screen[n].y
        local time = client.get_time and client.get_time() or os.clock()
        local pulse = 0.6 + 0.4 * math.sin(time * 5)

        -- Prediction = blue ring, real = red ring
        local r, g, b
        if is_prediction then
            r, g, b = 0.3, 0.5, 1.0
        else
            r, g, b = 1.0, 0.1, 0.1
        end

        imgui.fg_draw_circle(sx, sy, r, g, b, 0.8 * pulse, 20, 32, 3.0)
        imgui.fg_draw_circle_filled(sx, sy, r, g, b, 0.5, 7, 16)

        -- Crosshair
        imgui.fg_draw_line(sx - 18, sy, sx - 8, sy, r, 0, 0, 1.0, 2.5)
        imgui.fg_draw_line(sx + 8, sy, sx + 18, sy, r, 0, 0, 1.0, 2.5)
        imgui.fg_draw_line(sx, sy - 18, sx, sy - 8, r, 0, 0, 1.0, 2.5)
        imgui.fg_draw_line(sx, sy + 8, sx, sy + 18, r, 0, 0, 1.0, 2.5)
    end
end

-- ============================================================================
-- Ground shadow
-- ============================================================================

local function draw_ground_shadow(points, ox, oy, oz, is_prediction)
    if not DRAW_TRAJECTORY then return end
    local n = #points
    if n < 2 then return end

    local alpha = is_prediction and 0.2 or 0.35
    local prev_sx, prev_sy

    for i = 0, n, 3 do
        local px, py, pz
        if i == 0 then
            px, py, pz = ox, oy, oz
        else
            px, py, pz = points[i].x, points[i].y, points[i].z
        end

        local ok, result = pcall(gameutil.trace,
            { x = px, y = py, z = pz },
            { x = px, y = py, z = pz - 3000 },
            TRACE_MASK_VISIBLE
        )

        local ground_z = pz - 3000
        if ok and result and result.did_hit then
            ground_z = pz + (pz - 3000 - pz) * (result.fraction or 0)
        end

        local s = w2s(px, py, ground_z)
        if s then
            if prev_sx then
                imgui.fg_draw_line(prev_sx, prev_sy, s.x, s.y, 0.0, 0.0, 0.0, alpha, 2.0)
            end
            prev_sx, prev_sy = s.x, s.y
        end
    end
end

-- ============================================================================
-- Main — two phases
-- ============================================================================

local function draw_hunter_trajectory()
    local gravity = DEFAULT_GRAVITY
    local player = get_local_player()

    if not player or not is_hunter(player) or not is_alive(player) or is_ghost(player) then
        return
    end

    local okO, origin = pcall(player.get_origin, player)
    if not okO or not origin then return end

    local ox, oy, oz = vx(origin), vy(origin), vz(origin)

    -- Phase 1: Crouch prediction (before jumping)
    -- Try multiple class names and int instead of bool
    local isPouncing = false
    local isDucked = false
    local isDucking = false

    -- m_isAttemptingToPounce: try DT_TerrorLocalPlayerExclusive, DT_Hunter, DT_TerrorPlayer
    for _, cls in ipairs({"DT_TerrorLocalPlayerExclusive", "DT_Hunter", "DT_TerrorPlayer", "DT_BasePlayer"}) do
        local ok, val = pcall(player.get_prop_int, player, cls, "m_isAttemptingToPounce")
        if ok and val and val ~= 0 then isPouncing = true end
    end

    -- m_bDucked: try DT_Local, DT_LocalPlayerExclusive, DT_BasePlayer
    for _, cls in ipairs({"DT_Local", "DT_LocalPlayerExclusive", "DT_BasePlayer", "DT_TerrorPlayer"}) do
        local ok, val = pcall(player.get_prop_int, player, cls, "m_bDucked")
        if ok and val and val ~= 0 then isDucked = true end
    end

    -- m_bDucking: try same classes
    for _, cls in ipairs({"DT_Local", "DT_LocalPlayerExclusive", "DT_BasePlayer", "DT_TerrorPlayer"}) do
        local ok, val = pcall(player.get_prop_int, player, cls, "m_bDucking")
        if ok and val and val ~= 0 then isDucking = true end
    end

    -- Also check flags for FL_DUCKING (bit 1 = 2)
    local _, flags = pcall(player.get_flags, player)
    local flagDucking = flags and bit.band(flags, 2) ~= 0

    -- Predict when crouched AND on ground (not in air)
    local in_air = false
    local okg, onGround = pcall(player.is_on_ground, player)
    if okg and not onGround then in_air = true end
    if not in_air then
        local okf2, flags2 = pcall(player.get_flags, player)
        if okf2 and flags2 then
            in_air = bit.band(flags2, FL_ONGROUND) == 0
        end
    end

    local should_predict = (isPouncing or isDucked or isDucking or flagDucking) and not in_air

    -- Debug log
    if DEBUG then
        local t = client.get_time and client.get_time() or os.clock()
        if t - last_diag > 0.5 then
            last_diag = t
            client.log(string.format("[hunter_traj] pounce=%s duck=%s ducking=%s flag=%s predict=%s flags=%s",
                tostring(isPouncing), tostring(isDucked), tostring(isDucking),
                tostring(flagDucking), tostring(should_predict), tostring(flags)))
        end
    end

    if should_predict then
        -- Read eye angles to get launch direction
        local okEye, eyeAng = pcall(player.get_eye_angles, player)
        if okEye and eyeAng then
            local pitch, yaw, roll = vx(eyeAng), vy(eyeAng), vz(eyeAng)

            -- Get forward vector from eye angles
            local okFwd, fwd = pcall(mathutil.angle_vectors, eyeAng)
            if okFwd and fwd then
                local fx, fy, fz = vx(fwd), vy(fwd), vz(fwd)

                if DEBUG then
                    client.log(string.format("[hunter_traj] eye=(%.1f,%.1f,%.1f) fwd=(%.3f,%.3f,%.3f)",
                        pitch, yaw, roll, fx, fy, fz))
                end

                -- Pounce velocity = forward * z_lunge_power + up * z_lunge_up
                local velx = fx * LUNGE_POWER
                local vely = fy * LUNGE_POWER
                local velz = fz * LUNGE_POWER + LUNGE_UP

                -- Simulate from slightly above origin (hunter body center)
                local startZ = oz + 40

                local points, landing = simulate(ox, oy, startZ, velx, vely, velz, gravity)

                -- Draw as prediction (blue, dashed)
                draw_3d_world(points, landing, ox, oy, startZ)
                draw_ground_shadow(points, ox, oy, startZ, true)
                draw_2d_thick_parabola(points, landing, ox, oy, startZ, true)
            end
        end
    end

    -- Phase 2: Real-time trajectory (in air after jumping)
    local okV, velocity = pcall(player.get_velocity, player)
    if okV and velocity then
        local speed = vec_speed(velocity)
        if speed >= SPEED_THRESHOLD then
            local in_air = false
            local okg, onGround = pcall(player.is_on_ground, player)
            if okg and not onGround then in_air = true end
            if not in_air then
                local okf, flags = pcall(player.get_flags, player)
                if okf and flags then
                    in_air = bit.band(flags, FL_ONGROUND) == 0
                end
            end

            if in_air then
                local velx, vely, velz = vx(velocity), vy(velocity), vz(velocity)
                local points, landing = simulate(ox, oy, oz, velx, vely, velz, gravity)

                -- Draw as real trajectory (red, solid)
                draw_3d_world(points, landing, ox, oy, oz)
                draw_ground_shadow(points, ox, oy, oz, false)
                draw_2d_thick_parabola(points, landing, ox, oy, oz, false)
            end
        end
    end
end

-- ============================================================================
-- Callbacks
-- ============================================================================

function on_end_scene()
    pcall(draw_hunter_trajectory)
end

function on_unload()
end

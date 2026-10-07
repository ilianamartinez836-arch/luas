local ffi = require("ffi")
ffi.cdef[[
    typedef struct { float x,y,z, nx,ny,nz; unsigned int col; float u,v; } EchVertex;
]]

local RT_W, RT_H   = 800, 520
local DEG2RAD      = math.pi / 180.0

local cfg = {
    fbx_folder  = [[E:\Mimi_00]],
    tex_folder  = [[E:\Mimi_00]],
    fbx_list    = {},
    sel_idx     = 1,

    mdl = nil,
    rt  = nil,

    cam_yaw   = 0.3,   cam_pitch = 0.2,
    cam_dist  = 15.0,
    cam_tx    = 0.0,   cam_ty    = 5.0,  cam_tz = 0.0,

    mdl_scale = 8.0,
    mdl_yaw   = 0.0,

    r_textured  = true,
    r_chams     = false,
    r_wire      = false,
    r_outline   = false,
    r_glow      = false,
    r_skeleton  = false,
    r_bbox      = false,
    r_esp       = false,
    r_autorot   = false,

    gizmo_enabled  = false,
    gizmo_mode     = "move",
    gizmo_space    = "local",
    gizmo_active   = false,
    cam_orbiting   = false,
    gizmo_axis     = nil,
    gizmo_drag_origin = nil,
    gizmo_bone_origin = nil,

    vis_col   = {1.0, 0.2, 0.2, 1.0},
    occ_col   = {0.0, 0.3, 1.0, 0.4},
    ol_col    = {1.0, 1.0, 0.0, 1.0},
    ol_thick  = 1.05,
    gl_col    = {0.0, 0.8, 1.0, 1.0},
    gl_thick  = 1.10,
    esp_col   = {0.0, 1.0, 0.4, 1.0},
    tex_alpha = 1.0,

    mesh_visible = {},
    tex_overrides = {},
    custom_tex_path = "",
    direct_fbx_path = "",
    pose_path       = [[E:\Mimi_00\pose_default.lua]],

    bone_edit     = {},
    selected_bone = 0,

    selected_mesh   = 0,
    outliner_tab    = "meshes",
    prop_tab        = "render",

    last_world = nil,
    last_view  = nil,
    last_proj  = nil,

    vp_px = 0, vp_py = 0, vp_pw = 0, vp_ph = 0,
}

local normal_cache = {}

local function cache_normals(mdl)
    normal_cache = {}
    if not mdl then return end
    for mi = 1, model.mesh_count(mdl) do
        local ptr, count = model.lock_verts(mdl, mi)
        if not ptr then break end
        local vp = ffi.cast("EchVertex*", ptr)
        local e  = { count = count, nx = {}, ny = {}, nz = {}, orig = {} }
        for i = 0, count - 1 do
            e.nx[i]   = vp[i].nx
            e.ny[i]   = vp[i].ny
            e.nz[i]   = vp[i].nz
            e.orig[i] = vp[i].col
        end
        normal_cache[mi] = e
        model.unlock_verts(mdl, mi)
    end
end

local function fit_camera(m)
    local x1,y1,z1 = model.get_bmin(m)
    local x2,y2,z2 = model.get_bmax(m)
    local bsize = math.max(x2-x1, y2-y1, z2-z1)
    if bsize < 0.001 then return end
    cfg.mdl_scale = 10.0 / bsize
    cfg.cam_tx = (x1+x2)*0.5 * cfg.mdl_scale
    cfg.cam_ty = (y1+y2)*0.5 * cfg.mdl_scale
    cfg.cam_tz = (z1+z2)*0.5 * cfg.mdl_scale
    cfg.cam_dist = 10.0 * 1.8
end

local function reset_bone(i)
    cfg.bone_edit[i] = { 0,0,0, 0,0,0 }
end

local function init_after_load(m)
    cache_normals(m)
    fit_camera(m)

    cfg.bone_edit     = {}
    cfg.mesh_visible  = {}
    cfg.selected_bone = 0
    cfg.selected_mesh = 0

    local bc = model.bone_count(m)
    for i = 1, bc do reset_bone(i) end

    local mc = model.mesh_count(m)
    for i = 1, mc do
        cfg.mesh_visible[i] = true
        model.set_mesh_visible(m, i, true)
    end
end

local function scan()
    cfg.fbx_list = model.scan_fbx(cfg.fbx_folder)
end
local function load_model()
    for _, tex in pairs(cfg.tex_overrides) do
        if tex then client.release_texture(tex) end
    end
    cfg.tex_overrides = {}

    if cfg.mdl then model.free(cfg.mdl); cfg.mdl = nil end
    if cfg.sel_idx < 1 or cfg.sel_idx > #cfg.fbx_list then return end

    local fbx_dir = cfg.fbx_list[cfg.sel_idx]:match("^(.*)[/\\][^/\\]+$")
    if fbx_dir and fbx_dir ~= "" then cfg.tex_folder = fbx_dir end

    local m, err = model.load(cfg.fbx_list[cfg.sel_idx], cfg.tex_folder)
    if not m then
        client.log("[viewer] " .. (err or "load failed"), 3)
        return
    end
    cfg.mdl = m
    init_after_load(m)

    for i = 1, model.mesh_count(m) do
        local mn = model.mesh_name(m, i)
        if mn then
            local tname = mn:gsub("^mt_", "tx_") .. "_Base.tga"
            local tex   = client.load_texture(cfg.tex_folder .. "\\" .. tname)
            if tex then
                cfg.tex_overrides[i] = tex
                model.set_mesh_tex(m, i, tex)
            end
        end
    end

    client.log(string.format("[viewer] loaded  %dm  %db  tex=%s",
        model.mesh_count(m), model.bone_count(m), cfg.tex_folder), 1)
end

local function pose_save(path)
    local f, err = io.open(path, "w")
    if not f then
        client.log("[pose] save failed: " .. (err or "?"), 3)
        return false
    end

    f:write("-- Pose file saved by Model Viewer\n")
    f:write(string.format("-- Model: %s\n",
        cfg.fbx_list[cfg.sel_idx] or "unknown"))
    f:write(string.format("-- Date: %s\n\n", os.date("%Y-%m-%d %H:%M:%S")))

    if not cfg.mdl then f:close(); return false end
    local bc = model.bone_count(cfg.mdl)
    f:write("return {\n")
    for i = 1, bc do
        local ed = cfg.bone_edit[i]
        if ed and (ed[1]~=0 or ed[2]~=0 or ed[3]~=0 or
                   ed[4]~=0 or ed[5]~=0 or ed[6]~=0) then
            local nm = model.bone_name(cfg.mdl, i) or ("bone_" .. i)
            nm = nm:gsub("%*", ""):gsub("\n", "")
            f:write(string.format(
                "  [%d] = { %.6f, %.6f, %.6f, %.6f, %.6f, %.6f }, -- %s\n",
                i, ed[1], ed[2], ed[3], ed[4], ed[5], ed[6], nm))
        end
    end
    f:write("}\n")
    f:close()
    client.log("[pose] saved to " .. path, 1)
    return true
end

local function pose_load(path)
    local f, err = io.open(path, "r")
    if not f then
        client.log("[pose] load failed: " .. (err or "?"), 3)
        return false
    end
    f:close()

    local ok, data = pcall(dofile, path)
    if not ok or type(data) ~= "table" then
        client.log("[pose] invalid pose file: " .. tostring(data), 3)
        return false
    end

    if not cfg.mdl then
        client.log("[pose] no model loaded to apply pose to", 2)
        return false
    end

    local bc = model.bone_count(cfg.mdl)
    local applied = 0
    for i, ed in pairs(data) do
        if type(i) == "number" and type(ed) == "table" and
           i >= 1 and i <= bc then
            if not cfg.bone_edit[i] then reset_bone(i) end
            cfg.bone_edit[i][1] = ed[1] or 0
            cfg.bone_edit[i][2] = ed[2] or 0
            cfg.bone_edit[i][3] = ed[3] or 0
            cfg.bone_edit[i][4] = ed[4] or 0
            cfg.bone_edit[i][5] = ed[5] or 0
            cfg.bone_edit[i][6] = ed[6] or 0
            model.bone_set_pose(cfg.mdl, i,
                cfg.bone_edit[i][1], cfg.bone_edit[i][2], cfg.bone_edit[i][3],
                cfg.bone_edit[i][4], cfg.bone_edit[i][5], cfg.bone_edit[i][6])
            applied = applied + 1
        end
    end
    client.log(string.format("[pose] applied %d bone(s) from %s", applied, path), 1)
    return true
end

local function do_render()
    if not cfg.mdl or not cfg.rt then return end

    model.apply_skinning(cfg.mdl)

    if cfg.r_autorot then
        cfg.mdl_yaw = (cfg.mdl_yaw + client.get_frametime() * 45.0) % 360.0
    end

    model.begin_rt(cfg.rt, 0.08, 0.08, 0.10)

    local cd  = math.max(0.5, cfg.cam_dist)
    local cp, cy      = cfg.cam_pitch, cfg.cam_yaw
    local ctx, cty, ctz = cfg.cam_tx, cfg.cam_ty, cfg.cam_tz

    local ey = cty + cd * math.sin(cp)
    local ex = ctx + cd * math.cos(cp) * math.sin(cy)
    local ez = ctz - cd * math.cos(cp) * math.cos(cy)

    local view  = model.mat_lookat_lh(ex, ey, ez, ctx, cty, ctz)
    local proj  = model.mat_persp_lh(0.8, RT_W / RT_H, 0.1, 1000.0)
    model.set_view(view)
    model.set_proj(proj)

    local yr    = cfg.mdl_yaw * DEG2RAD
    local world = model.mat_mul(model.mat_scale(cfg.mdl_scale), model.mat_roty(yr))
    cfg.last_world = world
    cfg.last_view  = view
    cfg.last_proj  = proj

    local ok, err = pcall(function()
        if cfg.r_outline then
            local c = cfg.ol_col
            model.render_screen_outline(cfg.mdl, world,
                c[1],c[2],c[3],c[4], cfg.ol_thick, RT_W, RT_H)
        end
        if cfg.r_glow then
            local c = cfg.gl_col
            model.render_screen_glow(cfg.mdl, world,
                c[1],c[2],c[3],c[4], cfg.gl_thick, RT_W, RT_H)
        end
        if cfg.r_chams then
            local v, o = cfg.vis_col, cfg.occ_col
            model.render_chams(cfg.mdl, world,
                v[1],v[2],v[3],v[4],  o[1],o[2],o[3],o[4])
        end
        if cfg.r_textured then
            model.render_textured(cfg.mdl, world, cfg.tex_alpha)
        end
        if cfg.r_wire then
            model.rs(model.RS_ZFUNC, 8)
            model.render_wireframe(cfg.mdl, world, 0, 1, 0, 1)
            model.rs(model.RS_ZFUNC, model.CMP_LESSEQUAL)
        end
        if cfg.r_skeleton then
            model.render_blender_skeleton(cfg.mdl, world,
                0.15, 0.55, 0.9, 1.0, cfg.selected_bone)
        end
        if cfg.r_bbox then
            model.render_bbox(cfg.mdl, world, 0, 1, 1, 1)
        end
    end)

    if not ok then
        client.log("[render] " .. tostring(err), 2)
    end

    model.rs(model.RS_ALPHABLENDENABLE, 1)
    model.rs(19, 5)
    model.rs(20, 6)
    model.rs(model.RS_ZENABLE,        1)
    model.rs(model.RS_ZWRITEENABLE,   1)
    model.rs(model.RS_ZFUNC,          model.CMP_LESSEQUAL)
    model.rs(model.RS_LIGHTING,       0)
    model.rs(model.RS_FILLMODE,       model.FILL_SOLID)
    model.rs(model.RS_CULLMODE,       model.CULL_CCW)
    model.rs(168,                     0xF)

    model.end_rt(cfg.rt)
end

local function world_to_vp(wx, wy, wz)
    if not (cfg.last_view and cfg.last_proj) then return nil end
    local sx, sy = model.project(cfg.last_view, cfg.last_proj, RT_W, RT_H, wx, wy, wz)
    if not sx then return nil end

    local scx = cfg.vp_px + sx * (cfg.vp_pw / RT_W)
    local scy = cfg.vp_py + sy * (cfg.vp_ph / RT_H)
    return scx, scy
end

local function bone_world_xyz(bi)
    if not (cfg.mdl and cfg.last_world) then return nil end
    return model.bone_world_pos(cfg.mdl, cfg.last_world, bi)
end

local BONE_HIT_RADIUS = 10
local function pick_bone(mx, my)
    if not cfg.mdl then return 0 end
    local bc     = model.bone_count(cfg.mdl)
    local best   = 0
    local bestD  = BONE_HIT_RADIUS * BONE_HIT_RADIUS
    for bi = 1, bc do
        local wx, wy, wz = bone_world_xyz(bi)
        if wx then
            local sx, sy = world_to_vp(wx, wy, wz)
            if sx then
                local dx, dy = sx - mx, sy - my
                local d2 = dx*dx + dy*dy
                if d2 < bestD then bestD = d2; best = bi end
            end
        end
    end
    return best
end

local GIZMO_LEN   = 55
local GIZMO_SHAFT = 8
local RING_SEGS   = 48

local AXIS_COL = {
    X  = { {1,0.15,0.15,1},  {1,0.6,0.6,1}  },
    Y  = { {0.15,1,0.15,1},  {0.6,1,0.6,1}  },
    Z  = { {0.15,0.45,1,1},  {0.6,0.75,1,1} },
    XY = { {1,1,0,0.55},     {1,1,0,0.9}    },
    XZ = { {1,0,1,0.55},     {1,0,1,0.9}    },
    YZ = { {0,1,1,0.55},     {0,1,1,0.9}    },
}

local function draw_gizmo(dl, bi)
    if not (cfg.mdl and cfg.last_world and cfg.last_view and cfg.last_proj) then return end

    local wx, wy, wz = bone_world_xyz(bi)
    if not wx then return end
    local ox, oy = world_to_vp(wx, wy, wz)
    if not ox then return end

    local mode = cfg.gizmo_mode

    local function acol(axis)
        local t = AXIS_COL[axis]
        local active = (cfg.gizmo_axis == axis)
        local c = active and t[2] or t[1]
        return c[1], c[2], c[3], c[4]
    end

    local function screen_dir(dX, dY, dZ)

        local tip_wx = wx + dX * 0.5
        local tip_wy = wy + dY * 0.5
        local tip_wz = wz + dZ * 0.5
        local tx, ty = world_to_vp(tip_wx, tip_wy, tip_wz)
        if not tx then return 1, 0 end
        local dx, dy = tx - ox, ty - oy
        local l = math.sqrt(dx*dx + dy*dy)
        if l < 0.5 then return 1, 0 end
        return dx/l, dy/l
    end

    local xdx, xdy = screen_dir(1,0,0)
    local ydx, ydy = screen_dir(0,1,0)
    local zdx, zdy = screen_dir(0,0,1)

    if mode == "move" or mode == "scale" then
        local PLANE_SZ = GIZMO_LEN * 0.22
        local function plane_quad(ax1x,ax1y, ax2x,ax2y, axis_name)
            local cx = ox + (ax1x + ax2x) * GIZMO_LEN * 0.32
            local cy = oy + (ax1y + ax2y) * GIZMO_LEN * 0.32
            local r,g,b,a = acol(axis_name)
            imgui.win_draw_rect(cx - PLANE_SZ*0.5, cy - PLANE_SZ*0.5,
                                cx + PLANE_SZ*0.5, cy + PLANE_SZ*0.5,
                                r, g, b, a, 1, 0)
            imgui.win_draw_rect(cx - PLANE_SZ*0.5+1, cy - PLANE_SZ*0.5+1,
                                cx + PLANE_SZ*0.5-1, cy + PLANE_SZ*0.5-1,
                                r, g, b, a*0.35, 0, 0)
        end
        plane_quad(xdx,xdy, ydx,ydy, "XY")
        plane_quad(xdx,xdy, zdx,zdy, "XZ")
        plane_quad(ydx,ydy, zdx,zdy, "YZ")

        local function arrow(ddx, ddy, axis_name)
            local r,g,b,a = acol(axis_name)
            local ex = ox + ddx * GIZMO_LEN
            local ey = oy + ddy * GIZMO_LEN
            imgui.win_draw_line(ox, oy, ex, ey, r, g, b, a, 2.5)
            local px, py = -ddy, ddx
            local ahead  = 10
            local aside  = 5
            imgui.win_draw_line(ex, ey,
                ex - ddx*ahead + px*aside, ey - ddy*ahead + py*aside,
                r, g, b, a, 2)
            imgui.win_draw_line(ex, ey,
                ex - ddx*ahead - px*aside, ey - ddy*ahead - py*aside,
                r, g, b, a, 2)
            if mode == "scale" then
                local hs = 5
                imgui.win_draw_rect(ex-hs, ey-hs, ex+hs, ey+hs, r,g,b,a, 1.5, 0)
                imgui.win_draw_rect(ex-hs+1, ey-hs+1, ex+hs-1, ey+hs-1, r,g,b,a*0.5, 0, 0)
            end
        end
        arrow(xdx, xdy, "X")
        arrow(ydx, ydy, "Y")
        arrow(zdx, zdy, "Z")

        imgui.win_draw_line(ox-4, oy, ox+4, oy, 1,1,1,1, 2)
        imgui.win_draw_line(ox, oy-4, ox, oy+4, 1,1,1,1, 2)

    elseif mode == "rotate" then
        local function ring(ax, ay, az, axis_name)
            local r,g,b,a = acol(axis_name)
            local ux,uy,uz, vx,vy,vz
            if math.abs(ax) < 0.9 then
                ux,uy,uz = 1,0,0
            else
                ux,uy,uz = 0,1,0
            end
            local dot = ux*ax+uy*ay+uz*az
            ux=ux-dot*ax; uy=uy-dot*ay; uz=uz-dot*az
            local ul = math.sqrt(ux*ux+uy*uy+uz*uz)
            if ul < 1e-6 then return end
            ux=ux/ul; uy=uy/ul; uz=uz/ul
            vx=ay*uz-az*uy; vy=az*ux-ax*uz; vz=ax*uy-ay*ux

            local R = 0.6
            local pts = {}
            for i = 0, RING_SEGS do
                local t = i * 2 * math.pi / RING_SEGS
                local px = wx + (ux*math.cos(t) + vx*math.sin(t)) * R
                local py = wy + (uy*math.cos(t) + vy*math.sin(t)) * R
                local pz = wz + (uz*math.cos(t) + vz*math.sin(t)) * R
                local sx2, sy2 = world_to_vp(px, py, pz)
                if sx2 then pts[#pts+1] = {sx2, sy2} end
            end
            for i = 1, #pts - 1 do
                imgui.win_draw_line(pts[i][1],pts[i][2],
                                   pts[i+1][1],pts[i+1][2],
                                   r,g,b,a, 2)
            end
        end
        ring(1,0,0, "X")
        ring(0,1,0, "Y")
        ring(0,0,1, "Z")

        imgui.win_draw_line(ox-4, oy, ox+4, oy, 1,1,1,0.9, 2)
        imgui.win_draw_line(ox, oy-4, ox, oy+4, 1,1,1,0.9, 2)
    end
end

local function gizmo_hit(bi, mx, my)
    if not (cfg.mdl and cfg.last_world) then return nil end
    local wx, wy, wz = bone_world_xyz(bi)
    if not wx then return nil end
    local ox, oy = world_to_vp(wx, wy, wz)
    if not ox then return nil end

    local mode = cfg.gizmo_mode

    local function screen_dir(dX, dY, dZ)
        local tip_wx = wx + dX * 0.5
        local tip_wy = wy + dY * 0.5
        local tip_wz = wz + dZ * 0.5
        local tx, ty = world_to_vp(tip_wx, tip_wy, tip_wz)
        if not tx then return 1, 0 end
        local dx, dy = tx - ox, ty - oy
        local l = math.sqrt(dx*dx + dy*dy)
        if l < 0.5 then return 1, 0 end
        return dx/l, dy/l
    end

    local xdx, xdy = screen_dir(1,0,0)
    local ydx, ydy = screen_dir(0,1,0)
    local zdx, zdy = screen_dir(0,0,1)

    local function dist_to_arrow(ddx, ddy)
        local L = GIZMO_LEN
        local ex = ox + ddx*L
        local ey = oy + ddy*L
        local bx, by = ex-ox, ey-oy
        local t = ((mx-ox)*bx + (my-oy)*by) / (bx*bx+by*by+1e-9)
        t = math.max(0, math.min(1, t))
        local px2 = ox+t*bx - mx
        local py2 = oy+t*by - my
        return math.sqrt(px2*px2+py2*py2), t
    end

    if mode == "move" or mode == "scale" then
        local PLANE_SZ = GIZMO_LEN * 0.22
        local function plane_hit(ax1x,ax1y, ax2x,ax2y)
            local cx = ox + (ax1x + ax2x) * GIZMO_LEN * 0.32
            local cy = oy + (ax1y + ax2y) * GIZMO_LEN * 0.32
            return math.abs(mx-cx) < PLANE_SZ and math.abs(my-cy) < PLANE_SZ
        end
        if plane_hit(xdx,xdy, ydx,ydy) then return "XY" end
        if plane_hit(xdx,xdy, zdx,zdy) then return "XZ" end
        if plane_hit(ydx,ydy, zdx,zdy) then return "YZ" end

        local dX, tX = dist_to_arrow(xdx, xdy)
        local dY, tY = dist_to_arrow(ydx, ydy)
        local dZ, tZ = dist_to_arrow(zdx, zdy)
        if dX < GIZMO_SHAFT and tX > 0.05 then return "X" end
        if dY < GIZMO_SHAFT and tY > 0.05 then return "Y" end
        if dZ < GIZMO_SHAFT and tZ > 0.05 then return "Z" end

    elseif mode == "rotate" then
        local function ring_hit(ax, ay, az)
            local ux,uy,uz
            if math.abs(ax) < 0.9 then ux,uy,uz=1,0,0 else ux,uy,uz=0,1,0 end
            local dot=ux*ax+uy*ay+uz*az
            ux=ux-dot*ax; uy=uy-dot*ay; uz=uz-dot*az
            local ul=math.sqrt(ux*ux+uy*uy+uz*uz)
            if ul<1e-6 then return false end
            ux=ux/ul; uy=uy/ul; uz=uz/ul
            local vx=ay*uz-az*uy; vy=az*ux-ax*uz; vz=ax*uy-ay*ux

            local R = 0.6
            local minD = 1e9
            for i = 0, 15 do
                local t = i * 2 * math.pi / 16
                local px = wx + (ux*math.cos(t)+vx*math.sin(t))*R
                local py = wy + (uy*math.cos(t)+vy*math.sin(t))*R
                local pz = wz + (uz*math.cos(t)+vz*math.sin(t))*R
                local sx2, sy2 = world_to_vp(px, py, pz)
                if sx2 then
                    local dd = math.sqrt((sx2-mx)^2+(sy2-my)^2)
                    if dd < minD then minD = dd end
                end
            end
            return minD < 10
        end
        if ring_hit(1,0,0) then return "X" end
        if ring_hit(0,1,0) then return "Y" end
        if ring_hit(0,0,1) then return "Z" end
    end
    return nil
end

local function gizmo_apply_drag(bi, dx, dy)
    if not cfg.bone_edit[bi] then reset_bone(bi) end
    local ed  = cfg.bone_edit[bi]
    local axis = cfg.gizmo_axis
    local mode = cfg.gizmo_mode
    local sens_move = 0.02
    local sens_rot  = 0.9
    local sens_scl  = 0.02

    if mode == "move" then
        if axis == "X"  then ed[1] = cfg.gizmo_bone_origin[1] + dx * sens_move end
        if axis == "Y"  then ed[2] = cfg.gizmo_bone_origin[2] - dy * sens_move end
        if axis == "Z"  then ed[3] = cfg.gizmo_bone_origin[3] + dx * sens_move end
        if axis == "XY" then
            ed[1] = cfg.gizmo_bone_origin[1] + dx * sens_move
            ed[2] = cfg.gizmo_bone_origin[2] - dy * sens_move
        end
        if axis == "XZ" then
            ed[1] = cfg.gizmo_bone_origin[1] + dx * sens_move
            ed[3] = cfg.gizmo_bone_origin[3] - dy * sens_move
        end
        if axis == "YZ" then
            ed[2] = cfg.gizmo_bone_origin[2] - dy * sens_move
            ed[3] = cfg.gizmo_bone_origin[3] + dx * sens_move
        end
    elseif mode == "rotate" then
        local delta = (math.abs(dx) > math.abs(dy)) and dx or -dy
        if axis == "X" then ed[4] = cfg.gizmo_bone_origin[4] + delta * sens_rot end
        if axis == "Y" then ed[5] = cfg.gizmo_bone_origin[5] + delta * sens_rot end
        if axis == "Z" then ed[6] = cfg.gizmo_bone_origin[6] + delta * sens_rot end
    elseif mode == "scale" then
        local delta = (math.abs(dx) > math.abs(dy)) and dx or -dy
        if axis == "X"  then ed[1] = cfg.gizmo_bone_origin[1] + delta * sens_scl end
        if axis == "Y"  then ed[2] = cfg.gizmo_bone_origin[2] + delta * sens_scl end
        if axis == "Z"  then ed[3] = cfg.gizmo_bone_origin[3] + delta * sens_scl end
        if axis == "XY" or axis == "XZ" or axis == "YZ" then
            local s = delta * sens_scl
            ed[1] = cfg.gizmo_bone_origin[1] + s
            ed[2] = cfg.gizmo_bone_origin[2] + s
            ed[3] = cfg.gizmo_bone_origin[3] + s
        end
    end
    model.bone_set_pose(cfg.mdl, bi, ed[1],ed[2],ed[3],ed[4],ed[5],ed[6])
end

local function tbtn(label, val, w, h)
    local lbl = val and ("[" .. label .. "]") or (" " .. label .. " ")
    return imgui.Button(lbl .. "##t_" .. label, w or 120, h or 20)
end

local function ui_outliner_meshes(panel_w)
    if not cfg.mdl then imgui.TextDisabled("No model loaded"); return end
    local mc = model.mesh_count(cfg.mdl)

    imgui.Text(mc .. " meshes")
    if imgui.Button("All##msa", 38, 18) then
        for i = 1, mc do
            cfg.mesh_visible[i] = true
            model.set_mesh_visible(cfg.mdl, i, true)
        end
    end
    imgui.SameLine()
    if imgui.Button("None##msn", 45, 18) then
        for i = 1, mc do
            cfg.mesh_visible[i] = false
            model.set_mesh_visible(cfg.mdl, i, false)
        end
    end
    imgui.Separator()

    for i = 1, mc do
        local vis   = cfg.mesh_visible[i] ~= false
        local nm    = model.mesh_name(cfg.mdl, i) or ("Mesh " .. i)
        local maxch = math.max(1, panel_w / 7 - 6)
        local short = nm:len() > maxch and nm:sub(1, maxch - 1) .. "…" or nm

        local eye = vis and "O##ve" .. i or "-##ve" .. i
        if imgui.Button(eye, 20, 18) then
            cfg.mesh_visible[i] = not vis
            model.set_mesh_visible(cfg.mdl, i, not vis)
        end
        imgui.SameLine()

        local is_sel = (cfg.selected_mesh == i)
        if imgui.Selectable(short .. "##ms" .. i, is_sel) then
            cfg.selected_mesh = is_sel and 0 or i
            cfg.prop_tab = "mesh"
        end

        if cfg.tex_overrides[i] then
            imgui.SameLine()
            imgui.TextDisabled("T")
        end
    end
end

local function ui_outliner_bones(panel_w)
    if not cfg.mdl then imgui.TextDisabled("No model loaded"); return end
    local bc = model.bone_count(cfg.mdl)
    if bc == 0 then imgui.TextDisabled("No bones"); return end

    imgui.Text(bc .. " bones")
    imgui.Separator()

    local children = {}
    for i = 1, bc do children[i] = {} end
    local roots = {}
    for i = 1, bc do
        local _,_,_,par = model.bone_pos(cfg.mdl, i)
        if par < 0 then
            roots[#roots + 1] = i
        else
            local pi = par + 1
            if pi >= 1 and pi <= bc then
                children[pi][#children[pi] + 1] = i
            else
                roots[#roots + 1] = i
            end
        end
    end

    local max_name_chars = math.max(1, panel_w / 7)
    local function draw_tree(bi, depth)
        if not cfg.bone_edit[bi] then reset_bone(bi) end
        local nm    = model.bone_name(cfg.mdl, bi) or ("Bone " .. bi)
        local mc2   = math.max(1, max_name_chars - depth * 2)
        local short = nm:len() > mc2 and nm:sub(1, mc2 - 1) .. "…" or nm
        local indent = string.rep("  ", depth)
        local hch  = #children[bi] > 0
        local pfx   = indent .. (hch and "+ " or "  ")

        local ed   = cfg.bone_edit[bi]
        local mod  = ed and (ed[1]~=0 or ed[2]~=0 or ed[3]~=0 or
                              ed[4]~=0 or ed[5]~=0 or ed[6]~=0)
        local lbl  = pfx .. short .. (mod and " *" or "") .. "##bo" .. bi
        local isel = (cfg.selected_bone == bi)

        if imgui.Selectable(lbl, isel) then
            cfg.selected_bone = isel and 0 or bi
            cfg.prop_tab = "bone"
        end

        for _, ch in ipairs(children[bi]) do
            draw_tree(ch, depth + 1)
        end
    end

    for _, r in ipairs(roots) do
        draw_tree(r, 0)
    end
end

local function ui_prop_bone(pw)
    if not cfg.mdl then return end
    local bc = model.bone_count(cfg.mdl)

    if cfg.selected_bone == 0 or cfg.selected_bone > bc then
        imgui.TextDisabled("Select a bone in")
        imgui.TextDisabled("the Outliner (Bones)")
        imgui.Spacing()
        if tbtn("Show Skeleton", cfg.r_skeleton, pw - 14, 22) then
            cfg.r_skeleton = not cfg.r_skeleton
        end
        return
    end

    local bi  = cfg.selected_bone
    local nm  = model.bone_name(cfg.mdl, bi) or ("Bone " .. bi)
    local bx, by, bz, par = model.bone_pos(cfg.mdl, bi)

    imgui.TextColored(1, 0.85, 0.2, 1, nm)
    imgui.TextDisabled(string.format("#%d  parent: %d", bi, par))
    imgui.TextDisabled(string.format("rest  %.3f  %.3f  %.3f", bx, by, bz))
    imgui.Separator()

    if not cfg.bone_edit[bi] then reset_bone(bi) end
    local ed  = cfg.bone_edit[bi]
    local chg = false
    local v, c

    imgui.Text("Location  (parent-local)")
    imgui.PushItemWidth(pw - 14)
    v,c = imgui.SliderFloat("LX##bpx", ed[1], -10, 10); if c then ed[1]=v; chg=true end
    v,c = imgui.SliderFloat("LY##bpy", ed[2], -10, 10); if c then ed[2]=v; chg=true end
    v,c = imgui.SliderFloat("LZ##bpz", ed[3], -10, 10); if c then ed[3]=v; chg=true end

    imgui.Spacing()
    imgui.Text("Rotation  (degrees)")
    v,c = imgui.SliderFloat("RX##brx", ed[4], -180, 180); if c then ed[4]=v; chg=true end
    v,c = imgui.SliderFloat("RY##bry", ed[5], -180, 180); if c then ed[5]=v; chg=true end
    v,c = imgui.SliderFloat("RZ##brz", ed[6], -180, 180); if c then ed[6]=v; chg=true end
    imgui.PopItemWidth()

    if chg then
        model.bone_set_pose(cfg.mdl, bi, ed[1], ed[2], ed[3], ed[4], ed[5], ed[6])
    end

    imgui.Spacing()
    if imgui.Button("Reset Bone##bpr", 95, 22) then
        reset_bone(bi)
        model.bone_set_pose(cfg.mdl, bi, 0,0,0,0,0,0)
    end
    imgui.SameLine()
    if imgui.Button("Reset All##bpra", 90, 22) then
        for i = 1, bc do
            reset_bone(i)
            model.bone_set_pose(cfg.mdl, i, 0,0,0,0,0,0)
        end
    end

    imgui.Spacing()
    imgui.Separator()
    if tbtn("Show Skeleton", cfg.r_skeleton, pw - 14, 22) then
        cfg.r_skeleton = not cfg.r_skeleton
    end

    if cfg.last_world and cfg.last_view and cfg.last_proj then
        local wx, wy, wz = model.bone_world_pos(cfg.mdl, cfg.last_world, bi)
        if wx then
            local sx, sy = model.project(cfg.last_view, cfg.last_proj, RT_W, RT_H, wx, wy, wz)
            if sx then
                imgui.Spacing()
                imgui.TextDisabled(string.format("screen  %.0f, %.0f", sx, sy))
            end
        end
    end
end

local function ui_prop_mesh(pw)
    if not cfg.mdl then return end
    local mc = model.mesh_count(cfg.mdl)

    if cfg.selected_mesh == 0 or cfg.selected_mesh > mc then
        imgui.TextDisabled("Select a mesh in")
        imgui.TextDisabled("the Outliner (Meshes)")
        return
    end

    local i   = cfg.selected_mesh
    local nm  = model.mesh_name(cfg.mdl, i) or ("Mesh " .. i)
    local vc  = model.mesh_vert_count(cfg.mdl, i)
    local tc  = model.mesh_tri_count(cfg.mdl, i)

    imgui.TextColored(0.4, 0.85, 1, 1, nm)
    imgui.TextDisabled(vc .. " verts   " .. tc .. " tris")
    imgui.Separator()

    local vis = cfg.mesh_visible[i] ~= false
    local vlbl = vis and "Visible##mvt" or "Hidden##mvt"
    if imgui.Button(vlbl, pw - 14, 22) then
        cfg.mesh_visible[i] = not vis
        model.set_mesh_visible(cfg.mdl, i, not vis)
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Text("Texture override")
    imgui.PushItemWidth(pw - 14)
    local np, pc = imgui.InputText("##ctex_mi", cfg.custom_tex_path)
    if pc and np then cfg.custom_tex_path = np end
    imgui.PopItemWidth()

    if imgui.Button("Apply##ta", 56, 20) and cfg.custom_tex_path ~= "" then
        local tex = client.load_texture(cfg.custom_tex_path)
        if tex then
            if cfg.tex_overrides[i] then client.release_texture(cfg.tex_overrides[i]) end
            cfg.tex_overrides[i] = tex
            model.set_mesh_tex(cfg.mdl, i, tex)
        end
    end

    if cfg.tex_overrides[i] then
        imgui.SameLine()
        if imgui.Button("Clear##tc", 48, 20) then
            client.release_texture(cfg.tex_overrides[i])
            cfg.tex_overrides[i] = nil
            model.set_mesh_tex(cfg.mdl, i, nil)
        end
    end
end

local function ui_prop_render(pw)
    local bw = pw - 14

    imgui.Text("Render modes")
    imgui.Separator()

    local function rmb(lbl, key)
        if tbtn(lbl, cfg[key], bw, 20) then cfg[key] = not cfg[key] end
    end
    rmb("Textured",   "r_textured")
    rmb("Flat Chams", "r_chams")
    rmb("Wireframe",  "r_wire")
    rmb("Outline",    "r_outline")
    rmb("Glow",       "r_glow")
    rmb("Skeleton",   "r_skeleton")
    rmb("BBox",       "r_bbox")
    rmb("ESP 2D",     "r_esp")
    rmb("Auto-Rotate","r_autorot")

    imgui.Spacing()
    imgui.Separator()
    imgui.Text("Chams — Visible")
    local vr,vg,vb,va,vc = imgui.ColorEdit4("##vcc",
        cfg.vis_col[1], cfg.vis_col[2], cfg.vis_col[3], cfg.vis_col[4])
    if vc then cfg.vis_col = {vr,vg,vb,va} end

    imgui.Text("Chams — Occluded")
    local or_,og,ob,oa,oc = imgui.ColorEdit4("##occ2",
        cfg.occ_col[1], cfg.occ_col[2], cfg.occ_col[3], cfg.occ_col[4])
    if oc then cfg.occ_col = {or_,og,ob,oa} end

    imgui.Spacing()
    imgui.Text("Outline")
    local r,g,b,a,cc = imgui.ColorEdit4("##olc",
        cfg.ol_col[1], cfg.ol_col[2], cfg.ol_col[3], cfg.ol_col[4])
    if cc then cfg.ol_col = {r,g,b,a} end
    imgui.PushItemWidth(bw)
    local t, tc2 = imgui.SliderFloat("Thick##olt", cfg.ol_thick, 1.01, 1.20)
    if tc2 then cfg.ol_thick = t end

    imgui.Spacing()
    imgui.Text("Glow")
    local r2,g2,b2,a2,cc2 = imgui.ColorEdit4("##glc",
        cfg.gl_col[1], cfg.gl_col[2], cfg.gl_col[3], cfg.gl_col[4])
    if cc2 then cfg.gl_col = {r2,g2,b2,a2} end
    local t2, tc3 = imgui.SliderFloat("Thick##glt", cfg.gl_thick, 1.01, 1.20)
    if tc3 then cfg.gl_thick = t2 end

    imgui.Spacing()
    imgui.Text("Texture alpha")
    local al, alc = imgui.SliderFloat("##ta", cfg.tex_alpha, 0.0, 1.0)
    if alc then cfg.tex_alpha = al end

    imgui.Spacing()
    imgui.Text("ESP color")
    local er,eg,eb,ea,ecc = imgui.ColorEdit4("##espc",
        cfg.esp_col[1], cfg.esp_col[2], cfg.esp_col[3], cfg.esp_col[4])
    if ecc then cfg.esp_col = {er,eg,eb,ea} end
    imgui.PopItemWidth()
end

local function draw_esp_overlay(px, py, vpw, vph)
    if not (cfg.r_esp and cfg.mdl and cfg.last_world and cfg.last_view and cfg.last_proj) then
        return
    end
    local bx1,by1,bx2,by2 = model.bbox_screen(
        cfg.mdl, cfg.last_world, cfg.last_view, cfg.last_proj, RT_W, RT_H)
    if not bx1 then return end

    local sx = vpw / RT_W
    local sy = vph / RT_H
    bx1 = math.max(0, math.min(RT_W, bx1)) * sx
    by1 = math.max(0, math.min(RT_H, by1)) * sy
    bx2 = math.max(0, math.min(RT_W, bx2)) * sx
    by2 = math.max(0, math.min(RT_H, by2)) * sy

    if bx2 - bx1 < 2 or by2 - by1 < 2 then return end

    local ec = cfg.esp_col
    local lx1,ly1,lx2,ly2 = px+bx1, py+by1, px+bx2, py+by2
    imgui.win_draw_rect(lx1,ly1, lx2,ly2, ec[1],ec[2],ec[3],ec[4], 1.5, 2)

    local cw = (bx2-bx1)*0.18
    local ch = (by2-by1)*0.18
    local function cl(ax,ay, bxx,byy)
        imgui.win_draw_line(ax,ay, bxx,byy, ec[1],ec[2],ec[3],ec[4], 2)
    end
    cl(lx1,ly1, lx1+cw,ly1); cl(lx1,ly1, lx1,ly1+ch)
    cl(lx2,ly1, lx2-cw,ly1); cl(lx2,ly1, lx2,ly1+ch)
    cl(lx1,ly2, lx1+cw,ly2); cl(lx1,ly2, lx1,ly2-ch)
    cl(lx2,ly2, lx2-cw,ly2); cl(lx2,ly2, lx2,ly2-ch)
end

function on_end_scene()
    do_render()

    imgui.SetNextWindowSize(1100, 730, imgui.ImGuiCond_FirstUseEver or 2)
    if not imgui.Begin("Model Viewer — Pose Tool") then
        imgui.End()
        return
    end
    local wx, wy = imgui.GetWindowPos()
    local ww, wh = imgui.GetWindowSize()
    local dl = imgui.get_window_draw_list()
    dl:add_rect_filled(wx, wy, wx + ww, wy + wh, 0.10, 0.10, 0.10, 0.80, 8)

    imgui.Text("FBX:")
    imgui.SameLine()
    local nf, fc = imgui.InputText("##fbxdir", cfg.fbx_folder)
    if fc and nf then cfg.fbx_folder = nf end
    imgui.SameLine()
    if imgui.Button("Scan##top", 50, 22) then scan() end
    imgui.SameLine()
    local prev = (#cfg.fbx_list > 0)
        and (cfg.fbx_list[cfg.sel_idx]:match("[/\\]([^/\\]+)$") or "?")
        or  "none"
    if imgui.BeginCombo("##fbxpick", prev) then
        for i, p in ipairs(cfg.fbx_list) do
            local name = p:match("[/\\]([^/\\]+)$") or p
            if imgui.Selectable(name .. "##fi" .. i, i == cfg.sel_idx) then
                cfg.sel_idx = i
            end
        end
        imgui.EndCombo()
    end
    imgui.SameLine()
    if imgui.Button("Load##top", 55, 22) then load_model() end
    imgui.SameLine()
    imgui.Text("Tex:")
    imgui.SameLine()
    local nt, tc = imgui.InputText("##texdir", cfg.tex_folder)
    if tc and nt then cfg.tex_folder = nt end

    imgui.Separator()

    imgui.Text("Load:")
    imgui.SameLine()
    imgui.PushItemWidth(420)
    local np2, pc2 = imgui.InputText("##direct_fbx", cfg.direct_fbx_path)
    if pc2 and np2 then cfg.direct_fbx_path = np2 end
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button("Browse Folder##dbr", 100, 22) then
        local folder = cfg.direct_fbx_path:match("^(.*[/\\])") or cfg.fbx_folder
        local found  = model.scan_fbx(folder)
        if #found > 0 then
            cfg.fbx_list   = found
            cfg.fbx_folder = folder
            cfg.sel_idx    = 1
            client.log("[viewer] scanned " .. #found .. " file(s) in " .. folder, 1)
        else
            client.log("[viewer] no FBX/OBJ found in " .. folder, 2)
        end
    end
    imgui.SameLine()
if imgui.Button("Load File##dlf", 75, 22) then
    local path = cfg.direct_fbx_path
    if not path or path == "" then
        client.log("[viewer] no path entered — paste a full .fbx path", 2)
    elseif not path:match("%.[Ff][Bb][Xx]$")
       and not path:match("%.[Oo][Bb][Jj]$")
       and not path:match("%.[Dd][Aa][Ee]$")
       and not path:match("%.[Gg][Ll][Bb]$")
       and not path:match("%.[Gg][Ll][Tt][Ff]$") then
        client.log("[viewer] path must point to a model file (.fbx .obj .dae .glb .gltf), got: " .. path, 2)
    else
        local test = io.open(path, "rb")
        if not test then
            client.log("[viewer] file not found or not readable: " .. path, 3)
        else
            test:close()

            for _, tex in pairs(cfg.tex_overrides) do
                if tex then client.release_texture(tex) end
            end
            cfg.tex_overrides = {}
            if cfg.mdl then model.free(cfg.mdl); cfg.mdl = nil end

            local fbx_dir = path:match("^(.*)[/\\][^/\\]+$")
            if fbx_dir and fbx_dir ~= "" then
                cfg.tex_folder = fbx_dir
                client.log("[viewer] tex folder auto-set to " .. fbx_dir, 1)
            end

            local m, err = model.load(path, cfg.tex_folder)
            if not m then
                client.log("[viewer] direct load failed: " .. (err or "?"), 3)
            else
                cfg.mdl = m
                init_after_load(m)
                for i = 1, model.mesh_count(m) do
                    local mn = model.mesh_name(m, i)
                    if mn then
                        local tname = mn:gsub("^mt_", "tx_") .. "_Base.tga"
                        local tex   = client.load_texture(cfg.tex_folder .. "\\" .. tname)
                        if tex then
                            cfg.tex_overrides[i] = tex
                            model.set_mesh_tex(m, i, tex)
                        end
                    end
                end
                local already = false
                for i, p in ipairs(cfg.fbx_list) do
                    if p == path then cfg.sel_idx = i; already = true; break end
                end
                if not already then
                    cfg.fbx_list[#cfg.fbx_list + 1] = path
                    cfg.sel_idx = #cfg.fbx_list
                end
                client.log(string.format("[viewer] loaded %s  (%dm %db)  tex=%s",
                    path:match("[/\\]([^/\\]+)$") or path,
                    model.mesh_count(m), model.bone_count(m), cfg.tex_folder), 1)
            end
        end
    end
end

imgui.Separator()

    imgui.Text("Pose:")
    imgui.SameLine()
    imgui.PushItemWidth(420)
    local npp, ppc = imgui.InputText("##posepath", cfg.pose_path)
    if ppc and npp then cfg.pose_path = npp end
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button("Save Pose##psa", 80, 22) then
        local path = cfg.pose_path
        if path and path ~= "" then
            if not path:match("%.lua$") then path = path .. ".lua" end
            cfg.pose_path = path
            pose_save(path)
        else
            client.log("[pose] enter a file path first", 2)
        end
    end
    imgui.SameLine()
    if imgui.Button("Load Pose##plo", 80, 22) then
        local path = cfg.pose_path
        if path and path ~= "" then
            if not path:match("%.lua$") then path = path .. ".lua" end
            cfg.pose_path = path
            pose_load(path)
        else
            client.log("[pose] enter a file path first", 2)
        end
    end
    imgui.SameLine()
    if imgui.Button("Reset All##pra2", 80, 22) then
        if cfg.mdl then
            local bc = model.bone_count(cfg.mdl)
            for i = 1, bc do
                reset_bone(i)
                model.bone_set_pose(cfg.mdl, i, 0,0,0,0,0,0)
            end
            client.log("[pose] all bones reset", 1)
        end
    end

    imgui.Separator()

    local avail_w, avail_h = imgui.GetContentRegionAvail()
    local OW = 195
    local PW = 215
    local VW = math.max(80, avail_w - OW - PW - 22)
    local CH = avail_h - 2

    imgui.BeginChild("##outliner", OW, CH, true)

    imgui.TextColored(1, 0.9, 0.3, 1, "Outliner")
    imgui.Separator()

    local mt = cfg.outliner_tab == "meshes"
    local bt = cfg.outliner_tab == "bones"
    if imgui.Button(mt and "[Meshes]" or " Meshes ", OW - 10, 20) then
        cfg.outliner_tab = "meshes"
    end
    if imgui.Button(bt and "[Bones]" or " Bones  ", OW - 10, 20) then
        cfg.outliner_tab = "bones"
    end
    imgui.Separator()

    if cfg.outliner_tab == "meshes" then
        ui_outliner_meshes(OW - 10)
    else
        ui_outliner_bones(OW - 10)
    end

    imgui.EndChild()
    imgui.SameLine()

    imgui.BeginChild("##viewport", VW, CH, false)

    local function qtb(lbl, key)
        local on = cfg[key]
        local bl = on and ("[" .. lbl .. "]") or (" " .. lbl .. " ")
        if imgui.Button(bl .. "##q_" .. lbl, lbl:len()*7 + 6, 20) then
            cfg[key] = not cfg[key]
        end
        imgui.SameLine()
    end
    qtb("Tex",    "r_textured")
    qtb("Chams",  "r_chams")
    qtb("Wire",   "r_wire")
    qtb("Skel",   "r_skeleton")
    qtb("BBox",   "r_bbox")
    qtb("ESP",    "r_esp")
    qtb("Auto",   "r_autorot")

    do
        local on = cfg.gizmo_enabled
        local lbl = on and "[Gizmo]" or " Gizmo "
        if imgui.Button(lbl .. "##giz_tog", 60, 20) then
            cfg.gizmo_enabled = not cfg.gizmo_enabled
        end
        imgui.SameLine()
    end

    if cfg.gizmo_enabled then
        local modes = { {"G","move"}, {"R","rotate"}, {"S","scale"} }
        for _, mv in ipairs(modes) do
            local active = cfg.gizmo_mode == mv[2]
            local lbl2   = active and ("[" .. mv[1] .. "]") or (" " .. mv[1] .. " ")
            if imgui.Button(lbl2 .. "##gm_" .. mv[1], 26, 20) then
                cfg.gizmo_mode = mv[2]
            end
            imgui.SameLine()
        end
        imgui.TextDisabled("G=Move  R=Rot  S=Scale  |  LMB=select  drag=transform")
    end

    imgui.NewLine()

    local vpw = VW - 8
    local vph = math.min(math.floor(vpw * RT_H / RT_W), CH - 68)
    local px, py = imgui.GetCursorScreenPos()

    cfg.vp_px = px; cfg.vp_py = py
    cfg.vp_pw = vpw; cfg.vp_ph = vph

    imgui.InvisibleButton("##ivp", vpw, vph)
    local vp_hovered = imgui.IsItemHovered()
    local vp_clicked = imgui.IsItemClicked and imgui.IsItemClicked(0)

    if cfg.rt then
        local rtex = model.rt_tex(cfg.rt)
        if rtex then
            model.imgui_image(rtex, px, py, px + vpw, py + vph)
        end
    end

    imgui.win_draw_rect(px, py, px + vpw, py + vph, 0.12, 0.12, 0.2, 1, 1)

    draw_esp_overlay(px, py, vpw, vph)

    if cfg.gizmo_enabled and cfg.selected_bone > 0 and
       cfg.r_skeleton and cfg.mdl then
        draw_gizmo(dl, cfg.selected_bone)
    end

    if cfg.gizmo_enabled and cfg.r_skeleton and cfg.mdl and
       cfg.last_world and cfg.last_view and cfg.last_proj then
        imgui.PushClipRect(px, py, px + vpw, py + vph, true)
        local bc = model.bone_count(cfg.mdl)
        for bi = 1, bc do
            local wx2, wy2, wz2 = bone_world_xyz(bi)
            if wx2 then
                local sx2, sy2 = world_to_vp(wx2, wy2, wz2)
                if sx2 and
                   sx2 >= px and sx2 <= px + vpw and
                   sy2 >= py and sy2 <= py + vph then
                    local issel = (bi == cfg.selected_bone)
                    local cr,cg,cb,ca = 0.9, 0.9, 0.3, 0.9
                    if issel then cr,cg,cb,ca = 1,0.6,0,1 end
                    local r = issel and 5 or 3
                    imgui.win_draw_line(sx2-r, sy2, sx2+r, sy2, cr,cg,cb,ca, issel and 2.5 or 1.5)
                    imgui.win_draw_line(sx2, sy2-r, sx2, sy2+r, cr,cg,cb,ca, issel and 2.5 or 1.5)
                end
            end
        end
        imgui.PopClipRect()
    end

    if cfg.mdl then
        imgui.win_draw_text(px+5, py+3, 0.4, 1, 0.4, 0.8,
            string.format("%dm %db  dist=%.1f",
                model.mesh_count(cfg.mdl),
                model.bone_count(cfg.mdl),
                cfg.cam_dist), 11)
        if cfg.selected_bone > 0 then
            local bnm = model.bone_name(cfg.mdl, cfg.selected_bone)
                        or ("Bone " .. cfg.selected_bone)
            local mode_str = cfg.gizmo_enabled and (" [" .. cfg.gizmo_mode .. "]") or ""
            imgui.win_draw_text(px+5, py+16, 1, 0.8, 0.2, 0.9,
                "Bone: " .. bnm .. mode_str, 11)
        end
        if cfg.selected_mesh > 0 then
            local mnm = model.mesh_name(cfg.mdl, cfg.selected_mesh)
                        or ("Mesh " .. cfg.selected_mesh)
            imgui.win_draw_text(px+5, py+29, 0.4, 0.8, 1, 0.9, "Mesh: " .. mnm, 11)
        end
    end

    if vp_hovered then
        local mx, my = imgui.GetMousePos()


        if imgui.IsMouseClicked(0) then
            cfg.gizmo_active  = false
            cfg.gizmo_axis    = nil
            cfg.cam_orbiting  = false

            if cfg.gizmo_enabled and cfg.r_skeleton then
                if cfg.selected_bone > 0 then
                    local hit = gizmo_hit(cfg.selected_bone, mx, my)
                    if hit then
                        cfg.gizmo_active      = true
                        cfg.gizmo_axis        = hit
                        cfg.gizmo_drag_origin = {x = mx, y = my}
                        local ed = cfg.bone_edit[cfg.selected_bone] or {0,0,0,0,0,0}
                        cfg.gizmo_bone_origin = {ed[1],ed[2],ed[3],ed[4],ed[5],ed[6]}
                    else
                        local picked = pick_bone(mx, my)
                        if picked > 0 then
                            cfg.selected_bone = picked
                            cfg.prop_tab = "bone"
                        else
                            cfg.cam_orbiting = true
                        end
                    end
                else
                    local picked = pick_bone(mx, my)
                    if picked > 0 then
                        cfg.selected_bone = picked
                        cfg.prop_tab = "bone"
                    else
                        cfg.cam_orbiting = true
                    end
                end
            else
                cfg.cam_orbiting = true
            end
        end

        if imgui.IsMouseDragging(0) then
            if cfg.gizmo_active and cfg.gizmo_drag_origin and cfg.selected_bone > 0 then
                local ddx = mx - cfg.gizmo_drag_origin.x
                local ddy = my - cfg.gizmo_drag_origin.y
                gizmo_apply_drag(cfg.selected_bone, ddx, ddy)
            elseif cfg.cam_orbiting then
                local ddx, ddy = imgui.GetMouseDragDelta(0, 0)
                imgui.ResetMouseDragDelta(0)
                cfg.cam_yaw   = cfg.cam_yaw + ddx * 0.005
                cfg.cam_pitch = math.max(-1.5, math.min(1.5, cfg.cam_pitch - ddy * 0.005))
            end
        end

        if not imgui.IsMouseDown(0) then
            cfg.gizmo_active = false
            cfg.cam_orbiting = false
        end

        for btn = 1, 2 do
            if imgui.IsMouseDragging(btn) then
                local ddx, ddy = imgui.GetMouseDragDelta(btn, 0)
                imgui.ResetMouseDragDelta(btn)
                local f = cfg.cam_dist * 0.0015
                cfg.cam_ty = cfg.cam_ty + ddy * f
                cfg.cam_tx = cfg.cam_tx - ddx * math.cos(cfg.cam_yaw) * f
                cfg.cam_tz = cfg.cam_tz - ddx * math.sin(cfg.cam_yaw) * f
            end
        end

        local wheel = model.imgui_wheel()
        if wheel ~= 0 then
            cfg.cam_dist = math.max(0.5, cfg.cam_dist - wheel * 0.5)
            model.consume_wheel()
        end
    else
        if not imgui.IsMouseDown(0) then
            cfg.gizmo_active = false
        end
    end

    imgui.Spacing()
    imgui.PushItemWidth(105)
    local sc, scc = imgui.SliderFloat("Scale##vs", cfg.mdl_scale, 0.01, 30)
    if scc then cfg.mdl_scale = sc end
    imgui.SameLine()
    local yw, ywc = imgui.SliderFloat("Yaw##vy", cfg.mdl_yaw, -180, 180)
    if ywc then cfg.mdl_yaw = yw end
    imgui.SameLine()
    local dd, dc = imgui.SliderFloat("Dist##vd", cfg.cam_dist, 0.5, 200)
    if dc then cfg.cam_dist = dd end
    imgui.PopItemWidth()

    imgui.EndChild()
    imgui.SameLine()

    imgui.BeginChild("##props", PW, CH, true)

    imgui.TextColored(1, 0.9, 0.3, 1, "Properties")
    imgui.Separator()

    if imgui.Button(cfg.prop_tab=="bone"   and "[Bone]"   or " Bone   ", 62, 20) then cfg.prop_tab="bone"   end
    imgui.SameLine()
    if imgui.Button(cfg.prop_tab=="mesh"   and "[Mesh]"   or " Mesh   ", 62, 20) then cfg.prop_tab="mesh"   end
    imgui.SameLine()
    if imgui.Button(cfg.prop_tab=="render" and "[Render]" or " Render ", 72, 20) then cfg.prop_tab="render" end
    imgui.Separator()
    imgui.Spacing()

    if cfg.prop_tab == "bone" then
        ui_prop_bone(PW)
    elseif cfg.prop_tab == "mesh" then
        ui_prop_mesh(PW)
    else
        ui_prop_render(PW)
    end

    imgui.EndChild()

    imgui.End()
end

cfg.rt = model.create_rt(RT_W, RT_H)
if not cfg.rt then client.log("[viewer] render target creation failed", 3) end

scan()
if #cfg.fbx_list > 0 then load_model() end

function on_unload()
    if cfg.mdl then model.free(cfg.mdl);   cfg.mdl = nil end
    if cfg.rt  then model.free_rt(cfg.rt); cfg.rt  = nil end
    for _, tex in pairs(cfg.tex_overrides) do
        if tex then client.release_texture(tex) end
    end
    normal_cache      = {}
    cfg.bone_edit     = {}
    cfg.tex_overrides = {}
end
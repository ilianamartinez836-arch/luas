local ffi = require("ffi")
ffi.cdef[[
typedef struct { float x,y,z, nx,ny,nz; unsigned int col; float u,v; } EchVertex;
typedef unsigned short WORD;
]]

local mdl_normal_cache = {}
local function rotate_y(x, y, z, a)
    local c = math.cos(a)
    local s = math.sin(a)
    return x * c - z * s, y, x * s + z * c
end
local LIGHT = { x=0.3, y=0.8, z=-0.5 }
do
    local ll = math.sqrt(LIGHT.x^2 + LIGHT.y^2 + LIGHT.z^2)
    LIGHT.x, LIGHT.y, LIGHT.z = LIGHT.x/ll, LIGHT.y/ll, LIGHT.z/ll
end
local debug_shading = true
local debug_once = {}
local function cache_normals(mdl)
    mdl_normal_cache = {}
    if not mdl then return end

    for mi = 1, model.mesh_count(mdl) do
        local ptr, count = model.lock_verts(mdl, mi)
        if ptr then
            local vp = ffi.cast("EchVertex*", ptr)
            local e  = { count = count, nx = {}, ny = {}, nz = {}, orig = {} }

            local zero_n = 0
            local min_len, max_len = 1e9, 0.0

            for i = 0, count - 1 do
                local nx, ny, nz = vp[i].nx, vp[i].ny, vp[i].nz
                e.nx[i], e.ny[i], e.nz[i] = nx, ny, nz
                e.orig[i] = vp[i].col

                local len = math.sqrt(nx * nx + ny * ny + nz * nz)
                if len < 1e-6 then
                    zero_n = zero_n + 1
                end
                if len < min_len then min_len = len end
                if len > max_len then max_len = len end
            end

            mdl_normal_cache[mi] = e
            model.unlock_verts(mdl, mi)

            if debug_shading and not debug_once[mi] then
                debug_once[mi] = true
                client.log(string.format(
                    "[shade] mesh %d normals: count=%d zero=%d len[min=%.6f max=%.6f]",
                    mi, count, zero_n, min_len, max_len
                ), 1)
            end
        else
            if debug_shading then
                client.log(string.format("[shade] mesh %d: failed to lock verts", mi), 3)
            end
        end
    end
end

local function apply_shaded_colors(mdl, mi, ir, ig, ib, ia, lx, ly, lz)
    local e = mdl_normal_cache[mi]
    if not e then return false end

    local ptr = model.lock_verts(mdl, mi)
    if not ptr then return false end

    local vp = ffi.cast("EchVertex*", ptr)

    for i = 0, e.count - 1 do
        local nx, ny, nz = e.nx[i], e.ny[i], e.nz[i]
        local nl = math.sqrt(nx * nx + ny * ny + nz * nz)

        if nl > 1e-4 then
            nx, ny, nz = nx / nl, ny / nl, nz / nl
        else
            nx, ny, nz = 0, 1, 0
        end

        local ndl = nx * lx + ny * ly + nz * lz
        if ndl < 0.0 then ndl = 0.0 end

        if debug_shading and mi == 1 and i == 0 then
            client.log(string.format(
                "[shade] N=(%.3f,%.3f,%.3f) L=(%.3f,%.3f,%.3f) dot=%.3f",
                nx, ny, nz, lx, ly, lz, ndl
            ), 1)
        end

        local s = 0.45 + 0.55 * ndl

        local r = math.min(255, math.floor(ir * s))
        local g = math.min(255, math.floor(ig * s))
        local b = math.min(255, math.floor(ib * s))

        vp[i].col = (ia * 0x1000000) + (r * 0x10000) + (g * 0x100) + b
    end

    model.unlock_verts(mdl, mi)
    return true
end

local function restore_colors(mdl, mi)
    local e = mdl_normal_cache[mi]; if not e then return end
    local ptr = model.lock_verts(mdl, mi); if not ptr then return end
    local vp = ffi.cast("EchVertex*", ptr)
    for i = 0, e.count-1 do vp[i].col = e.orig[i] end
    model.unlock_verts(mdl, mi)
end
local function render_shaded_opaque(mdl, world, yaw_rad, r, g, b, a)
    if not mdl or not mdl_normal_cache[1] then return end

    local mc = model.mesh_count(mdl)

    model.rs(model.RS_LIGHTING, 0)
    model.rs(model.RS_ALPHABLENDENABLE, 0)
    model.rs(model.RS_ZENABLE, 1)
    model.rs(model.RS_ZWRITEENABLE, 1)
    model.rs(model.RS_ZFUNC, model.CMP_LESSEQUAL)
    model.rs(model.RS_CULLMODE, model.CULL_CCW)
    model.texture(0, nil)
    model.tss(0, model.TSS_COLOROP,   model.TOP_SELECTARG2)
    model.tss(0, model.TSS_COLORARG2, model.TA_DIFFUSE)
    model.tss(0, model.TSS_ALPHAOP,   model.TOP_SELECTARG2)
    model.tss(0, model.TSS_ALPHAARG2, model.TA_DIFFUSE)
    model.fvf(model.VERTEX_FVF)
    model.set_world(world)

    local lx, ly, lz = rotate_y(LIGHT.x, LIGHT.y, LIGHT.z, -yaw_rad)
    local ir = math.floor(r * 255)
    local ig = math.floor(g * 255)
    local ib = math.floor(b * 255)
    local ia = math.floor(a * 255)

    for mi = 1, mc do
        if apply_shaded_colors(mdl, mi, ir, ig, ib, ia, lx, ly, lz) then
            model.draw_mesh(mdl, mi)
            restore_colors(mdl, mi)
        end
    end
end
local function render_shaded_chams(mdl, world, yaw_rad, vr, vg, vb, va, or_, og, ob, oa)
    if not mdl or not mdl_normal_cache[1] then return end

    local mc = model.mesh_count(mdl)

    model.rs(model.RS_LIGHTING,         0)
    model.rs(model.RS_ALPHABLENDENABLE, 1)
    model.rs(model.RS_SRCBLEND,         model.BLEND_SRCALPHA)
    model.rs(model.RS_DESTBLEND,        model.BLEND_INVSRCALPHA)
    model.rs(model.RS_CULLMODE,         model.CULL_CCW)
    model.texture(0, nil)
    model.tss(0, model.TSS_COLOROP,   model.TOP_SELECTARG2)
    model.tss(0, model.TSS_COLORARG2, model.TA_DIFFUSE)
    model.tss(0, model.TSS_ALPHAOP,   model.TOP_SELECTARG2)
    model.tss(0, model.TSS_ALPHAARG2, model.TA_DIFFUSE)
    model.fvf(model.VERTEX_FVF)
    model.set_world(world)

    local lx, ly, lz = rotate_y(LIGHT.x, LIGHT.y, LIGHT.z, -yaw_rad)

    local function pass(r, g, b, a, zfn, zw)
        model.rs(model.RS_ZFUNC, zfn)
        model.rs(model.RS_ZWRITEENABLE, zw)

        local ir = math.floor(r * 255)
        local ig = math.floor(g * 255)
        local ib = math.floor(b * 255)
        local ia = math.floor(a * 255)

        for mi = 1, mc do
            if apply_shaded_colors(mdl, mi, ir, ig, ib, ia, lx, ly, lz) then
                model.draw_mesh(mdl, mi)
                restore_colors(mdl, mi)
            end
        end
    end

pass(vr, vg, vb, va, model.CMP_LESSEQUAL, 1)
end

local RT_W, RT_H = 640, 360

local cfg = {
    fbx_folder = "Models",
    tex_folder = "Models\\textures",
    fbx_list   = {},
    sel_idx    = 1,
    mdl        = nil,
    rt         = nil,

    occ_folder = "Models\\Occluders",
    occ_list   = {},
    occ_idx    = 1,
    occ_mdl    = nil,
    show_occ_debug = true,

    occ_pos    = { 0.0, 0.0, 0.0 },
    occ_yaw    = 0.0,
    occ_scale  = 1.0,

    cam_yaw   = 0.3,  cam_pitch = 0.2,
    cam_dist  = 15.0, cam_ty    = 5.0,
    cam_tx    = 0.0,  cam_tz    = 0.0, 
    mdl_scale = 8.0,  mdl_yaw   = 0.0,
    fake_aa   = false, fake_yaw = 180.0,

    vis    = {1.0, 0.2, 0.2, 1.0},
    occ    = {0.0, 0.3, 1.0, 0.4},
    sh_vis = {0.75, 0.85, 1.0, 1.0},
    sh_occ = {0.18, 0.28, 0.45, 0.45},
    ol   = {1.0, 1.0, 0.0, 1.0}, ol_t = 1.05,
    gl   = {0.0, 0.8, 1.0, 1.0}, gl_t = 1.10,
    bone_col = {0.0, 1.0, 0.0, 1.0},
    tex_alpha = 1.0,

    tex_overrides   = {},
    custom_tex_path = "",

    esp_col  = {0.0, 1.0, 0.4, 1.0},

    last_view  = nil,
    last_proj  = nil,
    last_world = nil,
}

local ui = {
    chams       = true,
    outline     = false,
    shaded      = false,
    glow        = false,
    wire        = false,
    skeleton    = false,
    bone_joints = false,
    bbox        = false,
    textured    = false,
    fake_aa     = false,
    esp_box     = false,  
}

local bone_editor = {
    open     = false,
    selected = 1,
}

local cfg_bones = {
    enabled = false,
    sel_idx  = 1,
    edit     = {}, 
}
local function scan_occ()
    cfg.occ_list = model.scan_fbx(cfg.occ_folder)
end
local occ_base_cache = {}  

local function cache_occ_base(mdl)
    occ_base_cache = {}
    if not mdl then return end

    for mi = 1, model.mesh_count(mdl) do
        local ptr, count = model.lock_verts(mdl, mi)
        if ptr then
            local vp = ffi.cast("EchVertex*", ptr)
            local e = {
                count = count,
                x = {}, y = {}, z = {},
                nx = {}, ny = {}, nz = {},
            }

            for i = 0, count - 1 do
                e.x[i]  = vp[i].x
                e.y[i]  = vp[i].y
                e.z[i]  = vp[i].z
                e.nx[i] = vp[i].nx
                e.ny[i] = vp[i].ny
                e.nz[i] = vp[i].nz
            end

            occ_base_cache[mi] = e
            model.unlock_verts(mdl, mi)
        end
    end
end

local function apply_occ_transform(mdl)
    if not mdl or not occ_base_cache[1] then return end

    local yaw = math.rad(cfg.occ_yaw or 0.0)
    local sc   = cfg.occ_scale or 1.0
    local ox, oy, oz = cfg.occ_pos[1], cfg.occ_pos[2], cfg.occ_pos[3]

    for mi = 1, model.mesh_count(mdl) do
        local base = occ_base_cache[mi]
        if base then
            local ptr = model.lock_verts(mdl, mi)
            if ptr then
                local vp = ffi.cast("EchVertex*", ptr)

                for i = 0, base.count - 1 do
                    local x = base.x[i] * sc
                    local y = base.y[i] * sc
                    local z = base.z[i] * sc

                    x, y, z = rotate_y(x, y, z, yaw)

                    vp[i].x = x + ox
                    vp[i].y = y + oy
                    vp[i].z = z + oz

                    local nx, ny, nz = rotate_y(base.nx[i], base.ny[i], base.nz[i], yaw)
                    local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
                    if nl > 1e-6 then
                        nx, ny, nz = nx / nl, ny / nl, nz / nl
                    end
                    vp[i].nx = nx
                    vp[i].ny = ny
                    vp[i].nz = nz
                end

                model.unlock_verts(mdl, mi)
            end
        end
    end
end
local function load_occ()
    if cfg.occ_mdl then
        model.free(cfg.occ_mdl)
        cfg.occ_mdl = nil
    end

    if cfg.occ_idx < 1 or cfg.occ_idx > #cfg.occ_list then
        return
    end

    local path = cfg.occ_list[cfg.occ_idx]
    local m, err = model.load(path, cfg.tex_folder)
    if m then
        cfg.occ_mdl = m
        client.log(string.format("[occ] loaded %s | %dm %db",
            path, model.mesh_count(m), model.bone_count(m)), 1)
    else
        client.log("[occ] " .. (err or "?"), 3)
    end
end
local function toggle_button(label, key)
    local state = ui[key]
    if imgui.Button(string.format("%s: %s", label, state and "ON" or "OFF"), 180, 22) then
        ui[key] = not state
    end
    return ui[key]
end
local function ensure_bone_edit(mdl)
    local bc = model.bone_count(mdl)
    for i = 1, bc do
        if not cfg_bones.edit[i] then
            cfg_bones.edit[i] = { 0, 0, 0, 0, 0, 0 }
        end
    end
end

local function clamp_bone_idx(mdl)
    local bc = model.bone_count(mdl)
    if bc <= 0 then
        cfg_bones.sel_idx = 1
        return 0
    end
    cfg_bones.sel_idx = math.max(1, math.min(cfg_bones.sel_idx, bc))
    return bc
end
local function scan()
    cfg.fbx_list = model.scan_fbx(cfg.fbx_folder)
end

local function load_model()
    if cfg.mdl then model.free(cfg.mdl); cfg.mdl = nil end
    cfg.tex_overrides = {}
    if cfg.sel_idx < 1 or cfg.sel_idx > #cfg.fbx_list then return end
    local path = cfg.fbx_list[cfg.sel_idx]
    local m, err = model.load(path, cfg.tex_folder)
    if m then
        cfg.mdl = m
        cache_normals(m)
        client.log(string.format("[chams] loaded %s | %dm %db",
            path, model.mesh_count(m), model.bone_count(m)), 1)
        
        for i = 1, model.mesh_count(m) do
            local mat_name = model.mesh_name(m, i)
            if mat_name then
                local tex_base_name = mat_name:gsub("^mt_", "tx_") .. "_Base.tga"
                local full_tex_path = cfg.tex_folder .. "\\" .. tex_base_name
                
                local tex = client.load_texture(full_tex_path)
                if tex then
                    cfg.tex_overrides[i] = tex
                    model.set_mesh_tex(m, i, tex)
                end
            end
        end
    else
        client.log("[chams] " .. (err or "?"), 3)
    end
end

cfg.rt = model.create_rt(RT_W, RT_H)
if not cfg.rt then
    client.log("[chams] failed to create render target", 3)
end

scan()
scan_occ()

if #cfg.fbx_list > 0 then load_model() end
if #cfg.occ_list > 0 then load_occ() end

function on_render_3d()
    if not cfg.mdl or not cfg.rt then return end

    model.apply_skinning(cfg.mdl)

    local dt = client.get_frametime()

    if cfg.fake_aa then
        cfg.fake_yaw = (cfg.fake_yaw + dt * 360.0) % 360.0
        cfg.mdl_yaw  = cfg.fake_yaw - 180.0
    end

    model.begin_rt(cfg.rt)

    local cp, cy  = cfg.cam_pitch, cfg.cam_yaw
    local cd, cty = cfg.cam_dist,  cfg.cam_ty
    local ctx = cfg.cam_tx or 0.0
    local ctz = cfg.cam_tz or 0.0

    local ey = cty + cd * math.sin(cp)
    local ex = ctx + cd * math.cos(cp) * math.sin(cy)
    local ez = ctz - cd * math.cos(cp) * math.cos(cy)

    local view = model.mat_lookat_lh(ex, ey, ez, ctx, cty, ctz)
    local proj = model.mat_persp_lh(0.8, RT_W / RT_H, 0.1, 1000.0)
    model.set_view(view)
    model.set_proj(proj)

local yr    = cfg.mdl_yaw * math.pi / 180.0
    local world = model.mat_mul(model.mat_scale(cfg.mdl_scale), model.mat_roty(yr))
    cfg.last_world = world   
    cfg.last_view  = view
    cfg.last_proj  = proj

local v, o, ol, gl = cfg.vis, cfg.occ, cfg.ol, cfg.gl
if cfg.occ_mdl and cfg.show_occ_debug then
    model.rs(model.RS_LIGHTING, 0)
    model.rs(model.RS_ALPHABLENDENABLE, 0)
    model.rs(model.RS_ZENABLE, 1)
    model.rs(model.RS_ZWRITEENABLE, 1)
    model.rs(model.RS_ZFUNC, model.CMP_LESSEQUAL)
    model.rs(model.RS_CULLMODE, model.CULL_CCW)
    model.texture(0, nil)
    model.tss(0, model.TSS_COLOROP, model.TOP_SELECTARG2)
    model.tss(0, model.TSS_COLORARG2, model.TA_DIFFUSE)
    model.tss(0, model.TSS_ALPHAOP, model.TOP_SELECTARG2)
    model.tss(0, model.TSS_ALPHAARG2, model.TA_DIFFUSE)
    model.fvf(model.VERTEX_FVF)

    local xx_world = model.mat_mul(model.mat_scale(1.0), model.mat_roty(0.0))
    model.set_world(xx_world)

    model.render_chams(cfg.occ_mdl, xx_world, 0.7, 0.7, 0.7, 1.0, 0.7, 0.7, 0.7, 1.0)
end

if ui.outline then
    model.render_outline(cfg.mdl, world, ol[1],ol[2],ol[3],ol[4], cfg.ol_t)
end
if ui.glow then
    model.render_glow(cfg.mdl, world, gl[1],gl[2],gl[3],gl[4], cfg.gl_t)
end
if ui.chams then
    model.render_chams(cfg.mdl, world, v[1],v[2],v[3],v[4], o[1],o[2],o[3],o[4])
end
if ui.shaded then
    local sv = cfg.sh_vis
    render_shaded_opaque(cfg.mdl, world, yr, sv[1], sv[2], sv[3], sv[4])
end
    if ui.textured then
        model.rs(model.RS_ZFUNC, 8)
        model.render_textured(cfg.mdl, world, cfg.tex_alpha)
        model.rs(model.RS_ZFUNC, model.CMP_LESSEQUAL)
    end

    if ui.wire then
        model.rs(model.RS_ZFUNC, 8)
        model.render_wireframe(cfg.mdl, world, 0, 1, 0, 1)
        model.rs(model.RS_ZFUNC, model.CMP_LESSEQUAL)
    end

    if ui.skeleton then
        local bc = cfg.bone_col or {0.0, 1.0, 0.0, 1.0}
        model.render_skeleton(cfg.mdl, world, bc[1], bc[2], bc[3], bc[4])
        if ui.bone_joints then
            model.render_bone_joints(cfg.mdl, world, 1, 1, 0, 1)
        end
    end
    if ui.bbox     then model.render_bbox    (cfg.mdl, world, 0, 1, 1, 1) end

    model.end_rt(cfg.rt)
end

menu.add_tab("chams_viewer", "Chams Viewer", "I", function()
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    if cfg.rt then
        local avail_w, _ = imgui.GetContentRegionAvail()
        local vw = math.min(avail_w - 8, RT_W)
        local vh = vw * (RT_H / RT_W)

        local px, py = imgui.GetCursorScreenPos()

        imgui.InvisibleButton("##vp3d", vw, vh)

        local tex = model.rt_tex(cfg.rt)
        if tex then
            model.imgui_image(tex, px, py, px + vw, py + vh)
        end

        imgui.win_draw_rect(px, py, px + vw, py + vh, 0.3, 0.3, 0.4, 0.8, 1)

    if ui.esp_box and cfg.mdl and cfg.last_world and cfg.last_view and cfg.last_proj then
            local x1, y1, x2, y2 = model.bbox_screen(
                cfg.mdl, cfg.last_world, cfg.last_view, cfg.last_proj, RT_W, RT_H)
            if x1 then
                x1 = math.max(0, math.min(RT_W, x1))
                y1 = math.max(0, math.min(RT_H, y1))
                x2 = math.max(0, math.min(RT_W, x2))
                y2 = math.max(0, math.min(RT_H, y2))
                if x2 - x1 < 2 or y2 - y1 < 2 then goto skip_esp end
                local sx = vw / RT_W
                local sy = vh / RT_H
                local ec = cfg.esp_col
                imgui.win_draw_rect(px+x1*sx, py+y1*sy, px+x2*sx, py+y2*sy,
                    ec[1], ec[2], ec[3], ec[4], 1.5, 2)
                local cw = (x2-x1)*sx*0.18
                local ch = (y2-y1)*sy*0.18
                local lx1,ly1,lx2,ly2 = px+x1*sx, py+y1*sy, px+x2*sx, py+y2*sy
                imgui.win_draw_line(lx1,ly1, lx1+cw,ly1, ec[1],ec[2],ec[3],ec[4],2)
                imgui.win_draw_line(lx1,ly1, lx1,ly1+ch, ec[1],ec[2],ec[3],ec[4],2)
                imgui.win_draw_line(lx2,ly1, lx2-cw,ly1, ec[1],ec[2],ec[3],ec[4],2)
                imgui.win_draw_line(lx2,ly1, lx2,ly1+ch, ec[1],ec[2],ec[3],ec[4],2)
                imgui.win_draw_line(lx1,ly2, lx1+cw,ly2, ec[1],ec[2],ec[3],ec[4],2)
                imgui.win_draw_line(lx1,ly2, lx1,ly2-ch, ec[1],ec[2],ec[3],ec[4],2)
                imgui.win_draw_line(lx2,ly2, lx2-cw,ly2, ec[1],ec[2],ec[3],ec[4],2)
                imgui.win_draw_line(lx2,ly2, lx2,ly2-ch, ec[1],ec[2],ec[3],ec[4],2)
                     ::skip_esp::
            end
        end
    if imgui.IsItemHovered() then
            if imgui.IsMouseDragging(0) then
                local dx, dy = imgui.GetMouseDragDelta(0, 0)
                imgui.ResetMouseDragDelta(0)
                cfg.cam_yaw  = cfg.cam_yaw + dx * 0.005
                cfg.cam_pitch = math.max(-1.5, math.min(1.5,
                    cfg.cam_pitch - dy * 0.005))
            end

            local drag_btn = imgui.IsMouseDragging(1) and 1 or (imgui.IsMouseDragging(2) and 2 or nil)
            if drag_btn then
                local dx, dy = imgui.GetMouseDragDelta(drag_btn, 0)
                imgui.ResetMouseDragDelta(drag_btn)
                
                local factor = cfg.cam_dist * 0.0015 
                cfg.cam_ty = cfg.cam_ty + dy * factor
                cfg.cam_tx = (cfg.cam_tx or 0.0) - dx * math.cos(cfg.cam_yaw) * factor
                cfg.cam_tz = (cfg.cam_tz or 0.0) - dx * math.sin(cfg.cam_yaw) * factor
            end

            local current_scroll = (imgui.GetScrollY or imgui.get_scroll_y or function() end)()
            local arrow_active = false
            
            local arrow_speed = 25.0 * client.get_frametime()
            local is_key_down = imgui.IsKeyDown or imgui.is_key_down

            if is_key_down and is_key_down(38) then -- Arrow Up (Zoom In)
                cfg.cam_dist = math.max(1.0, cfg.cam_dist - arrow_speed)
                arrow_active = true
            end
            if is_key_down and is_key_down(40) then -- Arrow Down (Zoom Out)
                cfg.cam_dist = math.max(1.0, cfg.cam_dist + arrow_speed)
                arrow_active = true
            end

            if arrow_active and current_scroll then
                local set_scroll = imgui.SetScrollY or imgui.set_scroll_y
                if set_scroll then set_scroll(current_scroll) end
            end

            local wheel = model.imgui_wheel()
            if wheel ~= 0 then
                cfg.cam_dist = math.max(1.0, cfg.cam_dist - wheel * 0.5)
                model.consume_wheel()  
            end
        end

        if cfg.mdl then
            imgui.win_draw_text(px + 6, py + 4, 0.5, 1, 0.5, 0.8,
                string.format("%dm %db  dist=%.1f",
                    model.mesh_count(cfg.mdl),
                    model.bone_count(cfg.mdl),
                    cfg.cam_dist), 11)
        end

        imgui.Spacing()
    end

    imgui.Separator()
    imgui.Spacing()

    imgui.Text("FBX Folder")
    local nf, fc = imgui.InputText("##fbxdir", cfg.fbx_folder)
    if fc and nf then cfg.fbx_folder = nf end
    imgui.SameLine()
    if imgui.Button("Scan", 70, 22) then scan() end

    imgui.Text("FBX File")
    local preview = (#cfg.fbx_list > 0)
        and (cfg.fbx_list[cfg.sel_idx]:match("[/\\]([^/\\]+)$") or cfg.fbx_list[cfg.sel_idx])
        or  "No files found"

    if imgui.BeginCombo("##fbxpick", preview) then
        for i, path in ipairs(cfg.fbx_list) do
            local name = path:match("[/\\]([^/\\]+)$") or path
            if imgui.Selectable(name .. "##fi" .. i, i == cfg.sel_idx) then
                cfg.sel_idx = i
            end
        end
        imgui.EndCombo()
    end

    imgui.Text("Texture Folder")
    local nt, tc = imgui.InputText("##texdir", cfg.tex_folder)
    if tc and nt then cfg.tex_folder = nt end

    if imgui.Button("Load Model", 110, 26) then load_model() end

    imgui.Spacing()
    imgui.Separator()
    imgui.Text("Camera")

    local d,  dc  = imgui.SliderFloat("Distance##cv", cfg.cam_dist,  1.0, 60.0)
    if dc  then cfg.cam_dist  = d  end
    local ty, tc2 = imgui.SliderFloat("Target Y##cv", cfg.cam_ty,    0.0, 20.0)
    if tc2 then cfg.cam_ty    = ty end

    imgui.Separator()
    imgui.Text("Transform")
    local sc, scc = imgui.SliderFloat("Scale##cv",  cfg.mdl_scale, 0.01, 8.0)
    if scc then cfg.mdl_scale = sc end
    local yw, ywc = imgui.SliderFloat("Yaw##cv",    cfg.mdl_yaw,  -180,  180)
    if ywc then cfg.mdl_yaw   = yw end

    cfg.fake_aa = toggle_button("Fake Anti-Aim", "fake_aa")

    imgui.Separator()
    imgui.Text("Render Modes")
    cfg.chams = toggle_button("Flat Chams", "chams")
    if cfg.chams then
        local vr, vg, vb, va, vc = imgui.ColorEdit4(
            "Visible##cv",
            cfg.vis[1], cfg.vis[2], cfg.vis[3], cfg.vis[4]
        )
        if vc then cfg.vis = { vr, vg, vb, va } end

        local or_, og, ob, oa, oc = imgui.ColorEdit4(
            "Occluded##cv",
            cfg.occ[1], cfg.occ[2], cfg.occ[3], cfg.occ[4]
        )
        if oc then cfg.occ = { or_, og, ob, oa } end
    end

    cfg.shaded = toggle_button("Shaded Chams", "shaded")
    if cfg.shaded then
        local vr,vg,vb,va,vc = imgui.ColorEdit4("Vis##shcv",
            cfg.sh_vis[1],cfg.sh_vis[2],cfg.sh_vis[3],cfg.sh_vis[4])
        if vc then cfg.sh_vis = {vr,vg,vb,va} end
        local or_,og,ob,oa,oc = imgui.ColorEdit4("Occ##shcv",
            cfg.sh_occ[1],cfg.sh_occ[2],cfg.sh_occ[3],cfg.sh_occ[4])
        if oc then cfg.sh_occ = {or_,og,ob,oa} end
    end

    cfg.outline = toggle_button("Outline", "outline")
    if cfg.outline then
        local r, g, b, a, cc = imgui.ColorEdit4(
            "Color##olcv",
            cfg.ol[1], cfg.ol[2], cfg.ol[3], cfg.ol[4]
        )
        if cc then cfg.ol = { r, g, b, a } end

        local t, tc3 = imgui.SliderFloat("Thickness##olcv", cfg.ol_t, 1.01, 1.15)
        if tc3 then cfg.ol_t = t end
    end

    cfg.glow = toggle_button("Glow", "glow")
    if cfg.glow then
        local r, g, b, a, cc = imgui.ColorEdit4(
            "Color##glcv",
            cfg.gl[1], cfg.gl[2], cfg.gl[3], cfg.gl[4]
        )
        if cc then cfg.gl = { r, g, b, a } end

        local t, tc4 = imgui.SliderFloat("Thickness##glcv", cfg.gl_t, 1.01, 1.20)
        if tc4 then cfg.gl_t = t end
    end

    cfg.textured = toggle_button("Textured", "textured")
    if cfg.textured then
        local a, ac = imgui.SliderFloat("Alpha##txcv", cfg.tex_alpha, 0.0, 1.0)
        if ac then cfg.tex_alpha = a end
    end

    cfg.wire     = toggle_button("Wireframe", "wire")
    cfg.skeleton = toggle_button("Skeleton", "skeleton")
    if cfg.skeleton then
        local br, bg, bb, ba, bc = imgui.ColorEdit4(
            "Bone Color##bonecv",
            cfg.bone_col[1], cfg.bone_col[2], cfg.bone_col[3], cfg.bone_col[4]
        )
        if bc then cfg.bone_col = { br, bg, bb, ba } end
    end
 cfg.bbox     = toggle_button("BBox", "bbox")

    cfg.esp_box  = toggle_button("ESP Box (2D)", "esp_box")
    if cfg.esp_box then
        local r,g,b,a,cc = imgui.ColorEdit4("Color##espcv",
            cfg.esp_col[1],cfg.esp_col[2],cfg.esp_col[3],cfg.esp_col[4])
        if cc then cfg.esp_col = {r,g,b,a} end
    end

    if cfg.mdl and model.mesh_count(cfg.mdl) > 0 then
        imgui.Spacing()
        imgui.Separator()
        if imgui.CollapsingHeader("Texture Swap##cv") then
            imgui.Text("Path:")
            local np, pc = imgui.InputText("##ctex", cfg.custom_tex_path)
            if pc and np then cfg.custom_tex_path = np end
            for i = 1, model.mesh_count(cfg.mdl) do
                local name = model.mesh_name(cfg.mdl, i) or ("mesh "..i)
                imgui.Text(string.format("[%d] %s", i, name))
                imgui.SameLine()
                if imgui.Button("Swap##ms"..i) and cfg.custom_tex_path ~= "" then
                    local tex = client.load_texture(cfg.custom_tex_path)
                    if tex then
                        if cfg.tex_overrides[i] then
                            client.release_texture(cfg.tex_overrides[i])
                        end
                        cfg.tex_overrides[i] = tex
                        model.set_mesh_tex(cfg.mdl, i, tex)
                    end
                end
                if cfg.tex_overrides[i] then
                    imgui.SameLine()
                    if imgui.Button("Reset##ms"..i) then
                        client.release_texture(cfg.tex_overrides[i])
                        cfg.tex_overrides[i] = nil
                        model.set_mesh_tex(cfg.mdl, i, nil)
                    end
                end
            end
        end
    end

if cfg.mdl and model.bone_count(cfg.mdl) > 0 then
    imgui.Spacing()
    imgui.Separator()

    local bc = model.bone_count(cfg.mdl)
    ensure_bone_edit(cfg.mdl)

    local be_label = string.format("%s  Bone Editor  [%d]",
        bone_editor.open and "▼" or "▶", bc)
    if imgui.Button(be_label, 220, 24) then
        bone_editor.open = not bone_editor.open
    end

    if bone_editor.open then
        bone_editor.selected = math.max(1, math.min(bone_editor.selected, bc))

        imgui.Spacing()
        local avail_w, _ = imgui.GetContentRegionAvail()
        local list_w = math.floor(math.min(170, avail_w * 0.36))
        local ctrl_w = avail_w - list_w - 12

        imgui.BeginChild("##be_list", list_w, 230, true)
        for i = 1, bc do
            local _, _, _, parent = model.bone_pos(cfg.mdl, i)
            local nm = model.bone_name(cfg.mdl, i) or ("Bone "..i)
            local pfx = (parent >= 0) and "    └ " or "• "
            local short = nm:len() > 14 and nm:sub(1,13).."…" or nm
            local lbl = string.format("%s%s##be%d", pfx, short, i)
            if imgui.Selectable(lbl, bone_editor.selected == i) then
                bone_editor.selected = i
            end
        end
        imgui.EndChild()

        imgui.SameLine()

        imgui.BeginChild("##be_ctrl", ctrl_w, 230, true)
        local ed = cfg_bones.edit[bone_editor.selected]
        local bx, by, bz, par = model.bone_pos(cfg.mdl, bone_editor.selected)
        local nm = model.bone_name(cfg.mdl, bone_editor.selected) or ("Bone "..bone_editor.selected)

        imgui.TextColored(0, 0.8, 1, 1, nm)
        imgui.TextDisabled(string.format("#%d  parent: %d", bone_editor.selected, par))
        imgui.TextDisabled(string.format("rest  %.2f  %.2f  %.2f", bx, by, bz))
        imgui.Separator()

        if ed then
            imgui.Text("Position")
            local px2, pc  = imgui.SliderFloat("X##bpx", ed[1], -5, 5)
            if pc  then ed[1]=px2 end
            local py2, pc2 = imgui.SliderFloat("Y##bpy", ed[2], -5, 5)
            if pc2 then ed[2]=py2 end
            local pz2, pc3 = imgui.SliderFloat("Z##bpz", ed[3], -5, 5)
            if pc3 then ed[3]=pz2 end

            imgui.Spacing()
            imgui.Text("Rotation")
            local rx, rc  = imgui.SliderFloat("X##brx", ed[4], -180, 180)
            if rc  then ed[4]=rx end
            local ry, rc2 = imgui.SliderFloat("Y##bry", ed[5], -180, 180)
            if rc2 then ed[5]=ry end
            local rz, rc3 = imgui.SliderFloat("Z##brz", ed[6], -180, 180)
            if rc3 then ed[6]=rz end

            model.bone_set_pose(cfg.mdl, bone_editor.selected,
                ed[1],ed[2],ed[3], ed[4],ed[5],ed[6])
        end
        imgui.EndChild()

        imgui.Spacing()
        if imgui.Button("Reset Bone##ber", 120, 22) then
            local i = bone_editor.selected
            cfg_bones.edit[i] = {0,0,0,0,0,0}
            model.bone_set_pose(cfg.mdl, i, 0,0,0,0,0,0)
        end
        imgui.SameLine()
        if imgui.Button("Reset All##bera", 100, 22) then
            for i = 1, bc do
                cfg_bones.edit[i] = {0,0,0,0,0,0}
                model.bone_set_pose(cfg.mdl, i, 0,0,0,0,0,0)
            end
        end
        imgui.SameLine()
        local show, sc = imgui.Checkbox("Joints##bej", ui.bone_joints)
        if sc then ui.bone_joints = show end

        imgui.Spacing()
        if cfg.last_world and cfg.last_view and cfg.last_proj then
            local wx,wy,wz = model.bone_world_pos(
                cfg.mdl, cfg.last_world, bone_editor.selected)
            if wx then
                local sx, sy = model.project(
                    cfg.last_view, cfg.last_proj, RT_W, RT_H, wx, wy, wz)
                if sx then
                    imgui.TextDisabled(string.format(
                        "screen  %.0f, %.0f", sx, sy))
                end
            end
        end
    end
end

    if cfg.mdl and imgui.Button("Dump verts[1..3]##cv") then
        local ptr, count = model.lock_verts(cfg.mdl, 1)
        if ptr then
            local v = ffi.cast("EchVertex*", ptr)
            for i = 0, math.min(count-1, 2) do
                client.log(string.format("v[%d] (%.3f,%.3f,%.3f) uv=(%.3f,%.3f)",
                    i, v[i].x, v[i].y, v[i].z, v[i].u, v[i].v), 1)
            end
            model.unlock_verts(cfg.mdl, 1)
        end
    end
    imgui.Spacing()
imgui.Separator()
imgui.Text("Occluder Model")

imgui.Text("Occluder Folder")
local of, ofc = imgui.InputText("##occdir", cfg.occ_folder)
if ofc and of then cfg.occ_folder = of end
imgui.SameLine()
if imgui.Button("Scan##occ", 70, 22) then
    scan_occ()
end

imgui.Text("Occluder File")
local o_preview = (#cfg.occ_list > 0)
    and (cfg.occ_list[cfg.occ_idx]:match("[/\\]([^/\\]+)$") or cfg.occ_list[cfg.occ_idx])
    or "No occluder found"

if imgui.BeginCombo("##occpick", o_preview) then
    for i, path in ipairs(cfg.occ_list) do
        local name = path:match("[/\\]([^/\\]+)$") or path
        if imgui.Selectable(name .. "##occi" .. i, i == cfg.occ_idx) then
            cfg.occ_idx = i
        end
    end
    imgui.EndCombo()
end

if imgui.Button("Load Occluder", 110, 26) then
    load_occ()
end

imgui.SameLine()
cfg.show_occ_debug = toggle_button("Show Occ Debug", "show_occ_debug")
end)

function on_unload()
    for _, tex in pairs(cfg.tex_overrides) do
        if tex then client.release_texture(tex) end
    end
 if cfg.mdl then model.free(cfg.mdl);  cfg.mdl = nil end
if cfg.occ_mdl then model.free(cfg.occ_mdl); cfg.occ_mdl = nil end
if cfg.rt  then model.free_rt(cfg.rt); cfg.rt  = nil end
mdl_normal_cache = {}
cfg_bones.edit = {}
menu.remove_tab("chams_viewer")
end

local ffi = require("ffi")
ffi.cdef[[
    void* GetModuleHandleA(const char* lpModuleName);
    int VirtualProtect(void* lpAddress, unsigned long dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]]
local HOOK_DLL_NAME   = "Storm.cpl"
local PAGE_EXECUTE_RW = 0x40
local HOOKS = {
    { name = "Paint",     rva = 0x2C74E0, bytes = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x64 } },
    { name = "GlowColor", rva = 0x257830, bytes = { 0x55, 0x8B, 0xEC, 0x53, 0x56, 0x8B } },
}
local client_base    = nil
local hooks_disabled = false
echidna_hooks.disable("ClientMode_CreateMove")
local function get_client_base()
    if client_base then return client_base end
    local h = ffi.C.GetModuleHandleA("client.dll")
    if h == nil then return nil end
    client_base = ffi.cast("uintptr_t", h)
    return client_base
end
local function is_hook_dll_loaded()
    return ffi.C.GetModuleHandleA(HOOK_DLL_NAME) ~= nil
end
local function is_hooked(rva)
    local base = get_client_base()
    if not base then return false end
    return ffi.cast("uint8_t*", base + rva)[0] == 0x68
end
local function write_bytes(address, bytes)
    local ptr      = ffi.cast("uint8_t*", address)
    local old_prot = ffi.new("unsigned long[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", ptr), #bytes, PAGE_EXECUTE_RW, old_prot) == 0 then
        return false
    end
    for i = 0, #bytes - 1 do
        ptr[i] = bytes[i + 1]
    end
    ffi.C.VirtualProtect(ffi.cast("void*", ptr), #bytes, old_prot[0], old_prot)
    return true
end
local function disable_all_hooks()
    if not is_hook_dll_loaded() then
        client.print(string.format("[Hook] %s not loaded\n", HOOK_DLL_NAME))
        return
    end
    local base = get_client_base()
    if not base then
        client.print("[Hook] Could not get client.dll base\n")
        return
    end
    for _, hook in ipairs(HOOKS) do
        if not is_hooked(hook.rva) then
            client.print(string.format("[Hook] %s already unhooked\n", hook.name))
        elseif write_bytes(base + hook.rva, hook.bytes) then
            client.print(string.format("[Hook] %s removed\n", hook.name))
        else
            client.print(string.format("[Hook] Failed to remove %s\n", hook.name))
        end
    end
    hooks_disabled = true
end
function on_end_scene()
    if not client.is_menu_open() then return end
    imgui.SetNextWindowPos(40, 40, imgui.ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize(300, 160, imgui.ImGuiCond_FirstUseEver)
    if imgui.Begin("Hook Control", 0) then
        imgui.draw_window_blur(1.0)
        local wx, wy = imgui.GetWindowPos()
        local ww, wh = imgui.GetWindowSize()
        local dl = imgui.get_window_draw_list()
        dl:add_rect_filled(wx, wy, wx + ww, wy + wh, 0.10, 0.10, 0.10, 0.50, 8)
        for _, hook in ipairs(HOOKS) do
            local hooked = is_hooked(hook.rva)
            local r, g   = hooked and 1 or 0, hooked and 0 or 1
            imgui.TextColored(r, g, 0, 1, string.format("%-10s %s", hook.name .. ":", hooked and "HOOKED" or "ORIGINAL"))
        end
        imgui.Spacing()
        imgui.SetCursorPosX(12)
        if not hooks_disabled then
            if imgui.Button("Disable All Hooks") then
                disable_all_hooks()
            end
        else
            imgui.TextColored(0.5, 0.5, 0.5, 1, "All hooks disabled")
        end
        imgui.End()
    end
end

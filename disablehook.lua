-- List every controllable hook
for _, name in ipairs(echidna_hooks.list()) do print(name, echidna_hooks.state(name)) end

-- Replace ClientMode's CreateMove entirely with your own
echidna_hooks.remove("ClientMode_CreateMove")

-- Your hook via hooks.create (requires ffi=true)
local addr = memory.find_pattern("client.dll", "55 8B EC ...")
local myHook = hooks.create(addr, "bool(__fastcall*)(void*,void*,float,void*)",
    function(orig, ecx, edx, frametime, cmd)
        -- your logic
        return orig(ecx, edx, frametime, cmd)
    end)

-- Temporarily mute on_paint from the engine without destroying the hook
echidna_hooks.disable("EngineVGui_Paint")

-- Restore it later
echidna_hooks.enable("EngineVGui_Paint")

-- Query before touching
if echidna_hooks.state("BasePlayer_CalcPlayerView") ~= "removed" then
    echidna_hooks.disable("BasePlayer_CalcPlayerView")
end

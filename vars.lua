-- @author: 1
-- @created: 07.06 11:58
-- Echidna Script
for _, id in ipairs(vars.list()) do print(id, vars.get(id)) end
 --list all
-- Toggle hitscan FOV between 30 and 60 each time the script is loaded
local id = "hitscan.fov"
local info = vars.info(id)
if not info then
    client.log("hitscan.fov not registered", 2)
    return
end

local cur = vars.get(id)
--vars.set(id, cur == 30 and 60 or 30)
--client.log(string.format("FOV set to %s", vars.get(id)))
-- Tint red channel only, leave others unchanged
--local c = vars["hitscan.color"]
--c.r = 255
--vars["hitscan.color"] = c
local info = vars.info("hitscan.fov")
-- info.kind  = "float"   ("bool", "int", "float", "color", "key", "unknown")
-- info.read  = true
-- info.write = true
-- info.label = "FOV"
-- Read
local fov = vars["hitscan.fov"]

-- Write
--vars["hitscan.fov"] = 60
--vars["hitscan.enable"] = false
--vars.set("hitscan.fov", 45)
--vars.set("hitscan.enable", true)
--vars.set("hitscan.color", { r=255, g=80, b=80, a=200 })
local fov = vars.get("hitscan.fov")   -- returns number
local on  = vars.get("hitscan.enable") -- returns boolean
local col = vars.get("hitscan.color")  -- returns { r, g, b, a } table
-- read
local col = Chams.Survivors.col_vis   -- returns {r,g,b,a}
local on  = Glow.Specials.enabled

-- write
--Chams.Survivors.col_vis = {r=255, g=0, b=0, a=200}
--Glow.Commons.thickness  = 2.5
--ESP.Survivors.box       = false
--Chams.ViewmodelArms.mat_vis = 3

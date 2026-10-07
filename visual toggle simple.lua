-- @author: suda
-- @created: visualtoggle

-- cualquier id puede ir aca
local VAR_ID = "misc.enable_rapid_fire" 

function on_end_scene()
    if not EngineClient.IsInGame() then return end
    
    -- state 
    local is_rapidfire_active = vars.get(VAR_ID)
    if is_rapidfire_active == nil then is_rapidfire_active = false end

    -- viewport
    local vw, vh = imgui.GetDisplaySize()
    local dl     = imgui.get_foreground_draw_list()
    
    -- donde va la cajita
    local box_w, box_h = 75, 25
    local x = (vw - 1300) 
    local y = vh - 700 
    
    local r, g, b = 0.5, 0.0, 0.0
    text = ""
    
    if is_rapidfire_active then  r, g, b = 0.0, 0.6, 0.0 
            end
    
    -- background frame
    dl:add_rect_filled(x, y, x + box_w, y + box_h, 0.05, 0.05, 0.08, 0.85, 4)
    -- linea de status
    dl:add_rect_filled(x, y + box_h - 3, x + box_w, y + box_h, r, g, b, 1.0, 2)
    
    -- texto nomas
	dl:add_text(x + 8, y + 2, 1, 1, 1, 1, "la esquizo")
        
    imgui.SetCursorScreenPos(x + 20, y + 8)
    if is_freelook_active then
        imgui.TextColored(r, g, b, 1.0, text)
    else
        imgui.TextDisabled(text)
    end
end

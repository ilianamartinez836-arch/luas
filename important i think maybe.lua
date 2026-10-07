vmt:
"UnlitGeneric"
{
    "$basetexture" "ion"
}

example: ion.vmt + ion.vtf (same folder inside materials folder in left4dead2)
custom image in-game lua
local tex_id = nil

function on_paint()
    if not tex_id then
        tex_id = MatSystemSurface.CreateNewTextureID(false)
        MatSystemSurface.DrawSetTextureFile(tex_id, "ion", 1, false)
    end

    MatSystemSurface.DrawSetColor(255, 255, 255, 200)
    MatSystemSurface.DrawSetTexture(tex_id)
    MatSystemSurface.DrawTexturedRect(100, 100, 300, 250)
end

Shows up in screenshots in-game

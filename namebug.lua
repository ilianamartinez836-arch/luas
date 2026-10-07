local chat_spam = {
    advertise = "A",
    advertise2 = "L",
    advertise3 = "I",
    advertise4 = "C",
    advertise5 = "E",
    newline_count = 2
}

local end_down = false

function on_key_down(key)
    if key == 0x23 then
        end_down = true
    end
end

function on_key_up(key)
    if key == 0x23 then
        end_down = false
    end
end

function on_cl_move_pre()
    local local_player = EntityCache.GetLocal()
    if not local_player then
        return
    end

    if not end_down then
        return
    end

    local newline = string.rep("\r", chat_spam.newline_count)
    local message = newline .. chat_spam.advertise .. newline .. chat_spam.advertise2 .. newline .. chat_spam.advertise3 .. newline .. chat_spam.advertise4 .. newline .. chat_spam.advertise5

    EngineClient.ClientCmd('setinfo name "' .. message .. '"')
end

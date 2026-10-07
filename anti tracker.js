// @author: Danee
// @created: 09.07 14:26
// Echidna JavaScript Script
var NAME_LENGTH = 6;
var last_map = "";
var change_count = 0;
var target_name = null;
var is_changing = false;

function generate_random_name(length) {
    var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var name = "";
    for (var i = 0; i < length; i++) {
        var rand = Math.floor(Math.random() * chars.length);
        name += chars.charAt(rand);
    }
    return name;
}

function get_map_name() {
    if (!Echidna.EngineClient.IsInGame()) {
        return "Menu";
    }
    
    var map = Echidna.EngineClient.GetLevelNameShort();
    if (map && map !== "") {
        return map;
    }
    
    return "Unknown";
}

function on_key_down(key) {
    if (key === 0x64) {
        last_map = "";
        change_count = 0;
        target_name = null;
        is_changing = false;
    }
}

function on_paint() {
    if (!Echidna.EngineClient.IsInGame()) {
        last_map = "";
        change_count = 0;
        target_name = null;
        is_changing = false;
        return;
    }

    var local_idx = Echidna.EngineClient.GetLocalPlayer();
    if (!local_idx) return;

    var local_ent = Echidna.ClientEntityList.GetClientEntity(local_idx);
    if (!local_ent) return;

    var local_p = local_ent.as("CTerrorPlayer");
    if (!local_p) return;

    var my_name = local_p.get_name();
    if (!my_name || my_name === "" || my_name === "unknown") return;

    var current_map = get_map_name();
    if (current_map !== last_map) {
        last_map = current_map;
        change_count = 0;
        target_name = null;
        is_changing = false;
    }

    if (change_count >= 2) {
        return;
    }

    if (is_changing) {
        if (my_name === target_name) {
            change_count = change_count + 1;
            is_changing = false;
        }
        return;
    }

    target_name = generate_random_name(NAME_LENGTH);
    is_changing = true;
    
    Echidna.EngineClient.ClientCmd('setinfo name "' + target_name + '"');
}

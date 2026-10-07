var originalStyleIdx   = Echidna.menu.get_active_custom_style_idx();
var originalUseBg      = Echidna.menu.get_bool("UseBackgroundImage");
var originalBgBlend    = Echidna.menu.get_float("BgBlend");
var originalBgBlur     = Echidna.menu.get_float("BgBlur");
var originalShowName   = Echidna.menu.get_bool("ShowDisplayName");
var originalUseSteam   = Echidna.menu.get_bool("UseSteamName");
var originalCustomName = Echidna.menu.get_custom_name();
var originalBgPath     = Echidna.menu.get_background_path();
var originalUserPath   = Echidna.menu.get_user_image_path();

var RUI_ARNEB = {
    name: "Rui Arneb",

    MainWindowBg: {
        r: 0.04,
        g: 0.03,
        b: 0.07,
        a: 1
    },

    BlockBackground: {
        r: 0.07,
        g: 0.05,
        b: 0.11,
        a: 1
    },

    SidebarBg: {
        r: 0.09,
        g: 0.06,
        b: 0.14,
        a: 1
    },

    SidebarSelection: {
        r: 0.18,
        g: 0.12,
        b: 0.30,
        a: 1
    },

    SidebarText: {
        r: 0.92,
        g: 0.88,
        b: 0.82,
        a: 1
    },

    Border: {
        r: 0.14,
        g: 0.09,
        b: 0.22,
        a: 1
    },

    Link: {
        r: 0.25,
        g: 0.55,
        b: 0.90,
        a: 1
    },

    Logo: {
        r: 0.92,
        g: 0.85,
        b: 0.80,
        a: 1
    },

    FrameBg: {
        r: 0.05,
        g: 0.04,
        b: 0.08,
        a: 1
    },

    FrameActiveBg: {
        r: 0.15,
        g: 0.10,
        b: 0.25,
        a: 1
    },

    ActiveText: {
        r: 1.00,
        g: 1.00,
        b: 1.00,
        a: 1
    },

    DisabledText: {
        r: 0.50,
        g: 0.45,
        b: 0.58,
        a: 1
    },

    WindowTitle: {
        r: 0.80,
        g: 0.75,
        b: 0.85,
        a: 1
    }
};

var styleIdx = Echidna.menu.find_custom_style(RUI_ARNEB.name);

if (styleIdx === null || styleIdx === undefined) {
    styleIdx = Echidna.menu.add_custom_style(RUI_ARNEB);
} else {
    Echidna.menu.modify_custom_style(styleIdx, RUI_ARNEB);
}

if (styleIdx !== null && styleIdx !== undefined) {

    Echidna.menu.select_custom_style(styleIdx);

    Echidna.menu.set_accent(0.25, 0.55, 0.90, 1.0);

    Echidna.menu.set_background_path(
        "C:\\Echidna-L4d2\\themes\\RuiArneb\\RuiBG.jpg"
    );
    Echidna.menu.reload_background();

    Echidna.menu.set_user_image_path(
        "C:\\Echidna-L4d2\\themes\\RuiArneb\\User.jpg"
    );
    Echidna.menu.reload_user_image();

    Echidna.menu.set_bool("UseBackgroundImage", true);
    Echidna.menu.set_float("BgBlend", 0.60);
    Echidna.menu.set_float("BgBlur", 0.40);

    Echidna.menu.set_bool("ShowDisplayName", true);
    Echidna.menu.set_bool("UseSteamName", false);
    Echidna.menu.set_custom_name("Rui Arneb");

    Echidna.client.log("[Theme] Rui Arneb theme applied.", 0);

} else {

    Echidna.client.log("[Theme] Failed to create custom style.", 1);

}

function on_unload() {

    if (originalStyleIdx === 0) {

        Echidna.menu.set_theme(1);
        Echidna.menu.reset_accent();

    } else {

        Echidna.menu.select_custom_style(originalStyleIdx);

    }

    Echidna.menu.set_background_path(
        originalBgPath ? originalBgPath : ""
    );
    Echidna.menu.reload_background();

    Echidna.menu.set_user_image_path(
        originalUserPath ? originalUserPath : ""
    );
    Echidna.menu.reload_user_image();

    Echidna.menu.set_bool("UseBackgroundImage", originalUseBg);
    Echidna.menu.set_float("BgBlend", originalBgBlend);
    Echidna.menu.set_float("BgBlur", originalBgBlur);

    Echidna.menu.set_bool("ShowDisplayName", originalShowName);
    Echidna.menu.set_bool("UseSteamName", originalUseSteam);

    if (originalCustomName) {
        Echidna.menu.set_custom_name(originalCustomName);
    }

    Echidna.client.log("[Theme] Original theme restored.", 0);
}

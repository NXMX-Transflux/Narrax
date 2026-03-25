local ws = windower.get_windower_settings()

return {
    DisplayMode        = 2,

    MovementCloses     = false,
    NoPromptCloseDelay = 10,
    AnimatePrompt      = true,
    TextSpeed          = 10,

    Theme         = 'Western',
    Scale         = 1.0,
    ShowPortraits = true,

    Translation    = false,
    lang           = 'french',
    Language_name  = 'Français',
    Language_code  = 'fr',

    Position = {
        X = ws.ui_x_res / 2,
        Y = ws.ui_y_res - 258,
    },
}

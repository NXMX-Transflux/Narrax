local theme = {}

local function stroke_from(node)
    if not node then return {} end
    return { width=node.width, alpha=node.alpha,
             red=node.red,     green=node.green, blue=node.blue }
end

theme.apply = function(cfg)
    local cm  = cfg.message
    local cn  = cfg.npcname
    local cp  = cfg.portrait
    local cpr = cfg.prompt
    local ct  = cfg.timer
    local cd  = cm.dialogue
    local cs  = cm.system

    local client_lang = windower.ffxi.get_info().language

    local base = windower.addon_path .. 'themes/' .. cfg.name .. '/'
    local opts = {
        narrax_background   = base .. 'narrax.png',
        system_background   = base .. 'system.png',
        portrait_background = base .. 'portrait-bg.png',
        portrait_frame      = base .. 'portrait-frame.png',
        name_background     = base .. 'name-bg.png',
        prompt_image        = base .. 'advance-prompt.png',
    }

    local dlg_stroke = stroke_from(cd.stroke)

    local msg_fonts = { English=cm.fontenglish, Japanese=cm.fontjapanese }
    opts.message = {
        width      = cm.width,
        height     = cm.height,
        offset_x   = cm.textoffsetx,
        offset_y   = cm.textoffsety,
        max_length = cm.maxlength or 75,
        font       = msg_fonts[client_lang],
        font_size  = cm.size,
        font_color = { alpha=cd.color.alpha, red=cd.color.red,
                       green=cd.color.green, blue=cd.color.blue },
        stroke     = dlg_stroke,
    }

    opts.message.dialogue = {
        alpha    = cd.color.alpha, red   = cd.color.red,
        green    = cd.color.green, blue  = cd.color.blue,
        items    = cd.items,       keyitems = cd.keyitems,
        gear     = cd.gear,        roe      = cd.roe,
        emote    = cd.emote,
        stroke   = dlg_stroke,
    }

    if cs then
        opts.message.system = {
            alpha    = cs.color.alpha, red   = cs.color.red,
            green    = cs.color.green, blue  = cs.color.blue,
            items    = cs.items,       keyitems = cs.keyitems,
            gear     = cs.gear,        roe      = cs.roe,
            emote    = cs.emote,
            stroke   = stroke_from(cs.stroke),
        }
    else
        opts.message.system = opts.message.dialogue
    end

    local name_fonts = { English=cn.fontenglish, Japanese=cn.fontjapanese }
    opts.name = {
        width               = cn.width,
        height              = cn.height,
        offset_x            = cn.textoffsetx,
        offset_y            = cn.textoffsety,
        background_offset_x = cn.offsetx,
        background_offset_y = cn.offsety,
        font                = name_fonts[client_lang],
        font_size           = cn.size,
        font_color          = { alpha=cn.color.alpha, red=cn.color.red,
                                green=cn.color.green, blue=cn.color.blue },
        stroke              = stroke_from(cn.stroke),
    }

    if cp then
        opts.portrait = {
            width            = cp.width,
            height           = cp.height,
            offset_x         = cp.offsetx,
            offset_y         = cp.offsety,
            max_length       = cp.maxlength,
            message_offset_x = cp.messagetextoffsetx,
            message_offset_y = cp.messagetextoffsety,
        }
    end

    if cpr then
        opts.prompt = {
            width    = cpr.width,
            height   = cpr.height,
            offset_x = cpr.offsetx,
            offset_y = cpr.offsety,
        }
    end

    if ct then
        local tf = { English  = ct.fontenglish  or cm.fontenglish,
                     Japanese = ct.fontjapanese or cm.fontjapanese }
        opts.timer = {
            offset_x   = ct.textoffsetx or (cpr and cpr.offsetx),
            offset_y   = ct.textoffsety or (cpr and cpr.offsety),
            font       = tf[client_lang],
            font_size  = ct.size or cm.size,
            font_color = ct.color and {
                alpha=ct.color.alpha, red=ct.color.red,
                green=ct.color.green, blue=ct.color.blue,
            } or opts.message.font_color,
            stroke = stroke_from(ct.stroke) or opts.message.stroke,
        }
    elseif cpr then
        opts.timer = {
            offset_x   = cpr.offsetx,
            offset_y   = cpr.offsety,
            font       = opts.message.font,
            font_size  = opts.message.font_size,
            font_color = opts.message.font_color,
            stroke     = opts.message.stroke,
        }
    end

    return opts
end

return theme
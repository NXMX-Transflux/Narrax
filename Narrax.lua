-------------------------------------------------------------------------------
-- Auteur  : DiableNoir
-- Version : v0.x.x
-- Basé sur Balloon (Hando 2018, Yuki 2021, Ghosty 2022, KenshiDRK 2025)
-------------------------------------------------------------------------------
--
_addon.author   = 'DiableNoir'
_addon.name     = 'Narrax'
_addon.version  = 'v0.x.x'
_addon.commands = {'narrax', 'nx'}

do
    local _gen_dir = windower.addon_path .. 'generated'
    if not windower.file_exists(_gen_dir) then
        windower.create_dir(_gen_dir)
    end
end

require('luau')
local chars  = require('chat.chars')
chars.cldquo = string.char(0x87, 0xB2)
chars.crdquo = string.char(0x87, 0xB3)

texts  = require('libs.texts')
images = require('images')

require('libs.translator')

local lang_db      = require('locales.languages')
local cfg_defaults = require('config.defaults')
local theme_mod    = require('libs.theme')
local panel        = require('libs.ui')

local tconcat     = table.concat
local str_format  = string.format
local w_chat      = windower.add_to_chat
local w_tojis     = windower.to_shift_jis
local w_fromjis   = windower.from_shift_jis
local w_fexists   = windower.file_exists
local w_path      = windower.addon_path
local ffxi_info   = windower.ffxi.get_info
local ffxi_player = windower.ffxi.get_player
local ffxi_mob    = windower.ffxi.get_mob_by_id
local co_sleep    = coroutine.sleep
local co_status   = coroutine.status
local co_close    = coroutine.close

local MSG = {
    DIALOGUE       = 150,
    SYSTEM         = 151,
    PROMPT_LESS    = 144,
    BATTLE         = 142,
    CUTSCENE_EMOTE =  15,
    EMOTE_FREE     =   7,
}

local MSG_VALID        = S{ 150, 151, 144, 142, 15, 7 }
local MSG_HAS_PROMPT   = S{ 150, 151 }
local MSG_SHORT_TIMER  = S{ 15, 7 }
local PKT_CLOSE        = S{ 0x52, 0x0B }

local KEY_ENTER       = 28
local KEY_SCROLL_LOCK = 70

local BYTES_PROMPT     = string.char(0x7F, 0x31)
local BYTES_AUTO_CLOSE = string.char(0x7F, 0x34, 0x01)
local BYTES_DEF_COLOR  = string.char(0x1E, 0x01)
local BYTES_NEWLINE    = string.char(0x07)
local LEN_PROMPT       = #BYTES_PROMPT
local LEN_DEF_COLOR    = #BYTES_DEF_COLOR

local CTRL_MAP = {
    [string.char(0x01)] = '', [string.char(0x02)] = '',
    [string.char(0x03)] = '', [string.char(0x04)] = '',
    [string.char(0x05)] = '', [string.char(0x06)] = '',
    [string.char(0x7F, 0x34)] = '',
    [string.char(0x7F, 0x35)] = '',
    [string.char(0x7F, 0x36)] = '',
    [string.char(0x1F, 0x0F)] = '',
}

local COLOR_DECODE = {
    { string.char(0x1E, 0x01), '@CR' },
    { string.char(0x1E, 0x02), '@C1' },
    { string.char(0x1E, 0x03), '@C2' },
    { string.char(0x1E, 0x04), '@C3' },
    { string.char(0x1E, 0x05), '@C4' },
    { string.char(0x1E, 0x06), '@C5' },
    { string.char(0x1E, 0x07), '@C6' },
    { string.char(0x1E, 0x08), '@C7' },
    { string.char(0x1F, 0x0F), ''    },
    { BYTES_PROMPT,             ''    },
}

local GLYPH_ENCODE = {
    { string.char(0x81, 0x40),       '    '           },
    { string.char(0x81, 0xF4),       '[NX_note]'      },
    { chars.bstar,                   '[NX_bstar]'     },
    { chars.wstar,                   '[NX_wstar]'     },
    { chars.wave,                    '[NX_wave]'      },
    { chars.cldquo,                  '[NX_cldquote]'  },
    { chars.crdquo,                  '[NX_crdquote]'  },
    { string.char(0x88, 0x69),       '[NX_e_acute]'   },
    { string.char(0x7F, 0xFC),       ''               },
    { string.char(0x7F, 0xFB),       ''               },
    { string.char(0xEF, 0x1F),       '[NX_Fire]'      },
    { string.char(0xEF, 0x20),       '[NX_Ice]'       },
    { string.char(0xEF, 0x21),       '[NX_Wind]'      },
    { string.char(0xEF, 0x22),       '[NX_Earth]'     },
    { string.char(0xEF, 0x23),       '[NX_Lightning]' },
    { string.char(0xEF, 0x25, 0x24), '[NX_Water]'     },
    { string.char(0xEF, 0x25, 0x25), '[NX_Light]'     },
    { string.char(0xEF, 0x26),       '[NX_Dark]'      },
}

local GLYPH_DECODE = {
    { '%[NX_note]',     '♪' },
    { '%[NX_bstar]',    '☆' },
    { '%[NX_wstar]',    '★' },
    { '%[NX_wave]',     '~' },
    { '%[NX_cldquote]', '"' },
    { '%[NX_crdquote]', '"' },
    { '%[NX_e_acute]',  'é' },
}

local ELEMENT_COLOR = {
    { '%[NX_Fire]',      '\\cs(255,0,0)Fire \\cr'        },
    { '%[NX_Ice]',       '\\cs(0,255,255)Ice \\cr'       },
    { '%[NX_Wind]',      '\\cs(0,255,0)Wind \\cr'        },
    { '%[NX_Earth]',     '\\cs(153,76,0)Earth \\cr'      },
    { '%[NX_Lightning]', '\\cs(127,0,255)Lightning \\cr' },
    { '%[NX_Water]',     '\\cs(0,76,153)Water \\cr'      },
    { '%[NX_Light]',     '\\cs(224,224,224)Light \\cr'   },
    { '%[NX_Dark]',      '\\cs(82,82,82)Dark \\cr'       },
}

local DISPLAY_LABELS = {
    [0] = 'Mode 0: panneau masqué + log visible',
    [1] = 'Mode 1: panneau visible + log masqué',
    [2] = 'Mode 2: panneau visible + log visible',
}

local HELP_TEXT = {
    'Narrax v' .. _addon.version .. ' — by DiableNoir',
    '  Commands: //narrax (alias: //nx)',
    '  //narrax 0/1/2          — display mode (0=log only, 1=panel only, 2=both)',
    '  //narrax reset          — reset panel position',
    '  //narrax theme <n>      — load a theme from themes/',
    '  //narrax scale <n>      — panel scale factor (e.g. 1.5)',
    '  //narrax delay <s>      — seconds before auto-close (no-prompt messages)',
    '  //narrax text_speed <n> — chars per frame (0=instant)',
    '  //narrax animate        — toggle prompt bounce animation',
    '  //narrax portrait       — toggle NPC portraits',
    '  //narrax move_closes    — toggle close-on-movement',
    '  //narrax translate      — toggle auto-translation',
    '  //narrax language <l>   — set translation language (see locales/languages.lua)',
    '  //narrax debug [off|all|mode|codes|chunk|process|chars|elements]',
    '  //narrax test <msg>     — display a test panel',
    '　',
}

local FRAME_CAP       = 36000
local MOVEMENT_POLL_S = 1

local settings      = {}
local theme_options = {}

local state = {
    ready          = false,
    debug_level    = 'off',
    is_moving      = false,
    prev_x         = 0,
    prev_y         = 0,
    panel_open     = false,
    key_held       = false,
    dragging       = false,
    auto_close     = false,
    frame          = 0,
    close_ticks    = 0,
    timer_active   = false,
    last_text      = '',
    last_mode      = 0,
    move_coroutine = nil,
}

local ctx = {
    zone_id    = nil,
    zone_name  = nil,
    lang_obj   = nil,
    lang_key   = nil,
    color_subs = nil,
}

local xlat_cache = {}

local function apply_subs(str, subs)
    for i = 1, #subs do
        str = str:gsub(subs[i][1], subs[i][2])
    end
    return str
end

local function str_split(str, delim)
    local dlen  = #delim
    local parts = {}
    local n     = 1
    local pos   = 1
    while true do
        local s = str:find(delim, pos, true)
        if not s then break end
        parts[n] = str:sub(pos, s - 1)
        n   = n + 1
        pos = s + dlen
    end
    parts[n] = str:sub(pos)
    return parts
end

local function rebuild_color_subs()
    local t = panel._type
    if not t then return end
    ctx.color_subs = {
        { '@CR', '\\cr'                               },
        { '@C1', '\\cs(' .. (t.items    or '') .. ')' },
        { '@C2', '\\cs(' .. (t.keyitems or '') .. ')' },
        { '@C3', '\\cs(' .. (t.keyitems or '') .. ')' },
        { '@C4', '\\cs(' .. (t.gear     or '') .. ')' },
        { '@C5', '\\cs(0,159,173)'                    },
        { '@C6', '\\cs(156,149,19)'                   },
        { '@C7', '\\cs(' .. (t.roe      or '') .. ')' },
    }
end

local function refresh_ctx()
    local info    = ffxi_info()
    local zone_id = info and info.zone
    if zone_id ~= ctx.zone_id then
        local res     = require('resources')
        ctx.zone_id   = zone_id
        ctx.zone_name = (res.zones and res.zones[zone_id] and res.zones[zone_id].english) or ''
    end
    local lk = settings.lang
    if lk ~= ctx.lang_key then
        ctx.lang_key = lk
        ctx.lang_obj = lang_db[lk]
    end
end

local function log(msg)
    w_chat(207, w_tojis('[Narrax] ' .. tostring(msg)))
end

local function dbg(category, msg)
    if state.debug_level == 'off' then return end
    if state.debug_level == 'all' or state.debug_level == category then
        print(msg)
    end
end

local function tlen(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function load_theme()
    local xml_path  = 'themes/' .. settings.Theme .. '/theme.xml'
    local theme_cfg = config.load(xml_path, { ['name'] = settings.Theme })
    theme_options   = theme_mod.apply(theme_cfg)
    panel:load(settings, theme_options)
    rebuild_color_subs()
end

local function initialize()
    settings = config.load('generated/settings.xml', cfg_defaults)
    config.save(settings)
    load_theme()
    timer:schedule(0)
    if settings.MovementCloses then
        state.move_coroutine = moving_check:schedule(0)
    end
    state.ready = true
end

local function apply_theme()
    load_theme()
    if state.panel_open and state.last_text ~= '' then
        process_message(state.last_text, state.last_mode)
    end
end

local function open_panel(timed, mode)
    if not state.ready then initialize() end
    if timed then
        state.close_ticks = MSG_SHORT_TIMER[mode] and 3 or settings.NoPromptCloseDelay
        panel.timer_txt:text(tostring(state.close_ticks))
    end
    panel:show(timed)
    state.auto_close = timed
    state.panel_open = true
end

local function close_panel()
    panel:hide()
    state.panel_open = false
    state.auto_close = false
end

function timer()
    if state.timer_active then return end
    state.timer_active = true
    while true do
        if state.auto_close then
            if state.close_ticks <= 0 then
                close_panel()
            else
                state.close_ticks = state.close_ticks - 1
                panel.timer_txt:text(tostring(state.close_ticks))
            end
        end
        co_sleep(1)
    end
end

function moving_check()
    local p = ffxi_player()
    if not p then return end
    local pid = p.id

    while true do
        co_sleep(MOVEMENT_POLL_S)
        local me = ffxi_mob(pid)
        if me then
            local dx = me.x - state.prev_x
            local dy = me.y - state.prev_y
            if dx > 1 or dx < -1 or dy > 1 or dy < -1 then
                state.is_moving = true
                state.prev_x    = me.x
                state.prev_y    = me.y
            else
                state.is_moving = false
            end
            if state.is_moving and settings.MovementCloses and state.panel_open then
                close_panel()
            end
        end
    end
end

local function encode_glyphs(str)
    dbg('chars', 'encode_glyphs in:  ' .. str)
    str = apply_subs(str, GLYPH_ENCODE)
    dbg('chars', 'encode_glyphs out: ' .. str)
    return str
end

local function decode_glyphs(str)
    dbg('chars', 'decode_glyphs in:  ' .. str)
    str = apply_subs(str, GLYPH_DECODE)
    dbg('chars', 'decode_glyphs out: ' .. str)
    return str
end

function process_message(npc_text, mode)
    if not state.ready then initialize() end

    state.last_text = npc_text
    state.last_mode = mode

    local timed = not (MSG_HAS_PROMPT[mode]
                       and npc_text:sub(-LEN_PROMPT) == BYTES_PROMPT)

    local npc_prefix, npc_name = '', ''
    local raw_prefix = npc_text:match('^(.-)%s*:%s+')
    if raw_prefix then
        npc_prefix = raw_prefix .. ': '
        npc_name   = raw_prefix:match('^%s*(.-)%s*$') or raw_prefix
    end

    if settings.ShowPortraits and npc_name ~= '' then
        if not panel:set_character(npc_name) then
            panel:set_type(mode)
        end
    else
        panel:set_type(mode)
    end

    local chat_result
    if settings.DisplayMode == 1 then
        chat_result = (npc_prefix == '') and '\n'
                      or npc_text:sub(#npc_text - 1, #npc_text)
    else
        chat_result = npc_text
    end

    local text = encode_glyphs(npc_text)
    text = w_fromjis(text)
    text = decode_glyphs(text)

    if npc_name ~= '' then
        text = text:gsub('^%s*.-[^%s]%s*:%s+', '', 1)
    end

    if text:sub(1, LEN_DEF_COLOR) == BYTES_DEF_COLOR and mode ~= 15 then
        text = text:sub(LEN_DEF_COLOR + 1)
    end

    dbg('process', 'Pre-process: ' .. text)
    dbg('codes',   'Hex dump: '    .. text)

    local do_translate = settings.Translation
    if do_translate then refresh_ctx() end

    local lines = str_split(text, BYTES_NEWLINE)
    local buf   = {}

    for i = 1, #lines do
        local v = lines[i]

        v = apply_subs(v, COLOR_DECODE)
        v = v:gsub('.', CTRL_MAP)
        v = v:gsub("^%?([%w%.'(<\"])",    '%1')
        v = v:gsub('(%w)(%.%.%.+)([%w"])', '%1%2 %3')
        v = v:gsub('([%w"])%-%- ([%w%p])', '%1-- %2')

        if do_translate and v ~= '' then
            v = v:gsub('Forrr ', 'For ')
            local cached = xlat_cache[v]
            if cached then
                v = cached
            else
                local orig       = v
                local translated = get_translation(v, ctx.lang_obj, npc_name, ctx.zone_name)
                if translated ~= nil then
                    xlat_cache[orig] = translated
                    v = translated
                end
            end
        end

        v = ' ' .. panel:wrap_text(v)
        v = apply_subs(v, ctx.color_subs)
        v = apply_subs(v, ELEMENT_COLOR)

        buf[i] = '\n' .. v
    end

    local final = tconcat(buf)
    dbg('process', 'Final: ' .. final)

    panel:set_message(final)
    open_panel(timed, mode)

    return chat_result
end

windower.register_event('load', function()
    local info = ffxi_info()
    if info and info.logged_in then initialize() end
end)

windower.register_event('login', function()
    initialize:schedule(10)
end)

local last_chunk_hex = 0x00
windower.register_event('incoming chunk', function(id, original)
    dbg('chunk', str_format('Chunk 0x%02X: %s', id, original))
    if not PKT_CLOSE[id] then return end
    if id == 0x52 then
        local hex = original:hex()
        if last_chunk_hex == hex then return end
        last_chunk_hex = hex
    end
    close_panel()
end)

windower.register_event('incoming text', function(original, modified, mode)
    dbg('mode', str_format('Mode %d: %s', mode, original))
    if not MSG_VALID[mode] then return end
    if original:endswith(BYTES_AUTO_CLOSE) then close_panel(); return end
    if settings.DisplayMode >= 1 then
        local result = process_message(original, mode)
        return settings.DisplayMode == 1 and result or modified
    end
end)

windower.register_event('prerender', function()
    state.frame = state.frame + 1
    if state.frame > FRAME_CAP then state.frame = 0 end
    if state.panel_open then
        if settings.AnimatePrompt then panel:animate_prompt(state.frame) end
        panel:animate_text(settings.TextSpeed)
    end
end)

windower.register_event('keyboard', function(key_id, pressed, _flags, blocked)
    if blocked              then return end
    if not state.panel_open then return end
    local info = ffxi_info()
    if not info or info.chat_open then return end

    if pressed and not state.key_held then
        if key_id == KEY_ENTER then
            state.key_held = true
            close_panel()
        elseif key_id == KEY_SCROLL_LOCK then
            state.key_held = true
            if panel:hidden() then panel:show() else panel:hide() end
        end
    elseif not pressed and (key_id == KEY_ENTER or key_id == KEY_SCROLL_LOCK) then
        state.key_held = false
    end
end)

windower.register_event('mouse', function(evt_type, x, y, _delta, _blocked)
    if not panel.msg_bg:hover(x, y) then return false end
    if evt_type == 1 then
        state.dragging = true
    elseif evt_type == 2 then
        state.dragging = false
        config.save(settings)
    end
    if state.dragging then
        local bg = panel.msg_bg
        settings.Position.X = bg:pos_x() + bg:width()  / 2
        settings.Position.Y = bg:pos_y() + bg:height() / 2
        panel:set_position(settings.Position.X, settings.Position.Y)
    end
end)

windower.register_event('addon command', function(command, ...)
    if not state.ready then initialize() end
    local args = L{...}
    local cmd  = command and command:lower() or ''

    if cmd == 'help' then
        for i = 1, #HELP_TEXT do
            w_chat(207, w_tojis(HELP_TEXT[i]))
        end

    elseif cmd == '0' or cmd == '1' or cmd == '2' then
        settings.DisplayMode = tonumber(cmd)
        log(DISPLAY_LABELS[settings.DisplayMode])

    elseif cmd == 'reset' then
        settings.Position.X = cfg_defaults.Position.X
        settings.Position.Y = cfg_defaults.Position.Y
        panel:set_position(settings.Position.X, settings.Position.Y)
        log('Position du panneau réinitialisée.')

    elseif cmd == 'theme' then
        if args:empty() then
            log(str_format("theme: '%s' (default: '%s')", settings.Theme, cfg_defaults.Theme))
        else
            local name = args[1]
            local path = 'themes/' .. name .. '/theme.xml'
            if not w_fexists(w_path .. path) then
                log('theme.xml introuvable : ' .. path)
                return
            end
            local prev = settings.Theme
            settings.Theme = name
            apply_theme()
            log(str_format("theme: '%s' → '%s'", prev, settings.Theme))
        end

    elseif cmd == 'scale' then
        if args:empty() then
            log(str_format('scale: %.2f (default: %.2f)', settings.Scale, cfg_defaults.Scale))
        else
            local prev = settings.Scale
            settings.Scale = tonumber(args[1]) or settings.Scale
            panel:scale(settings.Scale)
            log(str_format('scale: %.2f → %.2f', prev, settings.Scale))
        end

    elseif cmd == 'delay' then
        if args:empty() then
            log(str_format('delay: %ds (default: %ds)',
                settings.NoPromptCloseDelay, cfg_defaults.NoPromptCloseDelay))
        else
            local prev = settings.NoPromptCloseDelay
            settings.NoPromptCloseDelay = tonumber(args[1]) or settings.NoPromptCloseDelay
            log(str_format('delay: %ds → %ds', prev, settings.NoPromptCloseDelay))
        end

    elseif cmd == 'text_speed' then
        if args:empty() then
            log(str_format('text_speed: %d (default: %d)', settings.TextSpeed, cfg_defaults.TextSpeed))
        else
            local prev = settings.TextSpeed
            settings.TextSpeed = tonumber(args[1]) or settings.TextSpeed
            log(str_format('text_speed: %d → %d', prev, settings.TextSpeed))
        end

    elseif cmd == 'animate' then
        settings.AnimatePrompt = not settings.AnimatePrompt
        panel:set_position()
        log('animate prompt: ' .. (settings.AnimatePrompt and 'on' or 'off'))

    elseif cmd == 'portrait' then
        settings.ShowPortraits = not settings.ShowPortraits
        apply_theme()
        log('portraits: ' .. (settings.ShowPortraits and 'on' or 'off'))

    elseif cmd == 'move_closes' then
        settings.MovementCloses = not settings.MovementCloses
        if settings.MovementCloses then
            state.move_coroutine = moving_check:schedule(0)
        else
            if state.move_coroutine and co_status(state.move_coroutine) ~= 'dead' then
                co_close(state.move_coroutine)
                state.move_coroutine = nil
            end
        end
        log('close on movement: ' .. (settings.MovementCloses and 'on' or 'off'))

    elseif cmd == 'translate' then
        settings.Translation = not settings.Translation
        local lang_label = settings.Language_name or ''
        log('translation: ' .. (settings.Translation and 'on' or 'off')
            .. (lang_label ~= '' and (' (' .. lang_label .. ')') or ''))

    elseif cmd == 'language' then
        if args:empty() then
            log('Usage: //narrax language <n>  (voir locales/languages.lua)')
        else
            local key = args[1]:lower()
            if lang_db[key] then
                if settings.Language_name == lang_db[key].name then
                    log('Langue déjà définie : ' .. settings.Language_name)
                else
                    settings.lang          = key
                    settings.Language_name = lang_db[key].name
                    ctx.lang_key  = nil
                    xlat_cache    = {}
                    log('Langue → ' .. settings.Language_name)
                end
            else
                local list, n, total = {}, 0, tlen(lang_db)
                list[1] = str_format('Langue "%s" introuvable. Disponibles : ', args[1])
                for k in pairs(lang_db) do
                    n = n + 1
                    list[#list + 1] = k .. (n < total and ', ' or '.')
                end
                log(tconcat(list))
            end
        end

    elseif cmd == 'debug' then
        if args:empty() then
            state.debug_level = (state.debug_level == 'off') and 'all' or 'off'
        else
            state.debug_level = args[1]
        end
        log('debug: ' .. state.debug_level)

    elseif cmd == 'test' then
        process_message(args:concat(' '), MSG.DIALOGUE)

    else
        log(str_format('Commande inconnue : "%s". Tapez //narrax help.', cmd))
    end

    config.save(settings)
end)

function hex_dump(str)
    return str:gsub('.', function(c)
        return str_format('%s[%02X]', c, c:byte())
    end)
end
codes = hex_dump
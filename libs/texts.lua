local table = require('table')
local math = require('math')

local texts = {}
local meta = {}

windower.text.saved_texts = {}
local dragged

local events = {
    reload = true,
    left_click = true,
    double_left_click = true,
    right_click = true,
    double_right_click = true,
    middle_click = true,
    scroll_up = true,
    scroll_down = true,
    hover = true,
    drag = true,
    right_drag = true,
}

_libs = _libs or {}
_libs.texts = texts

_meta = _meta or {}
_meta.Text = _meta.Text or {}
_meta.Text.__class = 'Text'
_meta.Text.__index = texts

local set_value = function(t, key, value)
    local m = meta[t]
    m.values[key] = value
    m.texts[key] = value ~= nil and (m.formats[key] and m.formats[key]:format(value) or tostring(value)) or m.defaults[key]
end

_meta.Text.__newindex = function(t, k, v)
    set_value(t, k, v)
    t:update()
end

local default_settings = {}
default_settings.pos = {}
default_settings.pos.x = 0
default_settings.pos.y = 0
default_settings.bg = {}
default_settings.bg.alpha = 255
default_settings.bg.red = 0
default_settings.bg.green = 0
default_settings.bg.blue = 0
default_settings.bg.visible = true
default_settings.flags = {}
default_settings.flags.right = false
default_settings.flags.bottom = false
default_settings.flags.bold = false
default_settings.flags.draggable = true
default_settings.flags.italic = false
default_settings.padding = 0
default_settings.text = {}
default_settings.text.size = 12
default_settings.text.font = 'Segoe UI'
default_settings.text.fonts = {
    'Segoe UI',
    'Microsoft YaHei',
    'SimSun',
    'Yu Gothic',
    'Malgun Gothic',
    'Nirmala UI',
    'Tahoma',
    'Arial'
}
default_settings.text.alpha = 255
default_settings.text.red = 255
default_settings.text.green = 255
default_settings.text.blue = 255
default_settings.text.stroke = {}
default_settings.text.stroke.width = 0
default_settings.text.stroke.alpha = 255
default_settings.text.stroke.red = 0
default_settings.text.stroke.green = 0
default_settings.text.stroke.blue = 0

math.randomseed(os.clock())

local amend
amend = function(settings, defaults)
    for key, val in pairs(defaults) do
        if type(val) == 'table' then
            settings[key] = amend(settings[key] or {}, val)
        elseif settings[key] == nil then
            settings[key] = val
        end
    end
    return settings
end

local call_events = function(t, event, ...)
    if not meta[t].events[event] then return end
    for _, event in ipairs(meta[t].events[event]) do
        event(t, meta[t].root_settings)
    end
end

local apply_settings = function(_, t, settings)
    settings = settings or meta[t].settings
    texts.pos(t, settings.pos.x, settings.pos.y)
    texts.bg_alpha(t, settings.bg.alpha)
    texts.bg_color(t, settings.bg.red, settings.bg.green, settings.bg.blue)
    texts.bg_visible(t, settings.bg.visible)
    texts.color(t, settings.text.red, settings.text.green, settings.text.blue)
    texts.alpha(t, settings.text.alpha)
    texts.font(t, settings.text.font, unpack(settings.text.fonts))
    texts.size(t, settings.text.size)
    texts.pad(t, settings.padding)
    texts.italic(t, settings.flags.italic)
    texts.bold(t, settings.flags.bold)
    texts.right_justified(t, settings.flags.right)
    texts.bottom_justified(t, settings.flags.bottom)
    texts.visible(t, meta[t].status.visible)
    texts.stroke_width(t, settings.text.stroke.width)
    texts.stroke_color(t, settings.text.stroke.red, settings.text.stroke.green, settings.text.stroke.blue)
    texts.stroke_alpha(t, settings.text.stroke.alpha)
    call_events(t, 'reload')
end

function texts.new(str, settings, root_settings)
    if type(str) ~= 'string' then
        str, settings, root_settings = '', str, settings
    end

    if not _libs.config then
        root_settings = nil
    else
        root_settings =
            root_settings and class(root_settings) == 'Settings' and
                root_settings
            or settings and class(settings) == 'Settings' and
                settings
            or
                nil
    end

    local t = {}
    local m = {}
    meta[t] = m
    m.name = (_addon and _addon.name or 'text') .. '_gensym_' .. tostring(t):sub(8) .. '_%.8X':format(16^8 * math.random()):sub(3)
    t._name = m.name
    m.settings = settings or {}
    m.status = m.status or {visible = false, text = {}}
    m.root_settings = root_settings
    m.base_str = str
    m.events = {}
    m.keys = {}
    m.values = {}
    m.textorder = {}
    m.defaults = {}
    m.formats = {}
    m.texts = {}

    windower.text.create(m.name)
    amend(m.settings, default_settings)

    if _libs.config then
        if m.root_settings then
            _libs.config.save(m.root_settings)
        end
    end

    if _libs.config and m.root_settings and settings then
        _libs.config.register(m.root_settings, apply_settings, t, m.settings)
    else
        apply_settings(_, t, settings)
    end

    if str then
        texts.append(t, str)
    else
        windower.text.set_text(m.name, '')
    end

    table.insert(windower.text.saved_texts, 1, t)
    return setmetatable(t, _meta.Text)
end

function texts.update(t, attr)
    attr = attr or {}
    local m = meta[t]

    for key, value in pairs(attr) do
        m.keys[key] = true
    end

    for key in pairs(m.keys) do
        set_value(t, key, attr[key] == nil and m.values[key] or attr[key])
    end

    local str = ''
    for _, key in ipairs(meta[t].textorder) do
        str = str .. m.texts[key]
    end

    windower.text.set_text(m.name, str)
    m.status.text.content = str
    return str
end

function texts.clear(t)
    local m = meta[t]
    m.keys = {}
    m.values = {}
    m.textorder = {}
    m.texts = {}
    m.defaults = {}
    m.formats = {}
    texts.append(t, m.base_str or '')
end

function texts.append(t, str)
    local m = meta[t]
    local i = 1
    local index = #m.textorder + 1
    while i <= #str do
        local startpos, endpos = str:find('%${.-}', i)
        local rndname = '%s_%u':format(m.name, index)
        if startpos then
            local match = str:sub(i, startpos - 1)
            if match ~= '' then
                m.textorder[index] = rndname
                m.texts[rndname] = match
                index = index + 1
            end
            match = str:sub(startpos + 2, endpos - 1)
            local key = match
            local default = ''
            local format = nil
            local keystart, keyend = match:find('^.-|')
            if keystart then
                key = match:sub(1, keyend - 1)
                match = match:sub(keyend + 1)
                default = match
            end
            local defaultstart, defaultend = match:find('^.-|')
            if defaultstart then
                default = match:sub(1, defaultend - 1)
                format = match:sub(defaultend + 1)
            end
            m.textorder[index] = key
            m.keys[key] = true
            m.defaults[key] = default
            m.formats[key] = format
            index = index + 1
            i = endpos + 1
        else
            m.textorder[index] = rndname
            m.texts[rndname] = str:sub(i)
            break
        end
    end
    texts.update(t)
end

function texts.it(t)
    local key
    local m = meta[t]
    return function()
        key = next(m.keys, key)
        return key, m.values[key], m.defaults[key], m.formats[key], m.texts[key]
    end
end

function texts.appendline(t, str) t:append('\n' .. str) end

function texts.show(t)
    windower.text.set_visibility(meta[t].name, true)
    meta[t].status.visible = true
end

function texts.hide(t)
    windower.text.set_visibility(meta[t].name, false)
    meta[t].status.visible = false
end

function texts.visible(t, visible)
    if visible == nil then return meta[t].status.visible end
    windower.text.set_visibility(meta[t].name, visible)
    meta[t].status.visible = visible
end

function texts.text(t, str)
    if not str then return meta[t].status.text.content end
    meta[t].base_str = str
    texts.clear(t)
end

function texts.pos(t, x, y)
    local m = meta[t]
    if not x then return m.settings.pos.x, m.settings.pos.y end
    local settings = windower.get_windower_settings()
    windower.text.set_location(m.name, x + (m.settings.flags.right and settings.ui_x_res or 0), y + (m.settings.flags.bottom and settings.ui_y_res or 0))
    m.settings.pos.x = x
    m.settings.pos.y = y
end

function texts.pos_x(t, x)
    if not x then return meta[t].settings.pos.x end
    t:pos(x, meta[t].settings.pos.y)
end

function texts.pos_y(t, y)
    if not y then return meta[t].settings.pos.y end
    t:pos(meta[t].settings.pos.x, y)
end

function texts.extents(t) return windower.text.get_extents(meta[t].name) end

function texts.font(t, ...)
    if not ... then return meta[t].settings.text.font end
    windower.text.set_font(meta[t].name, ...)
    meta[t].settings.text.font = (...)
    meta[t].settings.text.fonts = {select(2, ...)}
end

function texts.size(t, size)
    if not size then return meta[t].settings.text.size end
    windower.text.set_font_size(meta[t].name, size)
    meta[t].settings.text.size = size
end

function texts.pad(t, padding)
    if not padding then return meta[t].settings.padding end
    windower.text.set_bg_border_size(meta[t].name, padding)
    meta[t].settings.padding = padding
end

function texts.color(t, red, green, blue)
    if not red then return meta[t].settings.text.red, meta[t].settings.text.green, meta[t].settings.text.blue end
    windower.text.set_color(meta[t].name, meta[t].settings.text.alpha, red, green, blue)
    meta[t].settings.text.red = red
    meta[t].settings.text.green = green
    meta[t].settings.text.blue = blue
end

function texts.alpha(t, alpha)
    if not alpha then return meta[t].settings.text.alpha end
    windower.text.set_color(meta[t].name, alpha, meta[t].settings.text.red, meta[t].settings.text.green, meta[t].settings.text.blue)
    meta[t].settings.text.alpha = alpha
end

function texts.transparency(t, transparency)
    if not transparency then return 1 - meta[t].settings.text.alpha/255 end
    texts.alpha(t, math.floor(255*(1-transparency)))
end

function texts.right_justified(t, right)
    if right == nil then return meta[t].settings.flags.right end
    windower.text.set_right_justified(meta[t].name, right)
    meta[t].settings.flags.right = right
end

function texts.bottom_justified(t, bottom)
    if bottom == nil then return meta[t].settings.flags.bottom end
end

function texts.italic(t, italic)
    if italic == nil then return meta[t].settings.flags.italic end
    windower.text.set_italic(meta[t].name, italic)
    meta[t].settings.flags.italic = italic
end

function texts.bold(t, bold)
    if bold == nil then return meta[t].settings.flags.bold end
    windower.text.set_bold(meta[t].name, bold)
    meta[t].settings.flags.bold = bold
end

function texts.bg_color(t, red, green, blue)
    if not red then return meta[t].settings.bg.red, meta[t].settings.bg.green, meta[t].settings.bg.blue end
    windower.text.set_bg_color(meta[t].name, meta[t].settings.bg.alpha, red, green, blue)
    meta[t].settings.bg.red = red
    meta[t].settings.bg.green = green
    meta[t].settings.bg.blue = blue
end

function texts.bg_visible(t, visible)
    if visible == nil then return meta[t].settings.bg.visible end
    windower.text.set_bg_visibility(meta[t].name, visible)
    meta[t].settings.bg.visible = visible
end

function texts.bg_alpha(t, alpha)
    if not alpha then return meta[t].settings.bg.alpha end
    windower.text.set_bg_color(meta[t].name, alpha, meta[t].settings.bg.red, meta[t].settings.bg.green, meta[t].settings.bg.blue)
    meta[t].settings.bg.alpha = alpha
end

function texts.bg_transparency(t, transparency)
    if not transparency then return 1 - meta[t].settings.bg.alpha/255 end
    texts.bg_alpha(t, math.floor(255*(1-transparency)))
end

function texts.stroke_width(t, width)
    if not width then return meta[t].settings.text.stroke.width end
    windower.text.set_stroke_width(meta[t].name, width)
    meta[t].settings.text.stroke.width = width
end

function texts.stroke_color(t, red, green, blue)
    if not red then return meta[t].settings.text.stroke.red, meta[t].settings.text.stroke.green, meta[t].settings.text.stroke.blue end
    windower.text.set_stroke_color(meta[t].name, meta[t].settings.text.stroke.alpha, red, green, blue)
    meta[t].settings.text.stroke.red = red
    meta[t].settings.text.stroke.green = green
    meta[t].settings.text.stroke.blue = blue
end

function texts.stroke_transparency(t, transparency)
    if not transparency then return 1 - meta[t].settings.text.stroke.alpha/255 end
    texts.stroke_alpha(t, math.floor(255 * (1 - transparency)))
end

function texts.stroke_alpha(t, alpha)
    if not alpha then return meta[t].settings.text.stroke.alpha end
    windower.text.set_stroke_color(meta[t].name, alpha, meta[t].settings.text.stroke.red, meta[t].settings.text.stroke.green, meta[t].settings.text.stroke.blue)
    meta[t].settings.text.stroke.alpha = alpha
end

function texts.draggable(t, draggable)
    if draggable == nil then return meta[t].settings.flags.draggable end
    meta[t].settings.flags.draggable = draggable
end

function texts.hover(t, x, y)
    if not t:visible() then return false end
    local pos_x, pos_y = windower.text.get_location(meta[t].name)
    local off_x, off_y = windower.text.get_extents(meta[t].name)
    if meta[t].settings.flags.right then pos_x = pos_x - off_x end
    return (pos_x <= x and x <= pos_x + off_x or pos_x >= x and x >= pos_x + off_x)
       and (pos_y <= y and y <= pos_y + off_y or pos_y >= y and y >= pos_y + off_y)
end

function texts.destroy(t)
    for i, t_needle in ipairs(windower.text.saved_texts) do
        if t == t_needle then
            table.remove(windower.text.saved_texts, i)
            break
        end
    end
    windower.text.delete(meta[t].name)
    meta[t] = nil
end

function texts.settings(t) return meta[t].settings end

windower.register_event('mouse', function(type, x, y, delta, blocked)
    if blocked then return end
    if type == 0 then
        if dragged then
            dragged.text:pos(x - dragged.x, y - dragged.y)
            return true
        end
    elseif type == 1 then
        for _, t in pairs(windower.text.saved_texts) do
            local m = meta[t]
            if m.settings.flags.draggable and t:hover(x, y) then
                local pos_x, pos_y = windower.text.get_location(m.name)
                local flags = m.settings.flags
                if flags.right or flags.bottom then
                    local info = windower.get_windower_settings()
                    if flags.right then pos_x = pos_x - info.ui_x_res
                    elseif flags.bottom then pos_y = pos_y - info.ui_y_res end
                end
                dragged = {text = t, x = x - pos_x, y = y - pos_y}
                return true
            end
        end
    elseif type == 2 then
        if dragged then
            if _libs.config and meta[dragged.text].root_settings then
                _libs.config.save(meta[dragged.text].root_settings)
            end
            dragged = nil
            return true
        end
    end
    return false
end)

function texts.register_event(t, key, fn)
    if not events[key] then
        error('Event %s not available for text objects.':format(key))
        return
    end
    local m = meta[t]
    m.events[key] = m.events[key] or {}
    m.events[key][#m.events[key] + 1] = fn
    return #m.events[key]
end

function texts.unregister_event(t, key, fn)
    if not (events[key] and meta[t].events[key]) then return end
    if type(fn) == 'number' then
        table.remove(meta[t].events[key], fn)
    else
        for index, event in ipairs(meta[t].events[key]) do
            if event == fn then
                table.remove(meta[t].events[key], index)
                return
            end
        end
    end
end

return texts
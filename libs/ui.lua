local ui = {}

local w_fexists = windower.file_exists
local w_path    = windower.addon_path
local ffxi_info = windower.ffxi.get_info
local math_sin  = math.sin
local tconcat   = table.concat
local tonumber  = tonumber

local res

local TEXT_DEFAULTS = { flags = { draggable = false }, padding = 2 }

local EMPTY_NAMES = S{'', ' '}

ui.msg_bg    = images.new()
ui.port_bg   = images.new()
ui.port_img  = images.new()
ui.port_frm  = images.new()
ui.name_bg   = images.new()
ui.prompt    = images.new()

ui.msg_txt   = nil
ui.name_txt  = nil
ui.timer_txt = nil

ui._hidden         = true
ui._cur_text       = ''
ui._chars_shown    = 0
ui._has_portrait   = false
ui._dlg_style      = {}
ui._sys_style      = {}
ui._type           = {}
ui._theme          = 'default'
ui._scale          = 1.0
ui._show_portraits = true
ui._theme_opts     = nil
ui._emote_dlg_rgb  = nil
ui._emote_sys_rgb  = nil

local function init_image(img, path)
    img:path(path)
    img:repeat_xy(1, 1)
    img:draggable(false)
    img:fit(false)
end

local function init_text(txt, opts)
    txt:bg_alpha(0)
    txt:bg_visible(false)
    txt:font(opts.font, 'meiryo', 'segoe ui', 'sans-serif')
    txt:size(opts.font_size)
    txt:alpha(opts.font_color.alpha)
    txt:color(opts.font_color.red, opts.font_color.green, opts.font_color.blue)
    txt:stroke_transparency(opts.stroke.alpha or 0)
    txt:stroke_color(opts.stroke.red or 0, opts.stroke.green or 0, opts.stroke.blue or 0)
    txt:stroke_width(opts.stroke.width or 0)
end

local function parse_rgb(str)
    if not str then return nil end
    local r, g, b = str:match('^(%d+),(%d+),(%d+)$')
    if r then return { tonumber(r), tonumber(g), tonumber(b) } end
    return nil
end

function ui:load(settings, theme_opts)
    if not self.msg_txt   then self.msg_txt   = texts.new(TEXT_DEFAULTS) end
    if not self.name_txt  then self.name_txt  = texts.new(TEXT_DEFAULTS) end
    if not self.timer_txt then self.timer_txt = texts.new(TEXT_DEFAULTS) end

    self._theme          = settings.Theme
    self._scale          = settings.Scale
    self._show_portraits = settings.ShowPortraits
    self._theme_opts     = theme_opts
    self._has_portrait   = false

    local td = theme_opts.message.dialogue
    self._dlg_style = {
        path     = theme_opts.narrax_background,
        color    = { alpha=td.alpha, red=td.red, green=td.green, blue=td.blue },
        items    = td.items,
        keyitems = td.keyitems,
        gear     = td.gear,
        roe      = td.roe,
        stroke   = {
            width=td.stroke.width, alpha=td.stroke.alpha,
            red=td.stroke.red,     green=td.stroke.green, blue=td.stroke.blue,
        },
    }
    self._emote_dlg_rgb = parse_rgb(td.emote or '125,175,255')

    local ts = theme_opts.message.system
    self._sys_style = {
        path     = theme_opts.system_background,
        color    = { alpha=ts.alpha, red=ts.red, green=ts.green, blue=ts.blue },
        items    = ts.items,
        keyitems = ts.keyitems,
        gear     = ts.gear,
        roe      = ts.roe,
        stroke   = {
            width=ts.stroke.width, alpha=ts.stroke.alpha,
            red=ts.stroke.red,     green=ts.stroke.green, blue=ts.stroke.blue,
        },
    }
    self._emote_sys_rgb = parse_rgb(ts.emote or '125,175,255')

    self._type    = self._dlg_style
    MSG_STYLE_MAP = nil

    init_image(self.msg_bg, self._type.path)
    if theme_opts.portrait then
        init_image(self.port_bg,  theme_opts.portrait_background)
        init_image(self.port_img, nil)
        init_image(self.port_frm, theme_opts.portrait_frame)
    end
    init_image(self.name_bg, theme_opts.name_background)
    if theme_opts.prompt then
        init_image(self.prompt, theme_opts.prompt_image)
    end

    init_text(self.msg_txt,   theme_opts.message)
    init_text(self.name_txt,  theme_opts.name)
    if theme_opts.timer then
        init_text(self.timer_txt, theme_opts.timer)
    end

    self:set_position(settings.Position.X, settings.Position.Y)
    self.msg_bg:draggable(true)
end

function ui:scale(s)
    self._scale = s
    self:set_position()
end

function ui:set_position(x_pos, y_pos)
    local sc = self._scale
    local to = self._theme_opts
    if not to then return end

    local mw = to.message.width
    local mh = to.message.height
    local hw = mw / 2
    local hh = mh / 2

    x_pos = x_pos or (self.msg_bg:pos_x() + hw * sc)
    y_pos = y_pos or (self.msg_bg:pos_y() + hh * sc)

    local ox = x_pos - hw * sc
    local oy = y_pos - hh * sc

    local mtx = to.message.offset_x * sc
    local mty = to.message.offset_y * sc
    if self._has_portrait and to.portrait then
        if to.portrait.message_offset_x then mtx = to.portrait.message_offset_x * sc end
        if to.portrait.message_offset_y then mty = to.portrait.message_offset_y * sc end
    end

    self.msg_bg:pos(ox, oy)
    self.msg_bg:size(mw * sc, mh * sc)

    if to.portrait then
        local px = ox + to.portrait.offset_x * sc
        local py = oy + to.portrait.offset_y * sc
        local pw = to.portrait.width  * sc
        local ph = to.portrait.height * sc
        self.port_bg:pos(px,  py);  self.port_bg:size(pw, ph)
        self.port_img:pos(px, py);  self.port_img:size(pw, ph)
        self.port_frm:pos(px, py);  self.port_frm:size(pw, ph)
    end

    self.name_bg:pos(ox + to.name.background_offset_x * sc,
                     oy + to.name.background_offset_y * sc)
    self.name_bg:size(to.name.width * sc, to.name.height * sc)

    if to.prompt then
        self.prompt:pos(ox + to.prompt.offset_x * sc, oy + to.prompt.offset_y * sc)
        self.prompt:size(to.prompt.width * sc, to.prompt.height * sc)
    end

    self.msg_txt:pos(ox + mtx,                    oy + mty)
    self.msg_txt:size(to.message.font_size * sc)
    self.name_txt:pos(ox + to.name.offset_x * sc, oy + to.name.offset_y * sc)
    self.name_txt:size(to.name.font_size * sc)
    if to.timer then
        self.timer_txt:pos(ox + to.timer.offset_x * sc, oy + to.timer.offset_y * sc)
        self.timer_txt:size(to.timer.font_size * sc)
    end
end

function ui:hide()
    self.msg_bg:hide();   self.name_bg:hide()
    self.port_bg:hide();  self.port_img:hide();  self.port_frm:hide()
    self.prompt:hide()
    self.msg_txt:hide();  self.name_txt:hide();  self.timer_txt:hide()
    self._hidden = true
end

function ui:show(timed)
    self.msg_bg:show()
    self.msg_txt:show()

    local has_name = not EMPTY_NAMES[self.name_txt:text()]
    if has_name then
        self.name_bg:show()
        self.name_txt:show()
        if self._has_portrait then
            self.port_bg:show();  self.port_img:show();  self.port_frm:show()
        else
            self.port_bg:hide();  self.port_img:hide();  self.port_frm:hide()
        end
    else
        self.name_bg:hide();   self.name_txt:hide()
        self.port_bg:hide();   self.port_img:hide();   self.port_frm:hide()
    end

    if not timed then
        self.prompt:show();    self.timer_txt:hide()
    else
        self.timer_txt:show(); self.prompt:hide()
    end

    self._hidden = false
end

function ui:hidden()
    return self._hidden
end

local MSG_STYLE_MAP   = nil
local EMOTE_MODE_SET  = S{15, 7}

function ui:set_type(type_id)
    if not MSG_STYLE_MAP then
        MSG_STYLE_MAP = {
            [150] = self._dlg_style,
            [151] = self._sys_style,
            [142] = self._dlg_style,
            [144] = self._dlg_style,
            [146] = self._sys_style,
            [15]  = self._sys_style,
            [7]   = self._sys_style,
        }
    end

    self._type = MSG_STYLE_MAP[type_id] or self._dlg_style
    self:update_msg_bg(self._type.path)

    local c = self._type.color
    self.msg_txt:alpha(c.alpha)

    if EMOTE_MODE_SET[type_id] then
        local rgb = self._emote_sys_rgb
        if rgb then self.msg_txt:color(rgb[1], rgb[2], rgb[3]) end
    else
        self.msg_txt:color(c.red, c.green, c.blue)
    end

    local sk = self._type.stroke
    self.msg_txt:stroke_transparency(sk.alpha)
    self.msg_txt:stroke_color(sk.red, sk.green, sk.blue)
    self.msg_txt:stroke_width(sk.width)
end

function ui:set_character(name)
    self.name_txt:text(' ' .. name)

    if not res then res = require('resources') end

    local info      = ffxi_info()
    local zone_name = (res.zones and res.zones[info.zone] and res.zones[info.zone].en) or ''
    local is_s      = zone_name:endswith('[S]')

    self._has_portrait = false

    if self._show_portraits and self._theme_opts.portrait then

        local base_theme   = w_path .. 'themes/' .. self._theme .. '/characters/'
        local base_default = w_path .. 'assets/portraits/'
        local sfx_s        = name .. ' (S).png'
        local sfx          = name .. '.png'

        local portrait_path
        if     is_s and w_fexists(base_theme   .. sfx_s) then portrait_path = base_theme   .. sfx_s
        elseif is_s and w_fexists(base_default .. sfx_s) then portrait_path = base_default .. sfx_s
        elseif          w_fexists(base_theme   .. sfx  ) then portrait_path = base_theme   .. sfx
        elseif          w_fexists(base_default .. sfx  ) then portrait_path = base_default .. sfx
        end

        if portrait_path then
            self.port_img:path(portrait_path)
            self._has_portrait = true
        end
    end

    local char_bg = w_path .. 'themes/' .. self._theme .. '/characters/' .. name .. '.png'
    if w_fexists(char_bg) then
        self:update_msg_bg(char_bg)
        return true
    end
    return false
end

function ui:update_msg_bg(path)
    if path and path ~= self.msg_bg:path() then
        self.msg_bg:path(path)
    end
end

function ui:wrap_text(str)
    local limit = self._theme_opts.message.max_length + 1
    if self._has_portrait and self._theme_opts.portrait
       and self._theme_opts.portrait.max_length then
        limit = self._theme_opts.portrait.max_length + 1
    end

    local lines = {}
    local line  = {}
    local room  = limit

    for word in str:gmatch('%S+') do
        local wlen = #word + 1
        if wlen > room then
            lines[#lines + 1] = tconcat(line, ' ')
            line = { word }
            room = limit - #word
        else
            line[#line + 1] = word
            room = room - wlen
        end
    end
    if #line > 0 then lines[#lines + 1] = tconcat(line, ' ') end

    return tconcat(lines, '\n ')
end

function ui:set_message(message)
    self._cur_text    = message
    self._chars_shown = 0
    self.msg_txt:text('')
    self:set_position()
end

local function sawtooth_bounce(t, freq)
    local x = t * freq
    return -math_sin(x - math_sin(x) / 2)
end

function ui:animate_prompt(frame)
    if not self._theme_opts.prompt then return end
    local bounce = sawtooth_bounce(frame / 60, 6) * 2.5
    local base_y = self.msg_bg:pos_y()
    self.prompt:pos_y(base_y + (self._theme_opts.prompt.offset_y + bounce) * self._scale)
end

function ui:animate_text(chars_per_frame)
    if self._chars_shown >= #self._cur_text then return end
    self._chars_shown = self._chars_shown + (chars_per_frame == 0 and 1000 or chars_per_frame)
    self.msg_txt:text(self._cur_text:sub(1, self._chars_shown))
end

ui.animate_text_display = ui.animate_text

return ui
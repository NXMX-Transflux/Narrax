local json     = require('libs.json')
local https    = require('ssl.https')
local ltn12    = require('ltn12')
local glossary = require('locales.glossary')
local res      = require('resources')

local j_encode  = json.encode
local j_decode  = json.decode
local tconcat   = table.concat
local tinsert   = table.insert
local sfmt      = string.format
local io_open   = io.open
local clock     = os.clock
local date_utc  = os.date
local math_max  = math.max
local math_min  = math.min
local math_rand = math.random
local pcall     = pcall
local pairs     = pairs
local ipairs    = ipairs
local tostring  = tostring
local type      = type
local w_chat    = windower.add_to_chat
local w_path    = windower.addon_path
local w_mkdir   = windower.create_dir
local w_fexists = windower.file_exists

local _api_key_cfg
do
    local ok, result = pcall(require, 'config.api_key')
    if not ok or type(result) ~= 'table' then
        windower.add_to_chat(167,
            '[Narrax] ERREUR : fichier config/api_key.lua introuvable ou invalide. '
            .. 'Créez-le à partir du modèle fourni et relancez l\'addon.')
        _api_key_cfg = {}
    else
        _api_key_cfg = result
    end
end

local _raw_key = _api_key_cfg.translator_key
if not _raw_key or _raw_key == '' or _raw_key == 'VOTRE_CLE_API_ICI' then
    windower.add_to_chat(167,
        '[Narrax] ERREUR : clé API DeepL non renseignée. '
        .. 'Ouvrez config/api_key.lua et remplacez VOTRE_CLE_API_ICI par votre clé.')
    _raw_key = nil
end

local DEEPL_API_KEY = _raw_key
local DEEPL_URL           = 'https://api-free.deepl.com/v2/translate'
local DEEPL_SOURCE_LANG   = 'EN'

local SERVER_URL          = ""
local MAX_NET_TIMEOUT     = 8
local MIN_NET_TIMEOUT     = 0.5
local BETWEEN_REQUESTS_S  = 0.2
local BETWEEN_SRV_SENDS_S = 0.1
local MAX_RETRIES         = 3
local LATENCY_MARGIN      = 0.3

local adaptive_timeout = 0.5

local SERVER_ENABLED = (SERVER_URL ~= '' and SERVER_URL ~= 'https://tonserveur.com/api/upload_cache')

local DEEPL_LANG_MAP = {
    ['pt-PT'] = 'PT-PT',
    ['pt-BR'] = 'PT-BR',
    ['zh']    = 'ZH-HANS',
    ['hi']    = nil,
    ['bn']    = nil,
    ['ur']    = nil,
    ['mr']    = nil,
    ['te']    = nil,
    ['ta']    = nil,
    ['kn']    = nil,
    ['gu']    = nil,
    ['ml']    = nil,
    ['pa']    = nil,
    ['fa']    = nil,
    ['ar']    = nil,
    ['kk']    = nil,
}

local function to_deepl_code(code)
    if not code then return nil end
    if DEEPL_LANG_MAP[code] ~= nil or DEEPL_LANG_MAP[code] == nil and DEEPL_LANG_MAP[code] ~= nil then
    end
    if DEEPL_LANG_MAP[code] == nil and not (DEEPL_LANG_MAP[code] == nil) then end

    local mapped, has_key
    for k, v in pairs(DEEPL_LANG_MAP) do
        if k == code then mapped = v; has_key = true; break end
    end
    if has_key then return mapped end

    return code:upper()
end

local function q_new()  return { head=1, tail=0 } end
local function q_push(q, v) q.tail=q.tail+1; q[q.tail]=v end
local function q_pop(q)
    if q.head > q.tail then return nil end
    local v=q[q.head]; q[q.head]=nil; q.head=q.head+1; return v
end
local function q_empty(q) return q.head > q.tail end

local sched_queue    = q_new()
local server_queue   = q_new()
local xlat_queue     = q_new()
local server_busy    = false
local xlat_busy      = false
local last_xlat_time = 0

local mem_cache = {}

local function schedule_later(delay_s, fn)
    q_push(sched_queue, { at = clock() + delay_s, fn = fn })
end

local function cache_file(lang, zone, npc)
    return w_path .. 'generated/translations/' .. lang .. '/' .. zone .. '/npc/' .. npc .. '.json'
end

local function ensure_dirs(lang, zone)
    local base = w_path .. 'generated/'
    w_mkdir(base)
    w_mkdir(base .. 'translations/')
    local b2 = base .. 'translations/'
    w_mkdir(b2 .. lang)
    w_mkdir(b2 .. lang .. '/' .. zone)
    w_mkdir(b2 .. lang .. '/' .. zone .. '/npc')
end

local function read_npc_cache(lang, zone, npc)
    local path = cache_file(lang, zone, npc)
    if not w_fexists(path) then return {} end
    local f = io_open(path, 'r')
    if not f then return {} end
    local raw = f:read('*all')
    f:close()
    if raw == '' then return {} end
    local ok, data = pcall(j_decode, raw)
    if ok and data and type(data.translations) == 'table' then
        return data.translations
    end
    return {}
end

local function write_npc_cache(lang, zone, npc, cache)
    ensure_dirs(lang, zone)
    local path = cache_file(lang, zone, npc)
    local f    = io_open(path, 'w+')
    if not f then return end

    local entries, n = {}, 0
    for k, v in pairs(cache) do
        if k ~= '_last_updated' then
            n = n + 1
            local ok_k, sk = pcall(j_encode, tostring(k))
            local ok_v, sv = pcall(j_encode, tostring(v))
            if ok_k and ok_v then
                entries[n] = '  ' .. sk .. ':' .. sv
            end
        end
    end

    f:write(sfmt('{"_last_updated":"%s","translations":{\n%s\n}}\n',
        date_utc('!%Y-%m-%dT%H:%M:%SZ'),
        tconcat(entries, ',\n')))
    f:close()
end

local RE_ESCAPE = "([%%%^%$%(%)%.%[%]%*%+%-%?%'%/])"
local function re_esc(s) return (s:gsub(RE_ESCAPE, '%%%1')) end

local glossary_fwd = {}
local glossary_rev = {}
do
    local inv = {}
    for orig, repl in pairs(glossary) do
        tinsert(glossary_fwd, { pat=re_esc(orig), rep=repl })
        inv[repl] = orig
    end
    for repl, orig in pairs(inv) do
        tinsert(glossary_rev, { pat=re_esc(repl), orig=orig })
    end
end

local function apply_glossary(text)
    for i = 1, #glossary_fwd do
        text = text:gsub(glossary_fwd[i].pat, glossary_fwd[i].rep)
    end
    return text
end

local function revert_glossary(text)
    for i = 1, #glossary_rev do
        text = text:gsub(glossary_rev[i].pat, glossary_rev[i].orig)
    end
    return text
end

local function mask_color_seqs(text)
    local tokens, n, out = {}, 0, text
    for seq in text:gmatch('@%d+.-@93537') do
        n = n + 1
        tokens[n] = seq
        out = out:gsub(seq, '__CX_' .. n .. '__', 1)
    end
    return out, tokens
end

local function unmask_color_seqs(text, tokens)
    if not tokens then return text end
    for i, seq in ipairs(tokens) do
        text = text:gsub('__CX_' .. i .. '__', seq)
    end
    return text
end

local plural_set = {}
do
    local grammar = res.items_grammar or {}
    for _, item in pairs(grammar) do
        if item.plural then plural_set[item.plural] = true end
    end
end

local function fix_article_plural(text, articles)
    if not articles or not articles.singular or not articles.plural then return text end
    local sg, pl = articles.singular, articles.plural
    for plural in pairs(plural_set) do
        local esc = re_esc(plural)
        text = text:gsub(' '..sg.masc..'%s+(@%d%d%d%d'..esc..'@93537)', ' '..pl.masc..' %1')
        text = text:gsub(' '..sg.fem ..'%s+(@%d%d%d%d'..esc..'@93537)', ' '..pl.fem ..' %1')
    end
    return text
end

local function http_post_deepl(target_lang, text_to_translate)
    if not DEEPL_API_KEY or DEEPL_API_KEY == '' then
        w_chat(167, '[Narrax] DeepL : clé API non configurée. '
            .. 'Renseignez translator_key dans config/api_key.lua')
        return nil
    end

    local payload = j_encode({
        text        = { text_to_translate },
        source_lang = DEEPL_SOURCE_LANG,
        target_lang = target_lang,
    })

    local headers = {
        ['Authorization'] = 'DeepL-Auth-Key ' .. DEEPL_API_KEY,
        ['Content-Type']  = 'application/json',
        ['Content-Length'] = tostring(#payload),
    }

    local attempts = 0
    while attempts < MAX_RETRIES do
        local t0   = clock()
        local body = {}
        https.TIMEOUT = adaptive_timeout

        local ok, status = pcall(function()
            local _, st = https.request{
                url     = DEEPL_URL,
                method  = 'POST',
                headers = headers,
                source  = ltn12.source.string(payload),
                sink    = ltn12.sink.table(body),
            }
            return st
        end)

        local rtt = clock() - t0
        local raw = tconcat(body)

        if ok and status == 200 and raw ~= '' then
            adaptive_timeout = math_max(MIN_NET_TIMEOUT, math_min(rtt + LATENCY_MARGIN, MAX_NET_TIMEOUT))
            return raw
        end

        if ok then
            if status == 403 then
                w_chat(167, '[Narrax] DeepL : clé API invalide ou quota dépassé (HTTP 403). '
                    .. 'Vérifiez translator_key dans config/api_key.lua')
                return nil
            elseif status == 456 then
                w_chat(167, '[Narrax] DeepL : quota mensuel épuisé (HTTP 456). '
                    .. 'Réinitialisé le 1er du mois sur deepl.com')
                return nil
            elseif status == 429 then
                schedule_later(2.0, function() end)
            elseif status == 400 then
                w_chat(167, sfmt('[Narrax] DeepL : requête invalide (HTTP 400) pour lang=%s', target_lang))
                return nil
            end
        end

        adaptive_timeout = math_min(adaptive_timeout * (1.3 + math_rand() * 0.4), MAX_NET_TIMEOUT)
        attempts = attempts + 1
    end

    return nil
end

local function get_npc_cache(lc, zone, npc_name)
    local lc_c = mem_cache[lc]
    if not lc_c then lc_c = {}; mem_cache[lc] = lc_c end
    local z_c  = lc_c[zone]
    if not z_c  then z_c  = {}; lc_c[zone]   = z_c  end
    local n_c  = z_c[npc_name]
    if not n_c then
        n_c = read_npc_cache(lc, zone, npc_name)
        z_c[npc_name] = n_c
    end
    return n_c
end

function get_translation(text, language, npc_name, zone)
    if not language or not language.code then return nil end
    local lc = language.code

    local deepl_code = to_deepl_code(lc)
    if not deepl_code then
        if not mem_cache['_unsupported_' .. lc] then
            mem_cache['_unsupported_' .. lc] = true
            w_chat(167, sfmt('[Narrax] DeepL : langue "%s" non supportée. '
                .. 'Consultez DEEPL_LANG_MAP dans libs/translator.lua', lc))
        end
        return nil
    end

    local n_cache = get_npc_cache(lc, zone, npc_name)
    if n_cache[text] then return n_cache[text] end

    local masked, color_tokens = mask_color_seqs(text)
    masked = apply_glossary(masked)

    local raw = http_post_deepl(deepl_code, masked)
    if not raw then return nil end

    local ok, data = pcall(j_decode, raw)
    if not ok or not data then return nil end

    local xlat_list = data.translations
    if not xlat_list or not xlat_list[1] or not xlat_list[1].text then
        return nil
    end

    local result = xlat_list[1].text
    result = unmask_color_seqs(revert_glossary(result), color_tokens)
    result = fix_article_plural(result, language.articles)

    n_cache[text] = result
    write_npc_cache(lc, zone, npc_name, n_cache)
    send_cache_to_server(lc, zone, npc_name, text, result)

    return result
end

local function flush_server_queue()
    if server_busy or q_empty(server_queue) then return end
    if not SERVER_ENABLED then return end
    server_busy = true

    local task    = q_pop(server_queue)
    local payload = j_encode({
        language     = task.lc,
        zone         = task.zone,
        npc          = task.npc,
        translations = { [task.text] = task.xlat },
    })

    coroutine.wrap(function()
        local resp = {}
        local ok, code = pcall(function()
            local _, st = https.request{
                url    = SERVER_URL,
                method = 'POST',
                headers = {
                    ['Content-Type']   = 'application/json',
                    ['Content-Length'] = tostring(#payload),
                },
                source = ltn12.source.string(payload),
                sink   = ltn12.sink.table(resp),
            }
            return st
        end)
        if ok and code == 200 then
            w_chat(207, '[Narrax] Cache envoyé : ' .. task.npc)
        else
            w_chat(167, '[Narrax] Échec envoi cache : ' .. tostring(ok and code or 'erreur réseau'))
        end
        schedule_later(BETWEEN_SRV_SENDS_S, function()
            server_busy = false
            flush_server_queue()
        end)
    end)()
end

function send_cache_to_server(lc, zone, npc, text, xlat)
    if not SERVER_ENABLED then return end
    q_push(server_queue, { lc=lc, zone=zone, npc=npc, text=text, xlat=xlat })
    flush_server_queue()
end

local function flush_xlat_queue()
    if q_empty(xlat_queue) or xlat_busy then return end
    if clock() - last_xlat_time < BETWEEN_REQUESTS_S then return end
    last_xlat_time = clock()
    xlat_busy      = true

    local task = q_pop(xlat_queue)

    local lc = task.lang and task.lang.code
    if lc then
        local n_c = get_npc_cache(lc, task.zone, task.npc)
        if n_c[task.text] then
            if task.cb then task.cb(n_c[task.text]) end
            xlat_busy = false
            return
        end
    end

    local result = get_translation(task.text, task.lang, task.npc, task.zone)
    if task.cb then task.cb(result) end
    xlat_busy = false
end

windower.register_event('prerender', function()
    local now = clock()

    local q = sched_queue
    local i = q.head
    while i <= q.tail do
        local t = q[i]
        if t and now >= t.at then
            t.fn()
            q[i] = nil
            if i == q.head then q.head = q.head + 1 end
        end
        i = i + 1
    end
    if q.head > 100 then
        local nq = q_new()
        for j = q.head, q.tail do
            if q[j] then q_push(nq, q[j]) end
        end
        sched_queue = nq
    end

    flush_xlat_queue()
end)

function get_translation_async(text, lang, npc, zone, cb)
    q_push(xlat_queue, { text=text, lang=lang, npc=npc, zone=zone, cb=cb })
end
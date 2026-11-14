-- The Ninomae launcher's way into Steam: a mailbox in ~/.cache/ninomae-steam, in your home so only this
-- account can open it. Not in $XDG_RUNTIME_DIR: Steam runs in its runtime container (steamrt64), which has a
-- /run/user of its own the shell can't see. Home is the same folder inside and out.
-- (Flatpak Steam can't see ~/.cache either.)
--   requests/<id>.json   written by the shell (scripts/game-launcher/steam_control.py): {"cmd", "args"}
--   replies/<id>.json    written here once the frontend has run it: {"ok", "value"} or {"ok": false, "error"}
--   alive                "<now> <loaded>": the last check, so the shell knows Steam and this plugin are up,
--                        and when this copy was loaded, so it knows when Steam still runs an older one
--   wanted               touched by the shell while the launcher is open: then checks come quickly
-- The frontend calls poll() (every 0.15 s while wanted, else every 2 s) and runs what it returns (a fixed
-- list of commands, in .millennium/Dist/index.js), then hands each result to reply().
local logger = require("logger")
local millennium = require("millennium")
local fs = require("fs")

local home = os.getenv("HOME")
local dir = home and home ~= "" and (home .. "/.cache/ninomae-steam") or nil
local REQUEST_SECS = 15 -- An older request was left by a shell that gave up on it: never run it late
local WANTED_SECS = 5 -- The shell touches "wanted" every second or two while the launcher is open
local loaded = os.time()
local last_alive, last_sweep = 0, 0

local function write(path, text) -- Whole, or not at all: a temp file, then renamed over the old one
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(text)
    f:close()
    return os.rename(tmp, path) ~= nil
end

local function make_dirs() -- True once both folders are there (create_directories says false when they were)
    if not dir then return false end
    fs.create_directories(dir .. "/requests")
    fs.create_directories(dir .. "/replies")
    return fs.is_directory(dir .. "/requests") and fs.is_directory(dir .. "/replies")
end

local function remove_all_in(folder, older_than)
    local now = os.time()
    for _, entry in ipairs(fs.list(folder) or {}) do
        local at = older_than and fs.last_write_time(entry.path)
        if not older_than or (at and now - at > older_than) then os.remove(entry.path) end
    end
end

local function quote(s) -- A Lua string as a JSON string
    return '"' .. s:gsub('[%c"\\]', function(c)
        return c == '"' and '\\"' or c == "\\" and "\\\\" or string.format("\\u%04x", c:byte())
    end) .. '"'
end

-- {"fast": whether the shell wants quick checks, "requests": [{"id", "body"}]} (body: the request
-- file's text, parsed by the frontend one at a time). Each file leaves the queue as it's read
function poll()
    if not dir then return '{"fast":false,"requests":[]}' end
    local now = os.time()
    if now ~= last_alive then
        last_alive = now
        if not write(dir .. "/alive", now .. " " .. loaded) then make_dirs() end -- The folder went: again
    end
    if now - last_sweep >= 60 then -- Replies the shell stopped waiting for
        last_sweep = now
        remove_all_in(dir .. "/replies", 60)
    end
    local out = {}
    for _, entry in ipairs(fs.list(dir .. "/requests") or {}) do
        local id = entry.is_file and entry.name:match("^([%w_-]+)%.json$")
        if id then
            local at = fs.last_write_time(entry.path)
            local f = io.open(entry.path, "r")
            local body = f and f:read("*a")
            if f then f:close() end
            os.remove(entry.path)
            if body and body ~= "" and at and now - at <= REQUEST_SECS then
                out[#out + 1] = '{"id":"' .. id .. '","body":' .. quote(body) .. "}"
            end
        end
    end
    local wanted = fs.last_write_time(dir .. "/wanted")
    local fast = wanted ~= nil and now - wanted <= WANTED_SECS
    return '{"fast":' .. tostring(fast) .. ',"requests":[' .. table.concat(out, ",") .. "]}"
end

-- A request's result, from the frontend
function reply(a_id, b_result)
    if not dir or type(a_id) ~= "string" or not a_id:match("^[%w_-]+$") then return false end
    return write(dir .. "/replies/" .. a_id .. ".json", tostring(b_result))
end

local function on_load()
    if make_dirs() then
        remove_all_in(dir .. "/requests") -- Left from before Steam started: not run now
        logger:info("Ninomae mailbox: " .. dir)
    else
        logger:error("No mailbox (HOME unset or ~/.cache not writable): the Ninomae launcher can't reach Steam")
    end
    millennium.ready()
end

local function on_unload()
    if dir then os.remove(dir .. "/alive") end
end

return {
    on_load = on_load,
    on_unload = on_unload,
    on_frontend_loaded = function() end,
}

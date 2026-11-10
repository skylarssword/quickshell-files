-- ani_resume.lua: press "c" in mpv to save your spot and quit.
-- Also drops a "finished" marker when you quit at 90% or later, which the
-- anime hub uses for Auto (play the next episode).
-- Loaded by scripts/ani-backend, which passes the options below with --script-opts:
--   ani_resume-dir=<folder>  ani_resume-id=<anime id>  ani_resume-ep=<episode>
--   ani_resume-finished=<marker file>  ani_resume-mode=<sub|dub>
-- Optional: ani_resume-key=<key> to use a different key than "c",
--           ani_resume-threshold=<0-1> to change the 90% finished point.
local options = require "mp.options"

local o = { dir = "", id = "", ep = "", key = "c", finished = "", mode = "", threshold = 0.90 }
options.read_options(o, "ani_resume")

-- remember the last known position: properties can already be gone at shutdown
local last_pos, last_dur = nil, nil
mp.observe_property("time-pos", "number", function(_, v) if v then last_pos = v end end)
mp.observe_property("duration", "number", function(_, v) if v then last_dur = v end end)

local function is_finished()
    return last_pos ~= nil and last_dur ~= nil and last_dur > 0
        and (last_pos / last_dur) >= o.threshold
end

local function save_and_quit()
    local pos = mp.get_property_number("time-pos")
    local dur = mp.get_property_number("duration")

    if o.dir == "" or o.id == "" or o.ep == "" or not pos then
        mp.osd_message("ani-resume: nothing to save", 2)
        return
    end

    -- right at the start, or finished (90%+): nothing worth resuming, just quit
    if pos < 10 or is_finished() or (dur and dur - pos < 30) then
        mp.command("quit")
        return
    end

    local f = io.open(o.dir .. "/" .. o.id, "w")
    if not f then
        mp.osd_message("ani-resume: could not save", 2)
        return
    end
    -- back up 3s so you get a little context when you come back
    f:write(string.format("%s\t%d\n", o.ep, math.max(0, math.floor(pos) - 3)))
    f:close()

    mp.osd_message("Saved your spot", 1)
    mp.command("quit")
end

mp.add_key_binding(o.key, "save-and-quit", save_and_quit)

-- On any exit (q, c, window close, end of file): note it if the episode was finished.
-- Line format: id <TAB> episode <TAB> unix time <TAB> mode
mp.register_event("shutdown", function()
    if o.finished == "" or o.id == "" or o.ep == "" or not is_finished() then return end
    local f = io.open(o.finished, "w")
    if not f then return end
    f:write(string.format("%s\t%s\t%d\t%s\n", o.id, o.ep, os.time(), o.mode))
    f:close()
end)

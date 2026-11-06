-- ani_resume.lua: press "c" in mpv to save your spot and quit.
-- Loaded by scripts/ani-backend, which passes the options below with --script-opts:
--   ani_resume-dir=<folder>  ani_resume-id=<anime id>  ani_resume-ep=<episode>
-- Optional: ani_resume-key=<key> to use a different key than "c".
local options = require "mp.options"

local o = { dir = "", id = "", ep = "", key = "c" }
options.read_options(o, "ani_resume")

local function save_and_quit()
    local pos = mp.get_property_number("time-pos")
    local dur = mp.get_property_number("duration")

    if o.dir == "" or o.id == "" or o.ep == "" or not pos then
        mp.osd_message("ani-resume: nothing to save", 2)
        return
    end

    -- right at the start or the very end: nothing worth resuming, just quit
    if pos < 10 or (dur and dur - pos < 30) then
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

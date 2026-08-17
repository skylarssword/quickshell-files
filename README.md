ipc toggle keybinds (lua)

hl.bind("SUPER + SLASH",       hl.dsp.exec_cmd("qs ipc -p /usr/share/tide-island call tide toggleSearch"),              { description = "App search" })
hl.bind("SUPER + CTRL + W",    hl.dsp.exec_cmd("qs ipc -p /usr/share/tide-island call wallpaper-picker toggle"),       { description = "Wallpaper picker" })
hl.bind("SUPER + D", hl.dsp.exec_cmd("tide-search"), { description = "App search" })
hl.bind("SUPER + C", hl.dsp.exec_cmd("tide-controlcenter"), { description = "Control center" })
hl.bind("SUPER + P", hl.dsp.exec_cmd("tide-power"), { description = "Power menu" })
hl.bind("SUPER + N", hl.dsp.exec_cmd("tide-notifications"), { description = "Notifications" })
hl.bind("SUPER + ALT + I", hl.dsp.exec_cmd("qs ipc -p /usr/share/tide-island call focus-mode toggle"), { description = "Focus Mode" })


(no longer in use):
--hl.bind("SUPER + C",           hl.dsp.exec_cmd("qs ipc -p /usr/share/tide-island call tide toggleControlCenter"),      { description = "Control center" })
--hl.bind("SUPER + P",           hl.dsp.exec_cmd("qs ipc -p /usr/share/tide-island call tide togglePowerMenu"),          { description = "Power menu" })
--hl.bind("SUPER + N",           hl.dsp.exec_cmd("qs ipc -p /usr/share/tide-island call tide toggleNotificationCenter"), { description = "Notification center" })
--hl.bind("SUPER + D",           hl.dsp.exec_cmd("qs ipc -p /usr/share/tide-island call tide toggleSearch"),              { description = "App search (alt)" })

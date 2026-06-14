for i = 1, 27 do
    shell.run("wget",
        "https://raw.githubusercontent.com/AnarhyShop/zmpplayer/main/"..i..".dfpwm",
        i..".dfpwm")
end

shell.run("wget",
    "https://raw.githubusercontent.com/AnarhyShop/zmpplayer/main/play.lua",
    "play.lua")

shell.run("wget",
    "https://raw.githubusercontent.com/AnarhyShop/zmpplayer/main/gui_play.lua",
    "gui_play.lua")

shell.run("wget",
    "https://raw.githubusercontent.com/AnarhyShop/zmpplayer/main/make_disk.lua",
    "make_disk.lua")

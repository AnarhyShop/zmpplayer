local diskPath = "disk"
if not fs.exists(diskPath) or not fs.isDir(diskPath) then
    print("Error: No floppy disk found!")
    print("Please attach a Disk Drive and insert a floppy disk.")
    return
end

local function copyFiles()
    print("Cleaning disk...")
    for _, file in ipairs(fs.list(diskPath)) do
        fs.delete(fs.combine(diskPath, file))
    end

    print("Creating autorun startup.lua...")
    -- The code that will run when the disk is inserted/booted
    local startupCode = [=[
term.clear()
term.setCursorPos(1,1)
print("=======================================")
print("      CC Music Player Installer        ")
print("=======================================")
print("")

print("Installing player...")
if fs.exists("gui_play.lua") then fs.delete("gui_play.lua") end
fs.copy("disk/gui_play.lua", "gui_play.lua")

print("Installing music...")
if not fs.exists("music") then fs.makeDir("music") end
if fs.exists("disk/music") then
    for _, file in ipairs(fs.list("disk/music")) do
        local localPath = "music/" .. file
        if fs.exists(localPath) then fs.delete(localPath) end
        fs.copy("disk/music/" .. file, localPath)
    end
end

print("Setting up autorun on this computer...")
local file = fs.open("startup.lua", "w")
file.write("shell.run('gui_play.lua', 'music')\n")
file.close()

print("")
print("Installation Complete!")
print("You can now remove the floppy disk.")
print("The player will automatically launch on every reboot.")
print("Starting player in 3 seconds...")
sleep(3)
shell.run("gui_play.lua", "music")
]=]

    local file, err = fs.open(fs.combine(diskPath, "startup.lua"), "w")
    if not file then
        print("Failed to create startup.lua: " .. tostring(err))
        return false
    end
    file.write(startupCode)
    file.close()

    print("Copying player script...")
    if fs.exists("gui_play.lua") then
        fs.copy("gui_play.lua", fs.combine(diskPath, "gui_play.lua"))
    else
        print("Warning: gui_play.lua not found in current directory!")
        print("Please make sure you run this script in the same folder as gui_play.lua")
        return false
    end

    print("Copying music files...")
    fs.makeDir(fs.combine(diskPath, "music"))
    local musicCount = 0
    local out_of_space = false
    
    local function findMusic(dir)
        for _, file in ipairs(fs.list(dir)) do
            if out_of_space then break end
            
            local path = fs.combine(dir, file)
            if not fs.isDir(path) and file:match("%.dfpwm$") then
                print(" -> " .. file)
                -- Use pcall because floppy disks have strict space limits
                local ok, err = pcall(fs.copy, path, fs.combine(diskPath, "music/" .. file))
                if ok then
                    musicCount = musicCount + 1
                else
                    print("Error copying (Disk full?): " .. file)
                    out_of_space = true
                end
            elseif fs.isDir(path) and path ~= diskPath and path ~= "rom" then
                findMusic(path)
            end
        end
    end
    
    findMusic(shell.dir())
    
    if musicCount == 0 then
        if out_of_space then
            print("Warning: Disk ran out of space before copying any music.")
        else
            print("Warning: No .dfpwm files found to copy.")
        end
    else
        print("Copied " .. musicCount .. " songs.")
        if out_of_space then
            print("Note: Some songs were skipped because the floppy disk is full.")
        end
    end

    -- Rename the floppy disk
    local drive = peripheral.find("drive")
    if drive and drive.isDiskPresent() then
        pcall(drive.setDiskLabel, "Music Installer")
    end
    
    return true
end

if copyFiles() then
    print("---------------------------------------")
    print("Disk created successfully!")
    print("Take this floppy disk and insert it into any new computer.")
    print("Turn on the new computer, and it will install the player,")
    print("copy the music, set up autorun, and start playing!")
end

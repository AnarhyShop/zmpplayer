local args = {...}

if #args < 1 then
    print("Usage: play <file.dfpwm or URL>")
    print("Example: play music.dfpwm")
    print("Example: play https://example.com/music.dfpwm")
    return
end

local source = args[1]
local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")

if not speaker then
    print("Error: No speaker attached!")
    print("Please place a Speaker block next to the computer.")
    return
end

local decoder = dfpwm.make_decoder()

local function playLocal(file_path)
    if not fs.exists(file_path) then
        print("Error: File not found: " .. file_path)
        return
    end
    print("Playing local file: " .. file_path)
    
    -- Open file in binary mode
    local file = fs.open(file_path, "rb")
    if not file then
        print("Failed to open file.")
        return
    end
    
    while true do
        local chunk = file.read(16 * 1024)
        if not chunk then break end
        
        local buffer = decoder(chunk)
        while not speaker.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    
    file.close()
    print("Finished playing.")
end

local function playWeb(url)
    print("Buffering from URL: " .. url)
    local request, err = http.get(url, nil, true)
    
    if not request then
        print("Failed to download audio: " .. tostring(err))
        return
    end
    
    print("Playing...")
    while true do
        local chunk = request.read(16 * 1024)
        if not chunk or chunk == "" then break end
        
        local buffer = decoder(chunk)
        while not speaker.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    
    request.close()
    print("Finished playing.")
end

if source:match("^http://") or source:match("^https://") then
    playWeb(source)
else
    playLocal(source)
end

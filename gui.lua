local dfpwm = require("cc.audio.dfpwm")
local raw_speakers = {peripheral.find("speaker")}
local speakers = {}
local seen_names = {}
for _, spk in ipairs(raw_speakers) do
    local name = peripheral.getName and peripheral.getName(spk) or tostring(spk)
    if not seen_names[name] then
        seen_names[name] = true
        table.insert(speakers, spk)
    end
end

if #speakers == 0 then
    print("Error: No speakers found!")
    print("Place at least one speaker next to the computer or connect via modem.")
    return
end

local args = {...}
local baseUrl = "https://raw.githubusercontent.com/AnarhyShop/zmpplayer/main/"

local playlist = {}
for i = 1, 27 do
    playlist[#playlist + 1] = i .. ".dfpwm"
end

-- State variables
local currentSongIdx = 1
local isPlaying = true
local isPaused = false
local volume = 1.0
local exitProgram = false
local skipSong = false
local needRedraw = true
local volume_supported = true
local justUnpaused = false

local w, h = term.getSize()

local function stopAllSpeakers()
    for _, spk in ipairs(speakers) do
        pcall(spk.stop)
    end
end

local function drawUI()
    if not needRedraw then return end
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Title Bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    local title = "  CC Music Player (GUI)  "
    term.setCursorPos(math.floor((w - #title)/2) + 1, 1)
    term.write(title)
    
    -- Info
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.setCursorPos(2, 3)
    term.write("Speakers: " .. #speakers)
    
    term.setCursorPos(2, 4)
    term.write(string.format("Volume:   %d%%", math.floor(volume * 100)))
    
    -- Song Info
    term.setTextColor(colors.white)
    term.setCursorPos(2, 6)
    term.write(string.format("Track: [%d / %d]", currentSongIdx, #playlist))
    term.setCursorPos(2, 7)
    term.setTextColor(colors.yellow)
    local songName = playlist[currentSongIdx] or ""
    if #songName > w - 4 then songName = songName:sub(1, w - 7) .. "..." end
    term.write(songName)
    
    -- Status
    term.setCursorPos(2, 9)
    if not isPlaying then
        term.setTextColor(colors.red)
        term.write("[ STOPPED ]")
    elseif isPaused then
        term.setTextColor(colors.orange)
        term.write("[ PAUSED ]")
    else
        term.setTextColor(colors.lime)
        term.write("[ PLAYING ]")
    end
    
    -- Controls
    term.setTextColor(colors.white)
    term.setCursorPos(2, 11)
    
    if w < 34 then
        -- Compact layout
        term.setBackgroundColor(colors.green)
        term.write(" [P]lay/Pause ")
        term.setBackgroundColor(colors.black)
        term.write(" ")
        
        term.setBackgroundColor(colors.red)
        term.write(" [S]top ")
        
        term.setCursorPos(2, 13)
        term.setBackgroundColor(colors.cyan)
        term.write(" [N]ext ")
        
        term.setCursorPos(2, 15)
        term.setBackgroundColor(colors.gray)
        term.write(" [-] Vol ")
        term.setBackgroundColor(colors.black)
        term.write(" ")
        
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(" [+] Vol ")
    else
        -- Normal layout
        term.setBackgroundColor(colors.green)
        term.write(" [P]lay/Pause ")
        term.setBackgroundColor(colors.black)
        term.write("  ")
        
        term.setBackgroundColor(colors.red)
        term.write(" [S]top ")
        term.setBackgroundColor(colors.black)
        term.write("  ")
        
        term.setBackgroundColor(colors.cyan)
        term.write(" [N]ext ")
        
        term.setCursorPos(2, 13)
        term.setBackgroundColor(colors.gray)
        term.write(" [-] Vol ")
        term.setBackgroundColor(colors.black)
        term.write("  ")
        
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(" [+] Vol ")
    end
    
    -- Quit
    term.setCursorPos(w - 9, h)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(" [Q]uit ")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    needRedraw = false
end

local function uiLoop()
    while not exitProgram do
        drawUI()
        local eventData = {os.pullEvent()}
        local event = eventData[1]
        
        if event == "key" then
            local key = eventData[2]
            if key == keys.q then exitProgram = true; stopAllSpeakers() end
            if key == keys.p then 
                isPaused = not isPaused; isPlaying = true; needRedraw = true
                -- ВАЖНО: Убрано stopAllSpeakers() для идеальной паузы
                if not isPaused then justUnpaused = true end
            end
            if key == keys.s then isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; stopAllSpeakers() end
            if key == keys.n then skipSong = true; isPlaying = true; needRedraw = true; stopAllSpeakers() end
            if key == keys.minus then volume = math.max(0.0, volume - 0.1); needRedraw = true end
            if key == keys.equals or key == keys.plus then volume = math.min(3.0, volume + 0.1); needRedraw = true end
            
        elseif event == "char" then
            local char = string.lower(eventData[2])
            if char == "q" then exitProgram = true; stopAllSpeakers() end
            if char == "p" then 
                isPaused = not isPaused; isPlaying = true; needRedraw = true
                -- ВАЖНО: Убрано stopAllSpeakers() для идеальной паузы
                if not isPaused then justUnpaused = true end
            end
            if char == "s" then isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; stopAllSpeakers() end
            if char == "n" then skipSong = true; isPlaying = true; needRedraw = true; stopAllSpeakers() end
            if char == "-" then volume = math.max(0.0, volume - 0.1); needRedraw = true end
            if char == "+" or char == "=" then volume = math.min(3.0, volume + 0.1); needRedraw = true end
            
        elseif event == "mouse_click" then
            local x, y = eventData[3], eventData[4]
            if w < 34 then
                if y == 11 then
                    if x >= 2 and x <= 15 then 
                        isPaused = not isPaused; isPlaying = true; needRedraw = true
                        if not isPaused then justUnpaused = true end
                    end
                    if x >= 17 and x <= 24 then 
                        isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; stopAllSpeakers() 
                    end
                elseif y == 13 then
                    if x >= 2 and x <= 9 then 
                        skipSong = true; isPlaying = true; needRedraw = true; stopAllSpeakers() 
                    end
                elseif y == 15 then
                    if x >= 2 and x <= 10 then volume = math.max(0.0, volume - 0.1); needRedraw = true end
                    if x >= 12 and x <= 20 then volume = math.min(3.0, volume + 0.1); needRedraw = true end
                elseif y == h and x >= w - 9 then
                    exitProgram = true; stopAllSpeakers()
                end
            else
                if y == 11 then
                    if x >= 2 and x <= 15 then 
                        isPaused = not isPaused; isPlaying = true; needRedraw = true
                        if not isPaused then justUnpaused = true end
                    end
                    if x >= 18 and x <= 25 then 
                        isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; stopAllSpeakers() 
                    end
                    if x >= 28 and x <= 35 then 
                        skipSong = true; isPlaying = true; needRedraw = true; stopAllSpeakers() 
                    end
                elseif y == 13 then
                    if x >= 2 and x <= 10 then volume = math.max(0.0, volume - 0.1); needRedraw = true end
                    if x >= 13 and x <= 21 then volume = math.min(3.0, volume + 0.1); needRedraw = true end
                elseif y == h and x >= w - 9 then
                    exitProgram = true; stopAllSpeakers()
                end
            end
        end
    end
end

local function sendToSpeaker(spk, buffer, vol)
    if volume_supported then
        local ok, res = pcall(spk.playAudio, buffer, vol)
        if not ok then
            volume_supported = false
            local ok2, res2 = pcall(spk.playAudio, buffer)
            if ok2 then return res2 else return true end
        end
        return res
    else
        local ok2, res2 = pcall(spk.playAudio, buffer)
        if ok2 then return res2 else return true end
    end
end

local function playAudioChunk(buffer)
    local accepted = {}
    local success_count = 0
    local current_vol = volume
    
    while success_count < #speakers do
        if exitProgram or skipSong or isPaused then return end
        
        for i, spk in ipairs(speakers) do
            if not accepted[i] then
                local res = sendToSpeaker(spk, buffer, current_vol)
                if res then
                    accepted[i] = true
                    success_count = success_count + 1
                end
            end
        end
        
        if success_count < #speakers then
            local timer = os.startTimer(5.0)
            while true do
                local eventData = {os.pullEvent()}
                local ev = eventData[1]
                
                if ev == "speaker_audio_empty" then
                    os.cancelTimer(timer)
                    break
                elseif ev == "timer" and eventData[2] == timer then
                    return
                end
                
                if exitProgram or skipSong or isPaused then
                    os.cancelTimer(timer)
                    return
                end
            end
        end
    end
end

local function audioLoop()
    while not exitProgram do
        if isPlaying then
            local currentFile = playlist[currentSongIdx]
            local file = http.get(baseUrl .. currentFile, nil, true)
            
            if file then
                local decoder = dfpwm.make_decoder()
                stopAllSpeakers()
                sleep(0.3) 
                
                while not exitProgram and not skipSong and isPlaying do
                    if isPaused then
                        sleep(0.1)
                    else
                        if justUnpaused then
                            sleep(0.1) -- Уменьшил задержку, чтобы стартовало мягко
                            justUnpaused = false
                        end
                        
                        -- Оптимизированный размер: 8 КБ (1 секунда). Пауза будет срабатывать плавно.
                        local chunk = file.read(8 * 1024) 
                        if not chunk or chunk == "" then break end
                        
                        local buffer = decoder(chunk)
                        playAudioChunk(buffer)
                    end
                end
                file.close()
            end
            
            if exitProgram then break end
            
            if skipSong then
                sleep(0.1)
                currentSongIdx = currentSongIdx + 1
                if currentSongIdx > #playlist then currentSongIdx = 1 end
                skipSong = false
                needRedraw = true
            elseif not isPlaying then
                while not isPlaying and not exitProgram and not skipSong do
                    sleep(0.1)
                end
            elseif not isPaused then
                sleep(1.0)
                currentSongIdx = currentSongIdx + 1
                if currentSongIdx > #playlist then currentSongIdx = 1 end
                needRedraw = true
            end
        else
            sleep(0.1)
        end
    end
    
    stopAllSpeakers()
end

term.clear()
parallel.waitForAny(uiLoop, audioLoop)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Exited CC Music Player.")

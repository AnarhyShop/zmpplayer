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

-- Audio Sync trackers
local queued_chunks = 0
local chunk_timers = {}

local w, h = term.getSize()

-- Новая функция очистки, которая сбрасывает и колонки, и наши таймеры
local function clearAudioQueue()
    for _, spk in ipairs(speakers) do
        pcall(spk.stop)
    end
    queued_chunks = 0
    chunk_timers = {}
end

local function drawUI()
    if not needRedraw then return end
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    local title = "  CC Music Player (GUI)  "
    term.setCursorPos(math.floor((w - #title)/2) + 1, 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.setCursorPos(2, 3)
    term.write("Speakers: " .. #speakers)
    
    term.setCursorPos(2, 4)
    term.write(string.format("Volume:   %d%%", math.floor(volume * 100)))
    
    term.setTextColor(colors.white)
    term.setCursorPos(2, 6)
    term.write(string.format("Track: [%d / %d]", currentSongIdx, #playlist))
    term.setCursorPos(2, 7)
    term.setTextColor(colors.yellow)
    local songName = playlist[currentSongIdx] or ""
    if #songName > w - 4 then songName = songName:sub(1, w - 7) .. "..." end
    term.write(songName)
    
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
    
    term.setTextColor(colors.white)
    term.setCursorPos(2, 11)
    
    if w < 34 then
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
            if key == keys.q then exitProgram = true; clearAudioQueue() end
            if key == keys.p then 
                isPaused = not isPaused; isPlaying = true; needRedraw = true
                clearAudioQueue()
            end
            if key == keys.s then isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; clearAudioQueue() end
            if key == keys.n then skipSong = true; isPlaying = true; needRedraw = true; clearAudioQueue() end
            if key == keys.minus then volume = math.max(0.0, volume - 0.1); needRedraw = true end
            if key == keys.equals or key == keys.plus then volume = math.min(3.0, volume + 0.1); needRedraw = true end
            
        elseif event == "char" then
            local char = string.lower(eventData[2])
            if char == "q" then exitProgram = true; clearAudioQueue() end
            if char == "p" then 
                isPaused = not isPaused; isPlaying = true; needRedraw = true
                clearAudioQueue()
            end
            if char == "s" then isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; clearAudioQueue() end
            if char == "n" then skipSong = true; isPlaying = true; needRedraw = true; clearAudioQueue() end
            if char == "-" then volume = math.max(0.0, volume - 0.1); needRedraw = true end
            if char == "+" or char == "=" then volume = math.min(3.0, volume + 0.1); needRedraw = true end
            
        elseif event == "mouse_click" then
            local x, y = eventData[3], eventData[4]
            if w < 34 then
                if y == 11 then
                    if x >= 2 and x <= 15 then 
                        isPaused = not isPaused; isPlaying = true; needRedraw = true
                        clearAudioQueue()
                    end
                    if x >= 17 and x <= 24 then 
                        isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; clearAudioQueue() 
                    end
                elseif y == 13 then
                    if x >= 2 and x <= 9 then 
                        skipSong = true; isPlaying = true; needRedraw = true; clearAudioQueue() 
                    end
                elseif y == 15 then
                    if x >= 2 and x <= 10 then volume = math.max(0.0, volume - 0.1); needRedraw = true end
                    if x >= 12 and x <= 20 then volume = math.min(3.0, volume + 0.1); needRedraw = true end
                elseif y == h and x >= w - 9 then
                    exitProgram = true; clearAudioQueue()
                end
            else
                if y == 11 then
                    if x >= 2 and x <= 15 then 
                        isPaused = not isPaused; isPlaying = true; needRedraw = true
                        clearAudioQueue()
                    end
                    if x >= 18 and x <= 25 then 
                        isPlaying = false; isPaused = false; skipSong = true; needRedraw = true; clearAudioQueue() 
                    end
                    if x >= 28 and x <= 35 then 
                        skipSong = true; isPlaying = true; needRedraw = true; clearAudioQueue() 
                    end
                elseif y == 13 then
                    if x >= 2 and x <= 10 then volume = math.max(0.0, volume - 0.1); needRedraw = true end
                    if x >= 13 and x <= 21 then volume = math.min(3.0, volume + 0.1); needRedraw = true end
                elseif y == h and x >= w - 9 then
                    exitProgram = true; clearAudioQueue()
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
                clearAudioQueue()
                sleep(0.1)
                
                while not exitProgram and not skipSong and isPlaying do
                    if isPaused then
                        -- Во время паузы ждем событий, чтобы не нагружать сервер
                        local ev, p1 = os.pullEvent()
                        if ev == "timer" and chunk_timers[p1] then
                            chunk_timers[p1] = nil
                            queued_chunks = math.max(0, queued_chunks - 1)
                        end
                    else
                        -- Идеальная синхронизация: держим в очереди не больше 2 чанков (1 секунда звука)
                        while queued_chunks >= 2 do
                            local ev, p1 = os.pullEvent()
                            if ev == "timer" and chunk_timers[p1] then
                                chunk_timers[p1] = nil
                                queued_chunks = math.max(0, queued_chunks - 1)
                            end
                            if isPaused or skipSong or exitProgram then break end
                        end
                        
                        if not isPaused and not skipSong and not exitProgram then
                            local chunk = file.read(4096) 
                            if not chunk or chunk == "" then break end
                            
                            local buffer = decoder(chunk)
                            
                            for _, spk in ipairs(speakers) do
                                if volume_supported then
                                    local ok = pcall(spk.playAudio, buffer, volume)
                                    if not ok then
                                        volume_supported = false
                                        pcall(spk.playAudio, buffer)
                                    end
                                else
                                    pcall(spk.playAudio, buffer)
                                end
                            end
                            
                            -- Запускаем таймер ровно на длину чанка
                            local tid = os.startTimer(0.512)
                            chunk_timers[tid] = true
                            queued_chunks = queued_chunks + 1
                        end
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
                sleep(0.5)
                currentSongIdx = currentSongIdx + 1
                if currentSongIdx > #playlist then currentSongIdx = 1 end
                needRedraw = true
            end
        else
            sleep(0.1)
        end
    end
    
    clearAudioQueue()
end

term.clear()
parallel.waitForAny(uiLoop, audioLoop)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Exited CC Music Player.")

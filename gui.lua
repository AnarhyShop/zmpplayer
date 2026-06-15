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

-- Единая машина состояний (PLAYING, PAUSED, STOPPED)
local state = "PLAYING" 
local currentSongIdx = 1
local volume = 1.0
local exitProgram = false
local skipSong = false
local needRedraw = true
local volume_supported = true

-- Точное отслеживание позиции в файле для идеальной паузы
local currentByteOffset = 0 

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
    if state == "STOPPED" then
        term.setTextColor(colors.red)
        term.write("[ STOPPED ]")
    elseif state == "PAUSED" then
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

local function handleControl(action)
    if action == "playpause" then
        if state == "PLAYING" then state = "PAUSED" else state = "PLAYING" end
        needRedraw = true
    elseif action == "stop" then
        state = "STOPPED"
        skipSong = true
        needRedraw = true
        stopAllSpeakers()
    elseif action == "next" then
        state = "PLAYING"
        skipSong = true
        needRedraw = true
        stopAllSpeakers()
    elseif action == "voldown" then
        volume = math.max(0.0, volume - 0.1); needRedraw = true
    elseif action == "volup" then
        volume = math.min(3.0, volume + 0.1); needRedraw = true
    elseif action == "quit" then
        exitProgram = true; stopAllSpeakers()
    end
end

local function uiLoop()
    while not exitProgram do
        drawUI()
        local eventData = {os.pullEvent()}
        local event = eventData[1]
        
        if event == "key" then
            local key = eventData[2]
            if key == keys.q then handleControl("quit")
            elseif key == keys.p then handleControl("playpause")
            elseif key == keys.s then handleControl("stop")
            elseif key == keys.n then handleControl("next")
            elseif key == keys.minus then handleControl("voldown")
            elseif key == keys.equals or key == keys.plus then handleControl("volup") end
        elseif event == "char" then
            local char = string.lower(eventData[2])
            if char == "q" then handleControl("quit")
            elseif char == "p" then handleControl("playpause")
            elseif char == "s" then handleControl("stop")
            elseif char == "n" then handleControl("next")
            elseif char == "-" then handleControl("voldown")
            elseif char == "+" or char == "=" then handleControl("volup") end
        elseif event == "mouse_click" then
            local x, y = eventData[3], eventData[4]
            if w < 34 then
                if y == 11 then
                    if x >= 2 and x <= 15 then handleControl("playpause") end
                    if x >= 17 and x <= 24 then handleControl("stop") end
                elseif y == 13 and x >= 2 and x <= 9 then handleControl("next")
                elseif y == 15 then
                    if x >= 2 and x <= 10 then handleControl("voldown") end
                    if x >= 12 and x <= 20 then handleControl("volup") end
                elseif y == h and x >= w - 9 then handleControl("quit") end
            else
                if y == 11 then
                    if x >= 2 and x <= 15 then handleControl("playpause") end
                    if x >= 18 and x <= 25 then handleControl("stop") end
                    if x >= 28 and x <= 35 then handleControl("next") end
                elseif y == 13 then
                    if x >= 2 and x <= 10 then handleControl("voldown") end
                    if x >= 13 and x <= 21 then handleControl("volup") end
                elseif y == h and x >= w - 9 then handleControl("quit") end
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
        -- Прерываем ожидание, если поставили на паузу
        if exitProgram or skipSong or state ~= "PLAYING" then return end
        
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
                local ev, p1 = os.pullEvent()
                if ev == "speaker_audio_empty" then
                    os.cancelTimer(timer)
                    break
                elseif ev == "timer" and p1 == timer then
                    return
                end
                -- Чутко реагируем на кнопки интерфейса во время паузы
                if exitProgram or skipSong or state ~= "PLAYING" then
                    os.cancelTimer(timer)
                    return
                end
            end
        end
    end
end

local function audioLoop()
    while not exitProgram do
        if state == "PLAYING" then
            local currentFile = playlist[currentSongIdx]
            local headers = {}
            -- Магия докачки: запрашиваем файл с места остановки
            if currentByteOffset > 0 then
                headers["Range"] = "bytes=" .. currentByteOffset .. "-"
            end
            
            local res = http.get(baseUrl .. currentFile, headers, true)
            
            if res then
                local responseCode = res.getResponseCode()
                local file = res.handle
                local decoder = dfpwm.make_decoder()
                
                -- Подстраховка: если сервер проигнорировал Range, отматываем вручную
                if currentByteOffset > 0 and responseCode ~= 206 then
                    local to_discard = currentByteOffset
                    while to_discard > 0 do
                        local dump = file.read(math.min(to_discard, 16384))
                        if not dump or dump == "" then break end
                        to_discard = to_discard - #dump
                    end
                end
                
                while state == "PLAYING" and not skipSong and not exitProgram do
                    -- Читаем по 8 КБ (ровно 1 секунда звука). Идеально для плавности
                    local chunk = file.read(8 * 1024) 
                    if not chunk or chunk == "" then
                        skipSong = true -- Конец трека
                        break 
                    end
                    
                    currentByteOffset = currentByteOffset + #chunk
                    local buffer = decoder(chunk)
                    playAudioChunk(buffer)
                end
                file.close()
            else
                skipSong = true -- Ошибка скачивания, прыгаем на следующий
            end
            
            if skipSong then
                if state ~= "STOPPED" then
                    currentSongIdx = currentSongIdx + 1
                    if currentSongIdx > #playlist then currentSongIdx = 1 end
                    state = "PLAYING"
                end
                currentByteOffset = 0
                skipSong = false
                needRedraw = true
                stopAllSpeakers() -- Сбрасываем кэш колонок перед новым треком
            end
        else
            sleep(0.1) -- Режим ожидания
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

local dfpwm = require("cc.audio.dfpwm")

-- ==========================================
-- УМНАЯ СИСТЕМА ПЕРИФЕРИИ
-- ==========================================
local speakers = {}

local function scanPeripherals()
    local raw_spk = {peripheral.find("speaker")}
    local new_speakers = {}
    for _, spk in ipairs(raw_spk) do table.insert(new_speakers, spk) end
    speakers = new_speakers
end
scanPeripherals()

local function getMonitor()
    local mon = peripheral.find("monitor")
    -- ВКЛЮЧАЕМ МАСШТАБ 0.5 ДЛЯ ПОЛУЧЕНИЯ ВЫСОКОГО РАЗРЕШЕНИЯ НА МОНИТОРЕ
    if mon then pcall(mon.setTextScale, 0.5) end
    return mon
end

-- ==========================================
-- ЗАГРУЗКА ПЛЕЙЛИСТА (GITHUB API)
-- ==========================================
local baseUrl = "https://raw.githubusercontent.com/AnarhyShop/zmpplayer/main/"
local playlist = {}

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
term.write("Connecting to GitHub API...\n")
term.write("Scanning playlist 'zmpplayer'...\n")

local apiRes = http.get("https://api.github.com/repos/AnarhyShop/zmpplayer/contents/", {["User-Agent"]="CC-MusicPlayer"})
if apiRes then
    local data = textutils.unserializeJSON(apiRes.readAll())
    apiRes.close()
    if type(data) == "table" then
        for _, item in ipairs(data) do
            if item.type == "file" and item.name:match("%.dfpwm$") then
                table.insert(playlist, item.name)
            end
        end
    end
end

if #playlist == 0 then
    term.setTextColor(colors.red)
    term.write("API error. Using fallback (1-27)...\n")
    for i = 1, 27 do playlist[#playlist + 1] = i .. ".dfpwm" end
    os.sleep(2)
end

table.sort(playlist, function(a, b)
    local numA = tonumber(a:match("%d+"))
    local numB = tonumber(b:match("%d+"))
    if numA and numB then 
        if numA ~= numB then return numA < numB end
    elseif numA then return false
    elseif numB then return true end
    return a < b
end)

term.setTextColor(colors.lime)
term.write("Loaded " .. #playlist .. " tracks!\n")
os.sleep(1)

-- ==========================================
-- ЯДРО ПЛЕЕРА И GUI
-- ==========================================

local currentSongIdx = 1
local isPlaying = true
local isPaused = false
local volume = 1.0
local exitProgram = false
local trackChanged = false
local needRedraw = true
local volume_supported = true
local justUnpaused = false
local playlistOffset = 1

local function stopAllSpeakers()
    for _, spk in ipairs(speakers) do pcall(spk.stop) end
end

-- Функция рисует UI на КОНКРЕТНОМ экране (term или mon)
local function drawUIOnTarget(target)
    if not target then return end
    local w, h = target.getSize()
    
    target.setBackgroundColor(colors.black)
    target.clear()
    
    -- Title Bar
    target.setCursorPos(1, 1)
    target.setBackgroundColor(colors.blue)
    target.setTextColor(colors.white)
    target.clearLine()
    local title = "  CC Music Player (GUI)  "
    target.setCursorPos(math.floor((w - #title)/2) + 1, 1)
    target.write(title)
    
    -- Info
    target.setBackgroundColor(colors.black)
    target.setTextColor(colors.gray)
    target.setCursorPos(2, 3)
    target.write("Speakers: " .. #speakers)
    
    target.setCursorPos(2, 4)
    target.write(string.format("Volume:   %d%%", math.floor(volume * 100)))
    
    -- Song Info
    target.setTextColor(colors.white)
    target.setCursorPos(2, 6)
    target.write(string.format("Track: [%d / %d]", currentSongIdx, #playlist))
    target.setCursorPos(2, 7)
    target.setTextColor(colors.yellow)
    local songName = playlist[currentSongIdx] or ""
    if #songName > 22 then songName = songName:sub(1, 19) .. "..." end
    target.write(songName)
    
    -- Status
    target.setCursorPos(2, 9)
    if not isPlaying then
        target.setTextColor(colors.red)
        target.write("[ STOPPED ]")
    elseif isPaused then
        target.setTextColor(colors.orange)
        target.write("[ PAUSED ]")
    else
        target.setTextColor(colors.lime)
        target.write("[ PLAYING ]")
    end
    
    -- Controls Layout
    target.setTextColor(colors.white)
    target.setCursorPos(2, 11)
    target.setBackgroundColor(colors.green)
    target.write(" [P]lay/Pause ")
    target.setBackgroundColor(colors.black)
    target.write(" ")
    target.setBackgroundColor(colors.red)
    target.write(" [S]top ")
    
    target.setCursorPos(2, 12)
    target.setBackgroundColor(colors.cyan)
    target.write(" [B]ack ")
    target.setBackgroundColor(colors.black)
    target.write("       ")
    target.setBackgroundColor(colors.blue)
    target.write(" [N]ext ")
    
    target.setCursorPos(2, 14)
    target.setBackgroundColor(colors.gray)
    target.write(" [-] Vol ")
    target.setBackgroundColor(colors.black)
    target.write("       ")
    target.setBackgroundColor(colors.lightGray)
    target.setTextColor(colors.black)
    target.write(" [+] Vol ")
    
    -- ОПТИМИЗИРОВАННЫЙ ИНТЕРАКТИВНЫЙ ПЛЕЙЛИСТ (Порог снижен до 35)
    if w >= 35 then
        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.gray)
        for r = 2, h do
            target.setCursorPos(26, r)
            target.write("|")
        end
        
        target.setCursorPos(w - 4, 2)
        target.setBackgroundColor(colors.gray)
        target.setTextColor(colors.white)
        target.write(" [^] ")
        
        target.setCursorPos(w - 4, h - 1)
        target.setBackgroundColor(colors.gray)
        target.setTextColor(colors.white)
        target.write(" [v] ")
        
        local visibleRows = h - 4
        target.setBackgroundColor(colors.black)
        for i = 0, visibleRows - 1 do
            local songIdx = playlistOffset + i
            if songIdx <= #playlist then
                local row = 3 + i
                target.setCursorPos(28, row)
                local displayName = playlist[songIdx]:sub(1, w - 33)
                if songIdx == currentSongIdx then
                    target.setTextColor(colors.lime)
                    target.write(string.format("> %02d. %s", songIdx, displayName))
                else
                    target.setTextColor(colors.white)
                    target.write(string.format("  %02d. %s", songIdx, displayName))
                end
            end
        end
    end
    
    -- Quit
    target.setCursorPos(2, h)
    target.setBackgroundColor(colors.red)
    target.setTextColor(colors.white)
    target.write(" [Q]uit ")

    target.setBackgroundColor(colors.black)
    target.setTextColor(colors.white)
end

local function drawAllDisplays()
    if not needRedraw then return end
    drawUIOnTarget(term)
    local mon = getMonitor()
    if mon then drawUIOnTarget(mon) end
    needRedraw = false
end

local function scrollPlaylist(dir, screen_h)
    local visibleRows = screen_h - 4
    local maxOffset = math.max(1, #playlist - visibleRows + 1)
    if dir == "up" then
        playlistOffset = math.max(1, playlistOffset - 1)
    elseif dir == "down" then
        playlistOffset = math.min(maxOffset, playlistOffset + 1)
    end
    needRedraw = true
end

-- Автоматически определяет высоту активного экрана с плейлистом для клавиатуры
local function getPlaylistScreenHeight()
    local mon = getMonitor()
    if mon then
        return select(2, mon.getSize())
    end
    return select(2, term.getSize())
end

local function handleInteraction(x, y, w, h)
    if y == 11 then
        if x >= 2 and x <= 15 then 
            isPaused = not isPaused; isPlaying = true; needRedraw = true
            stopAllSpeakers()
            if not isPaused then justUnpaused = true end
        elseif x >= 17 and x <= 24 then 
            isPlaying = false; isPaused = false; trackChanged = true; needRedraw = true; stopAllSpeakers() 
        end
    elseif y == 12 then
        if x >= 2 and x <= 9 then
            currentSongIdx = currentSongIdx - 1
            if currentSongIdx < 1 then currentSongIdx = #playlist end
            trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers()
        elseif x >= 17 and x <= 24 then
            currentSongIdx = (currentSongIdx % #playlist) + 1
            trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers()
        end
    elseif y == 14 then
        if x >= 2 and x <= 10 then volume = math.max(0.0, volume - 0.1); needRedraw = true
        elseif x >= 17 and x <= 25 then volume = math.min(3.0, volume + 0.1); needRedraw = true end
    elseif y == h and x >= 2 and x <= 9 then
        exitProgram = true; stopAllSpeakers()
    end
    
    -- Обновлённые хитбоксы кликов по списку песен (x >= 28)
    if w >= 35 and x >= 28 then
        if y == 2 and x >= w - 5 then
            scrollPlaylist("up", h)
        elseif y == h - 1 and x >= w - 5 then
            scrollPlaylist("down", h)
        elseif y >= 3 and y <= h - 2 then
            local clickedIdx = playlistOffset + (y - 3)
            if clickedIdx <= #playlist then
                currentSongIdx = clickedIdx
                trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers()
            end
        end
    end
end

local function uiLoop()
    while not exitProgram do
        drawAllDisplays()
        local eventData = {os.pullEvent()}
        local event = eventData[1]
        
        if event == "peripheral" or event == "peripheral_detach" then
            scanPeripherals()
            stopAllSpeakers()
            needRedraw = true
            
        elseif event == "key" then
            local key = eventData[2]
            if key == keys.q then exitProgram = true; stopAllSpeakers() end
            if key == keys.p then 
                isPaused = not isPaused; isPlaying = true; needRedraw = true
                stopAllSpeakers()
                if not isPaused then justUnpaused = true end
            end
            if key == keys.s then isPlaying = false; isPaused = false; trackChanged = true; needRedraw = true; stopAllSpeakers() end
            if key == keys.n then 
                currentSongIdx = (currentSongIdx % #playlist) + 1
                trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers() 
            end
            if key == keys.b then 
                currentSongIdx = currentSongIdx - 1
                if currentSongIdx < 1 then currentSongIdx = #playlist end
                trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers()
            end
            if key == keys.minus then volume = math.max(0.0, volume - 0.1); needRedraw = true end
            if key == keys.equals or key == keys.plus then volume = math.min(3.0, volume + 0.1); needRedraw = true end
            if key == keys.up then scrollPlaylist("up", getPlaylistScreenHeight()) end
            if key == keys.down then scrollPlaylist("down", getPlaylistScreenHeight()) end
            
        elseif event == "mouse_click" then
            local x, y = eventData[3], eventData[4]
            local term_w, term_h = term.getSize()
            handleInteraction(x, y, term_w, term_h)
            
        elseif event == "monitor_touch" then
            local mon = getMonitor()
            if mon then
                local x, y = eventData[3], eventData[4]
                local mon_w, mon_h = mon.getSize()
                handleInteraction(x, y, mon_w, mon_h)
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
            return ok2 and res2 or false
        end
        return res
    else
        local ok, res = pcall(spk.playAudio, buffer)
        return ok and res or false
    end
end

local function playAudioChunk(buffer)
    local current_speakers = speakers
    local accepted = {}
    local success_count = 0
    local target_count = #current_speakers
    local current_vol = volume
    
    while success_count < target_count do
        if exitProgram or trackChanged or isPaused then return end
        
        for i, spk in ipairs(current_speakers) do
            if not accepted[i] then
                local res = sendToSpeaker(spk, buffer, current_vol)
                if res then
                    accepted[i] = true
                    success_count = success_count + 1
                end
            end
        end
        
        if success_count < target_count then
            local timer = os.startTimer(2.0) 
            while true do
                local eventData = {os.pullEvent()}
                local ev = eventData[1]
                
                if ev == "speaker_audio_empty" then
                    os.cancelTimer(timer)
                    break
                elseif ev == "timer" and eventData[2] == timer then
                    return
                end
                
                if exitProgram or trackChanged or isPaused then
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
                
                while not exitProgram and not trackChanged and isPlaying do
                    if isPaused then
                        sleep(0.1)
                    else
                        if justUnpaused then
                            sleep(0.3)
                            justUnpaused = false
                        end
                        
                        local chunk = file.read(16 * 1024) 
                        if not chunk or chunk == "" then break end
                        
                        local buffer = decoder(chunk)
                        
                        if #speakers == 0 then
                            sleep(0.5) 
                        else
                            playAudioChunk(buffer)
                        end
                    end
                end
                file.close()
            end
            
            if exitProgram then break end
            
            if trackChanged then
                sleep(0.1)
                trackChanged = false
                needRedraw = true
            elseif not isPlaying then
                while not isPlaying and not exitProgram and not trackChanged do
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

parallel.waitForAny(uiLoop, audioLoop)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

local endMon = peripheral.find("monitor")
if endMon then
    endMon.setBackgroundColor(colors.black)
    endMon.clear()
end

print("Exited CC Music Player.")
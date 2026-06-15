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

-- ==========================================
-- УМНАЯ ЗАГРУЗКА ПЛЕЙЛИСТА ЧЕРЕЗ GITHUB API
-- ==========================================
local baseUrl = "https://raw.githubusercontent.com/AnarhyShop/zmpplayer/main/"
local playlist = {}

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("Connecting to GitHub API...")
print("Scanning playlist 'zmpplayer'...")

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

-- Если API GitHub не ответил (например, лимит запросов), используем резерв
if #playlist == 0 then
    term.setTextColor(colors.red)
    print("API limit reached or error. Using fallback (1-27)...")
    for i = 1, 27 do playlist[#playlist + 1] = i .. ".dfpwm" end
    os.sleep(2)
end

-- Умная сортировка: "10" должно идти после "9", а не после "1"
table.sort(playlist, function(a, b)
    local numA = tonumber(a:match("%d+"))
    local numB = tonumber(b:match("%d+"))
    -- Если оба файла имеют номера, сортируем по номерам
    if numA and numB then 
        if numA ~= numB then return numA < numB end
    -- Если только один имеет номер, он идет в конец
    elseif numA then return false
    elseif numB then return true end
    -- Если номеров нет, сортируем по алфавиту
    return a < b
end)

term.setTextColor(colors.lime)
print("Loaded " .. #playlist .. " tracks!")
os.sleep(1)

-- ==========================================
-- ЯДРО ПЛЕЕРА И GUI
-- ==========================================

-- State variables
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
    if #songName > 24 then songName = songName:sub(1, 21) .. "..." end
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
    
    -- Controls Layout
    term.setTextColor(colors.white)
    term.setCursorPos(2, 11)
    term.setBackgroundColor(colors.green)
    term.write(" [P]lay/Pause ")
    term.setBackgroundColor(colors.black)
    term.write(" ")
    term.setBackgroundColor(colors.red)
    term.write(" [S]top ")
    
    term.setCursorPos(2, 12)
    term.setBackgroundColor(colors.cyan)
    term.write(" [B]ack ")
    term.setBackgroundColor(colors.black)
    term.write("       ")
    term.setBackgroundColor(colors.blue)
    term.write(" [N]ext ")
    
    term.setCursorPos(2, 14)
    term.setBackgroundColor(colors.gray)
    term.write(" [-] Vol ")
    term.setBackgroundColor(colors.black)
    term.write("       ")
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.write(" [+] Vol ")
    
    -- Интерактивный плейлист
    if w >= 38 then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        for r = 2, h do
            term.setCursorPos(28, r)
            term.write("|")
        end
        
        term.setCursorPos(w - 4, 2)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(" [^] ")
        
        term.setCursorPos(w - 4, h - 1)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(" [v] ")
        
        local visibleRows = h - 4
        term.setBackgroundColor(colors.black)
        for i = 0, visibleRows - 1 do
            local songIdx = playlistOffset + i
            if songIdx <= #playlist then
                local row = 3 + i
                term.setCursorPos(30, row)
                local displayName = playlist[songIdx]:sub(1, w - 36)
                if songIdx == currentSongIdx then
                    term.setTextColor(colors.lime)
                    term.write(string.format("> %02d. %s", songIdx, displayName))
                else
                    term.setTextColor(colors.white)
                    term.write(string.format("  %02d. %s", songIdx, displayName))
                end
            end
        end
    end
    
    -- Quit
    term.setCursorPos(2, h)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(" [Q]uit ")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    needRedraw = false
end

local function scrollPlaylist(dir)
    local visibleRows = h - 4
    local maxOffset = math.max(1, #playlist - visibleRows + 1)
    if dir == "up" then
        playlistOffset = math.max(1, playlistOffset - 1)
    elseif dir == "down" then
        playlistOffset = math.min(maxOffset, playlistOffset + 1)
    end
    needRedraw = true
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
            if key == keys.up then scrollPlaylist("up") end
            if key == keys.down then scrollPlaylist("down") end
            
        elseif event == "char" then
            local char = string.lower(eventData[2])
            if char == "q" then exitProgram = true; stopAllSpeakers() end
            if char == "p" then 
                isPaused = not isPaused; isPlaying = true; needRedraw = true
                stopAllSpeakers()
                if not isPaused then justUnpaused = true end
            end
            if char == "s" then isPlaying = false; isPaused = false; trackChanged = true; needRedraw = true; stopAllSpeakers() end
            if char == "n" then 
                currentSongIdx = (currentSongIdx % #playlist) + 1
                trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers() 
            end
            if char == "b" then 
                currentSongIdx = currentSongIdx - 1
                if currentSongIdx < 1 then currentSongIdx = #playlist end
                trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers()
            end
            if char == "-" then volume = math.max(0.0, volume - 0.1); needRedraw = true end
            if char == "+" or char == "=" then volume = math.min(3.0, volume + 0.1); needRedraw = true end
            
        elseif event == "mouse_click" then
            local x, y = eventData[3], eventData[4]
            
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
            
            if w >= 38 and x >= 30 then
                if y == 2 and x >= w - 5 then
                    scrollPlaylist("up")
                elseif y == h - 1 and x >= w - 5 then
                    scrollPlaylist("down")
                elseif y >= 3 and y <= h - 2 then
                    local clickedIdx = playlistOffset + (y - 3)
                    if clickedIdx <= #playlist then
                        currentSongIdx = clickedIdx
                        trackChanged = true; isPlaying = true; isPaused = false; needRedraw = true; stopAllSpeakers()
                    end
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
        if exitProgram or trackChanged or isPaused then return end
        
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
                        playAudioChunk(buffer)
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
print("Exited CC Music Player.")

-- ==========================================
-- BunkerOS v4.0 - Survival Desktop
-- ==========================================

local sw, sh = term.getSize()
local windows = {}
local draggingWin = nil
local dragX, dragY = 0, 0
local menuOpen = false

-- Функция создания окон разных типов
local function openApp(appType)
    local win = {
        x = math.random(2, 15),
        y = math.random(2, 8),
        w = 28,
        h = 12,
        type = appType,
        data = {}
    }
    
    if appType == "files" then
        win.title = "File Explorer"
        win.data.files = fs.list("/")
    elseif appType == "paint" then
        win.title = "Paint (Draw)"
        -- Создаем чистое полотно (цвета: 32768 - серый, 1 - белый)
        for i=1, win.w * (win.h-1) do win.data[i] = colors.lightGray end
    elseif appType == "browser" then
        win.title = "NetBox Browser"
        -- Приостанавливаем GUI для ввода URL
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1,1)
        term.setTextColor(colors.green)
        print("BUNKER-NET: Enter URL to download")
        write("http://")
        local url = "http://" .. read()
        
        print("Connecting...")
        local res = http.get(url)
        if res then
            local text = res.readAll():gsub("<[^>]+>", "") -- убираем HTML
            win.data.text = text:sub(1, 400) -- берем первые 400 символов
            res.close()
        else
            win.data.text = "Error: Connection lost or invalid URL."
        end
    end
    
    table.insert(windows, win)
end

local function draw()
    -- 1. Рабочий стол
    term.setBackgroundColor(colors.cyan)
    term.clear()
    
    -- 2. Отрисовка окон
    for i, win in ipairs(windows) do
        -- Заголовок
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.setCursorPos(win.x, win.y)
        term.write(string.rep(" ", win.w))
        term.setCursorPos(win.x + 1, win.y)
        term.write(win.title)
        
        -- Крестик (Закрыть)
        term.setCursorPos(win.x + win.w - 1, win.y)
        term.setBackgroundColor(colors.red)
        term.write("X")
        
        -- Тело окна
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        for j = 1, win.h - 1 do
            term.setCursorPos(win.x, win.y + j)
            term.write(string.rep(" ", win.w))
        end
        
        -- Контент в зависимости от приложения
        if win.type == "files" then
            for idx, file in ipairs(win.data.files) do
                if idx < win.h then
                    term.setCursorPos(win.x + 1, win.y + idx)
                    if fs.isDir(file) then term.setTextColor(colors.blue)
                    else term.setTextColor(colors.black) end
                    term.write("- " .. file)
                end
            end
            
        elseif win.type == "paint" then
            -- Отрисовка пикселей
            local p = 1
            for py = 1, win.h - 1 do
                term.setCursorPos(win.x, win.y + py)
                for px = 1, win.w do
                    term.setBackgroundColor(win.data[p] or colors.lightGray)
                    term.write(" ")
                    p = p + 1
                end
            end
            
        elseif win.type == "browser" then
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
            local currentY = win.y + 1
            for line in (win.data.text or ""):gmatch("([^\n]*)\n?") do
                if currentY < win.y + win.h and line ~= "" then
                    term.setCursorPos(win.x + 1, currentY)
                    term.write(line:sub(1, win.w - 2))
                    currentY = currentY + 1
                end
            end
        end
    end
    
    -- 3. Меню Пуск (если открыто)
    if menuOpen then
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.setCursorPos(1, sh - 4) term.write("               ")
        term.setCursorPos(1, sh - 3) term.write(" 1. Files      ")
        term.setCursorPos(1, sh - 2) term.write(" 2. NetBox     ")
        term.setCursorPos(1, sh - 1) term.write(" 3. Paint      ")
    end
    
    -- 4. Панель задач (Taskbar)
    term.setCursorPos(1, sh)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" [START]   BunkerOS Survival")
end

-- ==========================================
-- Основной цикл (Обработка мыши)
-- ==========================================
while true do
    draw()
    local event, button, cx, cy = os.pullEvent()
    
    if event == "mouse_click" then
        -- Клик по кнопке START
        if cy == sh and cx <= 8 then
            menuOpen = not menuOpen
        
        -- Клик по меню Пуск
        elseif menuOpen and cx <= 15 and cy >= sh - 3 and cy <= sh - 1 then
            menuOpen = false
            if cy == sh - 3 then openApp("files")
            elseif cy == sh - 2 then openApp("browser")
            elseif cy == sh - 1 then openApp("paint")
            end
            
        else
            menuOpen = false
            -- Проверка окон (сверху вниз)
            for i = #windows, 1, -1 do
                local win = windows[i]
                
                -- Если кликнули в пределах окна
                if cx >= win.x and cx < win.x + win.w and cy >= win.y and cy < win.y + win.h then
                    -- Перемещаем окно на передний план
                    table.remove(windows, i)
                    table.insert(windows, win)
                    
                    -- Клик по крестику (Закрыть)
                    if cy == win.y and cx == win.x + win.w - 1 then
                        table.remove(windows, #windows)
                    
                    -- Клик по заголовку (Начать перетаскивание)
                    elseif cy == win.y then
                        draggingWin = win
                        dragX = cx - win.x
                        dragY = cy - win.y
                    
                    -- Клик внутри приложения Paint (Рисование)
                    elseif win.type == "paint" then
                        local px = cx - win.x + 1
                        local py = cy - win.y
                        local pIndex = (py - 1) * win.w + px
                        if button == 1 then
                            win.data[pIndex] = colors.black -- Левый клик: черный
                        else
                            win.data[pIndex] = colors.lightGray -- Правый клик: ластик
                        end
                    end
                    
                    break
                end
            end
        end
        
    elseif event == "mouse_drag" then
        -- Перетаскивание окон
        if draggingWin then
            draggingWin.x = cx - dragX
            draggingWin.y = cy - dragY
        else
            -- Рисование с зажатой кнопкой в Paint
            if #windows > 0 then
                local win = windows[#windows]
                if win.type == "paint" and cx >= win.x and cx < win.x + win.w and cy > win.y and cy < win.y + win.h then
                    local px = cx - win.x + 1
                    local py = cy - win.y
                    local pIndex = (py - 1) * win.w + px
                    if button == 1 then win.data[pIndex] = colors.black
                    else win.data[pIndex] = colors.lightGray end
                end
            end
        end
        
    elseif event == "mouse_up" then
        draggingWin = nil
        
    elseif event == "char" and button == "q" then
        -- Выход из ОС (нажать q)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1,1)
        print("BunkerOS safely shutdown.")
        break
    end
end
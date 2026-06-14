local repo = "AnarhyShop/zmpplayer"

local response = http.get("https://api.github.com/repos/" .. repo .. "/contents")
if not response then
    error("Не удалось получить список файлов")
end

local files = textutils.unserializeJSON(response.readAll())
response.close()

for _, file in ipairs(files) do
    if file.name:match("%.dfpwm$") then
        print("Скачиваю " .. file.name)
        shell.run("wget", file.download_url, file.name)
    end
end

print("Готово!")
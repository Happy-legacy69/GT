script_name("Google Table")
script_author("legaсу")
script_version("1.13")

local fa = require('fAwesome6_solid')
local imgui = require 'mimgui'
local encoding = require 'encoding'
local ffi = require 'ffi'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local renderWindow = imgui.new.bool(false)
local sheetData = nil
local lastGoodSheetData = nil
local isLoading = false
local firstLoadComplete = false
local searchQuery = imgui.new.char[128]()

local csvURL = "https://docs.google.com/spreadsheets/d/1WyZy0jQbnZIbV82wF2vT4R6lDPl4zfP_HzfRDYRMPo4/export?format=csv&gid=0"
local updateUrl = "https://raw.githubusercontent.com/Happy-legacy69/GT/refs/heads/main/update.json"

-- Система автообновления
local function checkForUpdate()
    local tmpFile = os.tmpname() .. ".json"
    downloadUrlToFile(updateUrl, tmpFile, function(success)
        if not success then
            sampAddChatMessage("[GT] Не удалось проверить обновление.", -1)
            return
        end

        local file = io.open(tmpFile, "r")
        if not file then return end
        local content = file:read("*a")
        file:close()
        os.remove(tmpFile)

        local ok, json = pcall(decodeJson, content)
        if not ok or not json or not json.version or not json.script_url then
            sampAddChatMessage("[GT] Неверный формат update.json", -1)
            return
        end

        if json.version ~= thisScript().version then
            sampAddChatMessage("[GT] Доступна новая версия: " .. json.version .. ", обновляем...", -1)
            local tmpLua = os.tmpname() .. ".lua"
            downloadUrlToFile(json.script_url, tmpLua, function(ok)
                if ok then
                    local src = io.open(tmpLua, "r")
                    local dst = io.open(thisScript().path, "w+")
                    if src and dst then
                        dst:write(src:read("*a"))
                        dst:close()
                        src:close()
                        os.remove(tmpLua)
                        sampAddChatMessage("[GT] Скрипт обновлён. Перезапустите скрипт или игру.", -1)
                    else
                        sampAddChatMessage("[GT] Ошибка при записи нового скрипта.", -1)
                    end
                else
                    sampAddChatMessage("[GT] Ошибка загрузки новой версии.", -1)
                end
            end)
        else
            sampAddChatMessage("[GT] Установлена последняя версия скрипта.", -1)
        end
    end)
end

local function theme()
    local s = imgui.GetStyle()
    local c = imgui.Col
    local clr = s.Colors
    s.WindowRounding = 0
    s.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    s.ChildRounding = 0
    s.FrameRounding = 5.0
    s.ItemSpacing = imgui.ImVec2(10, 10)
    clr[c.Text] = imgui.ImVec4(0.85, 0.86, 0.88, 1)
    clr[c.WindowBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.ChildBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.Button] = imgui.ImVec4(0.10, 0.15, 0.18, 1)
    clr[c.ButtonHovered] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.ButtonActive] = clr[c.ButtonHovered]
    clr[c.FrameBg] = imgui.ImVec4(0.10, 0.15, 0.18, 1)
    clr[c.FrameBgHovered] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.FrameBgActive] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.Separator] = imgui.ImVec4(0.20, 0.25, 0.30, 1)
    clr[c.TitleBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.TitleBgActive] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.TitleBgCollapsed] = imgui.ImVec4(0.05, 0.08, 0.10, 0.75)
    s.ScrollbarSize = 18
    s.ScrollbarRounding = 0
    s.GrabRounding = 0
    s.GrabMinSize = 38
    clr[c.ScrollbarBg] = imgui.ImVec4(0.04, 0.06, 0.07, 0.8)
    clr[c.ScrollbarGrab] = imgui.ImVec4(0.15, 0.15, 0.18, 1.0)
    clr[c.ScrollbarGrabHovered] = imgui.ImVec4(0.25, 0.25, 0.28, 1.0)
    clr[c.ScrollbarGrabActive] = imgui.ImVec4(0.35, 0.35, 0.38, 1.0)
end

imgui.OnInitialize(function()
    if MONET_DPI_SCALE == nil then MONET_DPI_SCALE = 1.0 end
    fa.Init(14 * MONET_DPI_SCALE)
    theme()
    imgui.GetIO().IniFilename = nil
end)

local function CenterText(text)
    local windowWidth = imgui.GetWindowSize().x
    local textWidth = imgui.CalcTextSize(text).x
    imgui.SetCursorPosX((windowWidth - textWidth) * 0.5)
    imgui.Text(text)
end

local function CenterTextInColumn(text)
    local columnWidth = imgui.GetColumnWidth()
    local textWidth = imgui.CalcTextSize(text).x
    imgui.SetCursorPosX(imgui.GetCursorPosX() + (columnWidth - textWidth) * 0.5)
    imgui.Text(text)
end

local function parseCSV(data)
    local rows = {}
    for line in data:gmatch("[^\r\n]+") do
        local row, i, inQuotes, cell = {}, 1, false, ''
        for c in (line .. ','):gmatch('.') do
            if c == '"' then inQuotes = not inQuotes
            elseif c == ',' and not inQuotes then
                row[i] = cell:gsub('^%s*"(.-)"%s*$', '%1'):gsub('""', '"')
                i = i + 1
                cell = ''
            else cell = cell .. c end
        end
        table.insert(rows, row)
    end
    return rows
end

local function drawSpinner()
    local center = imgui.GetWindowPos() + imgui.GetWindowSize() * 0.5
    local radius, thickness, segments = 32.0, 3.0, 30
    local time = imgui.GetTime()
    local angle_offset = (time * 3) % (2 * math.pi)
    local drawList = imgui.GetWindowDrawList()

    for i = 0, segments - 1 do
        local a0 = i / segments * 2 * math.pi
        local a1 = (i + 1) / segments * 2 * math.pi
        local alpha = i / segments
        if alpha > 0.25 and alpha < 0.75 then
            local x0 = center.x + radius * math.cos(a0 + angle_offset)
            local y0 = center.y + radius * math.sin(a0 + angle_offset)
            local x1 = center.x + radius * math.cos(a1 + angle_offset)
            local y1 = center.y + radius * math.sin(a1 + angle_offset)
            drawList:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1), imgui.GetColorU32(imgui.Col.Text), thickness)
        end
    end
end

local function drawTable(data)
    if not firstLoadComplete then
        drawSpinner()
        CenterText(u8"Загрузка таблицы...")
        return
    end

    if not data or #data == 0 then return end

    local filtered = {}
    local query = ffi.string(searchQuery)
    for i = 2, #data do
        local row = data[i]
        local cell = tostring(row[1] or "")
        if string.lower(u8:encode(cell)):find(string.lower(u8:encode(query)), 1, true) then
            table.insert(filtered, row)
        end
    end

    imgui.BeginChild("scrollingRegion", imgui.ImVec2(-1, -1), true)
    if #filtered == 0 then
        drawSpinner()
        imgui.Dummy(imgui.ImVec2(0, 40))
        CenterText(u8"Совпадений нет")
        imgui.EndChild()
        return
    end

    local regionWidth = imgui.GetContentRegionAvail().x
    local columnWidth = regionWidth / 3
    local pos = imgui.GetCursorScreenPos()
    local y0 = pos.y - imgui.GetStyle().ItemSpacing.y
    local y1 = pos.y + imgui.GetContentRegionAvail().y + imgui.GetScrollMaxY() + 7
    local x1, x2 = pos.x + columnWidth, pos.x + 2 * columnWidth

    local draw = imgui.GetWindowDrawList()
    local sepColor = imgui.GetColorU32(imgui.Col.Separator)
    draw:AddLine(imgui.ImVec2(x1, y0), imgui.ImVec2(x1, y1), sepColor, 1)
    draw:AddLine(imgui.ImVec2(x2, y0), imgui.ImVec2(x2, y1), sepColor, 1)

    imgui.Columns(3, nil, false)
    for i = 1, 3 do
        CenterTextInColumn(tostring(data[1][i] or ""))
        imgui.NextColumn()
    end
    imgui.Separator()

    for _, row in ipairs(filtered) do
        for col = 1, 3 do
            CenterTextInColumn(tostring(row[col] or ""))
            imgui.NextColumn()
        end
        imgui.Separator()
    end
    imgui.Columns(1)
    imgui.EndChild()
end

local function updateCSV()
    isLoading, firstLoadComplete = true, false
    local tmpPath = os.tmpname() .. ".csv"
    downloadUrlToFile(csvURL, tmpPath, function(success)
        if success then
            local f = io.open(tmpPath, "r")
            if f then
                local content = f:read("*a")
                f:close()
                sheetData = parseCSV(content)
                lastGoodSheetData = sheetData
                os.remove(tmpPath)
            else sheetData = lastGoodSheetData end
        else sheetData = lastGoodSheetData end
        isLoading, firstLoadComplete = false, true
    end)
end

imgui.OnFrame(function() return renderWindow[0] end, function()
    local sx, sy = getScreenResolution()
    local w, h = math.min(900, sx - 50), 500
    imgui.SetNextWindowPos(imgui.ImVec2((sx - w) / 2, (sy - h) / 2), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.FirstUseEver)

    if imgui.Begin(fa.EYE .. ' Google Table by legacy.', renderWindow) then
        local availableWidth = imgui.GetContentRegionAvail().x
        imgui.PushItemWidth(availableWidth * 0.7)
        imgui.InputTextWithHint("##Search", u8("Введите товар для поиска по Google Table"), searchQuery, ffi.sizeof(searchQuery))
        imgui.PopItemWidth()
        imgui.SameLine()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.15, 0.20, 0.23, 0.3))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.20, 0.23, 0.5))
        if imgui.SmallButton(fa.ERASER) then
            ffi.fill(searchQuery, ffi.sizeof(searchQuery))
        end
        imgui.PopStyleColor(3)
        if imgui.IsItemHovered() then imgui.SetTooltip(u8"Очистить поиск") end

        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.15, 0.20, 0.23, 0.3))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.20, 0.23, 0.5))
        if imgui.SmallButton(fa.MAGNIFYING_GLASS) then updateCSV() end
        imgui.PopStyleColor(3)
        if imgui.IsItemHovered() then imgui.SetTooltip(u8"Обновить таблицу") end

        imgui.Spacing()
        drawTable(sheetData)
        imgui.End()
    end
end)

function main()
    while not isSampAvailable() do wait(0) end
    checkForUpdate()
    sampAddChatMessage("{00FF00}[GT]{FFFFFF} Скрипт загружен. Для активации используйте {00FF00}/gt", 0xFFFFFF)
    sampRegisterChatCommand('gt', function()
        renderWindow[0] = not renderWindow[0]
        if renderWindow[0] then updateCSV() end
    end)
    wait(-1)
end

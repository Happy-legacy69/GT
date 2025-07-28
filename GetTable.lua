script_name("Google Table")
script_author("legaсу")
script_version("1.13")

local fa = require('fAwesome6_solid')
local imgui = require 'mimgui'
local encoding = require 'encoding'
local ffi = require 'ffi'
local json = require 'json'
local dlstatus = require('moonloader').download_status
local moonloader = require("moonloader")

encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- Переменные
local renderWindow = imgui.new.bool(false)
local sheetData = nil
local lastGoodSheetData = nil
local isLoading = false
local firstLoadComplete = false
local searchQuery = imgui.new.char[128]()
local updateChecked = false
local updateUrl = "https://raw.githubusercontent.com/Happy-legacy69/GT/refs/heads/main/update.json" -- <= Укажи свой

local csvURL = "https://docs.google.com/spreadsheets/d/1WyZy0jQbnZIbV82wF2vT4R6lDPl4zfP_HzfRDYRMPo4/export?format=csv&gid=0"

-- === UI и логика ===
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

-- Центрирование
local function CenterText(text)
    local w = imgui.GetWindowSize().x
    local tw = imgui.CalcTextSize(text).x
    if w > tw then imgui.SetCursorPosX((w - tw) / 2) end
    imgui.Text(text)
end

local function CenterTextInColumn(text)
    local colW = imgui.GetColumnWidth()
    local txtW = imgui.CalcTextSize(text).x
    if colW > txtW then imgui.SetCursorPosX(imgui.GetCursorPosX() + (colW - txtW) * 0.5) end
    imgui.Text(text)
end

-- CSV парсинг
local function parseCSV(data)
    local rows = {}
    for line in data:gmatch("[^\r\n]+") do
        local row, i, inQuotes, cell = {}, 1, false, ''
        for c in (line .. ','):gmatch('.') do
            if c == '"' then
                inQuotes = not inQuotes
            elseif c == ',' and not inQuotes then
                row[i] = cell:gsub('^%s*"(.-)"%s*$', '%1'):gsub('""', '"')
                i = i + 1
                cell = ''
            else
                cell = cell .. c
            end
        end
        table.insert(rows, row)
    end
    return rows
end

local function drawSpinner()
    local center = imgui.GetWindowPos() + imgui.GetWindowSize() * 0.5
    local radius, thickness, segments = 32.0, 3.0, 30
    local angle_offset = (imgui.GetTime() * 3) % (2 * math.pi)
    local drawList = imgui.GetWindowDrawList()

    for i = 0, segments - 1 do
        local a0 = i / segments * 2 * math.pi
        local a1 = (i + 1) / segments * 2 * math.pi
        local alpha = (i / segments)
        if alpha > 0.25 and alpha < 0.75 then
            local x0 = center.x + radius * math.cos(a0 + angle_offset)
            local y0 = center.y + radius * math.sin(a0 + angle_offset)
            local x1 = center.x + radius * math.cos(a1 + angle_offset)
            local y1 = center.y + radius * math.sin(a1 + angle_offset)
            drawList:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1), imgui.GetColorU32(imgui.Col.Text), thickness)
        end
    end
end

-- Таблица
local function drawTable(data)
    if not firstLoadComplete then drawSpinner() CenterText(u8"Загрузка таблицы...") return end
    if not data or #data == 0 then return end

    local filtered, query = {}, ffi.string(searchQuery)
    for i = 2, #data do
        local cell = tostring(data[i][1] or "")
        if string.lower(u8:encode(cell)):find(string.lower(u8:encode(query)), 1, true) then
            table.insert(filtered, data[i])
        end
    end

    imgui.BeginChild("scrollingRegion", imgui.ImVec2(-1, -1), true)
    if #filtered == 0 then drawSpinner() imgui.Dummy(imgui.ImVec2(0, 40)) CenterText(u8"Совпадений нет") imgui.EndChild() return end

    local colW = imgui.GetContentRegionAvail().x / 3
    local pos = imgui.GetCursorScreenPos()
    local y0 = pos.y - imgui.GetStyle().ItemSpacing.y
    local y1 = pos.y + imgui.GetContentRegionAvail().y + imgui.GetScrollMaxY() + 7
    local draw = imgui.GetWindowDrawList()
    local sep = imgui.GetColorU32(imgui.Col.Separator)
    draw:AddLine(imgui.ImVec2(pos.x + colW, y0), imgui.ImVec2(pos.x + colW, y1), sep, 1)
    draw:AddLine(imgui.ImVec2(pos.x + 2 * colW, y0), imgui.ImVec2(pos.x + 2 * colW, y1), sep, 1)

    imgui.Columns(3, nil, false)
    for i = 1, 3 do CenterTextInColumn(tostring(data[1][i] or "")) imgui.NextColumn() end
    imgui.Separator()
    for _, row in ipairs(filtered) do
        for i = 1, 3 do CenterTextInColumn(tostring(row[i] or "")) imgui.NextColumn() end
        imgui.Separator()
    end
    imgui.Columns(1)
    imgui.EndChild()
end

-- Загрузка таблицы
local function updateCSV()
    isLoading = true
    firstLoadComplete = false
    local tmp = os.tmpname() .. ".csv"
    downloadUrlToFile(csvURL, tmp, function(success)
        if success then
            local f = io.open(tmp, "r")
            if f then
                local content = f:read("*a")
                f:close()
                sheetData = parseCSV(content)
                lastGoodSheetData = sheetData
                os.remove(tmp)
            else
                sheetData = lastGoodSheetData
            end
        else
            sheetData = lastGoodSheetData
        end
        isLoading = false
        firstLoadComplete = true
    end)
end

-- Проверка обновления
local function checkForUpdate()
    if updateChecked then return end
    updateChecked = true
    local tmp = os.tmpname() .. ".json"
    downloadUrlToFile(updateUrl, tmp, function(success)
        if success then
            local f = io.open(tmp, "r")
            if f then
                local body = f:read("*a")
                f:close()
                local parsed = json.decode(body)
                local remote = tonumber(parsed.version)
                local current = tonumber(getScriptVersion():match("([%d%.]+)"))
                if remote and current and remote > current then
                    local scriptPath = thisScript().path
                    downloadUrlToFile(parsed.update_url, scriptPath, function(updated)
                        if updated then
                            sampAddChatMessage("{FFFF00}[GT] Доступна новая версия. Скрипт обновлён, перезапустите игру.", 0xFFFFFF)
                        else
                            sampAddChatMessage("{FF0000}[GT] Не удалось обновить скрипт.", 0xFFFFFF)
                        end
                    end)
                end
                os.remove(tmp)
            end
        end
    end)
end

-- UI
imgui.OnFrame(function() return renderWindow[0] end, function()
    local sx, sy = getScreenResolution()
    local w, h = math.min(900, sx - 50), 500
    imgui.SetNextWindowPos(imgui.ImVec2((sx - w) / 2, (sy - h) / 2), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.FirstUseEver)

    if imgui.Begin(fa.EYE .. ' Google Table by legacy.', renderWindow) then
        local avail = imgui.GetContentRegionAvail().x
        imgui.PushItemWidth(avail * 0.7)
        imgui.InputTextWithHint("##Search", u8("Введите товар для поиска по Google Table"), searchQuery, ffi.sizeof(searchQuery))
        imgui.PopItemWidth()
        imgui.SameLine()
        if imgui.SmallButton(fa.ERASER) then ffi.fill(searchQuery, ffi.sizeof(searchQuery)) end
        imgui.SameLine()
        if imgui.SmallButton(fa.MAGNIFYING_GLASS) then updateCSV() end
        imgui.Spacing()
        drawTable(sheetData)
        imgui.End()
    end
end)

-- Главный поток
function main()
    while not isSampAvailable() do wait(0) end
    sampAddChatMessage("{00FF00}[GT]{FFFFFF} Скрипт загружен. Для активации используйте {00FF00}/gt", 0xFFFFFF)
    checkForUpdate()
    sampRegisterChatCommand("gt", function()
        renderWindow[0] = not renderWindow[0]
        if renderWindow[0] then updateCSV() end
    end)
    wait(-1)
end

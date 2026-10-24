WorldLibrary = WorldLibrary or {}
-- ============================================================================
-- 1. UTILITIES & DATABASE HELPERS
-- ============================================================================
local libraryFrame = nil
local selectedTitle = nil
local currentTitle = nil
local BookDB = {}

local FONT_SIZES = {
    { label = "Small",  size = 12 },
    { label = "Medium", size = 14 },
    { label = "Large",  size = 18 }
}

local function GetFontSizeIndex()
    if BookDB and BookDB.fontSizeIndex then
        return BookDB.fontSizeIndex
    end
    return 2 -- Default to Medium
end

local function GetFullBookText(title)
    if not BookDB or not BookDB[title] then return "No text recorded." end

    local bookData = BookDB[title]
    local header = ""

    -- Add Location Header if available
    if bookData.location then
        header = "|cFF808080Found in: " .. bookData.location .. "|r\n\n"
    end

    if bookData.pages and next(bookData.pages) then
        local maxPage = 0
        for pNum, _ in pairs(bookData.pages) do
            if type(pNum) == "number" and pNum > maxPage then maxPage = pNum end
        end

        local combinedText = ""
        for i = 1, maxPage do
            local pText = bookData.pages[i]
            if pText and pText ~= "" then
                if combinedText ~= "" then
                    combinedText = combinedText .. "\n\n"
                end
                combinedText = combinedText .. pText
            end
        end

        if combinedText ~= "" then return header .. combinedText end
    end

    return header .. "No text recorded."
end

local function SaveBookTitleAndLocation()
    local title = ItemTextGetItem()

    if not title or title == "" then
        title = currentTitle or "Unknown Document"
    else
        currentTitle = title
    end

    -- Initialize book entry if it doesn't exist yet
    if not BookDB[title] then
        -- Capture location details safely using modern C_Map APIs
        local zone = GetRealZoneText() or "Unknown Zone"
        local subZone = GetMinimapZoneText() or ""
        local posX, posY = 0, 0

        if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID then
                local pos = C_Map.GetPlayerMapPosition(mapID, "player")
                if pos and pos.x and pos.y then
                    posX, posY = pos.x * 100, pos.y * 100
                end
            end
        end

        local locationStr = zone
        if subZone ~= "" and subZone ~= zone then
            locationStr = locationStr .. " (" .. subZone .. ")"
        end
        if posX > 0 or posY > 0 then
            locationStr = string.format("%s [%.1f, %.1f]", locationStr, posX, posY)
        end

        BookDB[title] = {
            pages = {},
            timestamp = date("%Y-%m-%d %H:%M:%S"),
            location = locationStr
        }
        print("|cFF00FF00[Book]|r Recording new book: " .. title)
    end

    return title
end

local function SaveCurrentPage(title)
    local pageText = ItemTextGetText()
    local pageNum = ItemTextGetPage()

    if not pageText or pageText == "" then return end

    if type(BookDB[title].pages) ~= "table" then
        BookDB[title].pages = {}
    end

    -- Early exit: If this page is already saved, do nothing more
    if BookDB[title].pages[pageNum] then return end

    -- Otherwise, save the new page
    BookDB[title].pages[pageNum] = pageText
    print("|cFF00FF00[Book]|r Recorded page " .. pageNum .. " for " .. title)
end


-- ============================================================================
-- 2. USER INTERFACE (BOOK VIEWER)
-- ============================================================================
local function UpdateFontSize()
    if not libraryFrame then return end

    local fontIdx = GetFontSizeIndex()
    local fontConfig = FONT_SIZES[fontIdx]

    -- Update body text font size
    if libraryFrame.bodyText then
        local fontFile, _, fontFlags = libraryFrame.bodyText:GetFont()
        if fontFile then
            libraryFrame.bodyText:SetFont(fontFile, fontConfig.size, fontFlags)
        end
    end

    if libraryFrame.sizeBtn then
        libraryFrame.sizeBtn:SetText("Text: " .. fontConfig.label)
    end

    -- Fully refresh the list layout to re-anchor rows with proper spacing
    if libraryFrame.RefreshList then
        libraryFrame.RefreshList()
    end

    -- Safely update layout height on next frame pass once text height resolves
    C_Timer.After(0, function()
        if libraryFrame and libraryFrame.textContent and libraryFrame.bodyText then
            local textHeight = libraryFrame.bodyText:GetStringHeight() or 0
            local targetHeight = math.max(textHeight + 40, 400)
            libraryFrame.textContent:SetHeight(targetHeight)
        end
    end)
end

local function UpdateBookView()
    if not libraryFrame or not selectedTitle then return end

    local fullText = GetFullBookText(selectedTitle)

    libraryFrame.titleText:SetText(selectedTitle)
    libraryFrame.bodyText:SetText(fullText)

    if libraryFrame.textScroll then
        libraryFrame.textScroll:SetVerticalScroll(0)
    end

    UpdateFontSize()
end

function WorldLibrary.BuildBookLibraryUI()
    if libraryFrame then return libraryFrame end

    -- Wider window size (780 x 540)
    local f = CreateFrame("Frame", "BookLibraryFrame", UIParent, "BackdropTemplate")
    f:SetSize(780, 540)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)

    -- Widened sidebar (240 width)
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetSize(240, 490)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -30)
    sidebar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    sidebar:SetBackdropColor(0, 0, 0, 0.6)

    local sidebarTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sidebarTitle:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -10)
    sidebarTitle:SetText("Books")

    local scrollFrame = CreateFrame("ScrollFrame", "BookLibraryListScroll", sidebar, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -34)
    scrollFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -28, 10)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(196, 440)
    scrollFrame:SetScrollChild(scrollContent)

    -- Widened right book reader panel
    local bookPage = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bookPage:SetSize(470, 490)
    bookPage:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -30)
    bookPage:SetBackdrop({
        bgFile = "Interface\\ItemText\\ItemText-Parchment",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })

    local sizeBtn = CreateFrame("Button", nil, bookPage, "UIPanelButtonTemplate")
    sizeBtn:SetSize(90, 20)
    sizeBtn:SetPoint("TOPLEFT", bookPage, "TOPLEFT", 12, -12)
    sizeBtn:SetText("Text: Medium")
    sizeBtn:SetScript("OnClick", function()
        local currentIdx = GetFontSizeIndex()
        local nextIdx = (currentIdx % #FONT_SIZES) + 1

        BookDB.fontSizeIndex = nextIdx
        UpdateFontSize()
    end)
    f.sizeBtn = sizeBtn

    local titleText = bookPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", bookPage, "TOP", 20, -14)
    titleText:SetWidth(320)
    titleText:SetJustifyH("CENTER")
    titleText:SetText("Select a Book")
    f.titleText = titleText

    local textScroll = CreateFrame("ScrollFrame", "BookLibraryTextScroll", bookPage, "UIPanelScrollFrameTemplate")
    textScroll:SetPoint("TOPLEFT", bookPage, "TOPLEFT", 20, -45)
    textScroll:SetPoint("BOTTOMRIGHT", bookPage, "BOTTOMRIGHT", -35, 20)
    f.textScroll = textScroll

    local textContent = CreateFrame("Frame", nil, textScroll)
    textContent:SetSize(395, 420)
    textScroll:SetScrollChild(textContent)
    f.textContent = textContent

    local bodyText = textContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bodyText:SetPoint("TOPLEFT", textContent, "TOPLEFT", 0, 0)
    bodyText:SetWidth(395)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetText("Choose a title from the list on the left to read.")
    f.bodyText = bodyText

    f.RefreshList = function()
        if scrollContent.buttons then
            for _, btn in ipairs(scrollContent.buttons) do btn:Hide() end
        end
        scrollContent.buttons = {}

        if not BookDB then return end

        local fontIdx = GetFontSizeIndex()
        local fontConfig = FONT_SIZES[fontIdx]
        local sidebarSize = math.max(fontConfig.size - 2, 10)
        
        -- Fully dynamic row height matching the font size plus spacing buffer
        local buttonHeight = sidebarSize + 10

        local previousButton = nil
        local totalHeight = 0

        for titleKey, _ in pairs(BookDB) do
            if titleKey ~= "fontSizeIndex" then
                local titleCaptured = titleKey
                local btn = CreateFrame("Button", nil, scrollContent)
                btn:SetSize(186, buttonHeight)

                if not previousButton then
                    btn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -4)
                    totalHeight = totalHeight + 4
                else
                    btn:SetPoint("TOPLEFT", previousButton, "BOTTOMLEFT", 0, -6)
                    totalHeight = totalHeight + 6
                end

                local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btnText:SetPoint("LEFT", btn, "LEFT", 4, 0)
                btnText:SetWidth(178)
                btnText:SetJustifyH("LEFT")
                
                local fontFile, _, fontFlags = btnText:GetFont()
                if fontFile then
                    btnText:SetFont(fontFile, sidebarSize, fontFlags)
                end

                btnText:SetText("|cFF808080•|r " .. titleCaptured)

                btn:SetScript("OnClick", function()
                    selectedTitle = titleCaptured
                    UpdateBookView()
                end)

                table.insert(scrollContent.buttons, btn)
                previousButton = btn
                totalHeight = totalHeight + buttonHeight
            end
        end
        scrollContent:SetHeight(math.max(totalHeight + 10, 440))
    end

    libraryFrame = f
    UpdateFontSize()
    return libraryFrame
end


-- ============================================================================
-- 3. EVENT LISTENER & NAVIGATION HOOKS
-- ============================================================================
local eventFrame = CreateFrame("Frame", "BookEventFrame")

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "WorldLibrary" then
        -- Do not use magic global variables in the code
        if not _G.BookDB then
            _G.BookDB = BookDB
        else 
            BookDB = _G.BookDB
        end 
        WorldLibrary.db = BookDB
    elseif event == "ITEM_TEXT_BEGIN" then
        currentTitle = SaveBookTitleAndLocation()
        SaveCurrentPage(currentTitle)
    elseif event == "ITEM_TEXT_READY" or event == "ITEM_TEXT_TRANSLATION" then
        SaveCurrentPage(currentTitle)
    elseif event == "ITEM_TEXT_CLOSED" then
        currentTitle = nil
    end
end

if eventFrame.ItemTextNextPageButton then
    eventFrame.ItemTextNextPageButton:HookScript("OnClick", function()
        C_Timer.After(0.05, function()
            SaveCurrentPage()
        end)
    end)
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("ITEM_TEXT_BEGIN")
eventFrame:RegisterEvent("ITEM_TEXT_READY")
eventFrame:RegisterEvent("ITEM_TEXT_TRANSLATION")
eventFrame:RegisterEvent("ITEM_TEXT_CLOSED")
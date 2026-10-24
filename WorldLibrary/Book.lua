WorldLibrary = WorldLibrary or {}
-- ============================================================================
-- 1. UTILITIES & DATABASE HELPERS
-- ============================================================================
local libraryFrame = nil
local currentTitle = nil

local BookDB = {}
BookDB.customCategories = { "Uncategorized", "Lore", "History", "Quests" }
local selectedCategory = "All"

StaticPopupDialogs["BOOK_LIBRARY_ADD_CATEGORY"] = {
    text = "Enter new category name:",
    button1 = "Accept",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        local editBox = self.editBox or _G[self:GetName() .. "EditBox"]
        local text = editBox and editBox:GetText()
        if text and text ~= "" then
            BookDB.customCategories = BookDB.customCategories or {}
            table.insert(BookDB.customCategories, text)
            print("|cFF00FF00[Book]|r Added category: " .. text)
            if libraryFrame and libraryFrame.RefreshList then
                libraryFrame.RefreshList()
            end
        end
        editBox:ClearText()
    end,
    EditBoxOnEnterPressed = function(editBox)
        local popup = editBox:GetParent()
        local accept = (popup.GetButton and popup:GetButton(1)) or popup.button1
        if accept then accept:Click() end
    end,
    OnHide = function(popup)
        popup.button1:UnlockHighlight()
        popup:SetScript("OnKeyDown", nil)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local FONT_SIZES = {
    { label = "Small",  size = 12 },
    { label = "Medium", size = 14 },
    { label = "Large",  size = 18 }
}

local function GetFontSizeIndex()
    if BookDB and BookDB.fontSizeIndex then
        return BookDB.fontSizeIndex
    end
    return 2
end

local function SaveBookTitleAndLocation(title)
    if not BookDB[title] then
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
            location = locationStr,
            category = "Uncategorized"
        }
        print("|cFF00FF00[Book]|r Recording new book: " .. title)
    end
end

local function SaveCurrentPage(title, pageText, pageNum)
    if not title or title == "" or not pageText or pageText == "" then return end

    SaveBookTitleAndLocation(title)

    if not pageText or pageText == "" then return end

    if type(BookDB[title].pages) ~= "table" then
        BookDB[title].pages = {}
    end

    if BookDB[title].pages[pageNum] then return end

    BookDB[title].pages[pageNum] = pageText
    print("|cFF00FF00[Book]|r Recorded page " .. pageNum .. " for " .. title)
end

local CASCADE_STEP  = 28   -- pixel offset between newly opened readers
local CASCADE_SLOTS = 8    -- offsets wrap after this many so windows stay on screen

local readerPool  = {}     -- released reader frames waiting to be reused
local openReaders = {}     -- [bookKey] = reader frame currently showing that book
local bookMenu    = nil    -- the single shared right-click menu frame

-- ---------------------------------------------------------------------------
-- Reader windows
-- ---------------------------------------------------------------------------

-- Shared OnUpdate handler (one function for every reader, no per-page closures).
-- Waits for SimpleHTML to lay out its text, then sizes it for scrolling.
-- Gives up after 10 frames so an empty page can't poll forever.
local function FitTextHeight(self)
    local height = self:GetContentHeight()
    self.fitTries = (self.fitTries or 0) + 1
    if height and height > 0 then
        self:SetHeight(height)
        self:SetScript("OnUpdate", nil)
    elseif self.fitTries >= 10 then
        self:SetScript("OnUpdate", nil)
    end
end

-- Returns a reader frame to the pool. Called from OnHide, so every way of
-- closing a reader (X button, delete, CloseBook) goes through here.
local function ReleaseReader(f)
    if f.released then return end
    f.released = true

    if f.bookKey and openReaders[f.bookKey] == f then
        openReaders[f.bookKey] = nil
    end
    f.bookKey, f.book = nil, nil
    f.Body:SetScript("OnUpdate", nil)
    readerPool[#readerPool + 1] = f
end

-- Builds one reader window. Only runs when the pool is empty, so the number
-- of frames ever created equals the peak number of books open at once.
local function BuildReaderFrame()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate") -- unnamed: no global collisions
    f:SetSize(400, 500)
    f:SetToplevel(true)            -- clicking a window brings it to the front
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:Raise(); self:StartMoving() end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f.released = false

    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -14)
    titleText:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    titleText:SetJustifyH("LEFT")
    f.TitleText = titleText

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetSize(350, 380)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -45)

    local body = CreateFrame("SimpleHTML", nil, scroll)
    body:SetSize(345, 380)
    scroll:SetScrollChild(body)
    body:SetFontObject("p", GameFontNormalLarge)
    body:SetTextColor("p", 0.9, 0.8, 0.7)
    body:SetJustifyH("p", "LEFT")
    f.Body = body

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local newScroll = self:GetVerticalScroll() - (delta * 30)
        local maxScroll = self:GetVerticalScrollRange()
        if newScroll < 0 then newScroll = 0 end
        if newScroll > maxScroll then newScroll = maxScroll end
        self:SetVerticalScroll(newScroll)
    end)

    local pageText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageText:SetPoint("BOTTOM", f, "BOTTOM", 0, 26)
    pageText:SetJustifyH("CENTER")

    local prevButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prevButton:SetSize(80, 25)
    prevButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 20)
    prevButton:SetText("Previous")

    local nextButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextButton:SetSize(80, 25)
    nextButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 20)
    nextButton:SetText("Next")

    -- Redraws the current page from f.book / f.currentPage
    function f:UpdatePage()
        local pages = self.book and self.book.pages
        local total = type(pages) == "table" and #pages or 0
        if self.currentPage > total then self.currentPage = math.max(total, 1) end

        scroll:SetVerticalScroll(0)
        body:SetHeight(380)
        if total > 0 then
            body:SetText(pages[self.currentPage] or "[Page not recorded]")
            pageText:SetText(string.format("Page %d of %d", self.currentPage, total))
        else
            body:SetText("[No pages recorded]")
            pageText:SetText("")
        end
        prevButton:SetEnabled(self.currentPage > 1)
        nextButton:SetEnabled(self.currentPage < total)

        body.fitTries = 0
        body:SetScript("OnUpdate", FitTextHeight)
    end

    prevButton:SetScript("OnClick", function()
        if f.currentPage > 1 then
            f.currentPage = f.currentPage - 1
            f:UpdatePage()
        end
    end)
    nextButton:SetScript("OnClick", function()
        local pages = f.book and f.book.pages
        if pages and f.currentPage < #pages then
            f.currentPage = f.currentPage + 1
            f:UpdatePage()
        end
    end)

    -- Release on any explicit Hide(). The IsShown() check ignores the case where
    -- the frame is only invisible because UIParent was hidden (Alt+Z), so books
    -- don't get closed when the player toggles the UI.
    f:SetScript("OnHide", function(self)
        if self:IsShown() then return end
        ReleaseReader(self)
    end)

    return f
end

local function AcquireReader()
    local f = table.remove(readerPool) or BuildReaderFrame()
    f.released = false
    return f
end

local function CountOpenReaders()
    local n = 0
    for _ in pairs(openReaders) do n = n + 1 end
    return n
end

-- Opens a book in its own window. Opening a book that is already open just
-- brings its window to the front, so the same book can never be open twice.
function WorldLibrary.OpenBook(bookKey, book)
    if not bookKey or type(book) ~= "table" then return end

    local f = openReaders[bookKey]
    if f then
        f:Raise()
        return f
    end

    f = AcquireReader()
    f.bookKey = bookKey
    f.book = book
    f.currentPage = 1
    f.TitleText:SetText(bookKey)
    openReaders[bookKey] = f

    local slot = (CountOpenReaders() - 1) % CASCADE_SLOTS
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", slot * CASCADE_STEP, -slot * CASCADE_STEP)
    f:UpdatePage()
    f:Show()
    f:Raise()
    return f
end

function WorldLibrary.CloseBook(bookKey)
    local f = openReaders[bookKey]
    if f then f:Hide() end   -- OnHide releases it back to the pool
end

function WorldLibrary.CloseAllBooks()
    local frames = {}
    for _, f in pairs(openReaders) do frames[#frames + 1] = f end
    for _, f in ipairs(frames) do f:Hide() end
end

-- ---------------------------------------------------------------------------
-- Right-click context menu (one frame, created on first use)
-- ---------------------------------------------------------------------------
local function InitBookMenu(self, level)
    local ctx = self.context
    if not ctx then return end
    local bookData = ctx.bookData
    local current = bookData.category or "Uncategorized"

    local titleInfo = UIDropDownMenu_CreateInfo()
    titleInfo.text = "Set Category for: " .. ctx.titleKey
    titleInfo.isTitle = true
    titleInfo.notCheckable = true
    UIDropDownMenu_AddButton(titleInfo, level)

    for _, cat in ipairs(BookDB.customCategories or {}) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = cat
        info.checked = (current == cat)
        info.func = function()
            bookData.category = cat
            if libraryFrame and libraryFrame.RefreshList then libraryFrame.RefreshList() end
        end
        UIDropDownMenu_AddButton(info, level)
    end

    local deleteInfo = UIDropDownMenu_CreateInfo()
    deleteInfo.text = "|cFFFF0000Delete Book|r"
    deleteInfo.notCheckable = true
    deleteInfo.func = function()
        BookDB[ctx.titleKey] = nil
        WorldLibrary.CloseBook(ctx.titleKey)   -- close its reader if it's open
        if libraryFrame and libraryFrame.RefreshList then libraryFrame.RefreshList() end
        print("|cFFFF0000[Book]|r Deleted book: " .. ctx.titleKey)
    end
    UIDropDownMenu_AddButton(deleteInfo, level)
end

local function ShowBookContextMenu(anchor, titleKey, bookData)
    if not bookMenu then
        bookMenu = CreateFrame("Frame", "WorldLibraryBookContextMenu", UIParent, "UIDropDownMenuTemplate")
    end
    bookMenu.context = { titleKey = titleKey, bookData = bookData }
    UIDropDownMenu_Initialize(bookMenu, InitBookMenu, "MENU")
    ToggleDropDownMenu(1, nil, bookMenu, anchor, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Book list (pooled buttons)
-- ---------------------------------------------------------------------------

-- One click handler shared by every list button; it reads the book from the
-- button's fields, so nothing is captured per refresh.
local function OnBookButtonClick(self, mouseButton)
    if not self.titleKey then return end
    if mouseButton == "LeftButton" then
        WorldLibrary.OpenBook(self.titleKey, self.bookData)
    elseif mouseButton == "RightButton" then
        ShowBookContextMenu(self, self.titleKey, self.bookData)
    end
end

local function CreateListButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", OnBookButtonClick)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", btn, "LEFT", 4, 0)
    text:SetWidth(230)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    btn.text = text
    return btn
end

-- Rebuilds the visible list. Buttons are created once and reused; extras are
-- hidden, never discarded. Books are shown alphabetically.
local function PopulateBookList(scrollContent)
    scrollContent.buttons = scrollContent.buttons or {}
    local pool = scrollContent.buttons

    local fontConfig = FONT_SIZES[GetFontSizeIndex()] or FONT_SIZES[2]
    local buttonHeight = fontConfig.size + 12
    local spacing = 4

    local titles = {}
    for titleKey, bookData in pairs(BookDB) do
        if titleKey ~= "fontSizeIndex" and titleKey ~= "customCategories" and type(bookData) == "table" then
            local category = bookData.category or "Uncategorized"
            if selectedCategory == "All" or category == selectedCategory then
                titles[#titles + 1] = titleKey
            end
        end
    end
    table.sort(titles, function(a, b) return a:lower() < b:lower() end)

    for i, titleKey in ipairs(titles) do
        local btn = pool[i]
        if not btn then
            btn = CreateListButton(scrollContent)
            pool[i] = btn
        end
        btn:SetSize(240, buttonHeight)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -(spacing + (i - 1) * (buttonHeight + spacing)))
        btn.titleKey = titleKey
        btn.bookData = BookDB[titleKey]

        local fontFile, _, fontFlags = btn.text:GetFont()
        if fontFile then btn.text:SetFont(fontFile, fontConfig.size, fontFlags) end
        btn.text:SetText("|cFF808080•|r " .. titleKey)
        btn:Show()
    end

    for i = #titles + 1, #pool do
        pool[i]:Hide()
        pool[i].titleKey, pool[i].bookData = nil, nil
    end

    scrollContent:SetHeight(math.max(spacing + #titles * (buttonHeight + spacing) + 10, 440))
end

-- ============================================================================
-- 3. MAIN LIBRARY UI PANEL
-- ============================================================================
function WorldLibrary.BuildBookLibraryUI()
    if libraryFrame then return libraryFrame end

    local f = CreateFrame("Frame", "BookLibraryFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(320, 540)
    f:SetPoint("CENTER", UIParent, "CENTER", -220, 0)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    
    if f.TitleText then
        f.TitleText:SetText("Library Collection")
    end
    f:Hide()

    local catBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    catBtn:SetSize(280, 22)
    catBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
    catBtn:SetText("Category: " .. selectedCategory)

    local categoryMenu = CreateFrame("Frame", "BookLibraryCategoryMenu", f, "UIDropDownMenuTemplate")
    catBtn:SetScript("OnClick", function()
        UIDropDownMenu_Initialize(categoryMenu, function(self, level)
            local allInfo = UIDropDownMenu_CreateInfo()
            allInfo.text = "All Categories"
            allInfo.value = "All"
            allInfo.func = function(btn)
                selectedCategory = btn.value
                catBtn:SetText("Category: All")
                if libraryFrame and libraryFrame.RefreshList then libraryFrame.RefreshList() end
            end
            UIDropDownMenu_AddButton(allInfo)

            if BookDB and BookDB.customCategories then
                for _, cat in ipairs(BookDB.customCategories) do
                    local catInfo = UIDropDownMenu_CreateInfo()
                    catInfo.text = cat
                    catInfo.value = cat
                    catInfo.func = function(btn)
                        selectedCategory = btn.value
                        catBtn:SetText("Category: " .. cat)
                        if libraryFrame and libraryFrame.RefreshList then libraryFrame.RefreshList() end
                    end
                    UIDropDownMenu_AddButton(catInfo)
                end
            end

            local addInfo = UIDropDownMenu_CreateInfo()
            addInfo.text = "|cFF00FF00+ Add Category...|r"
            addInfo.notCheckable = true
            addInfo.func = function()
                StaticPopup_Show("BOOK_LIBRARY_ADD_CATEGORY")
            end
            UIDropDownMenu_AddButton(addInfo)
        end)
        ToggleDropDownMenu(1, nil, categoryMenu, catBtn, 0, 0)
    end)

    local scrollFrame = CreateFrame("ScrollFrame", "BookLibraryListScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(500, 350)
    scrollFrame:SetScrollChild(scrollContent)

    f.RefreshList = function() PopulateBookList(scrollContent) end

    libraryFrame = f
    f:RefreshList()
    return libraryFrame
end

-- ============================================================================
-- 4. EVENT LISTENER & NAVIGATION HOOKS
-- ============================================================================
local eventFrame = CreateFrame("Frame", "BookEventFrame")

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "WorldLibrary" then
        if not _G.BookDB then
            _G.BookDB = BookDB
        else 
            BookDB = _G.BookDB
        end 
        BookDB.customCategories = BookDB.customCategories or { "Uncategorized", "Lore", "History", "Quests" }
        WorldLibrary.db = BookDB
    elseif event == "ITEM_TEXT_BEGIN" then
        currentTitle = ItemTextGetItem()
        SaveCurrentPage(currentTitle, ItemTextGetText(), ItemTextGetPage())
    elseif event == "ITEM_TEXT_READY" or event == "ITEM_TEXT_TRANSLATION" then
        SaveCurrentPage(currentTitle, ItemTextGetText(), ItemTextGetPage())
    elseif event == "ITEM_TEXT_CLOSED" then
        currentTitle = nil
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("ITEM_TEXT_BEGIN")
eventFrame:RegisterEvent("ITEM_TEXT_READY")
eventFrame:RegisterEvent("ITEM_TEXT_TRANSLATION")
eventFrame:RegisterEvent("ITEM_TEXT_CLOSED")
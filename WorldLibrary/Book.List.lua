-- ============================================================================
-- Book.List.lua
-- The scrolling list of books in the library panel: pooled buttons, the
-- category filter, and the right-click context menu (set category / delete).
-- ============================================================================
local WL = WorldLibrary

local bookMenu = nil    -- the single shared right-click menu frame

-- ---------------------------------------------------------------------------
-- Right-click context menu (one frame, created on first use)
-- ---------------------------------------------------------------------------
local function InitBookMenu(self, level)
    local ctx = self.context
    if not ctx then return end
    local bookData = ctx.bookData
    local current = bookData.category or WL.DEFAULT_CATEGORY

    local titleInfo = UIDropDownMenu_CreateInfo()
    titleInfo.text = "Set Category for: " .. ctx.titleKey
    titleInfo.isTitle = true
    titleInfo.notCheckable = true
    UIDropDownMenu_AddButton(titleInfo, level)

    for _, cat in ipairs(WL.GetCategories()) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = cat
        info.checked = (current == cat)
        info.func = function()
            bookData.category = cat
            WL.RefreshLibrary()
        end
        UIDropDownMenu_AddButton(info, level)
    end

    local deleteInfo = UIDropDownMenu_CreateInfo()
    deleteInfo.text = "|cFFFF0000Delete Book|r"
    deleteInfo.notCheckable = true
    deleteInfo.func = function()
        WL.db[ctx.titleKey] = nil
        WL.CloseBook(ctx.titleKey)   -- close its reader if it's open
        WL.RefreshLibrary()
        WL.Msg("Deleted book: " .. ctx.titleKey, true)
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
-- List buttons (pooled)
-- ---------------------------------------------------------------------------

-- One click handler shared by every list button; it reads the book from the
-- button's fields, so nothing is captured per refresh.
local function OnBookButtonClick(self, mouseButton)
    if not self.titleKey then return end
    if mouseButton == "LeftButton" then
        WL.OpenBook(self.titleKey, self.bookData)
    elseif mouseButton == "RightButton" then
        ShowBookContextMenu(self, self.titleKey, self.bookData)
    end
end

local function CreateListButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", OnBookButtonClick)

    -- Subtle hover highlight so wrapped (multi-line) entries read as one row
    btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    btn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)

    -- Width is set in PopulateBookList; text wraps and the button grows to fit
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -6)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    btn.text = text
    return btn
end

-- Titles of the books that match the current category filter, sorted A-Z
local function GetFilteredTitles()
    local selected = WL.state.selectedCategory
    local titles = {}
    WL.ForEachBook(function(book, title)
        local category = book.category or WL.DEFAULT_CATEGORY
        if selected == WL.ALL_CATEGORIES or category == selected then
            titles[#titles + 1] = title
        end
    end)
    table.sort(titles, function(a, b) return a:lower() < b:lower() end)
    return titles
end

-- Rebuilds the visible list. Buttons are created once and reused; extras are
-- hidden, never discarded. Books are shown alphabetically.
function WL.PopulateBookList(scrollContent)
    scrollContent.buttons = scrollContent.buttons or {}
    local pool = scrollContent.buttons

    local fontConfig = WL.GetFontConfig()
    local minHeight = fontConfig.size + 12
    local spacing = 4

    -- Fill the scroll frame's width. If its layout isn't resolved yet (the panel
    -- starts hidden), fall back to the default panel width of 272.
    local parentWidth = scrollContent:GetParent():GetWidth()
    local contentWidth = (parentWidth and parentWidth > 50) and parentWidth or 272
    scrollContent:SetWidth(contentWidth)
    local textWidth = contentWidth - 8

    local titles = GetFilteredTitles()

    local y = spacing
    for i, titleKey in ipairs(titles) do
        local btn = pool[i]
        if not btn then
            btn = CreateListButton(scrollContent)
            pool[i] = btn
        end

        -- Set font, width, then text, so GetStringHeight reflects the wrapped size
        local fontFile, _, fontFlags = btn.text:GetFont()
        if fontFile then btn.text:SetFont(fontFile, fontConfig.size, fontFlags) end
        btn.text:SetWidth(textWidth)
        btn.text:SetText("|cFF808080•|r " .. titleKey)

        local height = math.max(minHeight, math.ceil(btn.text:GetStringHeight()) + 12)
        btn:SetSize(contentWidth, height)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -y)
        btn.titleKey = titleKey
        btn.bookData = WL.db[titleKey]
        btn:Show()

        y = y + height + spacing
    end

    for i = #titles + 1, #pool do
        pool[i]:Hide()
        pool[i].titleKey, pool[i].bookData = nil, nil
    end

    scrollContent:SetHeight(math.max(y + 10, 440))
end

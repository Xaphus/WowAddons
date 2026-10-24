-- ============================================================================
-- WorldLibrary: records in-game books as you read them and lets you browse,
-- categorize and re-read them.
--
--   1. Utilities, saved data, and recording books
--   2. Category management (add / rename / delete) and its editor window
--   3. Book reader windows (pooled), book list, and context menu
--   4. Main library panel
--   5. Event listener
-- ============================================================================
WorldLibrary = WorldLibrary or {}

-- ============================================================================
-- 1. UTILITIES & DATABASE HELPERS
-- ============================================================================
local libraryFrame = nil
local currentTitle = nil

local BookDB = {}
BookDB.customCategories = { "Uncategorized", "Lore", "History", "Quests" }
local selectedCategory = "All"

-- Keys in BookDB that hold settings rather than books
local RESERVED_KEYS = { customCategories = true, fontSizeIndex = true }

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
    -- Ignore events that arrive without a title/text (e.g. after a /reload mid-read),
    -- and titles that would collide with the settings stored in BookDB.
    if not title or title == "" or RESERVED_KEYS[title] then return end
    if not pageText or pageText == "" or not pageNum then return end

    SaveBookTitleAndLocation(title)

    if type(BookDB[title].pages) ~= "table" then
        BookDB[title].pages = {}
    end

    if BookDB[title].pages[pageNum] then return end

    BookDB[title].pages[pageNum] = pageText
    print("|cFF00FF00[Book]|r Recorded page " .. pageNum .. " for " .. title)
end


-- ============================================================================
-- 2. CATEGORY MANAGEMENT (add / rename / delete) + EDITOR WINDOW
-- ============================================================================
local DEFAULT_CATEGORY  = "Uncategorized"  -- cannot be renamed or deleted
local ALL_CATEGORIES    = "All"            -- reserved: the "no filter" value
local EDITOR_ROW_HEIGHT = 28
local categoryEditor    = nil

local function Msg(text, isError)
    print((isError and "|cFFFF0000" or "|cFF00FF00") .. "[Book]|r " .. text)
end

-- Iterates real book records (skips config keys stored in the same table)
local function ForEachBook(fn)
    for key, value in pairs(BookDB) do
        if not RESERVED_KEYS[key] and type(value) == "table" then
            fn(value)
        end
    end
end

local function GetCategories()
    BookDB.customCategories = BookDB.customCategories
        or { DEFAULT_CATEGORY, "Lore", "History", "Quests" }
    return BookDB.customCategories
end

-- Case-insensitive lookup; returns the index or nil
local function FindCategory(name)
    local lower = name:lower()
    for i, cat in ipairs(GetCategories()) do
        if cat:lower() == lower then return i end
    end
end

local function IsProtected(name)
    return name:lower() == DEFAULT_CATEGORY:lower()
end

-- Older versions allowed empty/duplicate/untrimmed names. Clean them up and
-- re-point any book whose category no longer matches to a valid one.
local function CleanCategories()
    local seen, clean = {}, {}
    for _, cat in ipairs(GetCategories()) do
        local name = strtrim(cat)
        local key = name:lower()
        if name ~= "" and key ~= ALL_CATEGORIES:lower() and not seen[key] then
            seen[key] = true
            clean[#clean + 1] = name
        end
    end
    if not seen[DEFAULT_CATEGORY:lower()] then
        table.insert(clean, 1, DEFAULT_CATEGORY)
    end
    BookDB.customCategories = clean

    ForEachBook(function(book)
        local match = FindCategory(strtrim(book.category or DEFAULT_CATEGORY))
        book.category = match and clean[match] or DEFAULT_CATEGORY
    end)
end

-- ignoreName lets a rename keep (or change the case of) its own current name
local function ValidateName(name, ignoreName)
    if name == "" then
        return false, "Category name cannot be empty."
    end
    if name:lower() == ALL_CATEGORIES:lower() then
        return false, "\"" .. ALL_CATEGORIES .. "\" is a reserved name."
    end
    local index = FindCategory(name)
    if index then
        local existing = GetCategories()[index]
        if existing ~= ignoreName then
            return false, "A category named \"" .. existing .. "\" already exists."
        end
    end
    return true
end

local function NotifyCategoriesChanged()
    if libraryFrame then
        if libraryFrame.UpdateCategoryLabel then libraryFrame.UpdateCategoryLabel() end
        if libraryFrame.RefreshList then libraryFrame.RefreshList() end
    end
    if categoryEditor and categoryEditor:IsShown() then
        categoryEditor.Refresh()
    end
end

-- ---------------------------------------------------------------------------
-- Public API. Each returns (true) or (false, errorMessage).
-- ---------------------------------------------------------------------------
function WorldLibrary.AddCategory(name)
    name = strtrim(name or "")
    local ok, err = ValidateName(name)
    if not ok then return false, err end

    table.insert(GetCategories(), name)
    NotifyCategoriesChanged()
    return true
end

function WorldLibrary.RenameCategory(oldName, newName)
    local cats = GetCategories()
    local index = FindCategory(oldName or "")
    if not index then return false, "Category not found." end

    oldName = cats[index]
    if IsProtected(oldName) then
        return false, "\"" .. DEFAULT_CATEGORY .. "\" can't be renamed."
    end

    newName = strtrim(newName or "")
    if newName == oldName then return true end

    local ok, err = ValidateName(newName, oldName)
    if not ok then return false, err end

    cats[index] = newName
    ForEachBook(function(book)
        if book.category == oldName then book.category = newName end
    end)
    if selectedCategory == oldName then selectedCategory = newName end

    NotifyCategoriesChanged()
    return true
end

-- On success returns (true, numberOfBooksMoved)
function WorldLibrary.DeleteCategory(name)
    local cats = GetCategories()
    local index = FindCategory(name or "")
    if not index then return false, "Category not found." end

    name = cats[index]
    if IsProtected(name) then
        return false, "\"" .. DEFAULT_CATEGORY .. "\" can't be deleted."
    end

    table.remove(cats, index)

    local moved = 0
    ForEachBook(function(book)
        if book.category == name then
            book.category = DEFAULT_CATEGORY
            moved = moved + 1
        end
    end)
    if selectedCategory == name then selectedCategory = ALL_CATEGORIES end

    NotifyCategoriesChanged()
    return true, moved
end

-- ---------------------------------------------------------------------------
-- Delete confirmation
-- ---------------------------------------------------------------------------
StaticPopupDialogs["WORLDLIBRARY_DELETE_CATEGORY"] = {
    text = "Delete category \"%s\"?\nBooks in it will be moved to " .. DEFAULT_CATEGORY .. ".",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, data)
        local ok, result = WorldLibrary.DeleteCategory(data)
        if ok then
            Msg(string.format("Deleted category \"%s\" (%d book(s) moved to %s).",
                data, result, DEFAULT_CATEGORY))
        else
            Msg(result, true)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Editor window
-- ---------------------------------------------------------------------------
local function CreateEditorRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(240, EDITOR_ROW_HEIGHT)

    local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    edit:SetSize(180, 22)
    edit:SetPoint("LEFT", row, "LEFT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(32)

    -- Enter commits the rename. Leaving the box any other way (Esc, clicking
    -- away) discards the edit and restores the stored name.
    edit:SetScript("OnEnterPressed", function(self)
        local ok, err = WorldLibrary.RenameCategory(row.categoryName, self:GetText())
        if not ok then Msg(err, true) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        self:SetText(row.categoryName or "")
    end)

    local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    del:SetSize(26, 22)
    del:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    del:SetText("X")
    del:SetScript("OnClick", function()
        StaticPopup_Show("WORLDLIBRARY_DELETE_CATEGORY", row.categoryName, nil, row.categoryName)
    end)

    row.edit = edit
    row.delete = del
    return row
end

local function BuildCategoryEditor()
    local f = CreateFrame("Frame", "WorldLibraryCategoryEditor", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(300, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("Edit Categories") end
    tinsert(UISpecialFrames, "WorldLibraryCategoryEditor") -- Escape closes it

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
    hint:SetText("Edit a name and press Enter to rename. X deletes.")

    -- Scrolling list of categories
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -52)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 62)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(240, 1)
    scroll:SetScrollChild(content)

    -- "Add" row
    local addLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetText("New category:")

    local addBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    addBox:SetSize(170, 22)
    addBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 22)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(32)
    addLabel:SetPoint("BOTTOMLEFT", addBox, "TOPLEFT", -4, 4)

    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(70, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")

    local function SubmitNew()
        local ok, err = WorldLibrary.AddCategory(addBox:GetText())
        if ok then addBox:SetText("") else Msg(err, true) end
    end
    addBtn:SetScript("OnClick", SubmitNew)
    addBox:SetScript("OnEnterPressed", SubmitNew) -- stays focused for adding several
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Rebuilds the rows from BookDB.customCategories
    local rows = {}
    function f.Refresh()
        local cats = GetCategories()
        for i, name in ipairs(cats) do
            local row = rows[i]
            if not row then
                row = CreateEditorRow(content)
                rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * EDITOR_ROW_HEIGHT)
            row.categoryName = name
            row.edit:SetText(name)

            local locked = IsProtected(name)
            local shade = locked and 0.6 or 1
            row.edit:SetEnabled(not locked)
            row.edit:SetTextColor(shade, shade, shade)
            row.delete:SetEnabled(not locked)
            row:Show()
        end
        for i = #cats + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(#cats * EDITOR_ROW_HEIGHT, 1))
    end

    return f
end

function WorldLibrary.OpenCategoryEditor()
    if not categoryEditor then categoryEditor = BuildCategoryEditor() end
    CleanCategories()
    categoryEditor:Show()
    NotifyCategoriesChanged()
end

-- ============================================================================
-- 3. BOOK READER WINDOWS (pooled) + BOOK LIST + CONTEXT MENU
-- ============================================================================
local CASCADE_STEP  = 28   -- pixel offset between newly opened readers
local CASCADE_SLOTS = 8    -- offsets wrap after this many so windows stay on screen

-- Page images are pulled out of the page HTML and drawn centered in a fixed
-- (non-scrolling) area between the title and the scrolling text.
local TEXT_TOP           = 45    -- y offset where the text column starts when there are no images
local TEXT_HEIGHT        = 380   -- height of the text column when there are no images
local IMAGE_MAX_WIDTH    = 350   -- images are scaled down uniformly to fit this box
local IMAGE_MAX_HEIGHT   = 160   -- on pages that also have text; image-only pages use the whole column
local IMAGE_SPACING      = 8     -- gap between images when a page has several
local IMAGE_PADDING      = 6     -- space above and below the image row
local IMAGE_MAX_COUNT    = 4     -- extra images on a page are ignored
local DEFAULT_IMAGE_SIZE = 128   -- used when an <img> tag has no width/height

local readerPool  = {}     -- released reader frames waiting to be reused
local openReaders = {}     -- [bookKey] = reader frame currently showing that book
local bookMenu    = nil    -- the single shared right-click menu frame

-- ---------------------------------------------------------------------------
-- Reader windows
-- ---------------------------------------------------------------------------

-- Reads a numeric attribute (e.g. width="301") from an already-lowercased tag body
local function NumberAttr(lowerAttrs, name)
    return tonumber(lowerAttrs:match(name .. "%s*=%s*[\"']?(-?[%d%.]+)"))
end

-- Removes <img ...> tags from a page's HTML and returns (strippedHtml, images),
-- where images is a list of { src, width, height, left, right, top, bottom }.
-- left/right/top/bottom are the tag's texCoord* attributes: book textures are
-- usually power-of-two files with the artwork in a corner, so these select the
-- part of the file that should actually be drawn.
local function ExtractImages(html)
    local images = {}
    local stripped = html:gsub("<[Ii][Mm][Gg]%s+([^>]*)>", function(attrs)
        local src = attrs:match('[Ss][Rr][Cc]%s*=%s*"([^"]*)"')
            or attrs:match("[Ss][Rr][Cc]%s*=%s*'([^']*)'")
            or attrs:match("[Ss][Rr][Cc]%s*=%s*([^%s>]+)")
        if src and #images < IMAGE_MAX_COUNT then
            local lower = attrs:lower()
            images[#images + 1] = {
                src = src,
                width = NumberAttr(lower, "width"),
                height = NumberAttr(lower, "height"),
                left = NumberAttr(lower, "texcoordleft") or 0,
                right = NumberAttr(lower, "texcoordright") or 1,
                top = NumberAttr(lower, "texcoordtop") or 0,
                bottom = NumberAttr(lower, "texcoordbottom") or 1,
            }
        end
        return ""   -- always strip the tag so it doesn't render inside the scroll area
    end)
    return stripped, images
end

-- True if the HTML contains any readable text once its tags are removed
-- (an image-only page is just <HTML><BODY><IMG/></BODY></HTML> plus whitespace)
local function HasVisibleText(html)
    local plain = html:gsub("<[^>]*>", "")
    return plain:find("%S") ~= nil
end

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

    -- Fixed image area: same width and left edge as the text column, sits above
    -- the scroll frame. Hidden (and the text column full height) on pages with no images.
    local imageArea = CreateFrame("Frame", nil, f)
    imageArea:SetSize(350, 1)
    imageArea:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -TEXT_TOP)
    imageArea:Hide()
    local imageTextures = {}   -- reused across pages; created only as needed

    -- Lays the images out centered in imageArea, resizes the text column to fit
    -- below it, and returns the text column's height.
    -- On an image-only page the images get the whole text column and the scroll
    -- area is hidden; otherwise they're capped at IMAGE_MAX_HEIGHT.
    local function LayoutImages(images, imageOnly)
        local count = #images
        local areaHeight = 0

        if count > 0 then
            local totalWidth, tallest = IMAGE_SPACING * (count - 1), 0
            for _, img in ipairs(images) do
                img.w = img.width or DEFAULT_IMAGE_SIZE
                img.h = img.height or DEFAULT_IMAGE_SIZE
                totalWidth = totalWidth + img.w
                tallest = math.max(tallest, img.h)
            end
            local maxHeight = imageOnly and (TEXT_HEIGHT - IMAGE_PADDING * 2) or IMAGE_MAX_HEIGHT
            local scale = math.min(1, IMAGE_MAX_WIDTH / totalWidth, maxHeight / tallest)

            local x = -(totalWidth * scale) / 2   -- start left of center so the row is centered
            for i, img in ipairs(images) do
                local tex = imageTextures[i]
                if not tex then
                    tex = imageArea:CreateTexture(nil, "ARTWORK")
                    imageTextures[i] = tex
                end
                tex:SetTexture(tonumber(img.src) or img.src)
                tex:SetTexCoord(img.left, img.right, img.top, img.bottom)
                tex:SetSize(img.w * scale, img.h * scale)
                tex:ClearAllPoints()
                tex:SetPoint("LEFT", imageArea, "CENTER", x, 0)   -- vertically centered too
                tex:Show()
                x = x + (img.w + IMAGE_SPACING) * scale
            end
            areaHeight = math.ceil(tallest * scale) + IMAGE_PADDING * 2
            if imageOnly then areaHeight = TEXT_HEIGHT end   -- center in the full column
        end

        for i = count + 1, #imageTextures do imageTextures[i]:Hide() end

        imageArea:SetHeight(math.max(areaHeight, 1))
        imageArea:SetShown(count > 0)

        if count > 0 and imageOnly then
            scroll:Hide()   -- nothing to scroll; the image owns the whole column
            return 1
        end

        scroll:Show()
        local textHeight = TEXT_HEIGHT - areaHeight
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -(TEXT_TOP + areaHeight))
        scroll:SetSize(350, textHeight)
        return textHeight
    end

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

        local html
        if total > 0 then
            html = pages[self.currentPage] or "[Page not recorded]"
            pageText:SetText(string.format("Page %d of %d", self.currentPage, total))
        else
            html = "[No pages recorded]"
            pageText:SetText("")
        end

        local text, images = ExtractImages(html)
        local imageOnly = #images > 0 and not HasVisibleText(text)
        local textHeight = LayoutImages(images, imageOnly)

        scroll:SetVerticalScroll(0)
        body:SetHeight(textHeight)
        body:SetText(text)
        prevButton:SetEnabled(self.currentPage > 1)
        nextButton:SetEnabled(self.currentPage < total)

        if imageOnly then
            body:SetScript("OnUpdate", nil)   -- scroll area is hidden, nothing to size
        else
            body.fitTries = 0
            body:SetScript("OnUpdate", FitTextHeight)
        end
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

-- Rebuilds the visible list. Buttons are created once and reused; extras are
-- hidden, never discarded. Books are shown alphabetically.
local function PopulateBookList(scrollContent)
    scrollContent.buttons = scrollContent.buttons or {}
    local pool = scrollContent.buttons

    local fontConfig = FONT_SIZES[GetFontSizeIndex()] or FONT_SIZES[2]
    local minHeight = fontConfig.size + 12
    local spacing = 4

    -- Fill the scroll frame's width. If its layout isn't resolved yet (the panel
    -- starts hidden), fall back to the default panel width of 272.
    local parentWidth = scrollContent:GetParent():GetWidth()
    local contentWidth = (parentWidth and parentWidth > 50) and parentWidth or 272
    scrollContent:SetWidth(contentWidth)
    local textWidth = contentWidth - 8

    local titles = {}
    for titleKey, bookData in pairs(BookDB) do
        if not RESERVED_KEYS[titleKey] and type(bookData) == "table" then
            local category = bookData.category or "Uncategorized"
            if selectedCategory == "All" or category == selectedCategory then
                titles[#titles + 1] = titleKey
            end
        end
    end
    table.sort(titles, function(a, b) return a:lower() < b:lower() end)

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
        btn.bookData = BookDB[titleKey]
        btn:Show()

        y = y + height + spacing
    end

    for i = #titles + 1, #pool do
        pool[i]:Hide()
        pool[i].titleKey, pool[i].bookData = nil, nil
    end

    scrollContent:SetHeight(math.max(y + 10, 440))
end

-- ============================================================================
-- 4. MAIN LIBRARY UI PANEL
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

    -- Lets the category editor keep this label in sync after a rename or delete
    f.UpdateCategoryLabel = function()
        catBtn:SetText("Category: " .. selectedCategory)
    end

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

            local editInfo = UIDropDownMenu_CreateInfo()
            editInfo.text = "|cFF00FF00Edit Categories...|r"
            editInfo.notCheckable = true
            editInfo.func = function()
                WorldLibrary.OpenCategoryEditor()
            end
            UIDropDownMenu_AddButton(editInfo)
        end)
        ToggleDropDownMenu(1, nil, categoryMenu, catBtn, 0, 0)
    end)

    local scrollFrame = CreateFrame("ScrollFrame", "BookLibraryListScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(272, 350)   -- width is re-set to the scroll frame's width on every refresh
    scrollFrame:SetScrollChild(scrollContent)

    f.RefreshList = function()
        PopulateBookList(scrollContent)
    end

    -- The panel starts hidden, so the first layout may happen before the scroll
    -- frame's real width is known; re-run the layout once it resolves or changes.
    scrollFrame:HookScript("OnSizeChanged", function()
        if f.RefreshList then f.RefreshList() end
    end)

    libraryFrame = f
    f.RefreshList()
    return libraryFrame
end

-- ============================================================================
-- 5. EVENT LISTENER & NAVIGATION HOOKS
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
        CleanCategories()   -- tidy duplicate/empty categories left by older versions
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
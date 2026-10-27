-- ============================================================================
-- Book.Reader.lua
-- Book display: the pooled reader windows that show a recorded book's pages
-- (text plus any images), and the open / close API.
-- Nothing here touches the database directly; callers pass in the book record.
-- ============================================================================
local WL = WorldLibrary

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

-- ---------------------------------------------------------------------------
-- Page HTML helpers
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

-- ---------------------------------------------------------------------------
-- Reader frame pool
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Opens a book in its own window. Opening a book that is already open just
-- brings its window to the front, so the same book can never be open twice.
function WL.OpenBook(bookKey, book)
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

function WL.CloseBook(bookKey)
    local f = openReaders[bookKey]
    if f then f:Hide() end   -- OnHide releases it back to the pool
end

function WL.CloseAllBooks()
    local frames = {}
    for _, f in pairs(openReaders) do frames[#frames + 1] = f end
    for _, f in ipairs(frames) do f:Hide() end
end

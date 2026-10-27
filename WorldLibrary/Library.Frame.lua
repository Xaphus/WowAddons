-- ============================================================================
-- Library.Frame.lua
-- The main "Library Collection" panel: category dropdown + scrolling book list.
-- Opened by the /books command (see SlashCommands.lua).
-- ============================================================================
local WL = WorldLibrary

-- Refreshes the book list if the panel has been built; safe to call any time.
function WL.RefreshLibrary()
    local f = WL.state.libraryFrame
    if f and f.RefreshList then f.RefreshList() end
end

-- Fills the category dropdown: "All Categories", each category, then "Edit..."
local function InitCategoryMenu(catBtn)
    local function AddChoice(text, value)
        local info = UIDropDownMenu_CreateInfo()
        info.text = text
        info.value = value
        info.func = function(btn)
            WL.state.selectedCategory = btn.value
            catBtn:SetText("Category: " .. value)
            WL.RefreshLibrary()
        end
        UIDropDownMenu_AddButton(info)
    end

    AddChoice("All Categories", WL.ALL_CATEGORIES)
    for _, cat in ipairs(WL.GetCategories()) do
        AddChoice(cat, cat)
    end

    local editInfo = UIDropDownMenu_CreateInfo()
    editInfo.text = "|cFF00FF00Edit Categories...|r"
    editInfo.notCheckable = true
    editInfo.func = function() WL.OpenCategoryEditor() end
    UIDropDownMenu_AddButton(editInfo)
end

function WL.BuildBookLibraryUI()
    if WL.state.libraryFrame then return WL.state.libraryFrame end

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

    -- Category filter button + dropdown
    local catBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    catBtn:SetSize(280, 22)
    catBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
    catBtn:SetText("Category: " .. WL.state.selectedCategory)

    -- Lets the category editor keep this label in sync after a rename or delete
    f.UpdateCategoryLabel = function()
        catBtn:SetText("Category: " .. WL.state.selectedCategory)
    end

    local categoryMenu = CreateFrame("Frame", "BookLibraryCategoryMenu", f, "UIDropDownMenuTemplate")
    catBtn:SetScript("OnClick", function()
        UIDropDownMenu_Initialize(categoryMenu, function() InitCategoryMenu(catBtn) end)
        ToggleDropDownMenu(1, nil, categoryMenu, catBtn, 0, 0)
    end)

    -- Scrolling book list
    local scrollFrame = CreateFrame("ScrollFrame", "BookLibraryListScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(272, 350)   -- width is re-set to the scroll frame's width on every refresh
    scrollFrame:SetScrollChild(scrollContent)

    f.RefreshList = function()
        WL.PopulateBookList(scrollContent)
    end

    -- The panel starts hidden, so the first layout may happen before the scroll
    -- frame's real width is known; re-run the layout once it resolves or changes.
    scrollFrame:HookScript("OnSizeChanged", function()
        if f.RefreshList then f.RefreshList() end
    end)

    WL.state.libraryFrame = f
    f.RefreshList()
    return f
end

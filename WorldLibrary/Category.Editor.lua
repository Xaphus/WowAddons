-- ============================================================================
-- Category.Editor.lua
-- The "Edit Categories" window and its delete confirmation dialog.
-- All data changes go through the API in Category.lua.
-- ============================================================================
local WL = WorldLibrary
local Msg = WL.Msg
local DEFAULT_CATEGORY = WL.DEFAULT_CATEGORY

local EDITOR_ROW_HEIGHT = 28

-- ---------------------------------------------------------------------------
-- Delete confirmation
-- ---------------------------------------------------------------------------
StaticPopupDialogs["WORLDLIBRARY_DELETE_CATEGORY"] = {
    text = "Delete category \"%s\"?\nBooks in it will be moved to " .. DEFAULT_CATEGORY .. ".",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, data)
        local ok, result = WL.DeleteCategory(data)
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
-- One row: editable name + delete button
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
        local ok, err = WL.RenameCategory(row.categoryName, self:GetText())
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

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
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
        local ok, err = WL.AddCategory(addBox:GetText())
        if ok then addBox:SetText("") else Msg(err, true) end
    end
    addBtn:SetScript("OnClick", SubmitNew)
    addBox:SetScript("OnEnterPressed", SubmitNew) -- stays focused for adding several
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Rebuilds the rows from the saved category list
    local rows = {}
    function f.Refresh()
        local cats = WL.GetCategories()
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

            local locked = WL.IsProtectedCategory(name)
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

function WL.OpenCategoryEditor()
    if not WL.state.categoryEditor then
        WL.state.categoryEditor = BuildCategoryEditor()
    end
    WL.CleanCategories()
    WL.state.categoryEditor:Show()
    WL.NotifyCategoriesChanged()
end

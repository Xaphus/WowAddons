-- ============================================================================
-- Category.lua
-- Category data logic: lookup, validation, cleanup, add / rename / delete.
-- No windows are created here; see Category.Editor.lua for the UI.
--
-- The public functions return (true) or (false, errorMessage).
-- ============================================================================
local WL = WorldLibrary
local DEFAULT_CATEGORY = WL.DEFAULT_CATEGORY
local ALL_CATEGORIES   = WL.ALL_CATEGORIES

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
function WL.GetCategories()
    WL.db.customCategories = WL.db.customCategories or WL.NewDefaultCategories()
    return WL.db.customCategories
end
local GetCategories = WL.GetCategories

-- Case-insensitive lookup; returns the index or nil
local function FindCategory(name)
    local lower = name:lower()
    for i, cat in ipairs(GetCategories()) do
        if cat:lower() == lower then return i end
    end
end

function WL.IsProtectedCategory(name)
    return name:lower() == DEFAULT_CATEGORY:lower()
end
local IsProtected = WL.IsProtectedCategory

-- Older versions allowed empty/duplicate/untrimmed names. Clean them up and
-- re-point any book whose category no longer matches to a valid one.
function WL.CleanCategories()
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
    WL.db.customCategories = clean

    WL.ForEachBook(function(book)
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

-- Keeps the library panel and the editor window in sync after any change
local function NotifyCategoriesChanged()
    local library = WL.state.libraryFrame
    if library then
        if library.UpdateCategoryLabel then library.UpdateCategoryLabel() end
        if library.RefreshList then library.RefreshList() end
    end

    local editor = WL.state.categoryEditor
    if editor and editor:IsShown() then
        editor.Refresh()
    end
end
WL.NotifyCategoriesChanged = NotifyCategoriesChanged

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function WL.AddCategory(name)
    name = strtrim(name or "")
    local ok, err = ValidateName(name)
    if not ok then return false, err end

    table.insert(GetCategories(), name)
    NotifyCategoriesChanged()
    return true
end

function WL.RenameCategory(oldName, newName)
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
    WL.ForEachBook(function(book)
        if book.category == oldName then book.category = newName end
    end)
    if WL.state.selectedCategory == oldName then
        WL.state.selectedCategory = newName
    end

    NotifyCategoriesChanged()
    return true
end

-- On success returns (true, numberOfBooksMoved)
function WL.DeleteCategory(name)
    local cats = GetCategories()
    local index = FindCategory(name or "")
    if not index then return false, "Category not found." end

    name = cats[index]
    if IsProtected(name) then
        return false, "\"" .. DEFAULT_CATEGORY .. "\" can't be deleted."
    end

    table.remove(cats, index)

    local moved = 0
    WL.ForEachBook(function(book)
        if book.category == name then
            book.category = DEFAULT_CATEGORY
            moved = moved + 1
        end
    end)
    if WL.state.selectedCategory == name then
        WL.state.selectedCategory = ALL_CATEGORIES
    end

    NotifyCategoriesChanged()
    return true, moved
end

-- ============================================================================
-- Core.lua
-- Shared namespace, constants, runtime state, and the chat-message helper.
-- Loaded first: every other file reads from the table created here.
-- ============================================================================
WorldLibrary = WorldLibrary or {}
local WL = WorldLibrary

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
WL.DEFAULT_CATEGORY = "Uncategorized"   -- cannot be renamed or deleted
WL.ALL_CATEGORIES   = "All"             -- reserved: the "no filter" value

-- Returns a fresh copy each time so callers can safely add to it.
function WL.NewDefaultCategories()
    return { WL.DEFAULT_CATEGORY, "Lore", "History", "Quests" }
end

-- ---------------------------------------------------------------------------
-- Runtime state (not saved between sessions)
-- ---------------------------------------------------------------------------
WL.state = {
    selectedCategory = WL.ALL_CATEGORIES,  -- current filter in the library panel
    libraryFrame     = nil,                -- main panel, set by Library.Frame.lua
    categoryEditor   = nil,                -- editor window, set by Category.Editor.lua
}

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------
function WL.Msg(text, isError)
    print((isError and "|cFFFF0000" or "|cFF00FF00") .. "[Book]|r " .. text)
end

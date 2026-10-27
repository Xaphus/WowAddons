-- ============================================================================
-- Database.lua
-- Owns the saved-variable table (BookDB) and the helpers for reading it.
--
-- BookDB holds both book records (keyed by title) and a few settings keys.
-- Always reach it through WorldLibrary.db at call time: the table is swapped
-- for the real saved variable when the addon loads, so never cache it in an
-- upvalue.
-- ============================================================================
local WL = WorldLibrary

-- Placeholder used until ADDON_LOADED hands us the saved variable.
WL.db = { customCategories = WL.NewDefaultCategories() }

-- Keys in the DB that hold settings rather than books
local RESERVED_KEYS = { customCategories = true, fontSizeIndex = true }

function WL.IsReservedKey(key)
    return RESERVED_KEYS[key] == true
end

-- Called once from the ADDON_LOADED handler.
function WL.InitDatabase()
    if not _G.BookDB then
        _G.BookDB = WL.db
    else
        WL.db = _G.BookDB
    end
    WL.db.customCategories = WL.db.customCategories or WL.NewDefaultCategories()
end

-- Iterates real book records (skips settings stored in the same table).
-- fn receives (bookRecord, title).
function WL.ForEachBook(fn)
    for key, value in pairs(WL.db) do
        if not RESERVED_KEYS[key] and type(value) == "table" then
            fn(value, key)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Font size setting (used by the book list)
-- ---------------------------------------------------------------------------
local FONT_SIZES = {
    { label = "Small",  size = 12 },
    { label = "Medium", size = 14 },
    { label = "Large",  size = 18 },
}

function WL.GetFontConfig()
    local index = WL.db and WL.db.fontSizeIndex or 2
    return FONT_SIZES[index] or FONT_SIZES[2]
end

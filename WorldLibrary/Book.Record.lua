-- ============================================================================
-- Book.Record.lua
-- Recording: turns what the player is reading into saved book records.
-- ============================================================================
local WL = WorldLibrary

-- Builds a string like "Elwynn Forest (Goldshire) [42.1, 65.3]"
local function GetLocationString()
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
    return locationStr
end

-- Creates the record the first time a title is seen
local function EnsureBookRecord(title)
    if WL.db[title] then return end

    WL.db[title] = {
        pages = {},
        timestamp = date("%Y-%m-%d %H:%M:%S"),
        location = GetLocationString(),
        category = WL.DEFAULT_CATEGORY,
    }
    WL.Msg("Recording new book: " .. title)
end

function WL.SaveCurrentPage(title, pageText, pageNum)
    -- Ignore events that arrive without a title/text (e.g. after a /reload mid-read),
    -- and titles that would collide with the settings stored in the DB.
    if not title or title == "" or WL.IsReservedKey(title) then return end
    if not pageText or pageText == "" or not pageNum then return end

    EnsureBookRecord(title)

    local book = WL.db[title]
    if type(book.pages) ~= "table" then
        book.pages = {}
    end

    if book.pages[pageNum] then return end

    book.pages[pageNum] = pageText
    WL.Msg("Recorded page " .. pageNum .. " for " .. title)
end

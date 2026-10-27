-- ============================================================================
-- Events.lua
-- Event listener: initializes the database on load and feeds book text from
-- the game into the recorder as the player reads.
-- ============================================================================
local WL = WorldLibrary

local currentTitle = nil   -- title of the book being read right now

local eventFrame = CreateFrame("Frame", "BookEventFrame")

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "WorldLibrary" then
        WL.InitDatabase()
        WL.CleanCategories()   -- tidy duplicate/empty categories left by older versions
    elseif event == "ITEM_TEXT_BEGIN" then
        currentTitle = ItemTextGetItem()
        WL.SaveCurrentPage(currentTitle, ItemTextGetText(), ItemTextGetPage())
    elseif event == "ITEM_TEXT_READY" or event == "ITEM_TEXT_TRANSLATION" then
        WL.SaveCurrentPage(currentTitle, ItemTextGetText(), ItemTextGetPage())
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

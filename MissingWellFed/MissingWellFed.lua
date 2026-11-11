local addonName, addon = ...

-- Configuration Defaults
local DEFAULT_POINT = {"CENTER", nil, "CENTER", 0, 150}

-- Frame Setup
local frame = CreateFrame("Frame", "MissingWellFedFrame", UIParent)
frame:SetSize(250, 40)
frame:SetPoint(unpack(DEFAULT_POINT))
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if IsAltKeyDown() then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    MissingWellFedDB = MissingWellFedDB or {}
    MissingWellFedDB.point = {point, nil, relativePoint, x, y}
end)

-- Text Warning Label
local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
text:SetAllPoints(frame)
text:SetText("MISSING WELL FED!")
text:SetTextColor(1, 0.2, 0.2, 1)

-- Helper: Check for "Well Fed" aura
local function HasWellFedBuff()
    local index = 1
    while true do
        local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", index, "HELPFUL")
        if not name then break end
        -- Classic Era uses "Well Fed"; check both localized name and standard spell ID match
        if name == "Well Fed" then
            return true
        end
        index = index + 1
    end
    return false
end

-- Core Visibility Toggle Logic
local function UpdateBuffStatus()
    -- Hide in combat, while mounted, dead/ghost, or taxi to prevent clutter
    if UnitIsDeadOrGhost("player") or IsMounted() or UnitOnTaxi("player") then
        frame:Hide()
        return
    end

    if HasWellFedBuff() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Event Registration
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if MissingWellFedDB and MissingWellFedDB.point then
            self:ClearAllPoints()
            self:SetPoint(unpack(MissingWellFedDB.point))
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            UpdateBuffStatus()
        end
    else
        UpdateBuffStatus()
    end
end)

-- Slash Commands
SLASH_MISSINGWELLFED1 = "/mwf"
SLASH_MISSINGWELLFED2 = "/wellfed"
SlashCmdList["MISSINGWELLFED"] = function(msg)
    msg = msg:lower():trim()
    if msg == "reset" then
        MissingWellFedDB = {}
        frame:ClearAllPoints()
        frame:SetPoint(unpack(DEFAULT_POINT))
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[MissingWellFed]|r Frame position reset.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[MissingWellFed]|r Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /mwf reset - Reset frame position to center")
        DEFAULT_CHAT_FRAME:AddMessage("  (Hold ALT + Left-Click to drag the warning text)")
    end
end
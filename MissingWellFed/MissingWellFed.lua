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
    if IsAltKeyDown() and not InCombatLockdown() then
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

local DEBUG_LOGGING = false

-- Helper: Check for "Well Fed" aura via Retail AuraUtil / C_UnitAuras API
local function HasWellFedBuff()
    local index = 1
    local found = false

    if DEBUG_LOGGING then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[MWF Debug]|r Scanning Retail Auras via C_UnitAuras:")
    end

    while true do
        -- Retrieve aura structure directly via index
        local auraData = C_UnitAuras.GetBuffDataByIndex("player", index)
        if not auraData then break end

        local name = auraData.name or ""
        local icon = auraData.icon
        local spellId = auraData.spellId or 0

        if DEBUG_LOGGING then
            DEFAULT_CHAT_FRAME:AddMessage("  - [" .. index .. "] Name: '" .. name .. "' | Icon: " .. tostring(icon) .. " | SpellID: " .. spellId)
        end

        local lowerName = name:lower()

        -- Check name variations
        if lowerName:find("well fed") or lowerName:find("sated") then
            found = true
            break
        end

        -- Check FileDataID (Retail returns numeric FileDataIDs for icon textures)
        -- Standard Well Fed icon FileDataID on Retail is 133938
        if icon == 133938 then
            found = true
            break
        end

        index = index + 1
    end

    return found
end

-- Core Visibility Toggle Logic
local function UpdateBuffStatus()
    if InCombatLockdown() then
        frame:Hide()
        return
    end

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
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:Hide()
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
    msg = msg or ""
    msg = msg:lower():trim()
    if msg == "reset" then
        MissingWellFedDB = {}
        frame:ClearAllPoints()
        frame:SetPoint(unpack(DEFAULT_POINT))
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[MissingWellFed]|r Frame position reset.")
    elseif msg == "debug" then
        DEBUG_LOGGING = not DEBUG_LOGGING
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[MissingWellFed]|r Debug logging set to: " .. tostring(DEBUG_LOGGING))
        UpdateBuffStatus()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[MissingWellFed]|r Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /mwf reset - Reset frame position to center")
        DEFAULT_CHAT_FRAME:AddMessage("  /mwf debug - Toggle chat logging ON/OFF")
    end
end
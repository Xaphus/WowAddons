QuestJournal = QuestJournal or {}
local addonName, addon = ...
local QuestJournalDB = {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
frame:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
frame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")

local recentQuestId = nil

-- Enhanced coordinate, zone, and subzone lookup
local function GetPlayerLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return { mapID = 0, zone = "Unknown", subzone = "Unknown", x = 0, y = 0 } end
    
    local mapInfo = C_Map.GetMapInfo(mapID)
    local zoneName = mapInfo and mapInfo.name or "Unknown"
    local subzoneName = GetSubZoneText() or ""
    if subzoneName == "" then subzoneName = zoneName end
    
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y = 0, 0
    if position then
        x, y = position:GetXY()
        x = math.floor(x * 10000) / 100
        y = math.floor(y * 10000) / 100
    end
    
    return { mapID = mapID, zone = zoneName, subzone = subzoneName, x = x, y = y }
end

-- NPC details lookup
local function GetTargetDetails()
    local name = UnitName("npc") or UnitName("target") or "Unknown NPC"
    local guid = UnitGUID("npc") or UnitGUID("target") or "Unknown GUID"
    return name, guid
end

-- Fallback function to extract active quest ID from retail frames
local function ResolveActiveQuestID()
    local qID = GetQuestID()
    if qID and qID > 0 then return qID end
    
    if QuestOfferFrame and QuestOfferFrame.questID and QuestOfferFrame.questID > 0 then
        return QuestOfferFrame.questID
    end
    
    qID = C_QuestLog.GetSelectedQuest()
    if qID and qID > 0 then return qID end
    
    return nil
end

-- Get or initialize entry directly inside the global table
local function RecordQuestData(questID, titleOverride)
    if not questID or questID <= 0 then return nil end
    
    if not QuestJournalDB[questID] then
        QuestJournalDB[questID] = {
            questID = questID,
            title = titleOverride or C_QuestLog.GetTitleForQuestID(questID) or GetTitleText() or "Unknown Quest",
            giver = {},
            turnIn = {},
            location = GetPlayerLocation(),
            description = "",
            objectivesText = "",
            completionText = "",
            progressText = "",
            gossipHistory = {},
            conversations = {}
        }
    end
    return QuestJournalDB[questID]
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            if not _G.QuestJournalDB then
                _G.QuestJournalDB = QuestJournalDB
            else
                QuestJournalDB = _G.QuestJournalDB
            end
            QuestJournal.db = QuestJournalDB

            print("|cFF00FF00[QuestJournal]|r Addon loaded and initialized.")
        end

    elseif event == "QUEST_DETAIL" then
        local questID = ResolveActiveQuestID()
        if questID then
            recentQuestId = questID
            local record = RecordQuestData(questID, GetTitleText())
            if record then
                local npcName, npcGuid = GetTargetDetails()
                record.giver = { name = npcName, guid = npcGuid }
                record.location = GetPlayerLocation()
                record.description = GetQuestText() or ""
                record.objectivesText = GetObjectiveText() or ""
            end
        end

    elseif event == "QUEST_ACCEPTED" then
        local questID = ...
        if not questID or questID <= 0 then questID = ResolveActiveQuestID() end
        if questID and questID > 0 then
            recentQuestId = questID
            RecordQuestData(questID)
        end

    elseif event == "QUEST_PROGRESS" then
        local questID = ResolveActiveQuestID()
        if questID then
            recentQuestId = questID
            local record = RecordQuestData(questID)
            if record then
                record.progressText = GetProgressText() or ""
            end
        end

elseif event == "QUEST_COMPLETE" then
        local questID = ResolveActiveQuestID()
        if questID then
            recentQuestId = questID
            local record = RecordQuestData(questID, GetTitleText())
            if record then
                local npcName, npcGuid = GetTargetDetails()
                record.turnIn = { 
                    name = npcName, 
                    guid = npcGuid,
                    location = GetPlayerLocation()
                }
                record.completionText = GetRewardText() or ""
            end
        end

    elseif event == "QUEST_REMOVED" then
        local questID = ...
        if questID and questID > 0 then
            C_Timer.After(0.2, function()
                if not C_QuestLog.IsQuestFlaggedCompleted(questID) then
                    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
                    if not logIndex or logIndex == 0 then
                        if QuestJournalDB[questID] then
                            QuestJournalDB[questID] = nil
                            print(string.format("|cFF00FF00[QuestJournal]|r Quest ID %d abandoned. Removed from database.", questID))
                        end
                    end
                end
            end)
        end

    elseif event == "GOSSIP_SHOW" then
        local npcName, npcGuid = GetTargetDetails()
        local gossipText = C_GossipInfo.GetText() or ""
        
        if gossipText ~= "" and recentQuestId and QuestJournalDB[recentQuestId] then
            table.insert(QuestJournalDB[recentQuestId].gossipHistory, {
                timestamp = date("%Y-%m-%d %H:%M:%S"),
                npcName = npcName,
                npcGuid = npcGuid,
                text = gossipText,
                location = GetPlayerLocation()
            })
        end

    elseif event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL" 
        or event == "CHAT_MSG_MONSTER_WHISPER" or event == "CHAT_MSG_MONSTER_EMOTE" then
        local msg, sender, _, _, _, _, _, _, _, _, _, guid = ...
        
        if recentQuestId and QuestJournalDB[recentQuestId] then
            table.insert(QuestJournalDB[recentQuestId].conversations, {
                timestamp = date("%Y-%m-%d %H:%M:%S"),
                type = event,
                sender = sender,
                guid = guid,
                message = msg
            })
        end
    end
end)

-- Slash Commands
SLASH_QuestJournal1 = "/qc"
SlashCmdList["QuestJournal"] = function(msg)
    local args = {}
    for word in string.gmatch(msg or "", "%S+") do table.insert(args, word) end
    local cmd = string.lower(args[1] or "")

    if cmd == "list" then
        local count = 0
        print("|cFF00FF00[QuestJournal] Current Memory Database:|r")
        for qID, data in pairs(QuestJournalDB) do
            count = count + 1
            local locStr = data.location and string.format("%s (%s)", data.location.zone, data.location.subzone) or "Unknown Location"
            print(string.format("  |cFFFFD100[%d]|r %s — |cFF00CCFF%s|r", qID, data.title or "Unknown", locStr))
        end
        if count == 0 then print("  No quest entries currently recorded.") end

    elseif cmd == "view" then
        local qID = tonumber(args[2]) or recentQuestId
        if qID and QuestJournalDB[qID] then
            local q = QuestJournalDB[qID]
            print("|cFF00FF00=== Quest [" .. q.questID .. "]: " .. q.title .. " ===|r")
            print("  |cFFFFD100Giver:|r " .. (q.giver.name or "N/A"))
            if q.location then
                print(string.format("  |cFFFFD100Location:|r Zone: %s | Subzone: %s (Map ID: %s) at %.2f, %.2f", 
                    q.location.zone, q.location.subzone, tostring(q.location.mapID), q.location.x, q.location.y))
            end
            print("  |cFFFFD100TurnIn:|r " .. (q.turnIn.name or "N/A"))
            print("  |cFFFFD100Description:|r " .. (q.description ~= "" and q.description or "N/A"))
            print("  |cFFFFD100Completion:|r " .. (q.completionText ~= "" and q.completionText or "N/A"))
        else
            print("|cFF00FF00[QuestJournal]|r Quest ID not found.")
        end

    elseif cmd == "reset" then
        QuestJournalDB = {}
        recentQuestId = nil
        print("|cFF00FF00[QuestJournal]|r Database reset.")

    else
        local count = 0
        for _ in pairs(QuestJournalDB) do count = count + 1 end
        print(string.format("|cFF00FF00[QuestJournal]|r Memory records: %d. Last ID: %s", count, tostring(recentQuestId or "None")))
    end
end
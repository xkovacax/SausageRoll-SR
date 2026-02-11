----------------------------------------------------------------------
-- SoftResImport v3 - WoW 3.3.5a (Warmane)
-- SR section + MS ROLL section (tradeable instance items)
-- RW announce, roll tracking, winner eval, reimport
----------------------------------------------------------------------
local ADDON_NAME = "SausageRoll-SR"
local SR_VERSION = "1.3.0"
local SRI = CreateFrame("Frame", "SoftResImportFrame")

local C_GREEN  = "|cff00ff00"
local C_YELLOW = "|cffffff00"
local C_ORANGE = "|cffff8800"
local C_RED    = "|cffff0000"
local C_WHITE  = "|cffffffff"
local C_CYAN   = "|cff00ffff"
local C_GRAY   = "|cff888888"
local C_RESET  = "|r"
local PREFIX   = C_GREEN.."Sausage Roll"..C_WHITE.." - SR"..C_RESET

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
local reserves = {}
local reservesByName = {}
local importCount = 0
local hardReserves = {}
local hardReserveCustom = {}
local isLootOpen = false
local displayMode = "bag"  -- "loot" or "bag"
local minQualityFilter = 2 -- 2=Green+, 3=Blue+, 4=Epic+
local showBoE = false      -- show Bind on Equip items
local activeRoll = nil -- {itemId, link, mode, rolls={}}

-- Addon sync (ML -> clients)
local SYNC_PREFIX = "SAUSR"
local clientRoll = nil       -- received roll data from ML
local clientRollFrame = nil
local clientRollRows = {}
local clientAutoHideTimer = nil
local CreateClientRollWindow   -- forward decl
local RefreshClientRollWindow  -- forward decl

SausageRollImportDB = SausageRollImportDB or {}

----------------------------------------------------------------------
-- Scanning tooltip for reading item trade time
----------------------------------------------------------------------
local scanTip = CreateFrame("GameTooltip", "SRIScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Reads tooltip of a bag item, returns remaining trade seconds or nil
local function GetTradeTimeFromBag(bag, slot)
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
        local left = _G["SRIScanTooltipTextLeft"..i]
        if left then
            local text = left:GetText()
            if text then
                -- "You may trade this item with players that were also eligible to loot this item for the next 31 min."
                -- "You may trade this item ... for the next 1 hour 15 min."
                -- "You may trade this item ... for the next 45 min."
                local tradeMatch = text:match("You may trade this item")
                if tradeMatch then
                    local hours = text:match("(%d+) hour")
                    local mins = text:match("(%d+) min")
                    local secs = 0
                    if hours then secs = secs + tonumber(hours) * 3600 end
                    if mins then secs = secs + tonumber(mins) * 60 end
                    if secs == 0 then secs = 60 end -- at least ~1 min if text exists
                    return secs
                end
            end
        end
    end
    return nil
end

-- Check if item is Bind on Equip (tooltip scanning)
local function IsBoEFromBag(bag, slot)
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
        local left = _G["SRIScanTooltipTextLeft"..i]
        if left then
            local text = left:GetText()
            if text and text:match("Binds when equipped") then
                return true
            end
        end
    end
    return false
end

-- Check if item in loot window (loot items are always tradeable while in loot)
local function GetTradeTimeFromLoot(lootIndex)
    scanTip:ClearLines()
    scanTip:SetLootItem(lootIndex)
    for i = 1, scanTip:NumLines() do
        local left = _G["SRIScanTooltipTextLeft"..i]
        if left then
            local text = left:GetText()
            if text and text:match("You may trade this item") then
                return 7200 -- loot window = full 2h assumed
            end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------
local SR_DEBUG = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX..": "..msg)
end

local function DPrint(msg)
    if SR_DEBUG then DEFAULT_CHAT_FRAME:AddMessage(PREFIX..": "..msg) end
end

local function StripQuotes(s)
    if not s then return "" end
    s = s:match("^%s*(.-)%s*$")
    s = s:gsub('^"',''):gsub('"$','')
    return s
end

local function CapitalizeName(name)
    if not name or name == "" then return "" end
    return name:sub(1,1):upper()..name:sub(2):lower()
end

local function GetItemIdFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

local function IsInRaid() return GetNumRaidMembers() > 0 end

local function SendRW(msg)
    if IsInRaid() then
        if IsRaidLeader() or IsRaidOfficer() then
            SendChatMessage(msg, "RAID_WARNING")
        else
            SendChatMessage(msg, "RAID")
        end
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage(msg, "PARTY")
    else
        DPrint(msg)
    end
end

local function SendRaid(msg, prefix)
    prefix = prefix or "[HR]"
    if IsInRaid() then
        SendChatMessage(prefix.." "..msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage(prefix.." "..msg, "PARTY")
    else
        DPrint(msg)
    end
end

----------------------------------------------------------------------
-- Addon Sync helpers (ML -> clients)
----------------------------------------------------------------------
local function SendSync(msgType, ...)
    local parts = {msgType}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local payload = table.concat(parts, ":")
    local channel
    if IsInRaid() then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    else
        return
    end
    SendAddonMessage(SYNC_PREFIX, payload, channel)
end

local function SendSyncEligible(names)
    if not names or #names == 0 then return end
    local MAX_NAMES_LEN = 247  -- 250 total - 3 for "EL|"
    local currentStr = ""
    for _, name in ipairs(names) do
        local sep = currentStr == "" and "" or ","
        if #currentStr + #sep + #name > MAX_NAMES_LEN and currentStr ~= "" then
            SendSync("EL", currentStr)
            currentStr = name
        else
            currentStr = currentStr .. sep .. name
        end
    end
    if currentStr ~= "" then
        SendSync("EL", currentStr)
    end
end

local function OnSyncMessage(prefix, msg, channel, sender)
    if prefix ~= SYNC_PREFIX then return end
    if sender == UnitName("player") then return end

    local parts = {strsplit(":", msg)}
    local msgType = parts[1]

    if msgType == "RS" then
        local itemId = tonumber(parts[2])
        local quality = tonumber(parts[3])
        local mode = parts[4] or "sr"
        if not itemId then return end
        local iName, iLink, iRarity, _, _, _, _, _, _, iTexture = GetItemInfo(itemId)
        clientRoll = {
            itemId = itemId,
            link = iLink or ("[Item " .. itemId .. "]"),
            quality = quality or iRarity or 1,
            icon = iTexture,
            mode = mode,
            eligible = {},
            rolls = {},
            countdown = nil,
            winner = nil,
            winnerRoll = 0,
            finished = false,
        }
        clientAutoHideTimer = nil
        CreateClientRollWindow()
        RefreshClientRollWindow()

    elseif msgType == "EL" then
        if not clientRoll then return end
        local nameStr = parts[2]
        if nameStr and nameStr ~= "" then
            local names = {strsplit(",", nameStr)}
            for _, n in ipairs(names) do
                if n ~= "" then
                    table.insert(clientRoll.eligible, n)
                end
            end
        end
        RefreshClientRollWindow()

    elseif msgType == "RU" then
        if not clientRoll then return end
        table.insert(clientRoll.rolls, {
            name = parts[2],
            roll = tonumber(parts[3]) or 0,
            valid = parts[4] == "1",
        })
        RefreshClientRollWindow()

    elseif msgType == "RC" then
        if not clientRoll then return end
        clientRoll.countdown = tonumber(parts[2])
        RefreshClientRollWindow()

    elseif msgType == "RE" then
        if not clientRoll then return end
        local winnerName = parts[2]
        local winnerRoll = tonumber(parts[3]) or 0
        if winnerName and winnerName ~= "" then
            clientRoll.winner = winnerName
            clientRoll.winnerRoll = winnerRoll
        end
        clientRoll.finished = true
        clientRoll.countdown = nil
        local myName = UnitName("player") or ""
        if winnerName and winnerName ~= "" and winnerName:lower() == myName:lower() then
            PlaySoundFile("Interface\\AddOns\\SausageRoll-SR\\Sounds\\SausageAnnounce.mp3")
            RaidNotice_AddMessage(RaidWarningFrame, "YOU WON!", ChatTypeInfo["RAID_WARNING"])
        end
        clientAutoHideTimer = 8
        RefreshClientRollWindow()

    elseif msgType == "RX" then
        clientRoll = nil
        clientAutoHideTimer = nil
        if clientRollFrame then clientRollFrame:Hide() end
    end
end

-- Bank and Disenchant default characters
local bankCharName = nil
local dissCharName = nil

-- Award log: tracks who won which items (history for chat print)
-- Each entry: {itemId, winner, link}
local awardLog = {}

-- UID-based item instance tracking
local slotToUid = {}    -- "loot:3" or "bag:0:5" -> uid
local uidToSlot = {}    -- uid -> slot key
local uidToItemId = {}  -- uid -> itemId
local uidAwards = {}    -- uid -> {winner=name, link=link}
local nextItemUid = 1

----------------------------------------------------------------------
-- UID helper functions
----------------------------------------------------------------------
local function AssignUid(slotKey, itemId)
    if slotToUid[slotKey] then
        return slotToUid[slotKey]
    end
    local uid = nextItemUid
    nextItemUid = nextItemUid + 1
    slotToUid[slotKey] = uid
    uidToSlot[uid] = slotKey
    uidToItemId[uid] = itemId
    return uid
end

local pendingOrphans = {} -- itemId -> {uid, uid, ...}

local function SyncItemUids()
    wipe(pendingOrphans)

    -- 1) Mark all loot UIDs as potential orphans
    local lootOrphans = {} -- uid -> itemId
    local lootKeysToRemove = {}
    for key, uid in pairs(slotToUid) do
        if key:match("^loot:") then
            lootOrphans[uid] = uidToItemId[uid]
            table.insert(lootKeysToRemove, key)
        end
    end
    for _, key in ipairs(lootKeysToRemove) do
        slotToUid[key] = nil
    end

    -- 2) Rescan loot and reclaim UIDs that still exist
    if isLootOpen then
        for i = 1, GetNumLootItems() do
            local link = GetLootSlotLink(i)
            if link then
                local itemId = GetItemIdFromLink(link)
                if itemId then
                    local key = "loot:"..i
                    local matched = false
                    for uid, oItemId in pairs(lootOrphans) do
                        if oItemId == itemId then
                            slotToUid[key] = uid
                            uidToSlot[uid] = key
                            lootOrphans[uid] = nil
                            matched = true
                            break
                        end
                    end
                    if not matched then
                        AssignUid(key, itemId)
                    end
                end
            end
        end
    end

    -- 3) Remaining orphans = items that left loot (may appear in bags)
    for uid, itemId in pairs(lootOrphans) do
        if not pendingOrphans[itemId] then pendingOrphans[itemId] = {} end
        table.insert(pendingOrphans[itemId], uid)
        uidToSlot[uid] = nil
    end

    -- 4) Clean bag UIDs for items no longer at original slot
    local bagKeysToRemove = {}
    for key, uid in pairs(slotToUid) do
        local bagStr, slotStr = key:match("^bag:(%d+):(%d+)$")
        if bagStr then
            local bag, slot = tonumber(bagStr), tonumber(slotStr)
            local link = GetContainerItemLink(bag, slot)
            if not link or GetItemIdFromLink(link) ~= uidToItemId[uid] then
                table.insert(bagKeysToRemove, key)
                uidToSlot[uid] = nil
            end
        end
    end
    for _, key in ipairs(bagKeysToRemove) do
        slotToUid[key] = nil
    end
end

local function GetBagItemUid(slotKey, itemId)
    if slotToUid[slotKey] then
        return slotToUid[slotKey]
    end
    -- Try to match orphan (loot->bag transition)
    local orphans = pendingOrphans[itemId]
    if orphans and #orphans > 0 then
        local uid = table.remove(orphans, 1)
        slotToUid[slotKey] = uid
        uidToSlot[uid] = slotKey
        return uid
    end
    -- Brand new item
    return AssignUid(slotKey, itemId)
end

-- Forward declarations (needed by TryTradeItem, AnnounceWinnerFinal, ScheduleRefresh)
local ScheduleRefresh
local RefreshMainFrame

----------------------------------------------------------------------
-- Trade helpers
----------------------------------------------------------------------
local function FindBagSlot(itemId)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and GetItemIdFromLink(link) == itemId then
                return bag, slot
            end
        end
    end
    return nil, nil
end

local pendingTrade = nil -- {bag, slot, itemId}

-- Find UnitId for a player name in raid or party
local function GetUnitIdByName(targetName)
    if not targetName then return nil end
    local low = targetName:lower()
    if IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local uid = "raid"..i
            local n = UnitName(uid)
            if n and n:lower() == low then return uid end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local uid = "party"..i
            local n = UnitName(uid)
            if n and n:lower() == low then return uid end
        end
    end
    return nil
end

-- Get sorted list of all group members (for dropdown menus)
local function GetGroupMembers()
    local members = {}
    local seen = {}
    if IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name and not seen[name:lower()] then
                seen[name:lower()] = true
                table.insert(members, name)
            end
        end
    else
        local myName = UnitName("player")
        if myName then
            seen[myName:lower()] = true
            table.insert(members, myName)
        end
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party"..i)
            if name and not seen[name:lower()] then
                seen[name:lower()] = true
                table.insert(members, name)
            end
        end
    end
    table.sort(members)
    return members
end

-- Check if player is the Master Looter
local function IsMasterLooter()
    local method, pID, rID = GetLootMethod()
    if method ~= "master" then return false end
    if IsInRaid() then
        -- rID is raid member index (1-based), 0 means nobody
        if rID and rID > 0 then
            local name = GetRaidRosterInfo(rID)
            return name and name:lower() == UnitName("player"):lower()
        end
    else
        -- pID: 0 = player, 1-4 = party members
        return pID == 0
    end
    return false
end

local function TryTradeItem(targetName, itemId, itemLink, itemUid)
    if not targetName or targetName == "" then
        DPrint(C_RED.."No target name!"..C_RESET)
        return
    end

    -- 1) Check loot window FIRST - use Master Loot via UID-specific slot
    if isLootOpen and itemUid then
        local slotKey = uidToSlot[itemUid]
        local lootIdx = slotKey and tonumber(slotKey:match("^loot:(%d+)$"))
        if lootIdx then
            local link = GetLootSlotLink(lootIdx)
            if link and GetItemIdFromLink(link) == itemId then
                for ci = 1, 40 do
                    local cname = GetMasterLootCandidate(ci)
                    if not cname then break end
                    if cname:lower() == targetName:lower() then
                        GiveMasterLoot(lootIdx, ci)
                        DPrint(C_GREEN.."Master looted "..(itemLink or "item").." to "..targetName..C_RESET)
                        ScheduleRefresh(0.5)
                        return
                    end
                end
                DPrint(C_RED..targetName.." not in master loot candidates!"..C_RESET)
                return
            end
        end
    end

    -- 2) Item not in loot - check bags and trade
    local bag, slot = nil, nil
    if itemUid then
        local slotKey = uidToSlot[itemUid]
        if slotKey then
            local bagStr, slotStr = slotKey:match("^bag:(%d+):(%d+)$")
            if bagStr then
                bag, slot = tonumber(bagStr), tonumber(slotStr)
                -- Verify item is still there
                local link = GetContainerItemLink(bag, slot)
                if not link or GetItemIdFromLink(link) ~= itemId then
                    bag, slot = nil, nil
                end
            end
        end
    end
    -- Fallback to scan if uid slot not found
    if not bag then
        bag, slot = FindBagSlot(itemId)
    end
    if not bag then
        DPrint(C_RED.."Item not in loot or bags!"..C_RESET)
        return
    end

    local uid = GetUnitIdByName(targetName)
    if not uid then
        local myName = UnitName("player") or "me"
        SendRW((itemLink or "Item").." -> "..targetName.." trade "..myName)
        DPrint(C_YELLOW..targetName.." not found in group. Announced in RW."..C_RESET)
        return
    end
    if CheckInteractDistance(uid, 2) then
        pendingTrade = {bag=bag, slot=slot, itemId=itemId}
        InitiateTrade(uid)
        DPrint(C_GREEN.."Trading "..(itemLink or "item").." to "..targetName.."..."..C_RESET)
    else
        local myName = UnitName("player") or "me"
        SendRW((itemLink or "Item").." -> "..targetName.." trade "..myName)
        DPrint(C_YELLOW..targetName.." out of range. Announced in RW."..C_RESET)
    end
end

----------------------------------------------------------------------
-- CSV Parser
----------------------------------------------------------------------
local function ParseCSVLine(line)
    local fields = {}
    local pos = 1
    while pos <= #line do
        local c = line:sub(pos, pos)
        if c == '"' then
            local endQuote = line:find('"', pos + 1)
            if endQuote then
                table.insert(fields, line:sub(pos+1, endQuote-1))
                pos = endQuote + 2
            else
                table.insert(fields, line:sub(pos+1))
                break
            end
        elseif c == ',' then
            table.insert(fields, "")
            pos = pos + 1
        else
            local nc = line:find(',', pos)
            if nc then
                table.insert(fields, line:sub(pos, nc-1))
                pos = nc + 1
            else
                table.insert(fields, line:sub(pos))
                break
            end
        end
    end
    return fields
end

local function ClearAllData()
    wipe(reserves)
    wipe(reservesByName)
    wipe(awardLog)
    wipe(slotToUid)
    wipe(uidToSlot)
    wipe(uidToItemId)
    wipe(uidAwards)
    wipe(pendingOrphans)
    nextItemUid = 1
    importCount = 0
    activeRoll = nil
    displayMode = "bag"
    minQualityFilter = 2
    showBoE = false
    SausageRollImportDB.reserves = {}
    SausageRollImportDB.reservesByName = {}
    SausageRollImportDB.importCount = 0
    SausageRollImportDB.lastSRText = nil
end

local function ParseCSV(text)
    ClearAllData()
    local headerSkipped = false

    local function ProcessLine(line)
        local f = ParseCSVLine(line)
        if #f >= 4 then
            local itemName   = StripQuotes(f[1])
            local itemId     = tonumber(StripQuotes(f[2]))
            local from       = StripQuotes(f[3])
            local playerName = CapitalizeName(StripQuotes(f[4]))
            if itemId and playerName ~= "" then
                if not reserves[itemId] then reserves[itemId] = {} end
                table.insert(reserves[itemId], {name=playerName, itemName=itemName, from=from})
                if not reservesByName[playerName] then reservesByName[playerName] = {} end
                table.insert(reservesByName[playerName], {itemId=itemId, itemName=itemName, from=from})
                importCount = importCount + 1
            end
        end
    end

    for line in text:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            if not headerSkipped then
                local lo = line:lower()
                if lo:find("item") and (lo:find("itemid") or lo:find("item_id")) then
                    headerSkipped = true
                else
                    headerSkipped = true
                    ProcessLine(line)
                end
            else
                ProcessLine(line)
            end
        end
    end

    SausageRollImportDB.reserves = reserves
    SausageRollImportDB.reservesByName = reservesByName
    SausageRollImportDB.importCount = importCount
    SausageRollImportDB.lastSRText = text
    return importCount
end

local function ParseHRCSV(text)
    wipe(hardReserves)
    wipe(hardReserveCustom)
    local headerSkipped = false
    local inCustom = false
    local seen = {}

    for line in text:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            if inCustom then
                table.insert(hardReserveCustom, line)
            elseif line:match("^%-") then
                inCustom = true
                local after = line:match("^%-+%s*(.+)$")
                if after then table.insert(hardReserveCustom, after) end
            elseif not headerSkipped then
                local lo = line:lower()
                if lo:find("itemid") or lo:find("item_id") then
                    headerSkipped = true
                else
                    headerSkipped = true
                    local f = ParseCSVLine(line)
                    local id = tonumber(StripQuotes(f[1] or ""))
                    local name = StripQuotes(f[2] or "")
                    if id and not seen[id] then
                        seen[id] = true
                        table.insert(hardReserves, {itemId=id, itemName=name})
                    end
                end
            else
                local f = ParseCSVLine(line)
                local id = tonumber(StripQuotes(f[1] or ""))
                local name = StripQuotes(f[2] or "")
                if id and not seen[id] then
                    seen[id] = true
                    table.insert(hardReserves, {itemId=id, itemName=name})
                end
            end
        end
    end

    SausageRollImportDB.hardReserves = hardReserves
    SausageRollImportDB.hardReserveCustom = hardReserveCustom
    SausageRollImportDB.lastHRText = text
    return #hardReserves + #hardReserveCustom
end

----------------------------------------------------------------------
-- Item scanning
----------------------------------------------------------------------
local function ItemInBags(itemId)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and GetItemIdFromLink(link) == itemId then
                return true, link, bag, slot
            end
        end
    end
    return false, nil, nil, nil
end

local function ItemInLoot(itemId)
    if not isLootOpen then return false, nil end
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        if link and GetItemIdFromLink(link) == itemId then
            return true, link
        end
    end
    return false, nil
end

local function ItemExists(itemId)
    local inLoot, lLink = ItemInLoot(itemId)
    if inLoot then return true, "loot", lLink, nil, nil end
    local inBag, bLink, bag, slot = ItemInBags(itemId)
    if inBag then return true, "bag", bLink, bag, slot end
    return false, nil, nil, nil, nil
end

-- SR items that are physically present in loot/bags (duplicates preserved)
local function GetVisibleSRItems()
    local found = {}
    -- Loot items
    if isLootOpen and displayMode == "loot" then
        for i = 1, GetNumLootItems() do
            local link = GetLootSlotLink(i)
            if link then
                local itemId = GetItemIdFromLink(link)
                if itemId and reserves[itemId] then
                    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
                    if quality and quality >= minQualityFilter then
                        local slotKey = "loot:"..i
                        local uid = slotToUid[slotKey] or AssignUid(slotKey, itemId)
                        local award = uidAwards[uid]
                        local awardWinner = award and award.winner or nil
                        table.insert(found, {
                            itemId=itemId, link=link, icon=texture,
                            name=name or reserves[itemId][1].itemName,
                            quality=quality or 1, source="loot",
                            reservers=reserves[itemId],
                            lootIndex=i, uid=uid,
                            state=awardWinner and "AWARDED" or "HOLD",
                            awardWinner=awardWinner,
                        })
                    end
                end
            end
        end
    end
    -- Bag items (each slot separately - no dedup)
    if displayMode == "bag" then
        for bag = 0, 4 do
            for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local itemId = GetItemIdFromLink(link)
                    if itemId and reserves[itemId] then
                        local tradeTime = GetTradeTimeFromBag(bag, slot)
                        local isBoE = showBoE and (not tradeTime) and IsBoEFromBag(bag, slot)
                        local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
                        if quality and quality >= minQualityFilter then
                            local slotKey = "bag:"..bag..":"..slot
                            local uid = GetBagItemUid(slotKey, itemId)
                            local award = uidAwards[uid]
                            local awardWinner = award and award.winner or nil
                            table.insert(found, {
                                itemId=itemId, link=link, icon=texture,
                                name=name or reserves[itemId][1].itemName,
                                quality=quality or 1, source="bag",
                                reservers=reserves[itemId],
                                tradeTime=tradeTime,
                                tradeTimeScannedAt=tradeTime and GetTime() or nil,
                                bag=bag, slot=slot, uid=uid,
                                isBoE=isBoE,
                                state=awardWinner and "AWARDED" or "HOLD",
                                awardWinner=awardWinner,
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(found, function(a,b)
        if a.source ~= b.source then return a.source == "loot" end
        -- HOLD first, AWARDED last
        if a.state ~= b.state then return a.state == "HOLD" end
        return (a.quality or 0) > (b.quality or 0)
    end)
    return found
end

-- MS ROLL: non-SR items from loot + tradeable bag items (duplicates preserved)
local function GetMSRollItems()
    local found = {}
    if isLootOpen and displayMode == "loot" then
        for i = 1, GetNumLootItems() do
            local link = GetLootSlotLink(i)
            if link then
                local itemId = GetItemIdFromLink(link)
                if itemId and not reserves[itemId] then
                    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
                    if quality and quality >= minQualityFilter then
                        local slotKey = "loot:"..i
                        local uid = slotToUid[slotKey] or AssignUid(slotKey, itemId)
                        local award = uidAwards[uid]
                        local awardWinner = award and award.winner or nil
                        table.insert(found, {
                            itemId=itemId, link=link, icon=texture,
                            name=name or "Unknown", quality=quality,
                            source="loot", lootIndex=i, uid=uid,
                            state=awardWinner and "AWARDED" or "HOLD",
                            awardWinner=awardWinner,
                        })
                    end
                end
            end
        end
    end
    if displayMode == "bag" then
        for bag = 0, 4 do
            for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local itemId = GetItemIdFromLink(link)
                    if itemId and not reserves[itemId] then
                        local tradeTime = GetTradeTimeFromBag(bag, slot)
                        local isBoE = showBoE and (not tradeTime) and IsBoEFromBag(bag, slot)
                        if tradeTime or isBoE then
                            local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
                            if quality and quality >= minQualityFilter then
                                local slotKey = "bag:"..bag..":"..slot
                                local uid = GetBagItemUid(slotKey, itemId)
                                local award = uidAwards[uid]
                                local awardWinner = award and award.winner or nil
                                table.insert(found, {
                                    itemId=itemId, link=link, icon=texture,
                                    name=name or "Unknown", quality=quality,
                                    source="bag", tradeTime=tradeTime,
                                    tradeTimeScannedAt=tradeTime and GetTime() or nil,
                                    bag=bag, slot=slot, uid=uid,
                                    isBoE=isBoE,
                                    state=awardWinner and "AWARDED" or "HOLD",
                                    awardWinner=awardWinner,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(found, function(a,b)
        if a.source ~= b.source then return a.source == "loot" end
        if a.state ~= b.state then return a.state == "HOLD" end
        return (a.quality or 0) > (b.quality or 0)
    end)
    return found
end

----------------------------------------------------------------------
-- Quality colors
----------------------------------------------------------------------
local QC_TBL = {
    [0]={r=0.62,g=0.62,b=0.62}, [1]={r=1,g=1,b=1},
    [2]={r=0.12,g=1,b=0}, [3]={r=0,g=0.44,b=0.87},
    [4]={r=0.64,g=0.21,b=0.93}, [5]={r=1,g=0.5,b=0},
}
local function QC(q) return QC_TBL[q] or QC_TBL[1] end
local function QCHex(q)
    local c = QC(q)
    return string.format("|cff%02x%02x%02x", c.r*255, c.g*255, c.b*255)
end

----------------------------------------------------------------------
-- Roll system with countdown + separate Roll Window
----------------------------------------------------------------------
local COUNTDOWN_SECS = 3
local countdownTimer = nil
local rollFrame = nil  -- separate roll window
local rollRows = {}    -- Frame rows in roll window
local finishedRoll = nil -- stores last finished roll info {itemId, link, mode, winner, rolls}

local function CloseRollWindow()
    if activeRoll then SendSync("RX") end
    if rollFrame then rollFrame:Hide() end
    finishedRoll = nil
end

local function RefreshRollWindow()
    if not rollFrame then return end

    -- Determine what to show: active roll or finished roll
    local rollData = activeRoll or finishedRoll
    if not rollData then
        rollFrame:Hide()
        return
    end

    rollFrame:Show()
    -- Reposition next to main window
    if mainFrame and mainFrame:IsShown() then
        rollFrame:ClearAllPoints()
        rollFrame:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -4, 0)
    end

    -- Title
    if activeRoll then
        local cdText = ""
        if countdownTimer then
            if countdownTimer.remaining > 0 then
                cdText = "  "..C_RED..">> "..countdownTimer.remaining.." <<"..C_RESET
            elseif countdownTimer.remaining == 0 then
                cdText = "  "..C_RED..">> STOP! <<"..C_RESET
            else
                cdText = "  "..C_YELLOW.."..."..C_RESET
            end
        else
            cdText = "  "..C_GREEN.."("..#activeRoll.rolls.." rolls)"..C_RESET
        end
        rollFrame.title:SetText(C_ORANGE.."Rolling: "..C_RESET..(activeRoll.link or "?"))
        rollFrame.subtitle:SetText(C_ORANGE.."["..activeRoll.mode:upper().."]"..C_RESET..cdText)
    else
        -- Finished state
        rollFrame.title:SetText(C_GREEN.."Finished: "..C_RESET..(finishedRoll.link or "?"))
        if finishedRoll.winner then
            rollFrame.subtitle:SetText(C_GREEN.."Winner: "..C_CYAN..finishedRoll.winner..C_RESET.."  "..C_GRAY.."(trade to close)"..C_RESET)
        else
            rollFrame.subtitle:SetText(C_RED.."No winner"..C_RESET.."  "..C_GRAY.."(trade/bank to close)"..C_RESET)
        end
    end

    -- Get rolls to display
    local rolls = rollData.rolls or {}
    local validRolls = {}
    local excludedRolls = {}
    local invalidRolls = {}
    for _, r in ipairs(rolls) do
        if r.valid == false then
            table.insert(invalidRolls, r)
        elseif r.excluded then
            table.insert(excludedRolls, r)
        else
            table.insert(validRolls, r)
        end
    end
    table.sort(validRolls, function(a,b) return a.roll > b.roll end)
    table.sort(excludedRolls, function(a,b) return a.roll > b.roll end)

    -- Hide old rows
    for _, row in ipairs(rollRows) do row.text:SetText(""); row:Hide() end

    local maxShow = 20
    local yOff = 0
    local isActive = (activeRoll ~= nil)
    local totalToShow = #validRolls + #excludedRolls + #invalidRolls
    local displayIdx = 0

    -- Helper to get or create a roll row frame
    local function GetRow(idx)
        if not rollRows[idx] then
            local row = CreateFrame("Frame", nil, rollFrame.content)
            row:SetHeight(16)

            local btn = CreateFrame("Button", nil, row)
            btn:SetSize(14, 14)
            btn:SetPoint("LEFT", 0, 0)
            btn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"})
            btn:SetBackdropColor(0, 0, 0, 0.6)
            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btnText:SetPoint("CENTER")
            row.excludeBtn = btn
            row.excludeBtnText = btnText
            btn:SetScript("OnClick", function(self)
                if self.rollData then
                    self.rollData.excluded = not self.rollData.excluded
                    RefreshRollWindow()
                end
            end)

            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetJustifyH("LEFT")
            fs:SetPoint("LEFT", 18, 0)
            fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.text = fs

            table.insert(rollRows, row)
        end
        return rollRows[idx]
    end

    -- Display valid rolls
    for i, r in ipairs(validRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rollFrame.content, "TOPLEFT", 6, -yOff)
        row:SetPoint("RIGHT", rollFrame.content, "RIGHT", -6, 0)

        local srTag = ""
        if rollData.mode == "sr" then
            local entries = reserves[rollData.itemId] or {}
            for _, e in ipairs(entries) do
                if r.name:lower() == e.name:lower() then
                    srTag = C_GREEN.." [SR]"..C_RESET
                    break
                end
            end
        end
        local posColor = i == 1 and C_GREEN or C_WHITE
        row.text:SetText(posColor..i..". "..C_CYAN..r.name..C_WHITE.." - "..r.roll..srTag..C_RESET)

        if isActive then
            row.excludeBtn.rollData = r
            row.excludeBtnText:SetText(C_RED.."X"..C_RESET)
            row.excludeBtn:Show()
        else
            row.excludeBtn:Hide()
        end
        row:Show()
        yOff = yOff + 16
    end

    -- Display excluded rolls
    for _, r in ipairs(excludedRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rollFrame.content, "TOPLEFT", 6, -yOff)
        row:SetPoint("RIGHT", rollFrame.content, "RIGHT", -6, 0)

        row.text:SetText(C_GRAY..r.name.." - "..r.roll.." [EXCLUDED]"..C_RESET)

        if isActive then
            row.excludeBtn.rollData = r
            row.excludeBtnText:SetText(C_GREEN.."+"..C_RESET)
            row.excludeBtn:Show()
        else
            row.excludeBtn:Hide()
        end
        row:Show()
        yOff = yOff + 16
    end

    -- Display invalid rolls
    for _, r in ipairs(invalidRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rollFrame.content, "TOPLEFT", 6, -yOff)
        row:SetPoint("RIGHT", rollFrame.content, "RIGHT", -6, 0)

        row.text:SetText(C_GRAY.."  x "..r.name.." - "..r.roll.." (not eligible)"..C_RESET)
        row.excludeBtn:Hide()
        row:Show()
        yOff = yOff + 16
    end

    -- "Waiting" message if no rolls
    if totalToShow == 0 then
        displayIdx = 1
        local row = GetRow(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rollFrame.content, "TOPLEFT", 6, 0)
        row:SetPoint("RIGHT", rollFrame.content, "RIGHT", -6, 0)
        row.text:SetText(C_GRAY.."Waiting for /roll ..."..C_RESET)
        row.excludeBtn:Hide()
        row:Show()
        yOff = 16
    end

    rollFrame.content:SetHeight(math.max(yOff + 4, 1))
end

local function CreateRollWindow()
    if rollFrame then return end

    local f = CreateFrame("Frame","SRIRollFrame",UIParent)
    f:SetSize(280, 280)
    -- Position beside main window
    if mainFrame then
        f:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -4, 0)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -734, -10)
    end
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=24,
        insets={left=6,right=6,top=6,bottom=6},
    })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)

    local closeX = CreateFrame("Button",nil,f,"UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT",-2,-2)

    -- Title
    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    t:SetPoint("TOPLEFT", 10, -10)
    t:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    t:SetJustifyH("LEFT")
    f.title = t

    -- Subtitle (mode + countdown)
    local st = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    st:SetPoint("TOPLEFT", 10, -28)
    st:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    st:SetJustifyH("LEFT")
    f.subtitle = st

    -- Scroll for roll list
    local sc = CreateFrame("ScrollFrame", "SRIRollScroll", f, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 8, -46)
    sc:SetPoint("BOTTOMRIGHT", -28, 34)

    local ct = CreateFrame("Frame", nil, sc)
    ct:SetWidth(sc:GetWidth())
    ct:SetHeight(1)
    sc:SetScrollChild(ct)
    f.content = ct

    -- /roll button at bottom
    local rollBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rollBtn:SetSize(120, 22)
    rollBtn:SetPoint("BOTTOM", 0, 8)
    rollBtn:SetText("/roll")
    rollBtn:SetScript("OnClick", function() RandomRoll(1, 100) end)

    f:Hide()
    rollFrame = f
end

----------------------------------------------------------------------
-- Client Roll Window (non-ML players)
----------------------------------------------------------------------
RefreshClientRollWindow = function()
    if not clientRollFrame then return end
    if not clientRoll then
        clientRollFrame:Hide()
        return
    end
    clientRollFrame:Show()

    -- Refresh item info (may become available after initial RS)
    local iName, iLink, iRarity, _, _, _, _, _, _, iTexture = GetItemInfo(clientRoll.itemId)
    local link = iLink or clientRoll.link
    local quality = iRarity or clientRoll.quality or 1
    local texture = iTexture or clientRoll.icon
    clientRoll.link = link
    clientRoll.quality = quality
    clientRoll.icon = texture

    clientRollFrame.iconTex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local qc = QC(quality)
    clientRollFrame.iconBorder:SetBackdropBorderColor(qc.r, qc.g, qc.b, 0.8)
    clientRollFrame.itemText:SetText(QCHex(quality) .. (iName or ("Item " .. clientRoll.itemId)) .. C_RESET)

    -- Mode + countdown / winner
    local modeTag = C_ORANGE .. "[" .. clientRoll.mode:upper() .. "]" .. C_RESET
    if clientRoll.finished then
        if clientRoll.winner then
            clientRollFrame.subtitle:SetText(modeTag .. "  " .. C_GREEN .. "Winner: " .. C_CYAN .. clientRoll.winner .. C_WHITE .. " (" .. clientRoll.winnerRoll .. ")" .. C_RESET)
        else
            clientRollFrame.subtitle:SetText(modeTag .. "  " .. C_RED .. "No winner" .. C_RESET)
        end
    elseif clientRoll.countdown then
        if clientRoll.countdown > 0 then
            clientRollFrame.subtitle:SetText(modeTag .. "  " .. C_RED .. ">> " .. clientRoll.countdown .. " <<" .. C_RESET)
        else
            clientRollFrame.subtitle:SetText(modeTag .. "  " .. C_RED .. ">> STOP! <<" .. C_RESET)
        end
    else
        clientRollFrame.subtitle:SetText(modeTag .. "  " .. C_GREEN .. "(" .. #clientRoll.rolls .. " rolls)" .. C_RESET)
    end

    -- Eligible list (SR mode only)
    local yOff = 0
    local myName = UnitName("player")

    if clientRoll.mode == "sr" and #clientRoll.eligible > 0 then
        if not clientRollFrame.eligibleHeader then
            clientRollFrame.eligibleHeader = clientRollFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            clientRollFrame.eligibleHeader:SetJustifyH("LEFT")
        end
        clientRollFrame.eligibleHeader:ClearAllPoints()
        clientRollFrame.eligibleHeader:SetPoint("TOPLEFT", clientRollFrame.content, "TOPLEFT", 6, -yOff)
        clientRollFrame.eligibleHeader:SetText(C_ORANGE .. "Eligible: [x" .. #clientRoll.eligible .. "]" .. C_RESET)
        clientRollFrame.eligibleHeader:Show()
        yOff = yOff + 14

        local nameParts = {}
        for _, eName in ipairs(clientRoll.eligible) do
            if myName and eName:lower() == myName:lower() then
                table.insert(nameParts, C_GREEN .. eName .. C_RESET)
            else
                table.insert(nameParts, C_CYAN .. eName .. C_RESET)
            end
        end

        -- Build name lines, max 3 names per line (client window is narrow)
        local nameLines = {}
        for idx = 1, #nameParts, 3 do
            local chunk = {}
            for j = idx, math.min(idx + 2, #nameParts) do
                table.insert(chunk, nameParts[j])
            end
            table.insert(nameLines, table.concat(chunk, ", "))
        end

        if not clientRollFrame.eligibleText then
            local et = clientRollFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            et:SetJustifyH("LEFT")
            et:SetFont(et:GetFont(), 10)
            clientRollFrame.eligibleText = et
        end
        clientRollFrame.eligibleText:ClearAllPoints()
        clientRollFrame.eligibleText:SetPoint("TOPLEFT", clientRollFrame.content, "TOPLEFT", 10, -yOff)
        clientRollFrame.eligibleText:SetPoint("TOPRIGHT", clientRollFrame.content, "TOPRIGHT", -10, -yOff)
        clientRollFrame.eligibleText:SetText(table.concat(nameLines, "\n"))
        clientRollFrame.eligibleText:Show()
        local lineCount = #nameLines
        local lineH = 12
        yOff = yOff + (lineCount * lineH) + 6
    else
        if clientRollFrame.eligibleHeader then clientRollFrame.eligibleHeader:Hide() end
        if clientRollFrame.eligibleText then clientRollFrame.eligibleText:Hide() end
    end

    -- Rolls header
    if not clientRollFrame.rollsHeader then
        clientRollFrame.rollsHeader = clientRollFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        clientRollFrame.rollsHeader:SetJustifyH("LEFT")
    end
    clientRollFrame.rollsHeader:ClearAllPoints()
    clientRollFrame.rollsHeader:SetPoint("TOPLEFT", clientRollFrame.content, "TOPLEFT", 6, -yOff)
    clientRollFrame.rollsHeader:SetText(C_ORANGE .. "Rolls:" .. C_RESET)
    clientRollFrame.rollsHeader:Show()
    yOff = yOff + 14

    -- Sort rolls
    local validRolls, invalidRolls = {}, {}
    for _, r in ipairs(clientRoll.rolls) do
        if r.valid then table.insert(validRolls, r) else table.insert(invalidRolls, r) end
    end
    table.sort(validRolls, function(a,b) return a.roll > b.roll end)

    -- Hide old rows
    for _, row in ipairs(clientRollRows) do row:Hide() end

    local maxShow = 20
    local displayIdx = 0

    local function GetClientRow(idx)
        if not clientRollRows[idx] then
            local row = CreateFrame("Frame", nil, clientRollFrame.content)
            row:SetHeight(15)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetJustifyH("LEFT")
            fs:SetPoint("LEFT", 6, 0)
            fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.text = fs
            clientRollRows[idx] = row
        end
        return clientRollRows[idx]
    end

    -- Valid rolls
    for i, r in ipairs(validRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetClientRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", clientRollFrame.content, "TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", clientRollFrame.content, "RIGHT", 0, 0)
        local posColor = i == 1 and C_GREEN or C_WHITE
        local nameColor = (myName and r.name:lower() == myName:lower()) and C_YELLOW or C_CYAN
        row.text:SetText(posColor .. i .. ". " .. nameColor .. r.name .. C_WHITE .. " - " .. r.roll .. C_RESET)
        row:Show()
        yOff = yOff + 15
    end

    -- Invalid rolls
    for _, r in ipairs(invalidRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetClientRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", clientRollFrame.content, "TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", clientRollFrame.content, "RIGHT", 0, 0)
        row.text:SetText(C_GRAY .. "  x " .. r.name .. " - " .. r.roll .. " (not eligible)" .. C_RESET)
        row:Show()
        yOff = yOff + 15
    end

    -- Waiting message
    if #clientRoll.rolls == 0 then
        displayIdx = 1
        local row = GetClientRow(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", clientRollFrame.content, "TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", clientRollFrame.content, "RIGHT", 0, 0)
        row.text:SetText(C_GRAY .. "Waiting for /roll ..." .. C_RESET)
        row:Show()
        yOff = yOff + 15
    end

    clientRollFrame.content:SetHeight(math.max(yOff + 4, 1))

    -- /roll button state
    if clientRoll.finished then
        clientRollFrame.rollBtn:Disable()
    else
        clientRollFrame.rollBtn:Enable()
    end
end

CreateClientRollWindow = function()
    if clientRollFrame then return end

    local f = CreateFrame("Frame", "SRIClientRollFrame", UIParent)
    f:SetSize(260, 300)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=24,
        insets={left=6,right=6,top=6,bottom=6},
    })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)

    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)

    -- Item icon
    local iconBtn = CreateFrame("Button", nil, f)
    iconBtn:SetSize(28, 28)
    iconBtn:SetPoint("TOPLEFT", 10, -10)
    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    f.iconTex = iconTex

    local brd = CreateFrame("Frame", nil, iconBtn)
    brd:SetPoint("TOPLEFT", -2, 2)
    brd:SetPoint("BOTTOMRIGHT", 2, -2)
    brd:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2})
    f.iconBorder = brd

    iconBtn:SetScript("OnEnter", function(self)
        if clientRoll and clientRoll.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. clientRoll.itemId)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Item name
    local itemText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
    itemText:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    itemText:SetJustifyH("LEFT")
    f.itemText = itemText

    -- Subtitle
    local st = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    st:SetPoint("TOPLEFT", 10, -42)
    st:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    st:SetJustifyH("LEFT")
    f.subtitle = st

    -- Scroll
    local sc = CreateFrame("ScrollFrame", "SRIClientRollScroll", f, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 8, -58)
    sc:SetPoint("BOTTOMRIGHT", -28, 34)

    local ct = CreateFrame("Frame", nil, sc)
    ct:SetWidth(sc:GetWidth())
    ct:SetHeight(1)
    sc:SetScrollChild(ct)
    f.content = ct

    -- /roll button
    local rollBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rollBtn:SetSize(120, 22)
    rollBtn:SetPoint("BOTTOM", 0, 8)
    rollBtn:SetText("/roll")
    rollBtn:SetScript("OnClick", function() RandomRoll(1, 100) end)
    f.rollBtn = rollBtn

    f:Hide()
    clientRollFrame = f
end

local function StartRoll(uid, itemId, link, mode)
    countdownTimer = nil
    activeRoll = {uid=uid, itemId=itemId, link=link, mode=mode, rolls={}}
    if mode == "sr" then
        local entries = reserves[itemId]
        if entries then
            local names = {}
            for _, e in ipairs(entries) do
                local low = e.name:lower()
                local dup = false
                for _, n in ipairs(names) do if n:lower() == low then dup = true; break end end
                if not dup then table.insert(names, e.name) end
            end
            SendRW(link.." SR: "..table.concat(names, ", ").." - /roll!")
        end
    else
        SendRW(link.." "..mode:upper().." - /roll!")
    end
    DPrint(C_GREEN.."Roll started: "..link.." ("..mode:upper()..")"..C_RESET)
    CreateRollWindow()
    RefreshRollWindow()
    -- Broadcast to clients
    local _, _, rollQuality = GetItemInfo(link)
    SendSync("RS", itemId, rollQuality or 4, mode)
    if mode == "sr" then
        local srEntries = reserves[itemId]
        if srEntries then
            local eligibleNames = {}
            for _, e in ipairs(srEntries) do
                table.insert(eligibleNames, e.name)
            end
            SendSyncEligible(eligibleNames)
        end
    end
end

local function AnnounceWinnerFinal()
    if not activeRoll then return end
    local r = activeRoll
    if #r.rolls == 0 then
        SendRW(r.link.." - No rolls!")
        SendSync("RE", "", 0)
        finishedRoll = {uid=r.uid, itemId=r.itemId, link=r.link, mode=r.mode, rolls=r.rolls, winner=nil}
        activeRoll = nil
        countdownTimer = nil
        RefreshRollWindow()
        RefreshMainFrame()
        return
    end

    local winnerName = nil
    if r.mode == "sr" then
        local srRolls = {}
        local entries = reserves[r.itemId] or {}
        for _, roll in ipairs(r.rolls) do
            if roll.valid and not roll.excluded then
                for _, e in ipairs(entries) do
                    if roll.name:lower() == e.name:lower() then
                        table.insert(srRolls, roll)
                        break
                    end
                end
            end
        end
        if #srRolls == 0 then
            SendRW(r.link.." - No valid rolls!")
        else
            table.sort(srRolls, function(a,b) return a.roll > b.roll end)
            local w = srRolls[1]
            winnerName = w.name
            SendRW(r.link.." >> "..w.name.." wins ("..w.roll..")")
            table.insert(awardLog, {itemId=r.itemId, winner=w.name, link=r.link})
            uidAwards[r.uid] = {winner=w.name, link=r.link}
        end
    else
        local validRolls = {}
        for _, roll in ipairs(r.rolls) do
            if roll.valid ~= false and not roll.excluded then
                table.insert(validRolls, roll)
            end
        end
        if #validRolls == 0 then
            SendRW(r.link.." - No valid rolls!")
        else
            table.sort(validRolls, function(a,b) return a.roll > b.roll end)
            local w = validRolls[1]
            winnerName = w.name
            SendRW(r.link.." >> "..w.name.." wins ("..w.roll..")")
            table.insert(awardLog, {itemId=r.itemId, winner=w.name, link=r.link})
            uidAwards[r.uid] = {winner=w.name, link=r.link}
        end
    end

    DPrint(C_GRAY.."All rolls:"..C_RESET)
    table.sort(r.rolls, function(a,b) return a.roll > b.roll end)
    for _, roll in ipairs(r.rolls) do
        local exTag = roll.excluded and (" "..C_RED.."[EXCLUDED]"..C_RESET) or ""
        DPrint("  "..C_CYAN..roll.name..C_WHITE..": "..roll.roll..exTag..C_RESET)
    end

    -- Broadcast winner to clients
    if winnerName then
        local winRoll = 0
        for _, roll in ipairs(r.rolls) do
            if roll.name:lower() == winnerName:lower() and roll.valid ~= false and not roll.excluded then
                if roll.roll > winRoll then winRoll = roll.roll end
            end
        end
        SendSync("RE", winnerName, winRoll)
    else
        SendSync("RE", "", 0)
    end

    -- Keep roll window open — store finished roll
    finishedRoll = {uid=r.uid, itemId=r.itemId, link=r.link, mode=r.mode, rolls=r.rolls, winner=winnerName}
    activeRoll = nil
    countdownTimer = nil
    RefreshRollWindow()
    RefreshMainFrame()
end

local function StartCountdown()
    if not activeRoll then
        DPrint(C_RED.."No active roll!"..C_RESET)
        return
    end
    if countdownTimer then
        DPrint(C_YELLOW.."Countdown already running!"..C_RESET)
        return
    end
    SendRW(activeRoll.link.." ends in "..COUNTDOWN_SECS.."...")
    countdownTimer = {remaining=COUNTDOWN_SECS, elapsed=0}
end

local function UpdateCountdown(elapsed)
    if not countdownTimer then return end
    countdownTimer.elapsed = countdownTimer.elapsed + elapsed
    if countdownTimer.elapsed >= 1.0 then
        countdownTimer.elapsed = countdownTimer.elapsed - 1.0
        countdownTimer.remaining = countdownTimer.remaining - 1
        if countdownTimer.remaining > 0 then
            SendRW(countdownTimer.remaining.."...")
            SendSync("RC", countdownTimer.remaining)
        elseif countdownTimer.remaining == 0 then
            SendRW("STOP!")
            SendSync("RC", 0)
            countdownTimer.remaining = -1
        else
            AnnounceWinnerFinal()
        end
        RefreshRollWindow()
    end
end

local function OnSystemMsg(msg)
    if not activeRoll then return end
    local name, roll = msg:match("(.+) rolls (%d+) %(1%-100%)")
    if not name or not roll then return end
    roll = tonumber(roll)

    -- Count how many rolls this player already has
    local existingCount = 0
    for _, r in ipairs(activeRoll.rolls) do
        if r.name:lower() == name:lower() then
            existingCount = existingCount + 1
        end
    end

    if activeRoll.mode == "sr" then
        -- SR: allowed rolls = number of SR entries this player has for this item
        local allowedRolls = 0
        local entries = reserves[activeRoll.itemId] or {}
        for _, e in ipairs(entries) do
            if e.name:lower() == name:lower() then
                allowedRolls = allowedRolls + 1
            end
        end

        if allowedRolls == 0 then
            -- Not an SR holder - ignore silently (they might roll but it won't count)
            table.insert(activeRoll.rolls, {name=name, roll=roll, valid=false})
            SendSync("RU", name, roll, "0")
            RefreshRollWindow()
            return
        end

        if existingCount >= allowedRolls then
            -- Exceeded allowed rolls - whisper warning, don't add
            SendChatMessage(name.." - your roll was IGNORED! You have "..allowedRolls.."x SR = "..allowedRolls.." roll(s) allowed. You already rolled "..existingCount.."x.", "WHISPER", nil, name)
            DPrint(C_RED..name.." exceeded SR roll limit ("..existingCount.."/"..allowedRolls..") - ignored"..C_RESET)
            RefreshRollWindow()
            return
        end

        -- Valid SR roll
        table.insert(activeRoll.rolls, {name=name, roll=roll, valid=true})
        SendSync("RU", name, roll, "1")
    else
        -- MS: only 1 roll allowed per player
        if existingCount >= 1 then
            SendChatMessage(name.." - your extra roll was IGNORED! Only 1 roll allowed for MS.", "WHISPER", nil, name)
            DPrint(C_RED..name.." tried to roll again (MS) - ignored"..C_RESET)
            RefreshRollWindow()
            return
        end

        table.insert(activeRoll.rolls, {name=name, roll=roll, valid=true})
        SendSync("RU", name, roll, "1")
    end

    RefreshRollWindow()
end

-- Lightweight trade timer display update (no full rebuild)
local function UpdateTradeTimerDisplays()
    if not mainFrame or not mainFrame:IsShown() then return end
    local now = GetTime()
    local function UpdateRowTimer(row)
        if not row:IsShown() or not row.data then return end
        local item = row.data
        if item.source == "bag" and item.tradeTime and item.tradeTimeScannedAt
           and item.state ~= "AWARDED" then
            local remaining = item.tradeTime - (now - item.tradeTimeScannedAt)
            if remaining < 0 then remaining = 0 end
            local totalMins = math.floor(remaining / 60)
            local hours = math.floor(totalMins / 60)
            local mins = totalMins - (hours * 60)
            local timeStr = hours > 0 and (hours.."h "..mins.."m") or (mins.."m")
            local tColor = C_GREEN
            if totalMins < 10 then tColor = C_RED
            elseif totalMins < 30 then tColor = C_YELLOW end
            row.tradeText:SetText(tColor..timeStr..C_RESET)
        end
    end
    for _, row in ipairs(srRows) do UpdateRowTimer(row) end
    for _, row in ipairs(msRows) do UpdateRowTimer(row) end
end

-- Centralized ScheduleRefresh() - throttle/debounce for GUI updates
local refreshTimer = CreateFrame("Frame")
local refreshPending = false
local refreshDelay = 0
local REFRESH_MIN_INTERVAL = 0.3
local lastRefreshTime = 0

ScheduleRefresh = function(delay)
    delay = delay or 0.05
    if refreshPending then
        refreshDelay = math.min(refreshDelay, delay)
        return
    end
    refreshPending = true
    refreshDelay = delay
    local waited = 0
    refreshTimer:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if waited >= refreshDelay then
            self:SetScript("OnUpdate", nil)
            refreshPending = false
            local now = GetTime()
            if (now - lastRefreshTime) >= REFRESH_MIN_INTERVAL then
                lastRefreshTime = now
                if mainFrame then
                    RefreshMainFrame()
                end
            else
                local remaining = REFRESH_MIN_INTERVAL - (now - lastRefreshTime)
                ScheduleRefresh(remaining)
            end
        end
    end)
end

-- Countdown ticker frame + periodic trade timer refresh
local tickerFrame = CreateFrame("Frame")
local tradeTimerElapsed = 0
local tradeDisplayElapsed = 0
tickerFrame:SetScript("OnUpdate", function(self, elapsed)
    UpdateCountdown(elapsed)

    -- Client auto-hide timer
    if clientAutoHideTimer then
        clientAutoHideTimer = clientAutoHideTimer - elapsed
        if clientAutoHideTimer <= 0 then
            clientAutoHideTimer = nil
            clientRoll = nil
            if clientRollFrame then clientRollFrame:Hide() end
        end
    end

    tradeDisplayElapsed = tradeDisplayElapsed + elapsed
    if tradeDisplayElapsed >= 1 then
        tradeDisplayElapsed = 0
        UpdateTradeTimerDisplays()
    end

    tradeTimerElapsed = tradeTimerElapsed + elapsed
    if tradeTimerElapsed >= 5 then
        tradeTimerElapsed = 0
        if mainFrame and mainFrame:IsShown() then
            RefreshMainFrame()
        end
    end
end)

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local CreateImportFrame
local CreateHRImportFrame
local mainFrame, srRows, msRows = nil, {}, {}
local ROW_HEIGHT = 42
local MS_ROW_HEIGHT = 56
local rollModeMenuFrame = CreateFrame("Frame", "SRI_RollModeMenu", UIParent, "UIDropDownMenuTemplate")
local charDropdownFrame = CreateFrame("Frame", "SRI_CharDropdownMenu", UIParent, "UIDropDownMenuTemplate")

----------------------------------------------------------------------
-- GUI: Row builder
----------------------------------------------------------------------
local function CreateRow(parent, rowTable, index, mode)
    local rn = "SRI_"..mode.."_R"..index
    local row = CreateFrame("Frame", rn, parent)
    row:SetHeight(mode == "ms" and MS_ROW_HEIGHT or ROW_HEIGHT)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    if index % 2 == 0 then bg:SetVertexColor(0.15,0.15,0.15,0.6)
    else bg:SetVertexColor(0.08,0.08,0.08,0.4) end

    local iconBtn = CreateFrame("Button", rn.."I", row)
    iconBtn:SetSize(30,30)
    iconBtn:SetPoint("LEFT",4,0)
    local iconTex = iconBtn:CreateTexture(nil,"ARTWORK")
    iconTex:SetAllPoints()
    row.iconTex = iconTex

    local brd = CreateFrame("Frame", nil, iconBtn)
    brd:SetPoint("TOPLEFT", -2, 2)
    brd:SetPoint("BOTTOMRIGHT", 2, -2)
    brd:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2})
    row.iconBorder = brd

    iconBtn:SetScript("OnEnter", function(self)
        if row.link then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(row.link)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Buttons right-aligned: Roll | Winner | Trade | Bank
    local BW, BH, BF = 55, 18, 9
    local gap = 2

    local bankBtn = CreateFrame("Button", rn.."B", row, "UIPanelButtonTemplate")
    bankBtn:SetSize(BW, BH)
    bankBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    bankBtn:SetText("Bank")
    bankBtn:GetFontString():SetFont(bankBtn:GetFontString():GetFont(), BF)
    row.bankBtn = bankBtn

    local dissBtn = CreateFrame("Button", rn.."D", row, "UIPanelButtonTemplate")
    dissBtn:SetSize(BW, 16)
    dissBtn:SetPoint("BOTTOM", bankBtn, "TOP", 0, 2)
    dissBtn:SetText("Diss")
    dissBtn:GetFontString():SetFont(dissBtn:GetFontString():GetFont(), 8)
    row.dissBtn = dissBtn

    local tradeBtn = CreateFrame("Button", rn.."T", row, "UIPanelButtonTemplate")
    tradeBtn:SetSize(BW, BH)
    tradeBtn:SetPoint("RIGHT", bankBtn, "LEFT", -gap, 0)
    tradeBtn:SetText("Trade")
    tradeBtn:GetFontString():SetFont(tradeBtn:GetFontString():GetFont(), BF)
    row.tradeBtn = tradeBtn

    local resetBtn = CreateFrame("Button", rn.."Reset", row, "UIPanelButtonTemplate")
    resetBtn:SetSize(BW, 16)
    resetBtn:SetPoint("BOTTOMLEFT", tradeBtn, "TOPLEFT", 0, 2)
    resetBtn:GetFontString():SetFont(resetBtn:GetFontString():GetFont(), 8)
    resetBtn:SetText("Reset")
    row.resetBtn = resetBtn

    local winBtn = CreateFrame("Button", rn.."W", row, "UIPanelButtonTemplate")
    winBtn:SetSize(BW, BH)
    winBtn:SetPoint("RIGHT", tradeBtn, "LEFT", -gap, 0)
    winBtn:SetText("Winner")
    winBtn:GetFontString():SetFont(winBtn:GetFontString():GetFont(), BF)
    row.winBtn = winBtn

    local rollBtn = CreateFrame("Button", rn.."R", row, "UIPanelButtonTemplate")
    rollBtn:SetSize(BW, BH)
    rollBtn:SetPoint("RIGHT", winBtn, "LEFT", -gap, 0)
    rollBtn:SetText("Roll")
    rollBtn:GetFontString():SetFont(rollBtn:GetFontString():GetFont(), BF)
    row.rollBtn = rollBtn

    if mode == "ms" then
        local modeBtn = CreateFrame("Button", rn.."Mode", row, "UIPanelButtonTemplate")
        modeBtn:SetSize(BW*2 + gap, 16)
        modeBtn:SetPoint("BOTTOMLEFT", rollBtn, "TOPLEFT", 0, 2)
        modeBtn:GetFontString():SetFont(modeBtn:GetFontString():GetFont(), 8)
        modeBtn:SetText("MS")
        row.modeBtn = modeBtn
        row.rollMode = "ms"

        modeBtn:SetScript("OnClick", function(self)
            local menuList = {
                {text = "MS", checked = (row.rollMode == "ms"), func = function() row.rollMode = "ms"; modeBtn:SetText("MS"); row.infoText:SetText(C_YELLOW.."MS Roll"..C_RESET) end},
                {text = "OS", checked = (row.rollMode == "os"), func = function() row.rollMode = "os"; modeBtn:SetText("OS"); row.infoText:SetText(C_YELLOW.."OS Roll"..C_RESET) end},
                {text = "FREELOOT", checked = (row.rollMode == "freeloot"), func = function() row.rollMode = "freeloot"; modeBtn:SetText("FREELOOT"); row.infoText:SetText(C_YELLOW.."FREELOOT Roll"..C_RESET) end},
            }
            EasyMenu(menuList, rollModeMenuFrame, self, 0, 0, "MENU")
        end)
    end

    -- Source + Trade timer: left of Roll button
    local srcText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    srcText:SetPoint("RIGHT", rollBtn, "LEFT", -6, 6)
    row.srcText = srcText

    local tradeTimerText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tradeTimerText:SetPoint("RIGHT", rollBtn, "LEFT", -6, -6)
    tradeTimerText:SetFont(tradeTimerText:GetFont(), 9)
    row.tradeText = tradeTimerText

    -- Item name (top line) — from icon to src area
    local itemText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    itemText:SetPoint("TOPLEFT", iconBtn,"TOPRIGHT",6,-2)
    itemText:SetPoint("RIGHT", srcText, "LEFT", -8, 0)
    itemText:SetJustifyH("LEFT")
    row.itemText = itemText

    -- Info line (SR names / MS Roll) — hoverable for full list
    local infoBtn = CreateFrame("Button", rn.."Info", row)
    infoBtn:SetPoint("TOPLEFT", iconBtn,"TOPRIGHT",6,-16)
    infoBtn:SetPoint("RIGHT", srcText, "LEFT", -8, 0)
    local infoText = infoBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT")
    infoText:SetPoint("TOPRIGHT")
    infoText:SetJustifyH("LEFT")
    infoText:SetFont(infoText:GetFont(), 9)
    infoText:SetNonSpaceWrap(true)
    row.infoText = infoText
    row.infoBtn = infoBtn
    row.fullInfoText = "" -- store full text for tooltip

    infoBtn:SetScript("OnEnter", function(self)
        if row.fullInfoText and row.fullInfoText ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Soft Reserves:", 1, 0.82, 0, false)
            -- Split names for tooltip
            for part in row.fullInfoText:gmatch("[^,]+") do
                part = part:match("^%s*(.-)%s*$")
                GameTooltip:AddLine(part, 0, 1, 1, false)
            end
            GameTooltip:Show()
        end
    end)
    infoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:Hide()
    table.insert(rowTable, row)
    return row
end

local function SetupRow(row, item, mode)
    row.data = item
    row.link = item.link
    row.iconTex:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local qc = QC(item.quality)
    row.iconBorder:SetBackdropBorderColor(qc.r, qc.g, qc.b, 0.8)
    row.itemText:SetText(QCHex(item.quality)..(item.name or "?")..C_RESET)

    if mode == "sr" and item.reservers then
        local plainNames = {}
        local colorNames = {}
        for _, r in ipairs(item.reservers) do
            table.insert(plainNames, r.name)
            local color = C_CYAN
            if IsInRaid() then
                local found = false
                for i=1,GetNumRaidMembers() do
                    local rn = GetRaidRosterInfo(i)
                    if rn and rn:lower()==r.name:lower() then found=true; break end
                end
                if not found then color = C_RED end
            end
            table.insert(colorNames, color..r.name..C_RESET)
        end
        row.fullInfoText = table.concat(plainNames, ", ")
        local header = "SR: "..C_ORANGE.."[x"..#item.reservers.."]"..C_RESET
        -- Build name lines, max 4 names per line
        local nameLines = {}
        for idx = 1, #colorNames, 4 do
            local chunk = {}
            for j = idx, math.min(idx + 3, #colorNames) do
                table.insert(chunk, colorNames[j])
            end
            table.insert(nameLines, table.concat(chunk, ", "))
        end
        local info = header.."\n"..table.concat(nameLines, "\n")
        row.infoText:SetText(info)
        local lineCount = 1 + #nameLines  -- 1 header + name lines
        local lineH = 12
        local textHeight = lineCount * lineH
        row.infoBtn:SetHeight(textHeight)
        row.dynamicHeight = math.max(ROW_HEIGHT, 20 + textHeight + 4)
        row:SetHeight(row.dynamicHeight)
    else
        local rollLabel = (row.rollMode or "ms"):upper()
        row.infoText:SetText(C_YELLOW..rollLabel.." Roll"..C_RESET)
        row.fullInfoText = ""
    end

    -- State + Source display
    if item.state == "AWARDED" then
        row.srcText:SetText(C_GREEN.."AWARDED"..C_RESET)
        row.tradeText:SetText(C_CYAN.."-> "..item.awardWinner..C_RESET)
    elseif item.source == "loot" then
        row.srcText:SetText(C_ORANGE.."HOLD"..C_RESET)
        row.tradeText:SetText(C_GREEN.."LOOT"..C_RESET)
    else
        row.srcText:SetText(C_ORANGE.."HOLD"..C_RESET)
        if item.tradeTime then
            local totalMins = math.floor(item.tradeTime / 60)
            local hours = math.floor(totalMins / 60)
            local mins = totalMins - (hours * 60)
            local timeStr
            if hours > 0 then
                timeStr = hours.."h "..mins.."m"
            else
                timeStr = mins.."m"
            end
            local tColor = C_GREEN
            if totalMins < 10 then tColor = C_RED
            elseif totalMins < 30 then tColor = C_YELLOW end
            row.tradeText:SetText(tColor..timeStr..C_RESET)
        elseif item.isBoE then
            row.tradeText:SetText(C_GREEN.."BoE"..C_RESET)
        else
            row.tradeText:SetText(C_GRAY.."BAG"..C_RESET)
        end
    end

    -- Dim buttons for AWARDED items or items with active/finished roll
    local hasRoll = (activeRoll and activeRoll.uid == item.uid) or (finishedRoll and finishedRoll.uid == item.uid)
    if item.state == "AWARDED" or hasRoll then
        row.rollBtn:Disable()
    else
        row.rollBtn:Enable()
    end
    if item.state == "AWARDED" then
        row.winBtn:Disable()
    else
        row.winBtn:Enable()
    end
    if item.awardWinner then
        row.tradeBtn:Enable()
    else
        row.tradeBtn:Disable()
    end

    -- Reset button logic
    if row.resetBtn then
        row.resetBtn:SetScript("OnClick", function()
            -- 1) Clear award
            if item.uid then
                uidAwards[item.uid] = nil
            end
            -- 2) Clear active/finished roll for this item
            if activeRoll and activeRoll.uid == item.uid then
                SendSync("RX")
                activeRoll = nil
                countdownTimer = nil
            end
            if finishedRoll and finishedRoll.uid == item.uid then
                CloseRollWindow()
            end
            RefreshMainFrame()
        end)
        -- Reset is always enabled (even for AWARDED items)
        row.resetBtn:Enable()
    end

    -- Roll = Announce + Start Roll combined
    row.rollBtn:SetScript("OnClick", function()
        local effectiveMode = (mode == "sr") and mode or (row.rollMode or "ms")
        StartRoll(item.uid, item.itemId, item.link, effectiveMode)
        row.rollBtn:Disable()
    end)

    row.winBtn:SetScript("OnClick", function()
        if not activeRoll then
            DPrint(C_RED.."No active roll! Click Roll first."..C_RESET)
            return
        end
        if activeRoll.uid ~= item.uid then
            DPrint(C_RED.."Active roll is for: "..(activeRoll.link or "?")..C_RESET)
            return
        end
        StartCountdown()
    end)

    row.tradeBtn:SetScript("OnClick", function()
        if not item.awardWinner then
            DPrint(C_RED.."No winner for this item! Roll first."..C_RESET)
            return
        end
        TryTradeItem(item.awardWinner, item.itemId, item.link, item.uid)
        if finishedRoll and finishedRoll.uid == item.uid then CloseRollWindow() end
    end)

    row.bankBtn:SetScript("OnClick", function()
        if not bankCharName then
            DPrint(C_RED.."Set bank char: /sr bank <name>"..C_RESET)
            return
        end
        TryTradeItem(bankCharName, item.itemId, item.link, item.uid)
        if finishedRoll and finishedRoll.uid == item.uid then CloseRollWindow() end
    end)

    row.dissBtn:SetScript("OnClick", function()
        if not dissCharName then
            DPrint(C_RED.."Set diss char: /sr diss <name>"..C_RESET)
            return
        end
        TryTradeItem(dissCharName, item.itemId, item.link, item.uid)
        if finishedRoll and finishedRoll.uid == item.uid then CloseRollWindow() end
    end)

    row:Show()
end

----------------------------------------------------------------------
-- GUI: Main Window
----------------------------------------------------------------------
RefreshMainFrame = function()
    if not mainFrame then return end
    SyncItemUids()
    for _, r in ipairs(srRows) do r:Hide() end
    for _, r in ipairs(msRows) do r:Hide() end

    local srItems = GetVisibleSRItems()
    local msItems = GetMSRollItems()
    local yOff, hdrH = 0, 22

    -- SR header
    mainFrame.srHeader:ClearAllPoints()
    mainFrame.srHeader:SetPoint("TOPLEFT", mainFrame.content,"TOPLEFT",5,-yOff)
    if #srItems > 0 then
        local modeTag = displayMode == "loot" and "LOOT" or "BAG"
        mainFrame.srHeader:SetText(C_GREEN.."=== SOFT RESERVE - "..modeTag.." ("..#srItems..") ==="..C_RESET)
    else
        mainFrame.srHeader:SetText(C_GRAY.."=== SOFT RESERVE (none visible) ==="..C_RESET)
    end
    yOff = yOff + hdrH

    for i, item in ipairs(srItems) do
        local row = srRows[i]
        if not row then row = CreateRow(mainFrame.content, srRows, i, "sr") end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", mainFrame.content,"TOPLEFT",0,-yOff)
        row:SetPoint("RIGHT", mainFrame.content,"RIGHT",0,0)
        SetupRow(row, item, "sr")
        yOff = yOff + (row.dynamicHeight or ROW_HEIGHT)
    end

    yOff = yOff + 10

    -- MS header
    mainFrame.msHeader:ClearAllPoints()
    mainFrame.msHeader:SetPoint("TOPLEFT", mainFrame.content,"TOPLEFT",5,-yOff)
    if #msItems > 0 then
        local modeTag = displayMode == "loot" and "LOOT" or "BAG"
        mainFrame.msHeader:SetText(C_YELLOW.."=== ROLL - "..modeTag.." ("..#msItems..") ==="..C_RESET)
    else
        mainFrame.msHeader:SetText(C_GRAY.."=== ROLL (none) ==="..C_RESET)
    end
    yOff = yOff + hdrH

    for i, item in ipairs(msItems) do
        local row = msRows[i]
        if not row then row = CreateRow(mainFrame.content, msRows, i, "ms") end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", mainFrame.content,"TOPLEFT",0,-yOff)
        row:SetPoint("RIGHT", mainFrame.content,"RIGHT",0,0)
        SetupRow(row, item, "ms")
        yOff = yOff + MS_ROW_HEIGHT
    end

    mainFrame.content:SetHeight(math.max(yOff+10, 1))

    -- Status
    local pc = 0
    for _ in pairs(reservesByName) do pc = pc + 1 end
    local rs = ""
    if activeRoll then
        rs = " | "..C_ORANGE.."Rolling: "..(activeRoll.link or "?")..
             " ("..activeRoll.mode:upper()..", "..#activeRoll.rolls.." rolls)"..C_RESET
    end
    local srStatus
    if importCount > 0 then
        srStatus = C_GREEN..importCount..C_WHITE.." SR | "..C_GREEN..pc..C_WHITE.." players"
    else
        srStatus = C_GRAY.."No SR imported"
    end
    mainFrame.statusText:SetText(srStatus..rs)
    -- Bank/Diss display
    if mainFrame.bankText then
        local bankStr = bankCharName and (C_CYAN..bankCharName..C_RESET) or (C_RED.."not set"..C_RESET)
        local dissStr = dissCharName and (C_CYAN..dissCharName..C_RESET) or (C_RED.."not set"..C_RESET)
        mainFrame.bankText:SetText(C_GRAY.."Bank: "..bankStr..C_GRAY.." | Diss: "..dissStr)
    end
end

local function CreateMainFrame(silent)
    if not IsMasterLooter() then
        if not silent then
            DPrint(C_RED .. "You must be Master Looter to open this window." .. C_RESET)
        end
        return
    end
    if mainFrame then mainFrame:Show(); RefreshMainFrame(); return end

    local f = CreateFrame("Frame","SRIMainFrame",UIParent)
    f:SetSize(720,540)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=8,right=8,top=8,bottom=8},
    })
    f:SetBackdropColor(0,0,0,0.94)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames,"SRIMainFrame")

    local closeX = CreateFrame("Button",nil,f,"UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT",-2,-2)

    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    t:SetPoint("TOP",0,-12)
    t:SetText(C_GREEN.."Sausage Roll"..C_WHITE.." - SR Loot Tracker "..C_GRAY.."v"..SR_VERSION..C_RESET)

    f.statusText = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.statusText:SetPoint("TOP",0,-30)

    -- Rarity filter dropdown
    local dd = CreateFrame("Frame", "SRIRarityDropdown", f, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", -6, -14)
    UIDropDownMenu_SetWidth(dd, 96)

    local rarityOptions = {
        {text="Green+",  value=2, r=0.12, g=1,    b=0},
        {text="Blue+",   value=3, r=0,    g=0.44, b=0.87},
        {text="Epic+",   value=4, r=0.64, g=0.21, b=0.93},
    }

    local function RarityDropdown_Init(self, level)
        for _, opt in ipairs(rarityOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.colorCode = string.format("|cff%02x%02x%02x", opt.r*255, opt.g*255, opt.b*255)
            info.value = opt.value
            info.checked = (minQualityFilter == opt.value)
            info.func = function(btn)
                minQualityFilter = btn.value
                UIDropDownMenu_SetSelectedValue(dd, btn.value)
                UIDropDownMenu_SetText(dd, opt.text)
                RefreshMainFrame()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dd, RarityDropdown_Init)
    UIDropDownMenu_SetSelectedValue(dd, minQualityFilter)
    for _, opt in ipairs(rarityOptions) do
        if opt.value == minQualityFilter then
            UIDropDownMenu_SetText(dd, opt.text)
            break
        end
    end
    f.rarityDropdown = dd

    -- BoE checkbox (next to rarity dropdown)
    local boeCheck = CreateFrame("CheckButton", nil, f)
    boeCheck:SetSize(20, 20)
    boeCheck:SetPoint("LEFT", dd, "RIGHT", -2, 2)
    boeCheck:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    boeCheck:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    boeCheck:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    boeCheck:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    boeCheck:SetChecked(showBoE)
    boeCheck.label = boeCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boeCheck.label:SetPoint("LEFT", boeCheck, "RIGHT", 2, 0)
    boeCheck.label:SetText(C_GREEN.."BoE")
    boeCheck:SetScript("OnClick", function(self)
        showBoE = self:GetChecked()
        RefreshMainFrame()
    end)
    f.boeCheckbox = boeCheck

    local sc = CreateFrame("ScrollFrame","SRIMainScroll",f,"UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT",10,-66)
    sc:SetPoint("BOTTOMRIGHT",-30,62)
    f.scroll = sc

    local ct = CreateFrame("Frame",nil,sc)
    ct:SetWidth(sc:GetWidth())
    ct:SetHeight(1)
    sc:SetScrollChild(ct)
    f.content = ct

    f.srHeader = ct:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f.msHeader = ct:CreateFontString(nil,"OVERLAY","GameFontNormal")

    -- Bottom buttons
    local btn2 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btn2:SetSize(95,22); btn2:SetPoint("BOTTOMLEFT",10,36)
    btn2:SetText("Import SR CSV")
    btn2:SetScript("OnClick", function() CreateImportFrame() end)

    local btn3 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btn3:SetSize(110,22); btn3:SetPoint("BOTTOMLEFT",110,36)
    btn3:SetText("Announce All SR")
    btn3:SetScript("OnClick", function()
        local items = GetVisibleSRItems()
        if #items == 0 then DPrint(C_YELLOW.."No SR items."..C_RESET); return end
        SendRW("=== Soft Reserves ===")
        for _, item in ipairs(items) do
            local n = {}
            for _, r in ipairs(item.reservers) do table.insert(n, r.name) end
            SendRW(item.link.." -> "..table.concat(n, ", "))
        end
    end)

    -- Import HR CSV button
    local btnHR = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnHR:SetSize(95,22); btnHR:SetPoint("BOTTOMLEFT",10,12)
    btnHR:SetText("Import HR CSV")
    btnHR:SetScript("OnClick", function() CreateHRImportFrame() end)

    -- Announce All HR button
    local btnHRAnn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnHRAnn:SetSize(110,22); btnHRAnn:SetPoint("BOTTOMLEFT",110,12)
    btnHRAnn:SetText("Announce All HR")
    btnHRAnn:SetScript("OnClick", function()
        if #hardReserves == 0 and #hardReserveCustom == 0 then DPrint(C_YELLOW.."No HR items."..C_RESET); return end
        SendRaid("=== Hard Reserves ===")
        for _, hr in ipairs(hardReserves) do
            local _, link = GetItemInfo(hr.itemId)
            SendRaid(link or ("["..hr.itemName.."]"))
        end
        for _, line in ipairs(hardReserveCustom) do
            SendRaid(line)
        end
    end)

    local credit = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    credit:SetPoint("BOTTOM",0,10)
    credit:SetText(C_GRAY.."Sausage Roll - SR created by Sausage Party"..C_RESET)

    -- Set Bank button — dropdown from group members
    local btnSetBank = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnSetBank:SetSize(90,22); btnSetBank:SetPoint("BOTTOM",-48,36)
    btnSetBank:SetText("Set Bank")
    btnSetBank:SetScript("OnClick", function(self)
        local members = GetGroupMembers()
        local menuList = {}
        for _, name in ipairs(members) do
            table.insert(menuList, {
                text = name,
                checked = (bankCharName and bankCharName:lower() == name:lower()),
                func = function()
                    bankCharName = name
                    SausageRollImportDB.bankCharName = bankCharName
                    DPrint(C_GREEN.."Bank set to: "..C_CYAN..bankCharName..C_RESET)
                    RefreshMainFrame()
                end,
            })
        end
        table.insert(menuList, {
            text = "-- Clear --",
            func = function()
                bankCharName = nil
                SausageRollImportDB.bankCharName = nil
                DPrint(C_YELLOW.."Bank char cleared."..C_RESET)
                RefreshMainFrame()
            end,
        })
        EasyMenu(menuList, charDropdownFrame, self, 0, 0, "MENU")
    end)

    -- Set Diss button — dropdown from group members
    local btnSetDiss = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnSetDiss:SetSize(90,22); btnSetDiss:SetPoint("BOTTOM",48,36)
    btnSetDiss:SetText("Set Diss")
    btnSetDiss:SetScript("OnClick", function(self)
        local members = GetGroupMembers()
        local menuList = {}
        for _, name in ipairs(members) do
            table.insert(menuList, {
                text = name,
                checked = (dissCharName and dissCharName:lower() == name:lower()),
                func = function()
                    dissCharName = name
                    SausageRollImportDB.dissCharName = dissCharName
                    DPrint(C_GREEN.."Diss set to: "..C_CYAN..dissCharName..C_RESET)
                    RefreshMainFrame()
                end,
            })
        end
        table.insert(menuList, {
            text = "-- Clear --",
            func = function()
                dissCharName = nil
                SausageRollImportDB.dissCharName = nil
                DPrint(C_YELLOW.."Diss char cleared."..C_RESET)
                RefreshMainFrame()
            end,
        })
        EasyMenu(menuList, charDropdownFrame, self, 0, 0, "MENU")
    end)

    -- Grab All Loot to ML button
    local btnGrab = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnGrab:SetSize(120,22); btnGrab:SetPoint("TOPLEFT",10,-40)
    btnGrab:SetText("Grab All Loot")
    btnGrab:SetScript("OnClick", function()
        if not isLootOpen then
            DPrint(C_RED.."No loot window open!"..C_RESET)
            return
        end
        if not IsMasterLooter() then
            DPrint(C_RED.."You are not Master Looter!"..C_RESET)
            return
        end
        local myName = UnitName("player")
        -- Find my candidate index
        local myCandIdx = nil
        for ci = 1, 40 do
            local cname = GetMasterLootCandidate(ci)
            if not cname then break end
            if cname:lower() == myName:lower() then
                myCandIdx = ci
                break
            end
        end
        if not myCandIdx then
            DPrint(C_RED.."Can't find self in loot candidates!"..C_RESET)
            return
        end
        local grabbed = {}
        for li = GetNumLootItems(), 1, -1 do
            local link = GetLootSlotLink(li)
            if link then
                GiveMasterLoot(li, myCandIdx)
                table.insert(grabbed, link)
            end
        end
        if #grabbed > 0 then
            local channel = IsInRaid() and "RAID" or "PARTY"
            local msg = "Looted: "..grabbed[1]
            for i = 2, #grabbed do
                local appended = msg..", "..grabbed[i]
                if #appended > 250 then
                    SendChatMessage(msg, channel)
                    msg = "Looted: "..grabbed[i]
                else
                    msg = appended
                end
            end
            SendChatMessage(msg, channel)
            DPrint(C_GREEN.."Grabbed "..#grabbed.." items to inventory."..C_RESET)
        else
            DPrint(C_YELLOW.."No lootable items."..C_RESET)
        end
    end)

    -- Bank/Diss name display
    local bankText = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    bankText:SetPoint("BOTTOM", 0, 60)
    f.bankText = bankText

    local btn1 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btn1:SetSize(60,22); btn1:SetPoint("BOTTOMRIGHT",-10,36)
    btn1:SetText("Refresh")
    btn1:SetScript("OnClick", function() RefreshMainFrame() end)

    local btn4 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btn4:SetSize(60,22); btn4:SetPoint("BOTTOMRIGHT",-10,12)
    btn4:SetText("Close")
    btn4:SetScript("OnClick", function() f:Hide() end)

    mainFrame = f
    RefreshMainFrame()
end

----------------------------------------------------------------------
-- GUI: Import Window (always allows reimport + clear)
----------------------------------------------------------------------
CreateImportFrame = function()
    if SRIHRImportFrame and SRIHRImportFrame:IsShown() then SRIHRImportFrame:Hide() end
    if SRIImportFrame then
        SRIImportFrame.UpdateStatus()
        SRIImportFrame:Show()
        return
    end

    local f = CreateFrame("Frame","SRIImportFrame",UIParent)
    f:SetSize(480,380)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=8,right=8,top=8,bottom=8},
    })
    f:SetBackdropColor(0,0,0,0.94)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames,"SRIImportFrame")

    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    t:SetPoint("TOP",0,-12)
    t:SetText(C_GREEN.."Sausage Roll"..C_WHITE.." - Import SR CSV"..C_RESET)

    local st = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    st:SetPoint("TOP",0,-32)

    local function UpdateStatus()
        if importCount > 0 then
            local pc = 0
            for _ in pairs(reservesByName) do pc = pc + 1 end
            st:SetText(C_GREEN..importCount..C_WHITE.." reserves ("..
                C_GREEN..pc..C_WHITE.." players). Paste new CSV to reimport."..C_RESET)
        else
            st:SetText(C_GRAY.."Paste SR CSV (Ctrl+V), click Import"..C_RESET)
        end
    end
    f.UpdateStatus = UpdateStatus
    UpdateStatus()

    local bg = CreateFrame("Frame",nil,f)
    bg:SetPoint("TOPLEFT",12,-48)
    bg:SetPoint("BOTTOMRIGHT",-30,46)
    bg:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=14,
        insets={left=3,right=3,top=3,bottom=3},
    })
    bg:SetBackdropColor(0,0,0,0.6)
    bg:SetBackdropBorderColor(0.4,0.4,0.4,0.8)

    local sc = CreateFrame("ScrollFrame","SRIImportScroll",f,"UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT",16,-52)
    sc:SetPoint("BOTTOMRIGHT",-34,50)

    local eb = CreateFrame("EditBox","SRIImportEditBox",sc)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(sc:GetWidth())
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sc:SetScrollChild(eb)
    f.editBox = eb
    if SausageRollImportDB.lastSRText then eb:SetText(SausageRollImportDB.lastSRText) end

    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)

    local b1 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b1:SetSize(100,24); b1:SetPoint("BOTTOMLEFT",14,14)
    b1:SetText("Import")
    b1:SetScript("OnClick", function()
        local text = eb:GetText()
        if not text or text == "" then DPrint(C_RED.."Paste CSV first!"..C_RESET); return end
        local count = ParseCSV(text)
        local pc = 0
        for _ in pairs(reservesByName) do pc = pc + 1 end
        DPrint(C_GREEN..count..C_WHITE.." reserves imported ("..C_GREEN..pc..C_WHITE.." players)"..C_RESET)
        eb:ClearFocus()
        UpdateStatus()
        f:Hide()
        CreateMainFrame()
    end)

    local b2 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b2:SetSize(100,24); b2:SetPoint("BOTTOM",0,14)
    b2:SetText("Clear All SR")
    b2:SetScript("OnClick", function()
        ClearAllData(); eb:SetText(""); UpdateStatus()
        DPrint(C_YELLOW.."All reserves cleared."..C_RESET)
        if mainFrame and mainFrame:IsShown() then RefreshMainFrame() end
    end)

    local b3 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b3:SetSize(100,24); b3:SetPoint("BOTTOMRIGHT",-14,14)
    b3:SetText("Close")
    b3:SetScript("OnClick", function() f:Hide() end)
end

----------------------------------------------------------------------
-- GUI: HR Import Window
----------------------------------------------------------------------
CreateHRImportFrame = function()
    if SRIImportFrame and SRIImportFrame:IsShown() then SRIImportFrame:Hide() end
    if SRIHRImportFrame then
        SRIHRImportFrame.UpdateStatus()
        SRIHRImportFrame:Show()
        return
    end

    local f = CreateFrame("Frame","SRIHRImportFrame",UIParent)
    f:SetSize(480,380)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=8,right=8,top=8,bottom=8},
    })
    f:SetBackdropColor(0,0,0,0.94)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames,"SRIHRImportFrame")

    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    t:SetPoint("TOP",0,-12)
    t:SetText(C_GREEN.."Sausage Roll"..C_WHITE.." - Import HR CSV"..C_RESET)

    local st = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    st:SetPoint("TOP",0,-32)

    local function UpdateStatus()
        if #hardReserves > 0 or #hardReserveCustom > 0 then
            local parts = {}
            if #hardReserves > 0 then table.insert(parts, C_GREEN..#hardReserves..C_WHITE.." HR items") end
            if #hardReserveCustom > 0 then table.insert(parts, C_GREEN..#hardReserveCustom..C_WHITE.." custom lines") end
            st:SetText(table.concat(parts, " + ")..". Paste new CSV to reimport."..C_RESET)
        else
            st:SetText(C_GRAY.."Paste HR CSV, click Import"..C_RESET)
        end
    end
    f.UpdateStatus = UpdateStatus
    UpdateStatus()

    local bg = CreateFrame("Frame",nil,f)
    bg:SetPoint("TOPLEFT",12,-48)
    bg:SetPoint("BOTTOMRIGHT",-30,46)
    bg:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=14,
        insets={left=3,right=3,top=3,bottom=3},
    })
    bg:SetBackdropColor(0,0,0,0.6)
    bg:SetBackdropBorderColor(0.4,0.4,0.4,0.8)

    local sc = CreateFrame("ScrollFrame","SRIHRImportScroll",f,"UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT",16,-52)
    sc:SetPoint("BOTTOMRIGHT",-34,50)

    local eb = CreateFrame("EditBox","SRIHRImportEditBox",sc)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(sc:GetWidth())
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sc:SetScrollChild(eb)
    f.editBox = eb
    if SausageRollImportDB.lastHRText then eb:SetText(SausageRollImportDB.lastHRText) end

    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)

    local b1 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b1:SetSize(100,24); b1:SetPoint("BOTTOMLEFT",14,14)
    b1:SetText("Import")
    b1:SetScript("OnClick", function()
        local text = eb:GetText()
        if not text or text == "" then DPrint(C_RED.."Paste HR CSV first!"..C_RESET); return end
        ParseHRCSV(text)
        local parts = {}
        if #hardReserves > 0 then table.insert(parts, C_GREEN..#hardReserves..C_WHITE.." HR items") end
        if #hardReserveCustom > 0 then table.insert(parts, C_GREEN..#hardReserveCustom..C_WHITE.." custom lines") end
        if #parts > 0 then
            DPrint(table.concat(parts, " + ").." imported"..C_RESET)
        else
            DPrint(C_YELLOW.."No HR data found in text."..C_RESET)
        end
        eb:ClearFocus()
        UpdateStatus()
        f:Hide()
    end)

    local b2 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b2:SetSize(100,24); b2:SetPoint("BOTTOM",0,14)
    b2:SetText("Clear All HR")
    b2:SetScript("OnClick", function()
        wipe(hardReserves)
        wipe(hardReserveCustom)
        SausageRollImportDB.hardReserves = hardReserves
        SausageRollImportDB.hardReserveCustom = hardReserveCustom
        SausageRollImportDB.lastHRText = nil
        eb:SetText(""); UpdateStatus()
        DPrint(C_YELLOW.."All HR items cleared."..C_RESET)
    end)

    local b3 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b3:SetSize(100,24); b3:SetPoint("BOTTOMRIGHT",-14,14)
    b3:SetText("Close")
    b3:SetScript("OnClick", function() f:Hide() end)
end

----------------------------------------------------------------------
-- Tooltip Hook
----------------------------------------------------------------------
local function OnTooltipSetItem(tooltip)
    local _, link = tooltip:GetItem()
    if not link then return end
    local itemId = GetItemIdFromLink(link)
    if not itemId then return end
    local entries = reserves[itemId]
    if not entries or #entries == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(C_GREEN.."-- Soft Reserved --"..C_RESET)
    for _, e in ipairs(entries) do
        local color = C_CYAN
        if IsInRaid() then
            local ok = false
            for i=1,GetNumRaidMembers() do
                local rn = GetRaidRosterInfo(i)
                if rn and rn:lower()==e.name:lower() then ok=true; break end
            end
            if not ok then color = C_RED end
        end
        tooltip:AddLine("  "..color..e.name..C_RESET)
    end
    if #entries > 1 then
        tooltip:AddLine(C_ORANGE.."  ("..#entries.." SR - CONTESTED)"..C_RESET)
    end
    tooltip:Show()
end

GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
if ItemRefTooltip then
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
end

----------------------------------------------------------------------
-- Minimap Button
----------------------------------------------------------------------
local function CreateMinimapButton()
    local btn = CreateFrame("Button","SRIMinimapButton",Minimap)
    btn:SetSize(31,31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local ov = btn:CreateTexture(nil,"OVERLAY")
    ov:SetSize(53,53)
    ov:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ov:SetPoint("TOPLEFT")
    local ic = btn:CreateTexture(nil,"BACKGROUND")
    ic:SetSize(20,20)
    ic:SetTexture("Interface\\AddOns\\SausageRoll-SR\\Textures\\sausageroll")
    ic:SetPoint("CENTER",0,1)

    local angle = SausageRollImportDB.minimapAngle or 220
    btn:SetPoint("CENTER",Minimap,"CENTER",80*math.cos(math.rad(angle)),80*math.sin(math.rad(angle)))

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self) self.dragging=true end)
    btn:SetScript("OnDragStop", function(self)
        self.dragging=false
        local cx,cy=Minimap:GetCenter()
        local mx,my=GetCursorPosition()
        local s=UIParent:GetEffectiveScale()
        local a=math.deg(math.atan2(my/s-cy,mx/s-cx))
        SausageRollImportDB.minimapAngle=a
        self:ClearAllPoints()
        self:SetPoint("CENTER",Minimap,"CENTER",80*math.cos(math.rad(a)),80*math.sin(math.rad(a)))
    end)
    btn:SetScript("OnUpdate", function(self)
        if self.dragging then
            local cx,cy=Minimap:GetCenter()
            local mx,my=GetCursorPosition()
            local s=UIParent:GetEffectiveScale()
            local a=math.deg(math.atan2(my/s-cy,mx/s-cx))
            self:ClearAllPoints()
            self:SetPoint("CENTER",Minimap,"CENTER",80*math.cos(math.rad(a)),80*math.sin(math.rad(a)))
        end
    end)

    btn:RegisterForClicks("LeftButtonUp","RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button=="LeftButton" then
            displayMode = "bag"
            CreateMainFrame()
        elseif button=="RightButton" then
            displayMode = "bag"
            CreateMainFrame()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_LEFT")
        GameTooltip:AddLine(C_GREEN.."Sausage Roll"..C_WHITE.." - SR"..C_RESET)
        GameTooltip:AddLine(" ")
        local pc=0
        for _ in pairs(reservesByName) do pc=pc+1 end
        if importCount>0 then
            GameTooltip:AddLine(C_GREEN..importCount..C_WHITE.." reserves | "..C_GREEN..pc..C_WHITE.." players",1,1,1)
        else
            GameTooltip:AddLine(C_GRAY.."No reserves",1,1,1)
        end
        if activeRoll then GameTooltip:AddLine(C_ORANGE.."Roll active!",1,1,1) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(C_YELLOW.."LClick:"..C_WHITE.." Main | "..C_YELLOW.."RClick:"..C_WHITE.." Import",1,1,1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------
-- Slash Commands
----------------------------------------------------------------------
local function HandleSlash(msg)
    if not msg then msg="" end
    local cmd = msg:match("^(%S+)") or ""
    local arg = msg:match("^%S+%s+(.+)") or ""
    cmd = cmd:lower()

    if cmd=="" then
        displayMode = "bag"
        CreateMainFrame()
    elseif cmd=="import" then CreateImportFrame()
    elseif cmd=="show" or cmd=="list" then
        displayMode = "bag"
        CreateMainFrame()
    elseif cmd=="check" then
        if arg=="" then DPrint(C_RED.."/sr check <name>"..C_RESET); return end
        local name = CapitalizeName(arg)
        local items = reservesByName[name]
        if items and #items>0 then
            DPrint(C_CYAN..name..C_WHITE.." reserved:"..C_RESET)
            for _,e in ipairs(items) do
                local _,ilink=GetItemInfo(e.itemId)
                DPrint("  "..(ilink or ("["..e.itemName.."]"))..C_GRAY.." ("..e.from..")"..C_RESET)
            end
        else DPrint(C_YELLOW..name.." has no SR."..C_RESET) end
    elseif cmd=="clear" then
        ClearAllData()
        DPrint(C_YELLOW.."Cleared."..C_RESET)
        if mainFrame and mainFrame:IsShown() then RefreshMainFrame() end
    elseif cmd=="count" then
        local pc=0 for _ in pairs(reservesByName) do pc=pc+1 end
        local ic=0 for _ in pairs(reserves) do ic=ic+1 end
        DPrint(C_GREEN..importCount..C_WHITE.." SR | "..C_GREEN..pc..C_WHITE.." players | "..C_GREEN..ic..C_WHITE.." items"..C_RESET)
    elseif cmd=="winner" then StartCountdown()
    elseif cmd=="bank" then
        if arg=="" then
            if bankCharName then
                DPrint(C_WHITE.."Bank char: "..C_CYAN..bankCharName..C_RESET)
            else
                DPrint(C_RED.."/sr bank <n> - set bank character"..C_RESET)
            end
            return
        end
        bankCharName = CapitalizeName(arg)
        SausageRollImportDB.bankCharName = bankCharName
        DPrint(C_GREEN.."Bank set to: "..C_CYAN..bankCharName..C_RESET)
        if mainFrame and mainFrame:IsShown() then RefreshMainFrame() end
    elseif cmd=="diss" then
        if arg=="" then
            if dissCharName then
                DPrint(C_WHITE.."Diss char: "..C_CYAN..dissCharName..C_RESET)
            else
                DPrint(C_RED.."/sr diss <n> - set disenchant character"..C_RESET)
            end
            return
        end
        dissCharName = CapitalizeName(arg)
        SausageRollImportDB.dissCharName = dissCharName
        DPrint(C_GREEN.."Diss set to: "..C_CYAN..dissCharName..C_RESET)
        if mainFrame and mainFrame:IsShown() then RefreshMainFrame() end
    else DPrint("/sr | /sr import | /sr clear | /sr check <n> | /sr bank <n> | /sr diss <n> | /sr winner") end
end

SLASH_SOFTRESIMPORT1 = "/sri"
SLASH_SOFTRESIMPORT2 = "/softres"
SLASH_SOFTRESIMPORT3 = "/sr"
SlashCmdList["SOFTRESIMPORT"] = HandleSlash

----------------------------------------------------------------------
-- Loot opened handler
----------------------------------------------------------------------
local function LootHasRelevantItems()
    for i = 1, GetNumLootItems() do
        local _, _, _, rarity = GetLootSlotInfo(i)
        if rarity and rarity >= minQualityFilter then
            return true
        end
    end
    return false
end

local lootCheckFrame = CreateFrame("Frame")

local function OnLootOpened()
    isLootOpen = true
    displayMode = "loot"
    -- Delay auto-open: loot API needs time to populate slot data
    local waited = 0
    lootCheckFrame:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if waited >= 0.35 then
            self:SetScript("OnUpdate", nil)
            if isLootOpen and LootHasRelevantItems() then
                CreateMainFrame(true)
            end
        end
    end)
    ScheduleRefresh(0.3)
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
SRI:RegisterEvent("ADDON_LOADED")
SRI:RegisterEvent("LOOT_OPENED")
SRI:RegisterEvent("LOOT_CLOSED")
SRI:RegisterEvent("LOOT_SLOT_CLEARED")
SRI:RegisterEvent("BAG_UPDATE")
SRI:RegisterEvent("CHAT_MSG_SYSTEM")
SRI:RegisterEvent("TRADE_SHOW")
SRI:RegisterEvent("TRADE_ACCEPT_UPDATE")
SRI:RegisterEvent("TRADE_CLOSED")
SRI:RegisterEvent("CHAT_MSG_ADDON")

local tradeCloseFrame
SRI:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            if SausageRollImportDB.reserves then reserves = SausageRollImportDB.reserves end
            if SausageRollImportDB.reservesByName then reservesByName = SausageRollImportDB.reservesByName end
            if SausageRollImportDB.importCount then importCount = SausageRollImportDB.importCount end
            if SausageRollImportDB.bankCharName then bankCharName = SausageRollImportDB.bankCharName end
            if SausageRollImportDB.dissCharName then dissCharName = SausageRollImportDB.dissCharName end
            if SausageRollImportDB.hardReserves then hardReserves = SausageRollImportDB.hardReserves end
            if SausageRollImportDB.hardReserveCustom then hardReserveCustom = SausageRollImportDB.hardReserveCustom end
            CreateMinimapButton()
            if importCount > 0 then
                DPrint(C_GREEN.."Loaded! "..C_WHITE..importCount.." reserves. /sr to open."..C_RESET)
            else
                DPrint(C_GREEN.."Loaded! "..C_WHITE.."/sr to open."..C_RESET)
            end
        end
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "LOOT_CLOSED" then
        isLootOpen = false
        displayMode = "bag"
        if mainFrame then
            mainFrame:Hide()
        end
        ScheduleRefresh()
    elseif event == "LOOT_SLOT_CLEARED" then
        ScheduleRefresh(0.2)
    elseif event == "BAG_UPDATE" then
        if mainFrame and mainFrame:IsShown() then
            RefreshMainFrame()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if msg then OnSystemMsg(msg) end
    elseif event == "CHAT_MSG_ADDON" then
        OnSyncMessage(...)
    elseif event == "TRADE_SHOW" then
        -- Auto-place item with small delay (trade window needs time to init)
        if pendingTrade then
            local pt = pendingTrade
            pendingTrade = nil
            -- Use OnUpdate for a ~0.3s delay
            local delayFrame = CreateFrame("Frame")
            local waited = 0
            delayFrame:SetScript("OnUpdate", function(df, el)
                waited = waited + el
                if waited >= 0.3 then
                    df:SetScript("OnUpdate", nil)
                    -- Verify item still there
                    local link = GetContainerItemLink(pt.bag, pt.slot)
                    if link and GetItemIdFromLink(link) == pt.itemId then
                        ClearCursor()
                        PickupContainerItem(pt.bag, pt.slot)
                        ClickTradeButton(1)
                        DPrint(C_GREEN.."Item placed in trade. Confirm manually."..C_RESET)
                    else
                        DPrint(C_RED.."Item moved from bag slot!"..C_RESET)
                    end
                end
            end)
        end
    elseif event == "TRADE_ACCEPT_UPDATE" then
        ScheduleRefresh(0.5)
    elseif event == "TRADE_CLOSED" then
        if tradeCloseFrame then return end
        DPrint(C_YELLOW.."[SR] TRADE_CLOSED fired, scheduling refresh..."..C_RESET)
        tradeCloseFrame = CreateFrame("Frame")
        local tradeCloseWait = 0
        tradeCloseFrame:SetScript("OnUpdate", function(df, el)
            tradeCloseWait = tradeCloseWait + el
            if tradeCloseWait >= 1.0 then
                df:SetScript("OnUpdate", nil)
                tradeCloseFrame = nil
                if mainFrame then
                    DPrint(C_GREEN.."[SR] Refreshing GUI after trade."..C_RESET)
                    RefreshMainFrame()
                end
            end
        end)
    end
end)

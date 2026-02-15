----------------------------------------------------------------------
-- SausageData.lua - UID tracking, CSV parsing, persistence
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- UID helper functions
----------------------------------------------------------------------
function SR.AssignUid(slotKey, itemId)
    if SR.slotToUid[slotKey] then
        return SR.slotToUid[slotKey]
    end
    local uid = SR.nextItemUid
    SR.nextItemUid = SR.nextItemUid + 1
    SR.slotToUid[slotKey] = uid
    SR.uidToSlot[uid] = slotKey
    SR.uidToItemId[uid] = itemId
    return uid
end

function SR.SyncItemUids()
    -- 1) Mark all loot UIDs as potential orphans
    local lootOrphans = {}
    local lootKeysToRemove = {}
    for key, uid in pairs(SR.slotToUid) do
        if key:match("^loot:") then
            lootOrphans[uid] = SR.uidToItemId[uid]
            table.insert(lootKeysToRemove, key)
        end
    end
    for _, key in ipairs(lootKeysToRemove) do
        SR.slotToUid[key] = nil
    end

    -- 2) Rescan loot and reclaim UIDs that still exist
    if SR.isLootOpen then
        for i = 1, GetNumLootItems() do
            local link = GetLootSlotLink(i)
            if link then
                local itemId = SR.GetItemIdFromLink(link)
                if itemId then
                    local key = "loot:"..i
                    local matched = false
                    for uid, oItemId in pairs(lootOrphans) do
                        if oItemId == itemId then
                            SR.slotToUid[key] = uid
                            SR.uidToSlot[uid] = key
                            lootOrphans[uid] = nil
                            matched = true
                            break
                        end
                    end
                    -- Also try pendingOrphans (loot close→reopen reclaim)
                    if not matched then
                        local pOrphans = SR.pendingOrphans[itemId]
                        if pOrphans and #pOrphans > 0 then
                            local uid = table.remove(pOrphans, 1)
                            SR.slotToUid[key] = uid
                            SR.uidToSlot[uid] = key
                            matched = true
                        end
                    end
                    if not matched then
                        SR.AssignUid(key, itemId)
                    end
                end
            end
        end
    end

    -- 3) Remaining loot orphans → pendingOrphans (may reappear in bags or loot)
    for uid, itemId in pairs(lootOrphans) do
        if not SR.pendingOrphans[itemId] then SR.pendingOrphans[itemId] = {} end
        table.insert(SR.pendingOrphans[itemId], uid)
        SR.uidToSlot[uid] = nil
    end

    -- 4) Clean bag UIDs for items no longer at original slot → pendingOrphans
    local bagKeysToRemove = {}
    for key, uid in pairs(SR.slotToUid) do
        local bagStr, slotStr = key:match("^bag:(%d+):(%d+)$")
        if bagStr then
            local bag, slot = tonumber(bagStr), tonumber(slotStr)
            local link = GetContainerItemLink(bag, slot)
            if not link or SR.GetItemIdFromLink(link) ~= SR.uidToItemId[uid] then
                table.insert(bagKeysToRemove, key)
                SR.uidToSlot[uid] = nil
                local orphanItemId = SR.uidToItemId[uid]
                if orphanItemId then
                    if not SR.pendingOrphans[orphanItemId] then SR.pendingOrphans[orphanItemId] = {} end
                    table.insert(SR.pendingOrphans[orphanItemId], uid)
                end
            end
        end
    end
    for _, key in ipairs(bagKeysToRemove) do
        SR.slotToUid[key] = nil
    end
end

function SR.GetBagItemUid(slotKey, itemId)
    if SR.slotToUid[slotKey] then
        return SR.slotToUid[slotKey]
    end
    -- Try to match orphan (loot->bag transition)
    local orphans = SR.pendingOrphans[itemId]
    if orphans and #orphans > 0 then
        local uid = table.remove(orphans, 1)
        SR.slotToUid[slotKey] = uid
        SR.uidToSlot[uid] = slotKey
        return uid
    end
    -- Brand new item
    return SR.AssignUid(slotKey, itemId)
end

----------------------------------------------------------------------
-- CSV Parser
----------------------------------------------------------------------
function SR.ParseCSVLine(line)
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

function SR.ClearAllData()
    wipe(SR.reserves)
    wipe(SR.reservesByName)
    wipe(SR.awardLog)
    wipe(SR.slotToUid)
    wipe(SR.uidToSlot)
    wipe(SR.uidToItemId)
    wipe(SR.uidAwards)
    wipe(SR.pendingOrphans)
    wipe(SR.uidRolled)
    wipe(SR.unclaimedAwards)
    wipe(SR.unclaimedRolled)
    SR.nextItemUid = 1
    SR.importCount = 0
    SR.activeRoll = nil
    SR.displayMode = "bag"
    SR.minQualityFilter = 2
    SR.showBoE = false
    SausageRollImportDB.reserves = {}
    SausageRollImportDB.reservesByName = {}
    SausageRollImportDB.importCount = 0
    SausageRollImportDB.lastSRText = nil
    SausageRollImportDB.awards = nil
    SausageRollImportDB.rolledItems = nil
end

function SR.ParseCSV(text)
    SR.ClearAllData()
    local reserves = SR.reserves
    local reservesByName = SR.reservesByName
    local headerSkipped = false

    local function ProcessLine(line)
        local f = SR.ParseCSVLine(line)
        if #f >= 4 then
            local itemName   = SR.StripQuotes(f[1])
            local itemId     = tonumber(SR.StripQuotes(f[2]))
            local from       = SR.StripQuotes(f[3])
            local playerName = SR.CapitalizeName(SR.StripQuotes(f[4]))
            if itemId and playerName ~= "" then
                if not reserves[itemId] then reserves[itemId] = {} end
                table.insert(reserves[itemId], {name=playerName, itemName=itemName, from=from})
                if not reservesByName[playerName] then reservesByName[playerName] = {} end
                table.insert(reservesByName[playerName], {itemId=itemId, itemName=itemName, from=from})
                SR.importCount = SR.importCount + 1
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
    SausageRollImportDB.importCount = SR.importCount
    SausageRollImportDB.lastSRText = text
    return SR.importCount
end

function SR.ParseHRCSV(text)
    local hardReserves = SR.hardReserves
    local hardReserveCustom = SR.hardReserveCustom
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
                    local f = SR.ParseCSVLine(line)
                    local id = tonumber(SR.StripQuotes(f[1] or ""))
                    local name = SR.StripQuotes(f[2] or "")
                    if id and not seen[id] then
                        seen[id] = true
                        table.insert(hardReserves, {itemId=id, itemName=name})
                    end
                end
            else
                local f = SR.ParseCSVLine(line)
                local id = tonumber(SR.StripQuotes(f[1] or ""))
                local name = SR.StripQuotes(f[2] or "")
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
-- Loot history
----------------------------------------------------------------------
function SR.RecordLootHistory(itemId, link, name, quality, recipient, method, uid)
    -- Replace previous entry for same UID (prevents duplicates on retry)
    if uid then
        for i = #SR.lootHistory, 1, -1 do
            if SR.lootHistory[i].uid == uid then
                table.remove(SR.lootHistory, i)
                break
            end
        end
        if SausageRollImportDB.lootHistory then
            for i = #SausageRollImportDB.lootHistory, 1, -1 do
                if SausageRollImportDB.lootHistory[i].uid == uid then
                    table.remove(SausageRollImportDB.lootHistory, i)
                    break
                end
            end
        end
    end
    local entry = {
        itemId = itemId,
        link = link,
        name = name,
        quality = quality,
        recipient = recipient,
        method = method,
        timestamp = time(),
        uid = uid,
    }
    table.insert(SR.lootHistory, entry)
    if not SausageRollImportDB.lootHistory then SausageRollImportDB.lootHistory = {} end
    table.insert(SausageRollImportDB.lootHistory, entry)
end

function SR.RemoveLootHistoryByUid(uid, itemId)
    if not uid and not itemId then return end
    local found = false
    -- Try exact UID match first
    if uid then
        for i = #SR.lootHistory, 1, -1 do
            if SR.lootHistory[i].uid == uid then
                table.remove(SR.lootHistory, i)
                found = true
                break
            end
        end
        if SausageRollImportDB.lootHistory then
            for i = #SausageRollImportDB.lootHistory, 1, -1 do
                if SausageRollImportDB.lootHistory[i].uid == uid then
                    table.remove(SausageRollImportDB.lootHistory, i)
                    break
                end
            end
        end
    end
    -- Fallback: remove most recent entry for this itemId (handles UID mismatch after /reload)
    if not found and itemId then
        for i = #SR.lootHistory, 1, -1 do
            if SR.lootHistory[i].itemId == itemId then
                table.remove(SR.lootHistory, i)
                break
            end
        end
        if SausageRollImportDB.lootHistory then
            for i = #SausageRollImportDB.lootHistory, 1, -1 do
                if SausageRollImportDB.lootHistory[i].itemId == itemId then
                    table.remove(SausageRollImportDB.lootHistory, i)
                    break
                end
            end
        end
    end
end

function SR.ClearLootHistory()
    wipe(SR.lootHistory)
    SausageRollImportDB.lootHistory = nil
end

function SR.ExportLootHistoryCSV()
    local lines = {"Item,ItemID,Recipient,Method,Date"}
    for _, e in ipairs(SR.lootHistory) do
        local d = date("%d.%m.%Y %H:%M", e.timestamp)
        local safeName = (e.name or ""):gsub('"', '""')
        table.insert(lines, string.format('"%s",%d,"%s","%s","%s"',
            safeName, e.itemId or 0, e.recipient or "", e.method or "", d))
    end
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- Load saved data (ADDON_LOADED) — copy INTO existing tables
----------------------------------------------------------------------
function SR.LoadSavedData()
    local db = SausageRollImportDB
    if db.reserves then
        wipe(SR.reserves)
        for k, v in pairs(db.reserves) do SR.reserves[k] = v end
    end
    if db.reservesByName then
        wipe(SR.reservesByName)
        for k, v in pairs(db.reservesByName) do SR.reservesByName[k] = v end
    end
    if db.importCount then SR.importCount = db.importCount end
    if db.bankCharName then SR.bankCharName = db.bankCharName end
    if db.dissCharName then SR.dissCharName = db.dissCharName end
    if db.hardReserves then
        wipe(SR.hardReserves)
        for i, v in ipairs(db.hardReserves) do SR.hardReserves[i] = v end
    end
    if db.hardReserveCustom then
        wipe(SR.hardReserveCustom)
        for i, v in ipairs(db.hardReserveCustom) do SR.hardReserveCustom[i] = v end
    end
    if db.awards then
        wipe(SR.awardLog)
        for i, v in ipairs(db.awards) do SR.awardLog[i] = v end
    end
    if db.lootHistory then
        wipe(SR.lootHistory)
        for i, v in ipairs(db.lootHistory) do SR.lootHistory[i] = v end
    end
    SR.BuildClaimQueues()
end

----------------------------------------------------------------------
-- Claim system — persist awards/rolled across /reload
----------------------------------------------------------------------
function SR.BuildClaimQueues()
    wipe(SR.unclaimedAwards)
    wipe(SR.unclaimedRolled)
    for _, entry in ipairs(SR.awardLog) do
        local id = entry.itemId
        if not SR.unclaimedAwards[id] then SR.unclaimedAwards[id] = {} end
        table.insert(SR.unclaimedAwards[id], {winner=entry.winner, link=entry.link})
    end
    local db = SausageRollImportDB
    if db.rolledItems then
        for _, entry in ipairs(db.rolledItems) do
            local id = entry.itemId
            SR.unclaimedRolled[id] = (SR.unclaimedRolled[id] or 0) + 1
        end
    end
end

function SR.ClaimAward(itemId)
    local queue = SR.unclaimedAwards[itemId]
    if not queue or #queue == 0 then return nil end
    return table.remove(queue, 1)
end

function SR.ClaimRolled(itemId)
    local count = SR.unclaimedRolled[itemId]
    if not count or count <= 0 then return false end
    SR.unclaimedRolled[itemId] = count - 1
    return true
end

function SR.PersistAward(itemId, winner, link)
    local db = SausageRollImportDB
    if not db.awards then db.awards = {} end
    table.insert(db.awards, {itemId=itemId, winner=winner, link=link})
    -- Item is now awarded, remove one matching rolledItems entry
    if db.rolledItems then
        for i, entry in ipairs(db.rolledItems) do
            if entry.itemId == itemId then
                table.remove(db.rolledItems, i)
                break
            end
        end
    end
end

function SR.PersistRolled(itemId)
    local db = SausageRollImportDB
    if not db.rolledItems then db.rolledItems = {} end
    table.insert(db.rolledItems, {itemId=itemId})
end

function SR.RemovePersistedState(itemId)
    local db = SausageRollImportDB
    if db.awards then
        for i, entry in ipairs(db.awards) do
            if entry.itemId == itemId then
                table.remove(db.awards, i)
                break
            end
        end
    end
    if db.rolledItems then
        for i, entry in ipairs(db.rolledItems) do
            if entry.itemId == itemId then
                table.remove(db.rolledItems, i)
                break
            end
        end
    end
end

----------------------------------------------------------------------
-- Item existence helpers
----------------------------------------------------------------------
function SR.FindBagSlot(itemId)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and SR.GetItemIdFromLink(link) == itemId then
                return bag, slot
            end
        end
    end
    return nil, nil
end

function SR.ItemInBags(itemId)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and SR.GetItemIdFromLink(link) == itemId then
                return true, link, bag, slot
            end
        end
    end
    return false, nil, nil, nil
end

function SR.ItemInLoot(itemId)
    if not SR.isLootOpen then return false, nil end
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        if link and SR.GetItemIdFromLink(link) == itemId then
            return true, link
        end
    end
    return false, nil
end

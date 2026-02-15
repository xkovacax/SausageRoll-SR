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
    wipe(SR.pendingOrphans)

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
                    if not matched then
                        SR.AssignUid(key, itemId)
                    end
                end
            end
        end
    end

    -- 3) Remaining orphans = items that left loot (may appear in bags)
    for uid, itemId in pairs(lootOrphans) do
        if not SR.pendingOrphans[itemId] then SR.pendingOrphans[itemId] = {} end
        table.insert(SR.pendingOrphans[itemId], uid)
        SR.uidToSlot[uid] = nil
    end

    -- 4) Clean bag UIDs for items no longer at original slot
    local bagKeysToRemove = {}
    for key, uid in pairs(SR.slotToUid) do
        local bagStr, slotStr = key:match("^bag:(%d+):(%d+)$")
        if bagStr then
            local bag, slot = tonumber(bagStr), tonumber(slotStr)
            local link = GetContainerItemLink(bag, slot)
            if not link or SR.GetItemIdFromLink(link) ~= SR.uidToItemId[uid] then
                table.insert(bagKeysToRemove, key)
                SR.uidToSlot[uid] = nil
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

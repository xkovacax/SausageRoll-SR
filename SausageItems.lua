----------------------------------------------------------------------
-- SausageItems.lua - Item scanning pipeline (composable)
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- Scanning helpers
----------------------------------------------------------------------
function SR.ScanLootItems()
    local items = {}
    if not SR.isLootOpen then return items end
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        if link then
            local itemId = SR.GetItemIdFromLink(link)
            if itemId then
                local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
                table.insert(items, {
                    itemId = itemId, link = link, icon = texture,
                    name = name, quality = quality or 1,
                    source = "loot", lootIndex = i,
                })
            end
        end
    end
    return items
end

function SR.ScanBagItems()
    local items = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemId = SR.GetItemIdFromLink(link)
                if itemId then
                    local tradeTime = SR.GetTradeTimeFromBag(bag, slot)
                    local isBoE = SR.showBoE and (not tradeTime) and SR.IsBoEFromBag(bag, slot)
                    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
                    table.insert(items, {
                        itemId = itemId, link = link, icon = texture,
                        name = name, quality = quality or 1,
                        source = "bag", bag = bag, slot = slot,
                        tradeTime = tradeTime,
                        tradeTimeScannedAt = tradeTime and GetTime() or nil,
                        isBoE = isBoE,
                    })
                end
            end
        end
    end
    return items
end

----------------------------------------------------------------------
-- Filter predicates
----------------------------------------------------------------------
function SR.IsSRItem(item)
    return SR.reserves[item.itemId] ~= nil
end

function SR.IsMSItem(item)
    if SR.reserves[item.itemId] then return false end
    if item.source == "loot" then return true end
    return (item.tradeTime or item.isBoE) and true or false
end

function SR.MeetsQualityFilter(item)
    return item.quality and item.quality >= SR.minQualityFilter
end

----------------------------------------------------------------------
-- Enrichment
----------------------------------------------------------------------
function SR.EnrichWithUid(item)
    if item.source == "loot" then
        local slotKey = "loot:"..item.lootIndex
        item.uid = SR.slotToUid[slotKey] or SR.AssignUid(slotKey, item.itemId)
    else
        local slotKey = "bag:"..item.bag..":"..item.slot
        item.uid = SR.GetBagItemUid(slotKey, item.itemId)
    end
    local award = SR.uidAwards[item.uid]
    item.awardWinner = award and award.winner or nil
    if SR.activeRoll and SR.activeRoll.uid == item.uid then
        item.state = "ROLLING"
    elseif item.awardWinner then
        item.state = "AWARDED"
    elseif SR.uidRolled[item.uid] then
        item.state = "ROLLED"
    else
        item.state = "HOLD"
    end
end

function SR.AttachReservers(item)
    item.reservers = SR.reserves[item.itemId]
    if not item.name and item.reservers and item.reservers[1] then
        item.name = item.reservers[1].itemName
    end
end

function SR.SortBySourceAndQuality(items)
    table.sort(items, function(a, b)
        if a.source ~= b.source then return a.source == "loot" end
        if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
        return (a.uid or 0) < (b.uid or 0)
    end)
end

----------------------------------------------------------------------
-- Composed pipelines
----------------------------------------------------------------------
function SR.GetVisibleSRItems()
    local found = {}

    if SR.isLootOpen and SR.displayMode == "loot" then
        local lootItems = SR.ScanLootItems()
        for _, item in ipairs(lootItems) do
            if SR.IsSRItem(item) and SR.MeetsQualityFilter(item) then
                SR.EnrichWithUid(item)
                SR.AttachReservers(item)
                item.name = item.name or item.reservers[1].itemName
                table.insert(found, item)
            end
        end
    end

    if SR.displayMode == "bag" then
        local bagItems = SR.ScanBagItems()
        for _, item in ipairs(bagItems) do
            if SR.IsSRItem(item) and SR.MeetsQualityFilter(item) then
                SR.EnrichWithUid(item)
                SR.AttachReservers(item)
                item.name = item.name or item.reservers[1].itemName
                table.insert(found, item)
            end
        end
    end

    SR.SortBySourceAndQuality(found)
    return found
end

function SR.GetMSRollItems()
    local found = {}

    if SR.isLootOpen and SR.displayMode == "loot" then
        local lootItems = SR.ScanLootItems()
        for _, item in ipairs(lootItems) do
            if SR.IsMSItem(item) and SR.MeetsQualityFilter(item) then
                SR.EnrichWithUid(item)
                item.name = item.name or "Unknown"
                table.insert(found, item)
            end
        end
    end

    if SR.displayMode == "bag" then
        local bagItems = SR.ScanBagItems()
        for _, item in ipairs(bagItems) do
            if SR.IsMSItem(item) and SR.MeetsQualityFilter(item) then
                SR.EnrichWithUid(item)
                item.name = item.name or "Unknown"
                table.insert(found, item)
            end
        end
    end

    SR.SortBySourceAndQuality(found)
    return found
end

----------------------------------------------------------------------
-- Tooltip Hook
----------------------------------------------------------------------
local function OnTooltipSetItem(tooltip)
    local _, link = tooltip:GetItem()
    if not link then return end
    local itemId = SR.GetItemIdFromLink(link)
    if not itemId then return end
    local entries = SR.reserves[itemId]
    if not entries or #entries == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(SR.C_GREEN.."-- Soft Reserved --"..SR.C_RESET)
    for _, e in ipairs(entries) do
        local color = SR.C_CYAN
        if SR.IsInRaid() then
            local ok = false
            for i=1,GetNumRaidMembers() do
                local rn = GetRaidRosterInfo(i)
                if rn and rn:lower()==e.name:lower() then ok=true; break end
            end
            if not ok then color = SR.C_RED end
        end
        tooltip:AddLine("  "..color..e.name..SR.C_RESET)
    end
    if #entries > 1 then
        tooltip:AddLine(SR.C_ORANGE.."  ("..#entries.." SR - CONTESTED)"..SR.C_RESET)
    end
    tooltip:Show()
end

GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
if ItemRefTooltip then
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
end

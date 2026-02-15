----------------------------------------------------------------------
-- SausageTrade.lua - Trade logic (find + execute)
----------------------------------------------------------------------
local SR = SausageRollNS

function SR.FindItemForTrade(itemUid, itemId)
    -- Check loot window first via UID
    if SR.isLootOpen and itemUid then
        local slotKey = SR.uidToSlot[itemUid]
        local lootIdx = slotKey and tonumber(slotKey:match("^loot:(%d+)$"))
        if lootIdx then
            local link = GetLootSlotLink(lootIdx)
            if link and SR.GetItemIdFromLink(link) == itemId then
                return "loot", nil, nil, lootIdx
            end
        end
    end

    -- Check bags via UID
    local bag, slot = nil, nil
    if itemUid then
        local slotKey = SR.uidToSlot[itemUid]
        if slotKey then
            local bagStr, slotStr = slotKey:match("^bag:(%d+):(%d+)$")
            if bagStr then
                bag, slot = tonumber(bagStr), tonumber(slotStr)
                local link = GetContainerItemLink(bag, slot)
                if not link or SR.GetItemIdFromLink(link) ~= itemId then
                    bag, slot = nil, nil
                end
            end
        end
    end
    -- Fallback scan
    if not bag then
        bag, slot = SR.FindBagSlot(itemId)
    end
    if bag then
        return "bag", bag, slot, nil
    end
    return nil, nil, nil, nil
end

function SR.MasterLootTo(lootIdx, targetName, itemId, itemLink)
    for ci = 1, 40 do
        local cname = GetMasterLootCandidate(ci)
        if not cname then break end
        if cname:lower() == targetName:lower() then
            GiveMasterLoot(lootIdx, ci)
            SR.DPrint(SR.C_GREEN.."Master looted "..(itemLink or "item").." to "..targetName..SR.C_RESET)
            SR.ScheduleRefresh(0.5)
            return true
        end
    end
    SR.DPrint(SR.C_RED..targetName.." not in master loot candidates!"..SR.C_RESET)
    return false
end

function SR.InitiateTradeWith(targetName, bag, slot, itemId, itemLink)
    local uid = SR.GetUnitIdByName(targetName)
    if not uid then
        local myName = UnitName("player") or "me"
        SR.SendRW((itemLink or "Item").." -> "..targetName.." trade "..myName)
        SR.DPrint(SR.C_YELLOW..targetName.." not found in group. Announced in RW."..SR.C_RESET)
        return
    end
    if CheckInteractDistance(uid, 2) then
        SR.pendingTrade = {bag=bag, slot=slot, itemId=itemId}
        InitiateTrade(uid)
        SR.DPrint(SR.C_GREEN.."Trading "..(itemLink or "item").." to "..targetName.."..."..SR.C_RESET)
    else
        local myName = UnitName("player") or "me"
        SR.SendRW((itemLink or "Item").." -> "..targetName.." trade "..myName)
        SR.DPrint(SR.C_YELLOW..targetName.." out of range. Announced in RW."..SR.C_RESET)
    end
end

function SR.TryTradeItem(targetName, itemId, itemLink, itemUid)
    if not targetName or targetName == "" then
        SR.DPrint(SR.C_RED.."No target name!"..SR.C_RESET)
        return
    end

    local source, bag, slot, lootIdx = SR.FindItemForTrade(itemUid, itemId)

    if source == "loot" then
        SR.MasterLootTo(lootIdx, targetName, itemId, itemLink)
        return
    end

    if not source then
        SR.DPrint(SR.C_RED.."Item not in loot or bags!"..SR.C_RESET)
        return
    end

    SR.InitiateTradeWith(targetName, bag, slot, itemId, itemLink)
end

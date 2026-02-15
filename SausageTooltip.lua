----------------------------------------------------------------------
-- SausageTooltip.lua - Hidden tooltip scanning
----------------------------------------------------------------------
local SR = SausageRollNS

local scanTip = CreateFrame("GameTooltip", "SRIScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Shared helper: scan tooltip lines after setting it
local function ScanTooltipLines()
    local lines = {}
    for i = 1, scanTip:NumLines() do
        local left = _G["SRIScanTooltipTextLeft"..i]
        if left then
            local text = left:GetText()
            if text then
                table.insert(lines, text)
            end
        end
    end
    return lines
end

-- Shared helper: parse trade time from tooltip lines
local function ParseTradeTime(lines)
    for _, text in ipairs(lines) do
        if text:match("You may trade this item") then
            local hours = text:match("(%d+) hour")
            local mins = text:match("(%d+) min")
            local secs = 0
            if hours then secs = secs + tonumber(hours) * 3600 end
            if mins then secs = secs + tonumber(mins) * 60 end
            if secs == 0 then secs = 60 end
            return secs
        end
    end
    return nil
end

function SR.GetTradeTimeFromBag(bag, slot)
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    return ParseTradeTime(ScanTooltipLines())
end

function SR.GetTradeTimeFromLoot(lootIndex)
    scanTip:ClearLines()
    scanTip:SetLootItem(lootIndex)
    local lines = ScanTooltipLines()
    for _, text in ipairs(lines) do
        if text:match("You may trade this item") then
            return 7200
        end
    end
    return nil
end

function SR.IsBoEFromBag(bag, slot)
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    local lines = ScanTooltipLines()
    for _, text in ipairs(lines) do
        if text:match("Binds when equipped") then
            return true
        end
    end
    return false
end

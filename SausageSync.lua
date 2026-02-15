----------------------------------------------------------------------
-- SausageSync.lua - Addon sync protocol (ML <-> clients)
----------------------------------------------------------------------
local SR = SausageRollNS

function SR.SendSync(msgType, ...)
    local parts = {msgType}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local payload = table.concat(parts, ":")
    local channel
    if SR.IsInRaid() then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    else
        return
    end
    SendAddonMessage(SR.SYNC_PREFIX, payload, channel)
end

function SR.SendSyncEligible(names)
    if not names or #names == 0 then return end
    local MAX_NAMES_LEN = 247
    local currentStr = ""
    for _, name in ipairs(names) do
        local sep = currentStr == "" and "" or ","
        if #currentStr + #sep + #name > MAX_NAMES_LEN and currentStr ~= "" then
            SR.SendSync("EL", currentStr)
            currentStr = name
        else
            currentStr = currentStr .. sep .. name
        end
    end
    if currentStr ~= "" then
        SR.SendSync("EL", currentStr)
    end
end

function SR.OnSyncMessage(prefix, msg, channel, sender)
    if prefix ~= SR.SYNC_PREFIX then return end
    if sender == UnitName("player") then return end

    local parts = {strsplit(":", msg)}
    local msgType = parts[1]

    if msgType == "RS" then
        local itemId = tonumber(parts[2])
        local quality = tonumber(parts[3])
        local mode = parts[4] or "sr"
        if not itemId then return end
        local iName, iLink, iRarity, _, _, _, _, _, _, iTexture = GetItemInfo(itemId)
        SR.clientRoll = {
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
        SR.clientAutoHideTimer = nil
        SR.CreateClientRollWindow()
        SR.RefreshClientRollWindow()

    elseif msgType == "EL" then
        if not SR.clientRoll then return end
        local nameStr = parts[2]
        if nameStr and nameStr ~= "" then
            local names = {strsplit(",", nameStr)}
            for _, n in ipairs(names) do
                if n ~= "" then
                    table.insert(SR.clientRoll.eligible, n)
                end
            end
        end
        SR.RefreshClientRollWindow()

    elseif msgType == "RU" then
        if not SR.clientRoll then return end
        table.insert(SR.clientRoll.rolls, {
            name = parts[2],
            roll = tonumber(parts[3]) or 0,
            valid = parts[4] == "1",
        })
        SR.RefreshClientRollWindow()

    elseif msgType == "RC" then
        if not SR.clientRoll then return end
        SR.clientRoll.countdown = tonumber(parts[2])
        SR.RefreshClientRollWindow()

    elseif msgType == "RE" then
        if not SR.clientRoll then return end
        local winnerName = parts[2]
        local winnerRoll = tonumber(parts[3]) or 0
        if winnerName and winnerName ~= "" then
            SR.clientRoll.winner = winnerName
            SR.clientRoll.winnerRoll = winnerRoll
        end
        SR.clientRoll.finished = true
        SR.clientRoll.countdown = nil
        local myName = UnitName("player") or ""
        if winnerName and winnerName ~= "" and winnerName:lower() == myName:lower() then
            PlaySoundFile("Interface\\AddOns\\SausageRoll-SR\\Sounds\\SausageAnnounce.mp3")
            RaidNotice_AddMessage(RaidWarningFrame, "YOU WON!", ChatTypeInfo["RAID_WARNING"])
        end
        SR.clientAutoHideTimer = 8
        SR.RefreshClientRollWindow()

    elseif msgType == "RX" then
        SR.clientRoll = nil
        SR.clientAutoHideTimer = nil
        if SR.clientRollFrame then SR.clientRollFrame:Hide() end
    end
end

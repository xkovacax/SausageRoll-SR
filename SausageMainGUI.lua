----------------------------------------------------------------------
-- SausageMainGUI.lua - Main window, rows, buttons
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- Row builder
----------------------------------------------------------------------
local function CreateRow(parent, rowTable, index, mode)
    local rn = "SRI_"..mode.."_R"..index
    local row = CreateFrame("Frame", rn, parent)
    row:SetHeight(SR.ROW_HEIGHT)
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
    bankBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
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
    tradeBtn:SetSize(BW, BH + gap + 16)
    tradeBtn:SetPoint("BOTTOMRIGHT", bankBtn, "BOTTOMLEFT", -gap, 0)
    tradeBtn:SetText("Trade")
    tradeBtn:GetFontString():SetFont(tradeBtn:GetFontString():GetFont(), BF)
    row.tradeBtn = tradeBtn

    local winBtn = CreateFrame("Button", rn.."W", row, "UIPanelButtonTemplate")
    winBtn:SetSize(BW, BH)
    winBtn:SetPoint("RIGHT", bankBtn, "LEFT", -(BW + 2*gap), 0)
    winBtn:SetText("Winner")
    winBtn:GetFontString():SetFont(winBtn:GetFontString():GetFont(), BF)
    row.winBtn = winBtn

    local rollBtn = CreateFrame("Button", rn.."R", row, "UIPanelButtonTemplate")
    rollBtn:SetSize(BW, BH)
    rollBtn:SetPoint("RIGHT", winBtn, "LEFT", -gap, 0)
    rollBtn:SetText("Roll")
    rollBtn:GetFontString():SetFont(rollBtn:GetFontString():GetFont(), BF)
    row.rollBtn = rollBtn

    local resetBtn = CreateFrame("Button", rn.."Reset", row, "UIPanelButtonTemplate")
    resetBtn:SetSize(BW*2 + gap, 16)
    resetBtn:SetPoint("BOTTOMLEFT", rollBtn, "TOPLEFT", 0, 2)
    resetBtn:GetFontString():SetFont(resetBtn:GetFontString():GetFont(), 8)
    resetBtn:SetText("Reset")
    row.resetBtn = resetBtn

    -- Source + Trade timer: left of Roll button
    local srcText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    srcText:SetPoint("RIGHT", rollBtn, "LEFT", -6, 6)
    row.srcText = srcText

    local tradeTimerText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tradeTimerText:SetPoint("RIGHT", rollBtn, "LEFT", -6, -6)
    tradeTimerText:SetFont(tradeTimerText:GetFont(), 9)
    row.tradeText = tradeTimerText

    -- Item name (top line)
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
    row.fullInfoText = ""

    infoBtn:SetScript("OnEnter", function(self)
        if row.fullInfoText and row.fullInfoText ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Soft Reserves:", 1, 0.82, 0, false)
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

----------------------------------------------------------------------
-- SetupRow sub-functions
----------------------------------------------------------------------
function SR.SetupRowIcon(row, item)
    row.iconTex:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local qc = SR.QC(item.quality)
    row.iconBorder:SetBackdropBorderColor(qc.r, qc.g, qc.b, 0.8)
end

function SR.SetupRowItemText(row, item, mode)
    row.itemText:SetText(SR.QCHex(item.quality)..(item.name or "?")..SR.C_RESET)

    if mode == "sr" and item.reservers then
        local plainNames = {}
        local colorNames = {}
        for _, r in ipairs(item.reservers) do
            table.insert(plainNames, r.name)
            local color = SR.C_CYAN
            if SR.IsInRaid() then
                local found = false
                for i=1,GetNumRaidMembers() do
                    local rn = GetRaidRosterInfo(i)
                    if rn and rn:lower()==r.name:lower() then found=true; break end
                end
                if not found then color = SR.C_RED end
            end
            table.insert(colorNames, color..r.name..SR.C_RESET)
        end
        row.fullInfoText = table.concat(plainNames, ", ")
        local header = "SR: "..SR.C_ORANGE.."[x"..#item.reservers.."]"..SR.C_RESET
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
        local lineCount = 1 + #nameLines
        local lineH = 12
        local textHeight = lineCount * lineH
        row.infoBtn:SetHeight(textHeight)
        row.dynamicHeight = math.max(SR.ROW_HEIGHT, 20 + textHeight + 4)
        row:SetHeight(row.dynamicHeight)
    else
        row.infoText:SetText(SR.C_YELLOW.."MS/OS Roll"..SR.C_RESET)
        row.fullInfoText = ""
    end
end

function SR.SetupRowStatusText(row, item)
    if item.state == "ROLLING" then
        row.srcText:SetText(SR.C_YELLOW.."ROLLING"..SR.C_RESET)
        row.tradeText:SetText(SR.C_YELLOW.."in progress..."..SR.C_RESET)
    elseif item.state == "AWARDED" then
        row.srcText:SetText(SR.C_GREEN.."AWARDED"..SR.C_RESET)
        row.tradeText:SetText(SR.C_CYAN.."-> "..item.awardWinner..SR.C_RESET)
    elseif item.state == "ROLLED" then
        row.srcText:SetText(SR.C_GRAY.."ROLLED"..SR.C_RESET)
        if item.source == "loot" then
            row.tradeText:SetText(SR.C_GREEN.."LOOT"..SR.C_RESET)
        elseif item.tradeTime then
            local totalMins = math.floor(item.tradeTime / 60)
            local hours = math.floor(totalMins / 60)
            local mins = totalMins - (hours * 60)
            local timeStr = hours > 0 and (hours.."h "..mins.."m") or (mins.."m")
            local tColor = SR.C_GREEN
            if totalMins < 10 then tColor = SR.C_RED
            elseif totalMins < 30 then tColor = SR.C_YELLOW end
            row.tradeText:SetText(tColor..timeStr..SR.C_RESET)
        elseif item.isBoE then
            row.tradeText:SetText(SR.C_GREEN.."BoE"..SR.C_RESET)
        else
            row.tradeText:SetText(SR.C_GRAY.."BAG"..SR.C_RESET)
        end
    else -- HOLD
        row.srcText:SetText(SR.C_ORANGE.."HOLD"..SR.C_RESET)
        if item.source == "loot" then
            row.tradeText:SetText(SR.C_GREEN.."LOOT"..SR.C_RESET)
        elseif item.tradeTime then
            local totalMins = math.floor(item.tradeTime / 60)
            local hours = math.floor(totalMins / 60)
            local mins = totalMins - (hours * 60)
            local timeStr = hours > 0 and (hours.."h "..mins.."m") or (mins.."m")
            local tColor = SR.C_GREEN
            if totalMins < 10 then tColor = SR.C_RED
            elseif totalMins < 30 then tColor = SR.C_YELLOW end
            row.tradeText:SetText(tColor..timeStr..SR.C_RESET)
        elseif item.isBoE then
            row.tradeText:SetText(SR.C_GREEN.."BoE"..SR.C_RESET)
        else
            row.tradeText:SetText(SR.C_GRAY.."BAG"..SR.C_RESET)
        end
    end
end

function SR.SetupRowButtonStates(row, item)
    if item.state == "ROLLING" or item.state == "AWARDED" or item.state == "ROLLED" then
        row.rollBtn:Disable()
    else
        row.rollBtn:Enable()
    end
    if item.state == "ROLLING" and SR.activeRoll then
        row.winBtn:Enable()
    else
        row.winBtn:Disable()
    end
    if item.awardWinner then
        row.tradeBtn:Enable()
    else
        row.tradeBtn:Disable()
    end
end

function SR.SetupRowCallbacks(row, item, mode)
    -- Reset button
    if row.resetBtn then
        row.resetBtn:SetScript("OnClick", function()
            if item.uid then
                SR.uidAwards[item.uid] = nil
                SR.uidRolled[item.uid] = nil
            end
            SR.RemoveLootHistoryByUid(item.uid, item.itemId)
            SR.RemovePersistedState(item.itemId)
            if SR.activeRoll and SR.activeRoll.uid == item.uid then
                SR.SendSync("RX")
                SR.activeRoll = nil
                SR.countdownTimer = nil
            end
            if SR.finishedRoll and SR.finishedRoll.uid == item.uid then
                SR.CloseRollWindow()
            end
            SR.RefreshMainFrame()
        end)
        row.resetBtn:Enable()
    end

    -- Roll
    row.rollBtn:SetScript("OnClick", function()
        local effectiveMode = (mode == "sr") and mode or "ms"
        SR.StartRoll(item.uid, item.itemId, item.link, effectiveMode)
        row.rollBtn:Disable()
    end)

    -- Winner
    row.winBtn:SetScript("OnClick", function()
        if not SR.activeRoll then
            SR.DPrint(SR.C_RED.."No active roll! Click Roll first."..SR.C_RESET)
            return
        end
        if SR.activeRoll.uid ~= item.uid then
            SR.DPrint(SR.C_RED.."Active roll is for: "..(SR.activeRoll.link or "?")..SR.C_RESET)
            return
        end
        SR.StartCountdown()
    end)

    -- Trade
    row.tradeBtn:SetScript("OnClick", function()
        if not item.awardWinner then
            SR.DPrint(SR.C_RED.."No winner for this item! Roll first."..SR.C_RESET)
            return
        end
        SR.RecordLootHistory(item.itemId, item.link, item.name, item.quality,
            item.awardWinner, mode == "sr" and "SR" or "ROLL", item.uid)
        if item.awardWinner:lower() == UnitName("player"):lower() then
            SR.DPrint(SR.C_GREEN.."Claimed: "..(item.link or "?")..SR.C_RESET)
        else
            SR.TryTradeItem(item.awardWinner, item.itemId, item.link, item.uid)
        end
        if SR.finishedRoll and SR.finishedRoll.uid == item.uid then SR.CloseRollWindow() end
    end)

    -- Bank
    row.bankBtn:SetScript("OnClick", function()
        if not SR.bankCharName then
            SR.DPrint(SR.C_RED.."Set bank char: /sr bank <name>"..SR.C_RESET)
            return
        end
        SR.RecordLootHistory(item.itemId, item.link, item.name, item.quality,
            SR.bankCharName, "BANK", item.uid)
        SR.TryTradeItem(SR.bankCharName, item.itemId, item.link, item.uid, true)
        if SR.finishedRoll and SR.finishedRoll.uid == item.uid then SR.CloseRollWindow() end
    end)

    -- Diss
    row.dissBtn:SetScript("OnClick", function()
        if not SR.dissCharName then
            SR.DPrint(SR.C_RED.."Set diss char: /sr diss <name>"..SR.C_RESET)
            return
        end
        SR.RecordLootHistory(item.itemId, item.link, item.name, item.quality,
            SR.dissCharName, "DISS", item.uid)
        SR.TryTradeItem(SR.dissCharName, item.itemId, item.link, item.uid, true)
        if SR.finishedRoll and SR.finishedRoll.uid == item.uid then SR.CloseRollWindow() end
    end)

end

local function SetupRow(row, item, mode)
    row.data = item
    row.link = item.link
    SR.SetupRowIcon(row, item)
    SR.SetupRowItemText(row, item, mode)
    SR.SetupRowStatusText(row, item)
    SR.SetupRowButtonStates(row, item)
    SR.SetupRowCallbacks(row, item, mode)
    row:Show()
end

----------------------------------------------------------------------
-- Trade timer display update (lightweight, no full rebuild)
----------------------------------------------------------------------
function SR.UpdateTradeTimerDisplays()
    if not SR.mainFrame or not SR.mainFrame:IsShown() then return end
    local now = GetTime()
    local function UpdateRowTimer(row)
        if not row:IsShown() or not row.data then return end
        local item = row.data
        if item.source == "bag" and item.tradeTime and item.tradeTimeScannedAt
           and item.state ~= "AWARDED" and item.state ~= "ROLLING" then
            local remaining = item.tradeTime - (now - item.tradeTimeScannedAt)
            if remaining < 0 then remaining = 0 end
            local totalMins = math.floor(remaining / 60)
            local hours = math.floor(totalMins / 60)
            local mins = totalMins - (hours * 60)
            local timeStr = hours > 0 and (hours.."h "..mins.."m") or (mins.."m")
            local tColor = SR.C_GREEN
            if totalMins < 10 then tColor = SR.C_RED
            elseif totalMins < 30 then tColor = SR.C_YELLOW end
            row.tradeText:SetText(tColor..timeStr..SR.C_RESET)
        end
    end
    for _, row in ipairs(SR.srRows) do UpdateRowTimer(row) end
    for _, row in ipairs(SR.msRows) do UpdateRowTimer(row) end
end

----------------------------------------------------------------------
-- Refresh main frame
----------------------------------------------------------------------
----------------------------------------------------------------------
-- History row rendering
----------------------------------------------------------------------
local HISTORY_METHOD_COLORS = {
    SR   = SR.C_GREEN,
    ROLL = SR.C_YELLOW,
    BANK = SR.C_CYAN,
    DISS = SR.C_ORANGE,
    KEPT = SR.C_GRAY,
}

local function CreateHistoryRow(parent, index)
    local rn = "SRI_hist_R"..index
    local row = CreateFrame("Frame", rn, parent)
    row:SetHeight(30)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    if index % 2 == 0 then bg:SetVertexColor(0.15,0.15,0.15,0.6)
    else bg:SetVertexColor(0.08,0.08,0.08,0.4) end

    local iconBtn = CreateFrame("Button", rn.."I", row)
    iconBtn:SetSize(26,26)
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

    row.itemText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.itemText:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
    row.itemText:SetJustifyH("LEFT")

    row.recipientText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.recipientText:SetPoint("LEFT", row.itemText, "RIGHT", 6, 0)

    row.methodText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.methodText:SetPoint("RIGHT", row, "RIGHT", -80, 0)

    row.dateText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.dateText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.dateText:SetFont(row.dateText:GetFont(), 9)

    row:Hide()
    return row
end

local function SetupHistoryRow(row, entry)
    row.link = entry.link
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(entry.link or entry.itemId or 0)
    row.iconTex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    local qc = SR.QC(entry.quality or 1)
    row.iconBorder:SetBackdropBorderColor(qc.r, qc.g, qc.b, 0.8)
    row.itemText:SetText(SR.QCHex(entry.quality or 1)..(entry.name or "?")..SR.C_RESET)
    row.recipientText:SetText(SR.C_WHITE.."-> "..SR.C_CYAN..(entry.recipient or "?")..SR.C_RESET)
    local mc = HISTORY_METHOD_COLORS[entry.method] or SR.C_WHITE
    row.methodText:SetText(mc..(entry.method or "?")..SR.C_RESET)
    row.dateText:SetText(SR.C_GRAY..date("%d.%m %H:%M", entry.timestamp or 0)..SR.C_RESET)
    row:Show()
end

function SR.RefreshMainFrame()
    if not SR.mainFrame then return end
    local f = SR.mainFrame

    -- Hide all item rows and history rows
    for _, r in ipairs(SR.srRows) do r:Hide() end
    for _, r in ipairs(SR.msRows) do r:Hide() end
    for _, r in ipairs(SR.historyRows) do r:Hide() end

    -- Toggle visibility of normal vs history UI elements
    local showNormal = not SR.showHistory
    f.srHeader:SetAlpha(showNormal and 1 or 0)
    f.msHeader:SetAlpha(showNormal and 1 or 0)
    if f.historyHeader then f.historyHeader:SetAlpha(showNormal and 0 or 1) end

    -- Show/hide normal bottom buttons
    if f.normalButtons then
        for _, btn in ipairs(f.normalButtons) do
            if showNormal then btn:Show() else btn:Hide() end
        end
    end
    -- Show/hide history bottom buttons
    if f.historyButtons then
        for _, btn in ipairs(f.historyButtons) do
            if showNormal then btn:Hide() else btn:Show() end
        end
    end

    if SR.showHistory then
        -- History view
        local yOff, hdrH = 0, 22
        if not f.historyHeader then
            f.historyHeader = f.content:CreateFontString(nil,"OVERLAY","GameFontNormal")
        end
        f.historyHeader:SetAlpha(1)
        f.historyHeader:ClearAllPoints()
        f.historyHeader:SetPoint("TOPLEFT", f.content, "TOPLEFT", 5, -yOff)
        f.historyHeader:SetText(SR.C_CYAN.."=== LOOT HISTORY ("..#SR.lootHistory..") ==="..SR.C_RESET)
        yOff = yOff + hdrH

        -- Render newest first
        for i = #SR.lootHistory, 1, -1 do
            local entry = SR.lootHistory[i]
            local idx = #SR.lootHistory - i + 1
            local row = SR.historyRows[idx]
            if not row then
                row = CreateHistoryRow(f.content, idx)
                SR.historyRows[idx] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -yOff)
            row:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
            SetupHistoryRow(row, entry)
            yOff = yOff + 30
        end

        f.content:SetHeight(math.max(yOff + 10, 1))
    else
        -- Normal view
        SR.SyncItemUids()
        local srItems = SR.GetVisibleSRItems()
        local msItems = SR.GetMSRollItems()
        local yOff, hdrH = 0, 22

        -- SR header
        f.srHeader:ClearAllPoints()
        f.srHeader:SetPoint("TOPLEFT", f.content,"TOPLEFT",5,-yOff)
        if #srItems > 0 then
            local modeTag = SR.displayMode == "loot" and "LOOT" or "BAG"
            f.srHeader:SetText(SR.C_GREEN.."=== SOFT RESERVE - "..modeTag.." ("..#srItems..") ==="..SR.C_RESET)
        else
            f.srHeader:SetText(SR.C_GRAY.."=== SOFT RESERVE (none visible) ==="..SR.C_RESET)
        end
        yOff = yOff + hdrH

        for i, item in ipairs(srItems) do
            local row = SR.srRows[i]
            if not row then row = CreateRow(f.content, SR.srRows, i, "sr") end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.content,"TOPLEFT",0,-yOff)
            row:SetPoint("RIGHT", f.content,"RIGHT",0,0)
            SetupRow(row, item, "sr")
            yOff = yOff + (row.dynamicHeight or SR.ROW_HEIGHT)
        end

        yOff = yOff + 10

        -- MS header
        f.msHeader:ClearAllPoints()
        f.msHeader:SetPoint("TOPLEFT", f.content,"TOPLEFT",5,-yOff)
        if #msItems > 0 then
            local modeTag = SR.displayMode == "loot" and "LOOT" or "BAG"
            f.msHeader:SetText(SR.C_YELLOW.."=== ROLL - "..modeTag.." ("..#msItems..") ==="..SR.C_RESET)
        else
            f.msHeader:SetText(SR.C_GRAY.."=== ROLL (none) ==="..SR.C_RESET)
        end
        yOff = yOff + hdrH

        for i, item in ipairs(msItems) do
            local row = SR.msRows[i]
            if not row then row = CreateRow(f.content, SR.msRows, i, "ms") end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.content,"TOPLEFT",0,-yOff)
            row:SetPoint("RIGHT", f.content,"RIGHT",0,0)
            SetupRow(row, item, "ms")
            yOff = yOff + SR.ROW_HEIGHT
        end

        f.content:SetHeight(math.max(yOff+10, 1))
    end

    -- Status (always shown)
    local pc = 0
    for _ in pairs(SR.reservesByName) do pc = pc + 1 end
    local rs = ""
    if SR.activeRoll then
        rs = " | "..SR.C_ORANGE.."Rolling: "..(SR.activeRoll.link or "?")..
             " ("..SR.activeRoll.mode:upper()..", "..#SR.activeRoll.rolls.." rolls)"..SR.C_RESET
    end
    local srStatus
    if SR.importCount > 0 then
        srStatus = SR.C_GREEN..SR.importCount..SR.C_WHITE.." SR | "..SR.C_GREEN..pc..SR.C_WHITE.." players"
    else
        srStatus = SR.C_GRAY.."No SR imported"
    end
    f.statusText:SetText(srStatus..rs)
    -- Bank/Diss display
    if f.bankText then
        local bankStr = SR.bankCharName and (SR.C_CYAN..SR.bankCharName..SR.C_RESET) or (SR.C_RED.."not set"..SR.C_RESET)
        local dissStr = SR.dissCharName and (SR.C_CYAN..SR.dissCharName..SR.C_RESET) or (SR.C_RED.."not set"..SR.C_RESET)
        f.bankText:SetText(SR.C_GRAY.."Bank: "..bankStr..SR.C_GRAY.." | Diss: "..dissStr)
    end
end

----------------------------------------------------------------------
-- Create main frame
----------------------------------------------------------------------
function SR.CreateMainFrame(silent)
    if not SR.IsMasterLooter() then
        if not silent then
            SR.DPrint(SR.C_RED .. "You must be Master Looter to open this window." .. SR.C_RESET)
        end
        return
    end
    if SR.mainFrame then SR.mainFrame:Show(); SR.RefreshMainFrame(); return end

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
    closeX:SetPoint("TOPRIGHT",-6,-12)

    -- History checkbox (top-right, left of close X)
    local histCheck = CreateFrame("CheckButton", nil, f)
    histCheck:SetSize(20, 20)
    histCheck:SetPoint("RIGHT", closeX, "LEFT", -40, 0)
    histCheck:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    histCheck:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    histCheck:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    histCheck:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    histCheck:SetChecked(SR.showHistory)
    histCheck.label = histCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histCheck.label:SetPoint("LEFT", histCheck, "RIGHT", 2, 0)
    histCheck.label:SetText(SR.C_CYAN.."History")
    histCheck:SetScript("OnClick", function(self)
        SR.showHistory = self:GetChecked() and true or false
        SR.RefreshMainFrame()
    end)

    local headerTex = f:CreateTexture(nil, "ARTWORK")
    headerTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    headerTex:SetWidth(550)
    headerTex:SetHeight(64)
    headerTex:SetPoint("TOP", 0, 12)

    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    t:SetPoint("TOP", headerTex, "TOP", 0, -14)
    t:SetText(SR.C_GREEN.."Sausage Roll"..SR.C_WHITE.." - SR Loot Tracker "..SR.C_GRAY.."v"..SR.VERSION..SR.C_RESET)

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
            info.checked = (SR.minQualityFilter == opt.value)
            info.func = function(btn)
                SR.minQualityFilter = btn.value
                UIDropDownMenu_SetSelectedValue(dd, btn.value)
                UIDropDownMenu_SetText(dd, opt.text)
                SR.RefreshMainFrame()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dd, RarityDropdown_Init)
    UIDropDownMenu_SetSelectedValue(dd, SR.minQualityFilter)
    for _, opt in ipairs(rarityOptions) do
        if opt.value == SR.minQualityFilter then
            UIDropDownMenu_SetText(dd, opt.text)
            break
        end
    end
    f.rarityDropdown = dd

    -- BoE checkbox
    local boeCheck = CreateFrame("CheckButton", nil, f)
    boeCheck:SetSize(20, 20)
    boeCheck:SetPoint("LEFT", dd, "RIGHT", -2, 2)
    boeCheck:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    boeCheck:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    boeCheck:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    boeCheck:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    boeCheck:SetChecked(SR.showBoE)
    boeCheck.label = boeCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boeCheck.label:SetPoint("LEFT", boeCheck, "RIGHT", 2, 0)
    boeCheck.label:SetText(SR.C_GREEN.."BoE")
    boeCheck:SetScript("OnClick", function(self)
        SR.showBoE = self:GetChecked()
        SR.RefreshMainFrame()
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
    btn2:SetScript("OnClick", function() SR.CreateImportFrame() end)

    local btn3 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btn3:SetSize(110,22); btn3:SetPoint("BOTTOMLEFT",110,36)
    btn3:SetText("Announce All SR")
    btn3:SetScript("OnClick", function()
        if SR.importCount == 0 then SR.DPrint(SR.C_YELLOW.."No SR imported."..SR.C_RESET); return end
        SR.SendRaid("=== Soft Reserves ===")
        for itemId, entries in pairs(SR.reserves) do
            local _, link = GetItemInfo(itemId)
            local names = {}
            for _, e in ipairs(entries) do table.insert(names, e.name) end
            local itemStr = link or ("["..(entries[1].itemName or "?").."]")
            SR.SendRaid(itemStr.." - "..table.concat(names, ", "))
        end
    end)

    -- Import HR CSV button
    local btnHR = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnHR:SetSize(95,22); btnHR:SetPoint("BOTTOMLEFT",10,12)
    btnHR:SetText("Import HR CSV")
    btnHR:SetScript("OnClick", function() SR.CreateHRImportFrame() end)

    -- Announce All HR button
    local btnHRAnn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnHRAnn:SetSize(110,22); btnHRAnn:SetPoint("BOTTOMLEFT",110,12)
    btnHRAnn:SetText("Announce All HR")
    btnHRAnn:SetScript("OnClick", function()
        if #SR.hardReserves == 0 and #SR.hardReserveCustom == 0 then SR.DPrint(SR.C_YELLOW.."No HR items."..SR.C_RESET); return end
        SR.SendRaid("=== Hard Reserves ===")
        for _, hr in ipairs(SR.hardReserves) do
            local _, link = GetItemInfo(hr.itemId)
            SR.SendRaid(link or ("["..hr.itemName.."]"))
        end
        for _, line in ipairs(SR.hardReserveCustom) do
            SR.SendRaid(line)
        end
    end)

    local credit = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    credit:SetPoint("BOTTOM",0,10)
    credit:SetText(SR.C_GRAY.."Sausage Roll - SR created by Sausage Party"..SR.C_RESET)

    -- Set Bank button
    local btnSetBank = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnSetBank:SetSize(90,22); btnSetBank:SetPoint("BOTTOM",-48,36)
    btnSetBank:SetText("Set Bank")
    btnSetBank:SetScript("OnClick", function(self)
        local members = SR.GetGroupMembers()
        local menuList = {}
        for _, name in ipairs(members) do
            table.insert(menuList, {
                text = name,
                checked = (SR.bankCharName and SR.bankCharName:lower() == name:lower()),
                func = function()
                    SR.bankCharName = name
                    SausageRollImportDB.bankCharName = SR.bankCharName
                    SR.DPrint(SR.C_GREEN.."Bank set to: "..SR.C_CYAN..SR.bankCharName..SR.C_RESET)
                    SR.RefreshMainFrame()
                end,
            })
        end
        table.insert(menuList, {
            text = "-- Clear --",
            func = function()
                SR.bankCharName = nil
                SausageRollImportDB.bankCharName = nil
                SR.DPrint(SR.C_YELLOW.."Bank char cleared."..SR.C_RESET)
                SR.RefreshMainFrame()
            end,
        })
        EasyMenu(menuList, SR.charDropdownFrame, self, 0, 0, "MENU")
    end)

    -- Set Diss button
    local btnSetDiss = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnSetDiss:SetSize(90,22); btnSetDiss:SetPoint("BOTTOM",48,36)
    btnSetDiss:SetText("Set Diss")
    btnSetDiss:SetScript("OnClick", function(self)
        local members = SR.GetGroupMembers()
        local menuList = {}
        for _, name in ipairs(members) do
            table.insert(menuList, {
                text = name,
                checked = (SR.dissCharName and SR.dissCharName:lower() == name:lower()),
                func = function()
                    SR.dissCharName = name
                    SausageRollImportDB.dissCharName = SR.dissCharName
                    SR.DPrint(SR.C_GREEN.."Diss set to: "..SR.C_CYAN..SR.dissCharName..SR.C_RESET)
                    SR.RefreshMainFrame()
                end,
            })
        end
        table.insert(menuList, {
            text = "-- Clear --",
            func = function()
                SR.dissCharName = nil
                SausageRollImportDB.dissCharName = nil
                SR.DPrint(SR.C_YELLOW.."Diss char cleared."..SR.C_RESET)
                SR.RefreshMainFrame()
            end,
        })
        EasyMenu(menuList, SR.charDropdownFrame, self, 0, 0, "MENU")
    end)

    -- Grab All Loot to ML button
    local btnGrab = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnGrab:SetSize(120,22); btnGrab:SetPoint("TOPLEFT",10,-40)
    btnGrab:SetText("Grab All Loot")
    btnGrab:SetScript("OnClick", function()
        if not SR.isLootOpen then
            SR.DPrint(SR.C_RED.."No loot window open!"..SR.C_RESET)
            return
        end
        if not SR.IsMasterLooter() then
            SR.DPrint(SR.C_RED.."You are not Master Looter!"..SR.C_RESET)
            return
        end
        local myName = UnitName("player")
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
            SR.DPrint(SR.C_RED.."Can't find self in loot candidates!"..SR.C_RESET)
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
            local channel = SR.IsInRaid() and "RAID" or "PARTY"
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
            SR.DPrint(SR.C_GREEN.."Grabbed "..#grabbed.." items to inventory."..SR.C_RESET)
        else
            SR.DPrint(SR.C_YELLOW.."No lootable items."..SR.C_RESET)
        end
    end)

    -- Bank/Diss name display
    local bankText = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    bankText:SetPoint("BOTTOM", 0, 60)
    f.bankText = bankText

    local btn1 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btn1:SetSize(60,22); btn1:SetPoint("BOTTOMRIGHT",-10,36)
    btn1:SetText("Refresh")
    btn1:SetScript("OnClick", function() SR.RefreshMainFrame() end)

    local btn4 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btn4:SetSize(60,22); btn4:SetPoint("BOTTOMRIGHT",-10,12)
    btn4:SetText("Close")
    btn4:SetScript("OnClick", function() f:Hide() end)

    -- Collect normal bottom buttons for show/hide toggling
    f.normalButtons = {btn2, btn3, btnHR, btnHRAnn, btnSetBank, btnSetDiss, btnGrab,
                       f.boeCheckbox, f.rarityDropdown, bankText}

    -- History bottom buttons (hidden by default)
    local btnResetHist = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnResetHist:SetSize(90,22); btnResetHist:SetPoint("RIGHT", btn1, "LEFT", -4, 0)
    btnResetHist:SetText("Reset History")
    btnResetHist:GetFontString():SetFont(btnResetHist:GetFontString():GetFont(), 9)
    btnResetHist:SetScript("OnClick", function()
        SR.ClearLootHistory()
        SR.DPrint(SR.C_YELLOW.."Loot history cleared."..SR.C_RESET)
        SR.RefreshMainFrame()
    end)
    btnResetHist:Hide()

    local btnExport = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnExport:SetSize(90,22); btnExport:SetPoint("RIGHT", btn4, "LEFT", -4, 0)
    btnExport:SetText("Export CSV")
    btnExport:GetFontString():SetFont(btnExport:GetFontString():GetFont(), 9)
    btnExport:SetScript("OnClick", function()
        SR.CreateExportFrame()
    end)
    btnExport:Hide()

    f.historyButtons = {btnResetHist, btnExport}

    SR.mainFrame = f
    SR.RefreshMainFrame()
end

----------------------------------------------------------------------
-- Export frame (CSV popup)
----------------------------------------------------------------------
function SR.CreateExportFrame()
    if SR.exportFrame then
        SR.exportFrame.editBox:SetText(SR.ExportLootHistoryCSV())
        SR.exportFrame:Show()
        SR.exportFrame.editBox:HighlightText()
        SR.exportFrame.editBox:SetFocus()
        return
    end

    local ef = CreateFrame("Frame", "SRIExportFrame", UIParent)
    ef:SetSize(500, 350)
    ef:SetPoint("CENTER")
    ef:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=8,right=8,top=8,bottom=8},
    })
    ef:SetBackdropColor(0,0,0,0.95)
    ef:SetMovable(true); ef:EnableMouse(true)
    ef:RegisterForDrag("LeftButton")
    ef:SetScript("OnDragStart", ef.StartMoving)
    ef:SetScript("OnDragStop", ef.StopMovingOrSizing)
    ef:SetFrameStrata("FULLSCREEN_DIALOG")
    tinsert(UISpecialFrames, "SRIExportFrame")

    local closeX = CreateFrame("Button",nil,ef,"UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT",-2,-2)

    local title = ef:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",0,-12)
    title:SetText(SR.C_CYAN.."Loot History Export"..SR.C_RESET)

    local sc = CreateFrame("ScrollFrame", "SRIExportScroll", ef, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 12, -36)
    sc:SetPoint("BOTTOMRIGHT", -32, 12)

    local eb = CreateFrame("EditBox", "SRIExportEditBox", sc)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(sc:GetWidth() - 10)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ef:Hide() end)
    sc:SetScrollChild(eb)

    ef.editBox = eb
    SR.exportFrame = ef

    eb:SetText(SR.ExportLootHistoryCSV())
    eb:HighlightText()
    eb:SetFocus()
end

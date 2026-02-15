----------------------------------------------------------------------
-- SausageClientRollGUI.lua - Client roll window (non-ML players)
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- Client roll row helper
----------------------------------------------------------------------
local function GetClientRow(idx)
    if not SR.clientRollRows[idx] then
        local row = CreateFrame("Frame", nil, SR.clientRollFrame.content)
        row:SetHeight(15)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", 6, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.text = fs
        SR.clientRollRows[idx] = row
    end
    return SR.clientRollRows[idx]
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
function SR.RefreshClientRollWindow()
    if not SR.clientRollFrame then return end
    if not SR.clientRoll then
        SR.clientRollFrame:Hide()
        return
    end
    SR.clientRollFrame:Show()

    -- Refresh item info
    local iName, iLink, iRarity, _, _, _, _, _, _, iTexture = GetItemInfo(SR.clientRoll.itemId)
    local link = iLink or SR.clientRoll.link
    local quality = iRarity or SR.clientRoll.quality or 1
    local texture = iTexture or SR.clientRoll.icon
    SR.clientRoll.link = link
    SR.clientRoll.quality = quality
    SR.clientRoll.icon = texture

    SR.clientRollFrame.iconTex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local qc = SR.QC(quality)
    SR.clientRollFrame.iconBorder:SetBackdropBorderColor(qc.r, qc.g, qc.b, 0.8)
    SR.clientRollFrame.itemText:SetText(SR.QCHex(quality) .. (iName or ("Item " .. SR.clientRoll.itemId)) .. SR.C_RESET)

    -- Mode + countdown / winner
    local modeTag = SR.C_ORANGE .. "[" .. SR.clientRoll.mode:upper() .. "]" .. SR.C_RESET
    if SR.clientRoll.finished then
        if SR.clientRoll.winner then
            SR.clientRollFrame.subtitle:SetText(modeTag .. "  " .. SR.C_GREEN .. "Winner: " .. SR.C_CYAN .. SR.clientRoll.winner .. SR.C_WHITE .. " (" .. SR.clientRoll.winnerRoll .. ")" .. SR.C_RESET)
        else
            SR.clientRollFrame.subtitle:SetText(modeTag .. "  " .. SR.C_RED .. "No winner" .. SR.C_RESET)
        end
    elseif SR.clientRoll.countdown then
        if SR.clientRoll.countdown > 0 then
            SR.clientRollFrame.subtitle:SetText(modeTag .. "  " .. SR.C_RED .. ">> " .. SR.clientRoll.countdown .. " <<" .. SR.C_RESET)
        else
            SR.clientRollFrame.subtitle:SetText(modeTag .. "  " .. SR.C_RED .. ">> STOP! <<" .. SR.C_RESET)
        end
    else
        SR.clientRollFrame.subtitle:SetText(modeTag .. "  " .. SR.C_GREEN .. "(" .. #SR.clientRoll.rolls .. " rolls)" .. SR.C_RESET)
    end

    -- Eligible list (SR mode only)
    local yOff = 0
    local myName = UnitName("player")

    if SR.clientRoll.mode == "sr" and #SR.clientRoll.eligible > 0 then
        if not SR.clientRollFrame.eligibleHeader then
            SR.clientRollFrame.eligibleHeader = SR.clientRollFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            SR.clientRollFrame.eligibleHeader:SetJustifyH("LEFT")
        end
        SR.clientRollFrame.eligibleHeader:ClearAllPoints()
        SR.clientRollFrame.eligibleHeader:SetPoint("TOPLEFT", SR.clientRollFrame.content, "TOPLEFT", 6, -yOff)
        SR.clientRollFrame.eligibleHeader:SetText(SR.C_ORANGE .. "Eligible: [x" .. #SR.clientRoll.eligible .. "]" .. SR.C_RESET)
        SR.clientRollFrame.eligibleHeader:Show()
        yOff = yOff + 14

        local nameParts = {}
        for _, eName in ipairs(SR.clientRoll.eligible) do
            if myName and eName:lower() == myName:lower() then
                table.insert(nameParts, SR.C_GREEN .. eName .. SR.C_RESET)
            else
                table.insert(nameParts, SR.C_CYAN .. eName .. SR.C_RESET)
            end
        end

        local nameLines = {}
        for idx = 1, #nameParts, 3 do
            local chunk = {}
            for j = idx, math.min(idx + 2, #nameParts) do
                table.insert(chunk, nameParts[j])
            end
            table.insert(nameLines, table.concat(chunk, ", "))
        end

        if not SR.clientRollFrame.eligibleText then
            local et = SR.clientRollFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            et:SetJustifyH("LEFT")
            et:SetFont(et:GetFont(), 10)
            SR.clientRollFrame.eligibleText = et
        end
        SR.clientRollFrame.eligibleText:ClearAllPoints()
        SR.clientRollFrame.eligibleText:SetPoint("TOPLEFT", SR.clientRollFrame.content, "TOPLEFT", 10, -yOff)
        SR.clientRollFrame.eligibleText:SetPoint("TOPRIGHT", SR.clientRollFrame.content, "TOPRIGHT", -10, -yOff)
        SR.clientRollFrame.eligibleText:SetText(table.concat(nameLines, "\n"))
        SR.clientRollFrame.eligibleText:Show()
        local lineCount = #nameLines
        local lineH = 12
        yOff = yOff + (lineCount * lineH) + 6
    else
        if SR.clientRollFrame.eligibleHeader then SR.clientRollFrame.eligibleHeader:Hide() end
        if SR.clientRollFrame.eligibleText then SR.clientRollFrame.eligibleText:Hide() end
    end

    -- Rolls header
    if not SR.clientRollFrame.rollsHeader then
        SR.clientRollFrame.rollsHeader = SR.clientRollFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        SR.clientRollFrame.rollsHeader:SetJustifyH("LEFT")
    end
    SR.clientRollFrame.rollsHeader:ClearAllPoints()
    SR.clientRollFrame.rollsHeader:SetPoint("TOPLEFT", SR.clientRollFrame.content, "TOPLEFT", 6, -yOff)
    SR.clientRollFrame.rollsHeader:SetText(SR.C_ORANGE .. "Rolls:" .. SR.C_RESET)
    SR.clientRollFrame.rollsHeader:Show()
    yOff = yOff + 14

    -- Sort rolls
    local validRolls, invalidRolls = {}, {}
    for _, r in ipairs(SR.clientRoll.rolls) do
        if r.valid then table.insert(validRolls, r) else table.insert(invalidRolls, r) end
    end
    table.sort(validRolls, function(a,b) return a.roll > b.roll end)

    -- Hide old rows
    for _, row in ipairs(SR.clientRollRows) do row:Hide() end

    local maxShow = 20
    local displayIdx = 0

    -- Valid rolls
    for i, r in ipairs(validRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetClientRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SR.clientRollFrame.content, "TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", SR.clientRollFrame.content, "RIGHT", 0, 0)
        local posColor = i == 1 and SR.C_GREEN or SR.C_WHITE
        local nameColor = (myName and r.name:lower() == myName:lower()) and SR.C_YELLOW or SR.C_CYAN
        row.text:SetText(posColor .. i .. ". " .. nameColor .. r.name .. SR.C_WHITE .. " - " .. r.roll .. SR.C_RESET)
        row:Show()
        yOff = yOff + 15
    end

    -- Invalid rolls
    for _, r in ipairs(invalidRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetClientRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SR.clientRollFrame.content, "TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", SR.clientRollFrame.content, "RIGHT", 0, 0)
        row.text:SetText(SR.C_GRAY .. "  x " .. r.name .. " - " .. r.roll .. " (not eligible)" .. SR.C_RESET)
        row:Show()
        yOff = yOff + 15
    end

    -- Waiting message
    if #SR.clientRoll.rolls == 0 then
        displayIdx = 1
        local row = GetClientRow(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SR.clientRollFrame.content, "TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", SR.clientRollFrame.content, "RIGHT", 0, 0)
        row.text:SetText(SR.C_GRAY .. "Waiting for /roll ..." .. SR.C_RESET)
        row:Show()
        yOff = yOff + 15
    end

    SR.clientRollFrame.content:SetHeight(math.max(yOff + 4, 1))

    -- /roll button state
    if SR.clientRoll.finished then
        SR.clientRollFrame.rollBtn:Disable()
    else
        SR.clientRollFrame.rollBtn:Enable()
    end
end

----------------------------------------------------------------------
-- Create
----------------------------------------------------------------------
function SR.CreateClientRollWindow()
    if SR.clientRollFrame then return end

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
        if SR.clientRoll and SR.clientRoll.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. SR.clientRoll.itemId)
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
    SR.clientRollFrame = f
end

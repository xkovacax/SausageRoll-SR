----------------------------------------------------------------------
-- SausageRollGUI.lua - ML roll window
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- Roll row helper
----------------------------------------------------------------------
local function GetRollRow(idx)
    if not SR.rollRows[idx] then
        local row = CreateFrame("Frame", nil, SR.rollFrame.content)
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
                SR.RefreshRollWindow()
            end
        end)

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", 18, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.text = fs

        table.insert(SR.rollRows, row)
    end
    return SR.rollRows[idx]
end

----------------------------------------------------------------------
-- Categorize rolls
----------------------------------------------------------------------
function SR.CategorizeRolls(rolls)
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
    return validRolls, excludedRolls, invalidRolls
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
function SR.RefreshRollWindow()
    if not SR.rollFrame then return end

    local rollData = SR.activeRoll or SR.finishedRoll
    if not rollData then
        SR.rollFrame:Hide()
        return
    end

    SR.rollFrame:Show()
    if SR.mainFrame and SR.mainFrame:IsShown() then
        SR.rollFrame:ClearAllPoints()
        SR.rollFrame:SetPoint("TOPRIGHT", SR.mainFrame, "TOPLEFT", -4, 0)
    end

    -- Title
    if SR.activeRoll then
        local cdText = ""
        if SR.countdownTimer then
            if SR.countdownTimer.remaining > 0 then
                cdText = "  "..SR.C_RED..">> "..SR.countdownTimer.remaining.." <<"..SR.C_RESET
            elseif SR.countdownTimer.remaining == 0 then
                cdText = "  "..SR.C_RED..">> STOP! <<"..SR.C_RESET
            else
                cdText = "  "..SR.C_YELLOW.."..."..SR.C_RESET
            end
        else
            cdText = "  "..SR.C_GREEN.."("..#SR.activeRoll.rolls.." rolls)"..SR.C_RESET
        end
        SR.rollFrame.title:SetText(SR.C_ORANGE.."Rolling: "..SR.C_RESET..(SR.activeRoll.link or "?"))
        SR.rollFrame.subtitle:SetText(SR.C_ORANGE.."["..SR.activeRoll.mode:upper().."]"..SR.C_RESET..cdText)
    else
        SR.rollFrame.title:SetText(SR.C_GREEN.."Finished: "..SR.C_RESET..(SR.finishedRoll.link or "?"))
        if SR.finishedRoll.winner then
            SR.rollFrame.subtitle:SetText(SR.C_GREEN.."Winner: "..SR.C_CYAN..SR.finishedRoll.winner..SR.C_RESET.."  "..SR.C_GRAY.."(trade to close)"..SR.C_RESET)
        else
            SR.rollFrame.subtitle:SetText(SR.C_RED.."No winner"..SR.C_RESET.."  "..SR.C_GRAY.."(trade/bank to close)"..SR.C_RESET)
        end
    end

    local rolls = rollData.rolls or {}
    local validRolls, excludedRolls, invalidRolls = SR.CategorizeRolls(rolls)

    -- Hide old rows
    for _, row in ipairs(SR.rollRows) do row.text:SetText(""); row:Hide() end

    local maxShow = 20
    local yOff = 0
    local isActive = (SR.activeRoll ~= nil)
    local totalToShow = #validRolls + #excludedRolls + #invalidRolls
    local displayIdx = 0

    -- Display valid rolls
    for i, r in ipairs(validRolls) do
        displayIdx = displayIdx + 1
        if displayIdx > maxShow then break end
        local row = GetRollRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, -yOff)
        row:SetPoint("RIGHT", SR.rollFrame.content, "RIGHT", -6, 0)

        local srTag = ""
        if rollData.mode == "sr" then
            local entries = SR.reserves[rollData.itemId] or {}
            for _, e in ipairs(entries) do
                if r.name:lower() == e.name:lower() then
                    srTag = SR.C_GREEN.." [SR]"..SR.C_RESET
                    break
                end
            end
        end
        local posColor = i == 1 and SR.C_GREEN or SR.C_WHITE
        row.text:SetText(posColor..i..". "..SR.C_CYAN..r.name..SR.C_WHITE.." - "..r.roll..srTag..SR.C_RESET)

        if isActive then
            row.excludeBtn.rollData = r
            row.excludeBtnText:SetText(SR.C_RED.."X"..SR.C_RESET)
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
        local row = GetRollRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, -yOff)
        row:SetPoint("RIGHT", SR.rollFrame.content, "RIGHT", -6, 0)

        row.text:SetText(SR.C_GRAY..r.name.." - "..r.roll.." [EXCLUDED]"..SR.C_RESET)

        if isActive then
            row.excludeBtn.rollData = r
            row.excludeBtnText:SetText(SR.C_GREEN.."+"..SR.C_RESET)
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
        local row = GetRollRow(displayIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, -yOff)
        row:SetPoint("RIGHT", SR.rollFrame.content, "RIGHT", -6, 0)

        row.text:SetText(SR.C_GRAY.."  x "..r.name.." - "..r.roll.." (not eligible)"..SR.C_RESET)
        row.excludeBtn:Hide()
        row:Show()
        yOff = yOff + 16
    end

    -- "Waiting" message if no rolls
    if totalToShow == 0 then
        displayIdx = 1
        local row = GetRollRow(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, 0)
        row:SetPoint("RIGHT", SR.rollFrame.content, "RIGHT", -6, 0)
        row.text:SetText(SR.C_GRAY.."Waiting for /roll ..."..SR.C_RESET)
        row.excludeBtn:Hide()
        row:Show()
        yOff = 16
    end

    SR.rollFrame.content:SetHeight(math.max(yOff + 4, 1))
end

----------------------------------------------------------------------
-- Create
----------------------------------------------------------------------
function SR.CreateRollWindow()
    if SR.rollFrame then return end

    local f = CreateFrame("Frame","SRIRollFrame",UIParent)
    f:SetSize(280, 280)
    if SR.mainFrame then
        f:SetPoint("TOPRIGHT", SR.mainFrame, "TOPLEFT", -4, 0)
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

    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    t:SetPoint("TOPLEFT", 10, -10)
    t:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    t:SetJustifyH("LEFT")
    f.title = t

    local st = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    st:SetPoint("TOPLEFT", 10, -28)
    st:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    st:SetJustifyH("LEFT")
    f.subtitle = st

    local sc = CreateFrame("ScrollFrame", "SRIRollScroll", f, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 8, -46)
    sc:SetPoint("BOTTOMRIGHT", -28, 34)

    local ct = CreateFrame("Frame", nil, sc)
    ct:SetWidth(sc:GetWidth())
    ct:SetHeight(1)
    sc:SetScrollChild(ct)
    f.content = ct

    local rollBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rollBtn:SetSize(120, 22)
    rollBtn:SetPoint("BOTTOM", 0, 8)
    rollBtn:SetText("/roll")
    rollBtn:SetScript("OnClick", function() RandomRoll(1, 100) end)

    f:Hide()
    SR.rollFrame = f
end

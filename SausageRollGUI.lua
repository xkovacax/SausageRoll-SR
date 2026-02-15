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
        row:SetHeight(26)

        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(14, 14)
        btn:SetPoint("LEFT", 0, 4)
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
        fs:SetPoint("TOPLEFT", row, "TOPLEFT", 18, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.text = fs

        local classFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        classFs:SetJustifyH("LEFT")
        classFs:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 8, -1)
        row.classText = classFs

        table.insert(SR.rollRows, row)
    end
    return SR.rollRows[idx]
end

----------------------------------------------------------------------
-- Categorize rolls
----------------------------------------------------------------------
function SR.CategorizeRolls(rolls, mode)
    local msRolls = {}
    local osRolls = {}
    local excludedRolls = {}
    local invalidRolls = {}
    for _, r in ipairs(rolls) do
        if r.valid == false then
            table.insert(invalidRolls, r)
        elseif r.excluded then
            table.insert(excludedRolls, r)
        elseif mode ~= "sr" and r.spec == "os" then
            table.insert(osRolls, r)
        else
            table.insert(msRolls, r)
        end
    end
    table.sort(msRolls, function(a,b) return a.roll > b.roll end)
    table.sort(osRolls, function(a,b) return a.roll > b.roll end)
    table.sort(excludedRolls, function(a,b) return a.roll > b.roll end)
    return msRolls, osRolls, excludedRolls, invalidRolls
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
-- Helper: render a list of rolls into the scroll content
local function RenderRollSection(rolls, startIdx, yOff, maxShow, isActive, rollData, firstColor)
    local displayIdx = startIdx
    for i, r in ipairs(rolls) do
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
        local posColor = (i == 1 and firstColor) or SR.C_WHITE
        row.text:SetText(posColor..i..". "..SR.C_CYAN..r.name..SR.C_WHITE.." - "..r.roll..srTag..SR.C_RESET)

        local classFile = SR.GetPlayerClass(r.name)
        if classFile then
            local cc = RAID_CLASS_COLORS[classFile]
            local hex = cc and string.format("|cff%02x%02x%02x", cc.r*255, cc.g*255, cc.b*255) or SR.C_GRAY
            row.classText:SetText(hex..classFile..SR.C_RESET)
        else
            row.classText:SetText("")
        end

        if isActive then
            row.excludeBtn.rollData = r
            row.excludeBtnText:SetText(SR.C_RED.."X"..SR.C_RESET)
            row.excludeBtn:Show()
        else
            row.excludeBtn:Hide()
        end
        row:Show()
        yOff = yOff + 26
    end
    return displayIdx, yOff
end

-- Helper: render a section header font string
local function EnsureHeader(parent, key)
    if not parent[key] then
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        parent[key] = fs
    end
    return parent[key]
end

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
            local specLabel = ""
            if SR.finishedRoll.winnerSpec then specLabel = " "..SR.finishedRoll.winnerSpec:upper()..":" end
            SR.rollFrame.subtitle:SetText(SR.C_GREEN.."Winner"..specLabel.." "..SR.C_CYAN..SR.finishedRoll.winner..SR.C_RESET.."  "..SR.C_GRAY.."(trade to close)"..SR.C_RESET)
        else
            SR.rollFrame.subtitle:SetText(SR.C_RED.."No winner"..SR.C_RESET.."  "..SR.C_GRAY.."(trade/bank to close)"..SR.C_RESET)
        end
    end

    local rolls = rollData.rolls or {}
    local msRolls, osRolls, excludedRolls, invalidRolls = SR.CategorizeRolls(rolls, rollData.mode)

    -- Hide old rows
    for _, row in ipairs(SR.rollRows) do row.text:SetText(""); row.classText:SetText(""); row:Hide() end

    local maxShow = 20
    local yOff = 0
    local isActive = (SR.activeRoll ~= nil)
    local isSR = (rollData.mode == "sr")
    local totalToShow = #msRolls + #osRolls + #excludedRolls + #invalidRolls
    local displayIdx = 0

    -- Hide section headers by default
    local msHeader = EnsureHeader(SR.rollFrame.content, "msHeader")
    local osHeader = EnsureHeader(SR.rollFrame.content, "osHeader")
    msHeader:Hide()
    osHeader:Hide()

    if isSR then
        -- SR mode: single section, no headers
        displayIdx, yOff = RenderRollSection(msRolls, displayIdx, yOff, maxShow, isActive, rollData, SR.C_GREEN)
    else
        -- Non-SR: dual sections with headers
        msHeader:ClearAllPoints()
        msHeader:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, -yOff)
        msHeader:SetText(SR.C_ORANGE.."MS Rolls:"..SR.C_RESET)
        msHeader:Show()
        yOff = yOff + 14

        if #msRolls > 0 then
            displayIdx, yOff = RenderRollSection(msRolls, displayIdx, yOff, maxShow, isActive, rollData, SR.C_GREEN)
        else
            displayIdx = displayIdx + 1
            local row = GetRollRow(displayIdx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, -yOff)
            row:SetPoint("RIGHT", SR.rollFrame.content, "RIGHT", -6, 0)
            row.text:SetText(SR.C_GRAY.."(none)"..SR.C_RESET)
            row.classText:SetText("")
            row.excludeBtn:Hide()
            row:Show()
            yOff = yOff + 26
        end

        yOff = yOff + 4

        osHeader:ClearAllPoints()
        osHeader:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, -yOff)
        osHeader:SetText(SR.C_ORANGE.."OS Rolls:"..SR.C_RESET)
        osHeader:Show()
        yOff = yOff + 14

        if #osRolls > 0 then
            -- OS #1: green if no MS rolls (actual winner), yellow if MS rolls exist
            local osFirstColor = (#msRolls == 0) and SR.C_GREEN or SR.C_YELLOW
            displayIdx, yOff = RenderRollSection(osRolls, displayIdx, yOff, maxShow, isActive, rollData, osFirstColor)
        else
            displayIdx = displayIdx + 1
            local row = GetRollRow(displayIdx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, -yOff)
            row:SetPoint("RIGHT", SR.rollFrame.content, "RIGHT", -6, 0)
            row.text:SetText(SR.C_GRAY.."(none)"..SR.C_RESET)
            row.classText:SetText("")
            row.excludeBtn:Hide()
            row:Show()
            yOff = yOff + 26
        end
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

        local classFile = SR.GetPlayerClass(r.name)
        if classFile then
            local cc = RAID_CLASS_COLORS[classFile]
            local hex = cc and string.format("|cff%02x%02x%02x", cc.r*255, cc.g*255, cc.b*255) or SR.C_GRAY
            row.classText:SetText(hex..classFile..SR.C_RESET)
        else
            row.classText:SetText("")
        end

        if isActive then
            row.excludeBtn.rollData = r
            row.excludeBtnText:SetText(SR.C_GREEN.."+"..SR.C_RESET)
            row.excludeBtn:Show()
        else
            row.excludeBtn:Hide()
        end
        row:Show()
        yOff = yOff + 26
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

        local classFile = SR.GetPlayerClass(r.name)
        if classFile then
            local cc = RAID_CLASS_COLORS[classFile]
            local hex = cc and string.format("|cff%02x%02x%02x", cc.r*255, cc.g*255, cc.b*255) or SR.C_GRAY
            row.classText:SetText(hex..classFile..SR.C_RESET)
        else
            row.classText:SetText("")
        end

        row.excludeBtn:Hide()
        row:Show()
        yOff = yOff + 26
    end

    -- "Waiting" message if no rolls
    if totalToShow == 0 then
        if isSR then
            displayIdx = 1
            local row = GetRollRow(1)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", SR.rollFrame.content, "TOPLEFT", 6, 0)
            row:SetPoint("RIGHT", SR.rollFrame.content, "RIGHT", -6, 0)
            row.text:SetText(SR.C_GRAY.."Waiting for /roll ..."..SR.C_RESET)
            row.classText:SetText("")
            row.excludeBtn:Hide()
            row:Show()
            yOff = 26
        end
        -- Non-SR already shows "(none)" placeholders via dual sections above
    end

    SR.rollFrame.content:SetHeight(math.max(yOff + 4, 1))

    -- Button state
    if SR.rollFrame.msRollBtn then
        local finished = (SR.activeRoll == nil)
        local playerRolled = false
        if SR.activeRoll then
            local myName = UnitName("player") or ""
            for _, r in ipairs(SR.activeRoll.rolls) do
                if r.name:lower() == myName:lower() then playerRolled = true; break end
            end
        end
        if finished or playerRolled then
            SR.rollFrame.msRollBtn:Disable()
            if SR.rollFrame.osRollBtn then SR.rollFrame.osRollBtn:Disable() end
        else
            SR.rollFrame.msRollBtn:Enable()
            if SR.rollFrame.osRollBtn then SR.rollFrame.osRollBtn:Enable() end
        end

        -- SR mode: hide OS button, center MS button
        if rollData.mode == "sr" then
            SR.rollFrame.msRollBtn:SetText("/roll")
            SR.rollFrame.msRollBtn:SetSize(120, 22)
            SR.rollFrame.msRollBtn:ClearAllPoints()
            SR.rollFrame.msRollBtn:SetPoint("BOTTOM", 0, 8)
            if SR.rollFrame.osRollBtn then SR.rollFrame.osRollBtn:Hide() end
        else
            SR.rollFrame.msRollBtn:SetText("MS /roll")
            SR.rollFrame.msRollBtn:SetSize(80, 22)
            SR.rollFrame.msRollBtn:ClearAllPoints()
            SR.rollFrame.msRollBtn:SetPoint("BOTTOMRIGHT", SR.rollFrame, "BOTTOM", -4, 8)
            if SR.rollFrame.osRollBtn then
                SR.rollFrame.osRollBtn:Show()
                SR.rollFrame.osRollBtn:ClearAllPoints()
                SR.rollFrame.osRollBtn:SetPoint("BOTTOMLEFT", SR.rollFrame, "BOTTOM", 4, 8)
            end
        end
    end
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

    local msBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    msBtn:SetSize(80, 22)
    msBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 8)
    msBtn:SetText("MS /roll")
    msBtn:SetScript("OnClick", function() RandomRoll(1, 100) end)
    f.msRollBtn = msBtn

    local osBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    osBtn:SetSize(80, 22)
    osBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 8)
    osBtn:SetText("OS /roll 99")
    osBtn:SetScript("OnClick", function() RandomRoll(1, 99) end)
    f.osRollBtn = osBtn

    f:Hide()
    SR.rollFrame = f
end

----------------------------------------------------------------------
-- SausageImportGUI.lua - SR and HR import windows
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- SR Import Window
----------------------------------------------------------------------
function SR.CreateImportFrame()
    if SRIHRImportFrame and SRIHRImportFrame:IsShown() then SRIHRImportFrame:Hide() end
    if SRIImportFrame then
        SRIImportFrame.UpdateStatus()
        SRIImportFrame:Show()
        return
    end

    local f = CreateFrame("Frame","SRIImportFrame",UIParent)
    f:SetSize(480,380)
    f:SetPoint("CENTER")
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
    f:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames,"SRIImportFrame")

    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    t:SetPoint("TOP",0,-12)
    t:SetText(SR.C_GREEN.."Sausage Roll"..SR.C_WHITE.." - Import SR CSV"..SR.C_RESET)

    local st = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    st:SetPoint("TOP",0,-32)

    local function UpdateStatus()
        if SR.importCount > 0 then
            local pc = 0
            for _ in pairs(SR.reservesByName) do pc = pc + 1 end
            st:SetText(SR.C_GREEN..SR.importCount..SR.C_WHITE.." reserves ("..
                SR.C_GREEN..pc..SR.C_WHITE.." players). Paste new CSV to reimport."..SR.C_RESET)
        else
            st:SetText(SR.C_GRAY.."Paste SR CSV (Ctrl+V), click Import"..SR.C_RESET)
        end
    end
    f.UpdateStatus = UpdateStatus
    UpdateStatus()

    local bg = CreateFrame("Frame",nil,f)
    bg:SetPoint("TOPLEFT",12,-48)
    bg:SetPoint("BOTTOMRIGHT",-30,46)
    bg:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=14,
        insets={left=3,right=3,top=3,bottom=3},
    })
    bg:SetBackdropColor(0,0,0,0.6)
    bg:SetBackdropBorderColor(0.4,0.4,0.4,0.8)

    local sc = CreateFrame("ScrollFrame","SRIImportScroll",f,"UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT",16,-52)
    sc:SetPoint("BOTTOMRIGHT",-34,50)

    local eb = CreateFrame("EditBox","SRIImportEditBox",sc)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(sc:GetWidth())
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sc:SetScrollChild(eb)
    f.editBox = eb
    if SausageRollImportDB.lastSRText then eb:SetText(SausageRollImportDB.lastSRText) end

    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)

    local b1 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b1:SetSize(100,24); b1:SetPoint("BOTTOMLEFT",14,14)
    b1:SetText("Import")
    b1:SetScript("OnClick", function()
        local text = eb:GetText()
        if not text or text == "" then SR.DPrint(SR.C_RED.."Paste CSV first!"..SR.C_RESET); return end
        local count = SR.ParseCSV(text)
        local pc = 0
        for _ in pairs(SR.reservesByName) do pc = pc + 1 end
        SR.DPrint(SR.C_GREEN..count..SR.C_WHITE.." reserves imported ("..SR.C_GREEN..pc..SR.C_WHITE.." players)"..SR.C_RESET)
        eb:ClearFocus()
        UpdateStatus()
        f:Hide()
        SR.CreateMainFrame()
    end)

    local b2 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b2:SetSize(100,24); b2:SetPoint("BOTTOM",0,14)
    b2:SetText("Clear All SR")
    b2:SetScript("OnClick", function()
        SR.ClearAllData(); eb:SetText(""); UpdateStatus()
        SR.DPrint(SR.C_YELLOW.."All reserves cleared."..SR.C_RESET)
        if SR.mainFrame and SR.mainFrame:IsShown() then SR.RefreshMainFrame() end
    end)

    local b3 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b3:SetSize(100,24); b3:SetPoint("BOTTOMRIGHT",-14,14)
    b3:SetText("Close")
    b3:SetScript("OnClick", function() f:Hide() end)
end

----------------------------------------------------------------------
-- HR Import Window
----------------------------------------------------------------------
function SR.CreateHRImportFrame()
    if SRIImportFrame and SRIImportFrame:IsShown() then SRIImportFrame:Hide() end
    if SRIHRImportFrame then
        SRIHRImportFrame.UpdateStatus()
        SRIHRImportFrame:Show()
        return
    end

    local f = CreateFrame("Frame","SRIHRImportFrame",UIParent)
    f:SetSize(480,380)
    f:SetPoint("CENTER")
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
    f:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames,"SRIHRImportFrame")

    local t = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    t:SetPoint("TOP",0,-12)
    t:SetText(SR.C_GREEN.."Sausage Roll"..SR.C_WHITE.." - Import HR CSV"..SR.C_RESET)

    local st = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    st:SetPoint("TOP",0,-32)

    local function UpdateStatus()
        if #SR.hardReserves > 0 or #SR.hardReserveCustom > 0 then
            local parts = {}
            if #SR.hardReserves > 0 then table.insert(parts, SR.C_GREEN..#SR.hardReserves..SR.C_WHITE.." HR items") end
            if #SR.hardReserveCustom > 0 then table.insert(parts, SR.C_GREEN..#SR.hardReserveCustom..SR.C_WHITE.." custom lines") end
            st:SetText(table.concat(parts, " + ")..". Paste new CSV to reimport."..SR.C_RESET)
        else
            st:SetText(SR.C_GRAY.."Paste HR CSV, click Import"..SR.C_RESET)
        end
    end
    f.UpdateStatus = UpdateStatus
    UpdateStatus()

    local bg = CreateFrame("Frame",nil,f)
    bg:SetPoint("TOPLEFT",12,-48)
    bg:SetPoint("BOTTOMRIGHT",-30,46)
    bg:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=14,
        insets={left=3,right=3,top=3,bottom=3},
    })
    bg:SetBackdropColor(0,0,0,0.6)
    bg:SetBackdropBorderColor(0.4,0.4,0.4,0.8)

    local sc = CreateFrame("ScrollFrame","SRIHRImportScroll",f,"UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT",16,-52)
    sc:SetPoint("BOTTOMRIGHT",-34,50)

    local eb = CreateFrame("EditBox","SRIHRImportEditBox",sc)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(sc:GetWidth())
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sc:SetScrollChild(eb)
    f.editBox = eb
    if SausageRollImportDB.lastHRText then eb:SetText(SausageRollImportDB.lastHRText) end

    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)

    local b1 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b1:SetSize(100,24); b1:SetPoint("BOTTOMLEFT",14,14)
    b1:SetText("Import")
    b1:SetScript("OnClick", function()
        local text = eb:GetText()
        if not text or text == "" then SR.DPrint(SR.C_RED.."Paste HR CSV first!"..SR.C_RESET); return end
        SR.ParseHRCSV(text)
        local parts = {}
        if #SR.hardReserves > 0 then table.insert(parts, SR.C_GREEN..#SR.hardReserves..SR.C_WHITE.." HR items") end
        if #SR.hardReserveCustom > 0 then table.insert(parts, SR.C_GREEN..#SR.hardReserveCustom..SR.C_WHITE.." custom lines") end
        if #parts > 0 then
            SR.DPrint(table.concat(parts, " + ").." imported"..SR.C_RESET)
        else
            SR.DPrint(SR.C_YELLOW.."No HR data found in text."..SR.C_RESET)
        end
        eb:ClearFocus()
        UpdateStatus()
        f:Hide()
    end)

    local b2 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b2:SetSize(100,24); b2:SetPoint("BOTTOM",0,14)
    b2:SetText("Clear All HR")
    b2:SetScript("OnClick", function()
        wipe(SR.hardReserves)
        wipe(SR.hardReserveCustom)
        SausageRollImportDB.hardReserves = SR.hardReserves
        SausageRollImportDB.hardReserveCustom = SR.hardReserveCustom
        SausageRollImportDB.lastHRText = nil
        eb:SetText(""); UpdateStatus()
        SR.DPrint(SR.C_YELLOW.."All HR items cleared."..SR.C_RESET)
    end)

    local b3 = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b3:SetSize(100,24); b3:SetPoint("BOTTOMRIGHT",-14,14)
    b3:SetText("Close")
    b3:SetScript("OnClick", function() f:Hide() end)
end

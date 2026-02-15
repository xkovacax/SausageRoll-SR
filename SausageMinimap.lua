----------------------------------------------------------------------
-- SausageMinimap.lua - Minimap button
----------------------------------------------------------------------
local SR = SausageRollNS

function SR.CreateMinimapButton()
    local btn = CreateFrame("Button","SRIMinimapButton",Minimap)
    btn:SetSize(31,31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local ov = btn:CreateTexture(nil,"OVERLAY")
    ov:SetSize(53,53)
    ov:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ov:SetPoint("TOPLEFT")
    local ic = btn:CreateTexture(nil,"BACKGROUND")
    ic:SetSize(20,20)
    ic:SetTexture("Interface\\AddOns\\SausageRoll-SR\\Textures\\sausageroll")
    ic:SetPoint("CENTER",0,1)

    local angle = SausageRollImportDB.minimapAngle or 220
    btn:SetPoint("CENTER",Minimap,"CENTER",80*math.cos(math.rad(angle)),80*math.sin(math.rad(angle)))

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self) self.dragging=true end)
    btn:SetScript("OnDragStop", function(self)
        self.dragging=false
        local cx,cy=Minimap:GetCenter()
        local mx,my=GetCursorPosition()
        local s=UIParent:GetEffectiveScale()
        local a=math.deg(math.atan2(my/s-cy,mx/s-cx))
        SausageRollImportDB.minimapAngle=a
        self:ClearAllPoints()
        self:SetPoint("CENTER",Minimap,"CENTER",80*math.cos(math.rad(a)),80*math.sin(math.rad(a)))
    end)
    btn:SetScript("OnUpdate", function(self)
        if self.dragging then
            local cx,cy=Minimap:GetCenter()
            local mx,my=GetCursorPosition()
            local s=UIParent:GetEffectiveScale()
            local a=math.deg(math.atan2(my/s-cy,mx/s-cx))
            self:ClearAllPoints()
            self:SetPoint("CENTER",Minimap,"CENTER",80*math.cos(math.rad(a)),80*math.sin(math.rad(a)))
        end
    end)

    btn:RegisterForClicks("LeftButtonUp","RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button=="LeftButton" then
            SR.displayMode = "bag"
            SR.CreateMainFrame()
        elseif button=="RightButton" then
            if SR.IsMasterLooter() then
                if SR.activeRoll or SR.finishedRoll then
                    SR.CreateRollWindow()
                    SR.RefreshRollWindow()
                end
            else
                if SR.clientRoll then
                    SR.CreateClientRollWindow()
                    SR.RefreshClientRollWindow()
                end
            end
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_LEFT")
        GameTooltip:AddLine(SR.C_GREEN.."Sausage Roll"..SR.C_WHITE.." - SR"..SR.C_RESET)
        GameTooltip:AddLine(" ")
        local pc=0
        for _ in pairs(SR.reservesByName) do pc=pc+1 end
        if SR.importCount>0 then
            GameTooltip:AddLine(SR.C_GREEN..SR.importCount..SR.C_WHITE.." reserves | "..SR.C_GREEN..pc..SR.C_WHITE.." players",1,1,1)
        else
            GameTooltip:AddLine(SR.C_GRAY.."No reserves",1,1,1)
        end
        if SR.activeRoll then GameTooltip:AddLine(SR.C_ORANGE.."Roll active!",1,1,1) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(SR.C_YELLOW.."LClick:"..SR.C_WHITE.." Main | "..SR.C_YELLOW.."RClick:"..SR.C_WHITE.." Active Roll",1,1,1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

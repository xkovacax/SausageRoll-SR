----------------------------------------------------------------------
-- SausageInit.lua - Event handlers, scheduler, slash commands
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- Centralized ScheduleRefresh - throttle/debounce for GUI updates
----------------------------------------------------------------------
local refreshTimer = CreateFrame("Frame")
local refreshPending = false
local refreshDelay = 0
local REFRESH_MIN_INTERVAL = 0.3
local lastRefreshTime = 0

function SR.ScheduleRefresh(delay)
    delay = delay or 0.05
    if refreshPending then
        refreshDelay = math.min(refreshDelay, delay)
        return
    end
    refreshPending = true
    refreshDelay = delay
    local waited = 0
    refreshTimer:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if waited >= refreshDelay then
            self:SetScript("OnUpdate", nil)
            refreshPending = false
            local now = GetTime()
            if (now - lastRefreshTime) >= REFRESH_MIN_INTERVAL then
                lastRefreshTime = now
                if SR.mainFrame then
                    SR.RefreshMainFrame()
                end
            else
                local remaining = REFRESH_MIN_INTERVAL - (now - lastRefreshTime)
                SR.ScheduleRefresh(remaining)
            end
        end
    end)
end

----------------------------------------------------------------------
-- Countdown ticker + periodic trade timer refresh
----------------------------------------------------------------------
local tickerFrame = CreateFrame("Frame")
local tradeTimerElapsed = 0
local tradeDisplayElapsed = 0
tickerFrame:SetScript("OnUpdate", function(self, elapsed)
    SR.UpdateCountdown(elapsed)

    -- Client auto-hide timer
    if SR.clientAutoHideTimer then
        SR.clientAutoHideTimer = SR.clientAutoHideTimer - elapsed
        if SR.clientAutoHideTimer <= 0 then
            SR.clientAutoHideTimer = nil
            SR.clientRoll = nil
            if SR.clientRollFrame then SR.clientRollFrame:Hide() end
        end
    end

    tradeDisplayElapsed = tradeDisplayElapsed + elapsed
    if tradeDisplayElapsed >= 1 then
        tradeDisplayElapsed = 0
        SR.UpdateTradeTimerDisplays()
    end

    tradeTimerElapsed = tradeTimerElapsed + elapsed
    if tradeTimerElapsed >= 5 then
        tradeTimerElapsed = 0
        if SR.mainFrame and SR.mainFrame:IsShown() then
            SR.RefreshMainFrame()
        end
    end
end)

----------------------------------------------------------------------
-- Loot opened handler
----------------------------------------------------------------------
local function LootHasRelevantItems()
    for i = 1, GetNumLootItems() do
        local _, _, _, rarity = GetLootSlotInfo(i)
        if rarity and rarity >= SR.minQualityFilter then
            return true
        end
    end
    return false
end

local lootCheckFrame = CreateFrame("Frame")

local function OnLootOpened()
    SR.isLootOpen = true
    SR.displayMode = "loot"
    local waited = 0
    lootCheckFrame:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if waited >= 0.35 then
            self:SetScript("OnUpdate", nil)
            if SR.isLootOpen and LootHasRelevantItems() then
                SR.CreateMainFrame(true)
            end
        end
    end)
    SR.ScheduleRefresh(0.3)
end

----------------------------------------------------------------------
-- Slash Commands
----------------------------------------------------------------------
local function HandleSlash(msg)
    if not msg then msg="" end
    local cmd = msg:match("^(%S+)") or ""
    local arg = msg:match("^%S+%s+(.+)") or ""
    cmd = cmd:lower()

    if cmd=="" then
        SR.displayMode = "bag"
        SR.CreateMainFrame()
    elseif cmd=="import" then SR.CreateImportFrame()
    elseif cmd=="show" or cmd=="list" then
        SR.displayMode = "bag"
        SR.CreateMainFrame()
    elseif cmd=="check" then
        if arg=="" then SR.DPrint(SR.C_RED.."/sr check <name>"..SR.C_RESET); return end
        local name = SR.CapitalizeName(arg)
        local items = SR.reservesByName[name]
        if items and #items>0 then
            SR.DPrint(SR.C_CYAN..name..SR.C_WHITE.." reserved:"..SR.C_RESET)
            for _,e in ipairs(items) do
                local _,ilink=GetItemInfo(e.itemId)
                SR.DPrint("  "..(ilink or ("["..e.itemName.."]"))..SR.C_GRAY.." ("..e.from..")"..SR.C_RESET)
            end
        else SR.DPrint(SR.C_YELLOW..name.." has no SR."..SR.C_RESET) end
    elseif cmd=="clear" then
        SR.ClearAllData()
        SR.DPrint(SR.C_YELLOW.."Cleared."..SR.C_RESET)
        if SR.mainFrame and SR.mainFrame:IsShown() then SR.RefreshMainFrame() end
    elseif cmd=="count" then
        local pc=0 for _ in pairs(SR.reservesByName) do pc=pc+1 end
        local ic=0 for _ in pairs(SR.reserves) do ic=ic+1 end
        SR.DPrint(SR.C_GREEN..SR.importCount..SR.C_WHITE.." SR | "..SR.C_GREEN..pc..SR.C_WHITE.." players | "..SR.C_GREEN..ic..SR.C_WHITE.." items"..SR.C_RESET)
    elseif cmd=="winner" then SR.StartCountdown()
    elseif cmd=="bank" then
        if arg=="" then
            if SR.bankCharName then
                SR.DPrint(SR.C_WHITE.."Bank char: "..SR.C_CYAN..SR.bankCharName..SR.C_RESET)
            else
                SR.DPrint(SR.C_RED.."/sr bank <n> - set bank character"..SR.C_RESET)
            end
            return
        end
        SR.bankCharName = SR.CapitalizeName(arg)
        SausageRollImportDB.bankCharName = SR.bankCharName
        SR.DPrint(SR.C_GREEN.."Bank set to: "..SR.C_CYAN..SR.bankCharName..SR.C_RESET)
        if SR.mainFrame and SR.mainFrame:IsShown() then SR.RefreshMainFrame() end
    elseif cmd=="diss" then
        if arg=="" then
            if SR.dissCharName then
                SR.DPrint(SR.C_WHITE.."Diss char: "..SR.C_CYAN..SR.dissCharName..SR.C_RESET)
            else
                SR.DPrint(SR.C_RED.."/sr diss <n> - set disenchant character"..SR.C_RESET)
            end
            return
        end
        SR.dissCharName = SR.CapitalizeName(arg)
        SausageRollImportDB.dissCharName = SR.dissCharName
        SR.DPrint(SR.C_GREEN.."Diss set to: "..SR.C_CYAN..SR.dissCharName..SR.C_RESET)
        if SR.mainFrame and SR.mainFrame:IsShown() then SR.RefreshMainFrame() end
    else SR.DPrint("/sr | /sr import | /sr clear | /sr check <n> | /sr bank <n> | /sr diss <n> | /sr winner") end
end

SLASH_SOFTRESIMPORT1 = "/sri"
SLASH_SOFTRESIMPORT2 = "/softres"
SLASH_SOFTRESIMPORT3 = "/sr"
SlashCmdList["SOFTRESIMPORT"] = HandleSlash

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local SRI = CreateFrame("Frame", "SoftResImportFrame")
SRI:RegisterEvent("ADDON_LOADED")
SRI:RegisterEvent("LOOT_OPENED")
SRI:RegisterEvent("LOOT_CLOSED")
SRI:RegisterEvent("LOOT_SLOT_CLEARED")
SRI:RegisterEvent("BAG_UPDATE")
SRI:RegisterEvent("CHAT_MSG_SYSTEM")
SRI:RegisterEvent("TRADE_SHOW")
SRI:RegisterEvent("TRADE_ACCEPT_UPDATE")
SRI:RegisterEvent("TRADE_CLOSED")
SRI:RegisterEvent("CHAT_MSG_ADDON")

local tradeCloseFrame
SRI:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == SR.ADDON_NAME then
            SR.LoadSavedData()
            SR.CreateMinimapButton()
            if SR.importCount > 0 then
                SR.DPrint(SR.C_GREEN.."Loaded! "..SR.C_WHITE..SR.importCount.." reserves. /sr to open."..SR.C_RESET)
            else
                SR.DPrint(SR.C_GREEN.."Loaded! "..SR.C_WHITE.."/sr to open."..SR.C_RESET)
            end
        end
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "LOOT_CLOSED" then
        SR.isLootOpen = false
        SR.displayMode = "bag"
        if SR.mainFrame then
            SR.mainFrame:Hide()
        end
        SR.ScheduleRefresh()
    elseif event == "LOOT_SLOT_CLEARED" then
        SR.ScheduleRefresh(0.2)
    elseif event == "BAG_UPDATE" then
        if SR.mainFrame and SR.mainFrame:IsShown() then
            SR.RefreshMainFrame()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if msg then SR.OnSystemMsg(msg) end
    elseif event == "CHAT_MSG_ADDON" then
        SR.OnSyncMessage(...)
    elseif event == "TRADE_SHOW" then
        if SR.pendingTrade then
            local pt = SR.pendingTrade
            SR.pendingTrade = nil
            local delayFrame = CreateFrame("Frame")
            local waited = 0
            delayFrame:SetScript("OnUpdate", function(df, el)
                waited = waited + el
                if waited >= 0.3 then
                    df:SetScript("OnUpdate", nil)
                    local link = GetContainerItemLink(pt.bag, pt.slot)
                    if link and SR.GetItemIdFromLink(link) == pt.itemId then
                        ClearCursor()
                        PickupContainerItem(pt.bag, pt.slot)
                        ClickTradeButton(1)
                        SR.DPrint(SR.C_GREEN.."Item placed in trade. Confirm manually."..SR.C_RESET)
                    else
                        SR.DPrint(SR.C_RED.."Item moved from bag slot!"..SR.C_RESET)
                    end
                end
            end)
        end
    elseif event == "TRADE_ACCEPT_UPDATE" then
        SR.ScheduleRefresh(0.5)
    elseif event == "TRADE_CLOSED" then
        if tradeCloseFrame then return end
        SR.DPrint(SR.C_YELLOW.."[SR] TRADE_CLOSED fired, scheduling refresh..."..SR.C_RESET)
        tradeCloseFrame = CreateFrame("Frame")
        local tradeCloseWait = 0
        tradeCloseFrame:SetScript("OnUpdate", function(df, el)
            tradeCloseWait = tradeCloseWait + el
            if tradeCloseWait >= 1.0 then
                df:SetScript("OnUpdate", nil)
                tradeCloseFrame = nil
                if SR.mainFrame then
                    SR.DPrint(SR.C_GREEN.."[SR] Refreshing GUI after trade."..SR.C_RESET)
                    SR.RefreshMainFrame()
                end
            end
        end)
    end
end)

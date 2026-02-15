----------------------------------------------------------------------
-- SausageCore.lua - Namespace, constants, utility functions
----------------------------------------------------------------------
SausageRollNS = {}
local SR = SausageRollNS

SR.ADDON_NAME = "SausageRoll-SR"
SR.VERSION = "1.3.0"
SR.SR_DEBUG = false

-- Color constants
SR.C_GREEN  = "|cff00ff00"
SR.C_YELLOW = "|cffffff00"
SR.C_ORANGE = "|cffff8800"
SR.C_RED    = "|cffff0000"
SR.C_WHITE  = "|cffffffff"
SR.C_CYAN   = "|cff00ffff"
SR.C_GRAY   = "|cff888888"
SR.C_RESET  = "|r"
SR.PREFIX   = SR.C_GREEN.."Sausage Roll"..SR.C_WHITE.." - SR"..SR.C_RESET

-- Sync protocol prefix
SR.SYNC_PREFIX = "SAUSR"
SR.COUNTDOWN_SECS = 3

-- Row heights
SR.ROW_HEIGHT = 42

-- Shared data tables (NEVER replace — only wipe+copy)
SR.reserves = {}
SR.reservesByName = {}
SR.hardReserves = {}
SR.hardReserveCustom = {}
SR.awardLog = {}
SR.slotToUid = {}
SR.uidToSlot = {}
SR.uidToItemId = {}
SR.uidAwards = {}
SR.pendingOrphans = {}
SR.srRows = {}
SR.msRows = {}
SR.rollRows = {}
SR.clientRollRows = {}
SR.uidRolled = {}
SR.unclaimedAwards = {}   -- {[itemId] = {{winner, link}, ...}}
SR.unclaimedRolled = {}   -- {[itemId] = count}
SR.lootHistory = {}
SR.showHistory = false
SR.historyRows = {}

-- Shared scalars (always read/write via SR.xxx)
SR.importCount = 0
SR.isLootOpen = false
SR.displayMode = "bag"
SR.minQualityFilter = 2
SR.showBoE = false
SR.activeRoll = nil
SR.finishedRoll = nil
SR.countdownTimer = nil
SR.pendingTrade = nil
SR.bankCharName = nil
SR.dissCharName = nil
SR.nextItemUid = 1
SR.clientRoll = nil
SR.clientAutoHideTimer = nil
SR.clientRollClicked = nil  -- "ms"/"os"/nil; reset on new RS sync

-- Frame references
SR.mainFrame = nil
SR.rollFrame = nil
SR.clientRollFrame = nil

-- Dropdown frames (created once)
SR.charDropdownFrame = CreateFrame("Frame", "SRI_CharDropdownMenu", UIParent, "UIDropDownMenuTemplate")

-- SavedVariables init
SausageRollImportDB = SausageRollImportDB or {}

----------------------------------------------------------------------
-- Quality colors
----------------------------------------------------------------------
SR.QC_TBL = {
    [0]={r=0.62,g=0.62,b=0.62}, [1]={r=1,g=1,b=1},
    [2]={r=0.12,g=1,b=0}, [3]={r=0,g=0.44,b=0.87},
    [4]={r=0.64,g=0.21,b=0.93}, [5]={r=1,g=0.5,b=0},
}

function SR.QC(q) return SR.QC_TBL[q] or SR.QC_TBL[1] end

function SR.QCHex(q)
    local c = SR.QC(q)
    return string.format("|cff%02x%02x%02x", c.r*255, c.g*255, c.b*255)
end

----------------------------------------------------------------------
-- Utility functions
----------------------------------------------------------------------
function SR.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(SR.PREFIX..": "..msg)
end

function SR.DPrint(msg)
    if SR.SR_DEBUG then DEFAULT_CHAT_FRAME:AddMessage(SR.PREFIX..": "..msg) end
end

function SR.StripQuotes(s)
    if not s then return "" end
    s = s:match("^%s*(.-)%s*$")
    s = s:gsub('^"',''):gsub('"$','')
    return s
end

function SR.CapitalizeName(name)
    if not name or name == "" then return "" end
    return name:sub(1,1):upper()..name:sub(2):lower()
end

function SR.GetItemIdFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

function SR.IsInRaid() return GetNumRaidMembers() > 0 end

function SR.SendRW(msg)
    if SR.IsInRaid() then
        if IsRaidLeader() or IsRaidOfficer() then
            SendChatMessage(msg, "RAID_WARNING")
        else
            SendChatMessage(msg, "RAID")
        end
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage(msg, "PARTY")
    else
        SR.DPrint(msg)
    end
end

function SR.SendRaid(msg)
    if SR.IsInRaid() then
        SendChatMessage(msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage(msg, "PARTY")
    else
        SR.DPrint(msg)
    end
end

function SR.IsMasterLooter()
    local method, pID, rID = GetLootMethod()
    if method ~= "master" then return false end
    if SR.IsInRaid() then
        if rID and rID > 0 then
            local name = GetRaidRosterInfo(rID)
            return name and name:lower() == UnitName("player"):lower()
        end
    else
        return pID == 0
    end
    return false
end

function SR.GetUnitIdByName(targetName)
    if not targetName then return nil end
    local low = targetName:lower()
    if SR.IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local uid = "raid"..i
            local n = UnitName(uid)
            if n and n:lower() == low then return uid end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local uid = "party"..i
            local n = UnitName(uid)
            if n and n:lower() == low then return uid end
        end
    end
    return nil
end

function SR.GetGroupMembers()
    local members = {}
    local seen = {}
    if SR.IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name and not seen[name:lower()] then
                seen[name:lower()] = true
                table.insert(members, name)
            end
        end
    else
        local myName = UnitName("player")
        if myName then
            seen[myName:lower()] = true
            table.insert(members, myName)
        end
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party"..i)
            if name and not seen[name:lower()] then
                seen[name:lower()] = true
                table.insert(members, name)
            end
        end
    end
    table.sort(members)
    return members
end

function SR.GetPlayerClass(name)
    if not name then return nil end
    local low = name:lower()
    if SR.IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local rName, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if rName and rName:lower() == low then
                return classFile
            end
        end
    else
        if UnitName("player") and UnitName("player"):lower() == low then
            local _, classFile = UnitClass("player")
            return classFile
        end
        for i = 1, GetNumPartyMembers() do
            local pName = UnitName("party"..i)
            if pName and pName:lower() == low then
                local _, classFile = UnitClass("party"..i)
                return classFile
            end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- SausageRoll.lua - Roll system (parse + validate + record + winner)
----------------------------------------------------------------------
local SR = SausageRollNS

----------------------------------------------------------------------
-- Roll management
----------------------------------------------------------------------
function SR.StartRoll(uid, itemId, link, mode)
    SR.countdownTimer = nil
    SR.activeRoll = {uid=uid, itemId=itemId, link=link, mode=mode, rolls={}}
    SR.uidRolled[uid] = true
    if mode == "sr" then
        local entries = SR.reserves[itemId]
        if entries then
            local names = {}
            for _, e in ipairs(entries) do
                local low = e.name:lower()
                local dup = false
                for _, n in ipairs(names) do if n:lower() == low then dup = true; break end end
                if not dup then table.insert(names, e.name) end
            end
            SR.SendRW(link.." SR: "..table.concat(names, ", ").." - /roll!")
        end
    else
        SR.SendRW(link.."  MS - /roll  ||||  OS - /roll 99")
    end
    SR.DPrint(SR.C_GREEN.."Roll started: "..link.." ("..mode:upper()..")"..SR.C_RESET)
    SR.CreateRollWindow()
    SR.RefreshRollWindow()
    -- Broadcast to clients
    local _, _, rollQuality = GetItemInfo(link)
    SR.SendSync("RS", itemId, rollQuality or 4, mode)
    if mode == "sr" then
        local srEntries = SR.reserves[itemId]
        if srEntries then
            local eligibleNames = {}
            for _, e in ipairs(srEntries) do
                table.insert(eligibleNames, e.name)
            end
            SR.SendSyncEligible(eligibleNames)
        end
    end
end

function SR.CloseRollWindow()
    if SR.activeRoll then SR.SendSync("RX") end
    if SR.rollFrame then SR.rollFrame:Hide() end
    SR.finishedRoll = nil
end

----------------------------------------------------------------------
-- Roll message parsing + validation
----------------------------------------------------------------------
function SR.ParseRollMessage(msg)
    local name, roll = msg:match("(.+) rolls (%d+) %(1%-100%)")
    if name and roll then return name, tonumber(roll), "ms" end
    name, roll = msg:match("(.+) rolls (%d+) %(1%-99%)")
    if name and roll then return name, tonumber(roll), "os" end
    return nil, nil, nil
end

function SR.CountPlayerRolls(name)
    if not SR.activeRoll then return 0 end
    local count = 0
    for _, r in ipairs(SR.activeRoll.rolls) do
        if r.name:lower() == name:lower() then
            count = count + 1
        end
    end
    return count
end

function SR.GetAllowedRolls(name, itemId, mode)
    if mode == "sr" then
        local allowed = 0
        local entries = SR.reserves[itemId] or {}
        for _, e in ipairs(entries) do
            if e.name:lower() == name:lower() then
                allowed = allowed + 1
            end
        end
        return allowed
    else
        return 1
    end
end

function SR.ValidateRoll(name, roll, spec)
    if not SR.activeRoll then return "ignored", "no active roll" end

    local mode = SR.activeRoll.mode
    local itemId = SR.activeRoll.itemId
    local existingCount = SR.CountPlayerRolls(name)
    local allowedRolls = SR.GetAllowedRolls(name, itemId, mode)

    if mode == "sr" then
        if spec == "os" then
            return "silent", "OS roll during SR"
        end
        if allowedRolls == 0 then
            return "invalid", "not an SR holder"
        end
        if existingCount >= allowedRolls then
            return "ignored", "exceeded SR roll limit ("..existingCount.."/"..allowedRolls..")"
        end
        return "valid", nil
    else
        if existingCount >= 1 then
            return "ignored", "already rolled"
        end
        return "valid", nil
    end
end

function SR.RecordRoll(name, roll, status, spec)
    if not SR.activeRoll then return end
    if status == "invalid" then
        table.insert(SR.activeRoll.rolls, {name=name, roll=roll, valid=false, spec=spec})
        SR.SendSync("RU", name, roll, "0", spec)
    elseif status == "valid" then
        table.insert(SR.activeRoll.rolls, {name=name, roll=roll, valid=true, spec=spec})
        SR.SendSync("RU", name, roll, "1", spec)
    end
    -- "ignored"/"silent" = don't record at all
end

function SR.OnSystemMsg(msg)
    if not SR.activeRoll then return end
    local name, roll, spec = SR.ParseRollMessage(msg)
    if not name or not roll then return end

    local status, reason = SR.ValidateRoll(name, roll, spec)

    if status == "silent" then return end

    if status == "ignored" then
        local mode = SR.activeRoll.mode
        if mode == "sr" then
            local allowedRolls = SR.GetAllowedRolls(name, SR.activeRoll.itemId, mode)
            local existingCount = SR.CountPlayerRolls(name)
            SendChatMessage(name.." - your roll was IGNORED! You have "..allowedRolls.."x SR = "..allowedRolls.." roll(s) allowed. You already rolled "..existingCount.."x.", "WHISPER", nil, name)
        else
            SendChatMessage(name.." - your extra roll was IGNORED! Only 1 roll allowed (MS or OS, not both).", "WHISPER", nil, name)
        end
        SR.DPrint(SR.C_RED..name.." "..reason.." - ignored"..SR.C_RESET)
        SR.RefreshRollWindow()
        return
    end

    SR.RecordRoll(name, roll, status, spec)
    SR.RefreshRollWindow()
end

----------------------------------------------------------------------
-- Winner determination
----------------------------------------------------------------------
function SR.GetValidRolls(rolls, mode, itemId, filterSpec)
    local filtered = {}
    if mode == "sr" then
        local entries = SR.reserves[itemId] or {}
        for _, roll in ipairs(rolls) do
            if roll.valid and not roll.excluded then
                for _, e in ipairs(entries) do
                    if roll.name:lower() == e.name:lower() then
                        table.insert(filtered, roll)
                        break
                    end
                end
            end
        end
    else
        for _, roll in ipairs(rolls) do
            if roll.valid ~= false and not roll.excluded then
                if not filterSpec or roll.spec == filterSpec then
                    table.insert(filtered, roll)
                end
            end
        end
    end
    return filtered
end

function SR.DetermineWinner(validRolls)
    if #validRolls == 0 then return nil end
    table.sort(validRolls, function(a,b) return a.roll > b.roll end)
    return validRolls[1]
end

function SR.RecordAward(uid, itemId, link, winnerName)
    table.insert(SR.awardLog, {itemId=itemId, winner=winnerName, link=link})
    SR.uidAwards[uid] = {winner=winnerName, link=link}
end

function SR.AnnounceWinnerFinal()
    if not SR.activeRoll then return end
    local r = SR.activeRoll

    if #r.rolls == 0 then
        SR.SendRW(r.link.." - No rolls!")
        SR.SendSync("RE", "", 0, "")
        SR.finishedRoll = {uid=r.uid, itemId=r.itemId, link=r.link, mode=r.mode, rolls=r.rolls, winner=nil, winnerSpec=nil}
        SR.activeRoll = nil
        SR.countdownTimer = nil
        SR.RefreshRollWindow()
        SR.RefreshMainFrame()
        return
    end

    local winner, winnerSpec
    local winnerName = nil

    if r.mode == "sr" then
        local validRolls = SR.GetValidRolls(r.rolls, r.mode, r.itemId)
        winner = SR.DetermineWinner(validRolls)
    else
        -- MS priority: try MS rolls first, then OS
        local msRolls = SR.GetValidRolls(r.rolls, r.mode, r.itemId, "ms")
        winner = SR.DetermineWinner(msRolls)
        if winner then
            winnerSpec = "ms"
        else
            local osRolls = SR.GetValidRolls(r.rolls, r.mode, r.itemId, "os")
            winner = SR.DetermineWinner(osRolls)
            if winner then winnerSpec = "os" end
        end
    end

    if not winner then
        SR.SendRW(r.link.." - No valid rolls!")
    else
        winnerName = winner.name
        if winnerSpec then
            SR.SendRW(r.link.." >> "..winner.name.." wins "..winnerSpec:upper().." ("..winner.roll..")")
        else
            SR.SendRW(r.link.." >> "..winner.name.." wins ("..winner.roll..")")
        end
        SR.RecordAward(r.uid, r.itemId, r.link, winnerName)
    end

    SR.DPrint(SR.C_GRAY.."All rolls:"..SR.C_RESET)
    table.sort(r.rolls, function(a,b) return a.roll > b.roll end)
    for _, roll in ipairs(r.rolls) do
        local exTag = roll.excluded and (" "..SR.C_RED.."[EXCLUDED]"..SR.C_RESET) or ""
        SR.DPrint("  "..SR.C_CYAN..roll.name..SR.C_WHITE..": "..roll.roll..exTag..SR.C_RESET)
    end

    -- Broadcast winner to clients
    if winnerName then
        local winRoll = 0
        for _, roll in ipairs(r.rolls) do
            if roll.name:lower() == winnerName:lower() and roll.valid ~= false and not roll.excluded then
                if roll.roll > winRoll then winRoll = roll.roll end
            end
        end
        SR.SendSync("RE", winnerName, winRoll, winnerSpec or "")
    else
        SR.SendSync("RE", "", 0, "")
    end

    SR.finishedRoll = {uid=r.uid, itemId=r.itemId, link=r.link, mode=r.mode, rolls=r.rolls, winner=winnerName, winnerSpec=winnerSpec}
    SR.activeRoll = nil
    SR.countdownTimer = nil
    SR.RefreshRollWindow()
    SR.RefreshMainFrame()
end

----------------------------------------------------------------------
-- Countdown
----------------------------------------------------------------------
function SR.StartCountdown()
    if not SR.activeRoll then
        SR.DPrint(SR.C_RED.."No active roll!"..SR.C_RESET)
        return
    end
    if SR.countdownTimer then
        SR.DPrint(SR.C_YELLOW.."Countdown already running!"..SR.C_RESET)
        return
    end
    SR.SendRW(SR.activeRoll.link.." ends in "..SR.COUNTDOWN_SECS.."...")
    SR.countdownTimer = {remaining=SR.COUNTDOWN_SECS, elapsed=0}
end

function SR.UpdateCountdown(elapsed)
    if not SR.countdownTimer then return end
    SR.countdownTimer.elapsed = SR.countdownTimer.elapsed + elapsed
    if SR.countdownTimer.elapsed >= 1.0 then
        SR.countdownTimer.elapsed = SR.countdownTimer.elapsed - 1.0
        SR.countdownTimer.remaining = SR.countdownTimer.remaining - 1
        if SR.countdownTimer.remaining > 0 then
            SR.SendRW(SR.countdownTimer.remaining.."...")
            SR.SendSync("RC", SR.countdownTimer.remaining)
        elseif SR.countdownTimer.remaining == 0 then
            SR.SendRW("STOP!")
            SR.SendSync("RC", 0)
            SR.countdownTimer.remaining = -1
        else
            SR.AnnounceWinnerFinal()
        end
        SR.RefreshRollWindow()
    end
end

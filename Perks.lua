local _, NS = ...

-- Synastria perk progress in DragonUI's objective tracker, the way the Synastria build of Questie lists
-- it: every active perk that still has a task to finish (unlock or next rank) gets a block with its task
-- and progress. Uses the server's perk globals (PerkMgrPerks, PerkMgrTaskAll, GetPerkTask*...).
-- Perks are listed above quests. Nothing fires when perk progress moves, so a cheap poll notices it.
local Part = {}
NS.Register(Part)

local MISC_CATEGORY = 19
local POLL = 2
local NO_COLOURS = { text = "", symbol = "", symbol2 = "" }

local OT, lastSignature

local function available()
    return type(PerkMgrPerks) == "table" and type(PerkMgrTaskAll) == "table"
        and GetPerkActive and GetPerkTaskAssign1 and GetPerkTaskAssign2 and GetPerkTaskProg
end

local function enabled()
    return NS.db and NS.db.trackPerks ~= false
end

-- How far the task has to go, the same rule the perk window's progress bar uses.
local function taskGoal(task)
    local flags = task.flags or 0
    if bit.band(flags, 0x80) ~= 0 then return task.req3 or 0 end
    if bit.band(flags, 2) ~= 0 then return task.req2 or 0 end
    return task.req0 or 1
end

local function taskText(task, guid)
    local text = task.text or ""
    -- "#123" points at another task's text.
    if text:sub(1, 1) == "#" then
        local ref = PerkMgrTaskAll[tonumber(text:sub(2)) or 0]
        text = ref and ref.text or text
    end
    if text:find("$", 1, true) then
        local amounts = { task.req0, task.req1, task.req2, task.req3, PerkMgrTaskStr and PerkMgrTaskStr[guid] or "" }
        local ok, generated = false, nil
        if CustomGenerateDescription then
            ok, generated = pcall(CustomGenerateDescription, text, amounts, NO_COLOURS)
        end
        if ok and generated then
            text = generated
        else
            text = text:gsub("%$(%d)[dDs]", function(i) return tostring(amounts[tonumber(i) + 1] or "") end)
                :gsub("%$r", tostring(UnitLevel("player") - 3)):gsub("%$[cCn]", "")
        end
    end
    return (text:gsub("%s*\n+%s*", " "))
end

-- One entry per active perk with an open task: { perk, task, guid, progress, goal, unlocking }.
local function activePerks()
    local list = {}
    for perkId, perk in pairs(PerkMgrPerks) do
        if type(perk) == "table" and perk.cat ~= MISC_CATEGORY and GetPerkActive(perkId) then
            local guid = GetPerkTaskAssign1(perkId)
            local task = guid and PerkMgrTaskAll[GetPerkTaskAssign2(guid) or -1]
            local rank = GetPerkAcquired and GetPerkAcquired(perkId) or 0
            local maxRank = type(perk.levels) == "table" and #perk.levels or 0
            local unlocking = task and perk.unlock == task.id
            if task and (unlocking or rank < maxRank) then
                list[#list + 1] = {
                    id = perkId, perk = perk, task = task, guid = guid, rank = rank, maxRank = maxRank, unlocking = unlocking,
                    progress = GetPerkTaskProg(guid) or 0, goal = taskGoal(task),
                }
            end
        end
    end
    table.sort(list, function(a, b) return (a.perk.name or "") < (b.perk.name or "") end)
    return list
end

-- The group Questie files a perk under: "Unlock" while unlocking, else its task's header (category).
local function groupName(entry)
    if entry.unlocking then return "Unlock" end
    local header = PerkMgrTaskHeader and PerkMgrTaskHeader[entry.task.header]
    return header and header.text or "Perks"
end

local function togglePerkWindow()
    if PerkMgrFrame and PerkMgrFrame:IsShown() and ClosePerkMgr then
        ClosePerkMgr()
    elseif OpenPerkMgr then
        -- Read-only: the same window the View Perks spell opens.
        OpenPerkMgr(false)
    end
end

local function showTooltip(block)
    local entry = block.ref
    if not entry then return end
    GameTooltip:SetOwner(block, "ANCHOR_LEFT")
    GameTooltip:SetText(entry.perk.name or "", 1, 1, 1)
    if entry.maxRank > 0 then
        GameTooltip:AddLine(entry.unlocking and "Not unlocked yet" or string.format("Rank %d / %d", entry.rank, entry.maxRank), 1, 0.82, 0)
    end
    GameTooltip:AddLine(taskText(entry.task, entry.guid), 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: open perks", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function menu()
    return {
        { text = "Open perks", func = togglePerkWindow },
        { text = "Stop tracking perks", func = function()
            NS.db.trackPerks = false
            if OT then OT.Refresh() end
        end },
    }
end

local function collect(blocks)
    if not (enabled() and available()) then return end
    local entries = activePerks()
    for index, entry in ipairs(entries) do
        local title = entry.perk.name or "?"
        if entry.unlocking then
            title = title .. " (unlock)"
        elseif entry.maxRank > 0 then
            title = string.format("%s (%d/%d)", title, entry.rank, entry.maxRank)
        end
        local line = string.format("%d/%d %s", entry.progress, entry.goal, taskText(entry.task, entry.guid))
        -- Above the quests, like Questie lists them.
        table.insert(blocks, index, {
            kind = "perk", title = title, ref = entry, group = groupName(entry),
            lines = { { text = line } },
            onClick = togglePerkWindow, menu = menu,
            onEnter = showTooltip, onLeave = function() GameTooltip:Hide() end,
        })
    end
end

-- A string of every tracked perk's progress; the tracker redraws only when it changes.
local function signature()
    if not (enabled() and available()) then return "" end
    local parts = {}
    for _, entry in ipairs(activePerks()) do
        parts[#parts + 1] = entry.id .. ":" .. entry.progress .. ":" .. entry.rank .. ":" .. (entry.task.id or 0)
    end
    return table.concat(parts, ",")
end

function NS.RefreshPerks()
    lastSignature = nil
    if OT and OT.Refresh then OT.Refresh() end
end

local elapsed = 0
local poller = CreateFrame("Frame")
poller:Hide()
poller:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < POLL then return end
    elapsed = 0
    local now = signature()
    if now ~= lastSignature then
        lastSignature = now
        if OT and OT.Refresh then OT.Refresh() end
    end
end)

function Part.Init()
    OT = NS.D and NS.D.ObjectiveTracker
    if not (OT and OT.AddCollector) then return end
    OT.AddCollector(collect)
    poller:Show()
end

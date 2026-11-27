local _, NS = ...

-- Retail-style sections in DragonUI's objective tracker: "Perks", "Quests" and "Achievements" each get a
-- header bar (DragonUI's tracker header art) that folds the section. Inside Perks, perks are grouped by
-- zone (the perk task's header, as Questie does) or by perk type, each group with its own foldable line.
-- Quests are not split further. Timers stay on top; other blocks (tracked recipes...) stay at the end.
--
-- Runs as the last tracker collector, so it sees every block the others added and reorders them; the
-- header art is put on after the tracker lays out (its frame's SetSize is the last thing a refresh does).
local Part = {}
NS.Register(Part)

local OT
local totalItems = 0
local lastKeys = {}

local PERK_TYPES = {
    [15] = "Offensive", [16] = "Defensive", [17] = "Support", [18] = "Utility",
}

local function enabled()
    return NS.db and NS.db.trackerGroups ~= false
end

local function folded()
    NS.db.trackerCollapsed = NS.db.trackerCollapsed or {}
    return NS.db.trackerCollapsed
end

local function refresh()
    if OT and OT.Refresh then OT.Refresh() end
end

local function setAll(value)
    local set = folded()
    for _, key in ipairs(lastKeys) do set[key] = value or nil end
    refresh()
end

local function toggle(key)
    local set = folded()
    set[key] = not set[key] or nil
    refresh()
end

local function menu()
    return {
        { text = "Collapse all", func = function() setAll(true) end },
        { text = "Expand all", func = function() setAll(false) end },
    }
end

-- kind "dsynSection" = big bar, "dsynGroup" = perk group line.
local function headerBlock(kind, key, label, count)
    lastKeys[#lastKeys + 1] = key
    -- Section headers always show their count; perk groups only while folded.
    local title = string.format("%s (%d)", label, count)
    if kind == "dsynGroup" and not folded()[key] then
        title = label
    end
    return {
        kind = kind, title = title, ref = key, lines = {},
        onClick = function() toggle(key) end, menu = menu,
    }
end

local function perkGroup(block)
    if NS.db.perkGrouping == "type" then
        local entry = block.ref
        local cat = entry and entry.perk and entry.perk.cat
        if PERK_TYPES[cat] then return PERK_TYPES[cat] end
        return "Class"
    end
    return block.group or "Perks"
end

local function regroup(blocks)
    totalItems = #blocks
    if not enabled() then return end

    local top, tail, quests, achievements = {}, {}, {}, {}
    local perkGroups, perkOrder, perkCount = {}, {}, 0
    for _, block in ipairs(blocks) do
        if block.kind == "perk" then
            local name = perkGroup(block)
            local group = perkGroups[name]
            if not group then
                group = { name = name, items = {} }
                perkGroups[name] = group
                perkOrder[#perkOrder + 1] = group
            end
            group.items[#group.items + 1] = block
            perkCount = perkCount + 1
        elseif block.kind == "quest" then
            quests[#quests + 1] = block
        elseif block.kind == "achievement" then
            achievements[#achievements + 1] = block
        elseif block.kind == "timer" then
            top[#top + 1] = block
        else
            tail[#tail + 1] = block
        end
    end
    table.sort(perkOrder, function(a, b) return a.name < b.name end)

    wipe(blocks)
    wipe(lastKeys)
    local set = folded()
    local function add(block) blocks[#blocks + 1] = block end
    for _, block in ipairs(top) do add(block) end

    if perkCount > 0 then
        add(headerBlock("dsynSection", "sec:perks", "Perks", perkCount))
        if not set["sec:perks"] then
            for _, group in ipairs(perkOrder) do
                local key = "perk:" .. (NS.db.perkGrouping or "zone") .. ":" .. group.name
                add(headerBlock("dsynGroup", key, group.name, #group.items))
                if not set[key] then
                    for _, block in ipairs(group.items) do add(block) end
                end
            end
        end
    end
    if #quests > 0 then
        add(headerBlock("dsynSection", "sec:quests", QUESTS_LABEL or "Quests", #quests))
        if not set["sec:quests"] then
            for _, block in ipairs(quests) do add(block) end
        end
    end
    if #achievements > 0 then
        add(headerBlock("dsynSection", "sec:achievements", TRACKER_HEADER_ACHIEVEMENTS or ACHIEVEMENTS or "Achievements", #achievements))
        if not set["sec:achievements"] then
            for _, block in ipairs(achievements) do add(block) end
        end
    end
    for _, block in ipairs(tail) do add(block) end
end

-- ---------------------------------------------------------------------------
-- Header art, applied to the pooled tracker blocks after each layout.
-- ---------------------------------------------------------------------------

local function atlas(tex, name, blend)
    local unpackAtlas = NS.D.functions and NS.D.functions.UnpackAtlas
    if not unpackAtlas then return false end
    -- Called on its own line: "x and f()" would keep only f's first return value.
    local file, _, _, l, r, t, b = unpackAtlas(name)
    if not (file and l) then return false end
    tex:SetTexture(file)
    tex:SetTexCoord(l, r, t, b)
    if blend then tex:SetBlendMode(blend) end
    return true
end

local function decoration(block)
    local deco = block._dsynDeco
    if deco then return deco end
    deco = {}
    -- Section bar: the tracker header art, title sitting on it.
    deco.bar = block:CreateTexture(nil, "BACKGROUND")
    atlas(deco.bar, "QuestTracker-Header")
    deco.bar:SetAlpha(0.9)
    -- Group line: a faint band with a thin rule under it.
    deco.band = block:CreateTexture(nil, "BACKGROUND")
    deco.band:SetTexture("Interface\\Buttons\\WHITE8X8")
    deco.band:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 0.08, 1, 1, 1, 0)
    deco.rule = block:CreateTexture(nil, "BORDER")
    deco.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    deco.rule:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.5, 1, 0.82, 0, 0)
    deco.rule:SetHeight(1)
    -- Hover glow; HIGHLIGHT shows only while the mouse is over the block.
    deco.glow = block:CreateTexture(nil, "HIGHLIGHT")
    deco.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    deco.glow:SetBlendMode("ADD")
    deco.glow:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.18, 1, 0.82, 0, 0)
    -- Fold state: DragonUI's red tracker button art for sections, a +/- for groups.
    deco.button = block:CreateTexture(nil, "ARTWORK")
    deco.button:SetSize(16, 17)
    deco.buttonGlow = block:CreateTexture(nil, "HIGHLIGHT")
    deco.buttonGlow:SetAllPoints(deco.button)
    atlas(deco.buttonGlow, "QuestTracker-Red-Highlight", "ADD")
    deco.sign = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    block._dsynDeco = deco
    return deco
end

local function hideDeco(deco)
    for _, region in pairs(deco) do region:Hide() end
end

local function styleBlock(block)
    local kind = block.kind
    local deco = block._dsynDeco
    if kind ~= "dsynSection" and kind ~= "dsynGroup" then
        if deco then hideDeco(deco) end
        return
    end
    deco = decoration(block)
    hideDeco(deco)
    local width = block:GetWidth()
    local isFolded = folded()[block.ref]
    local rowMid = -8

    if kind == "dsynSection" then
        block.title:SetText("|cffffd100" .. (block.title:GetText() or "") .. "|r")
        deco.bar:ClearAllPoints()
        deco.bar:SetSize(width + 14, math.min(26, (width + 14) / 8))
        deco.bar:SetPoint("LEFT", block, "TOPLEFT", -10, rowMid - 1)
        deco.bar:Show()
        deco.button:ClearAllPoints()
        deco.button:SetPoint("RIGHT", block, "TOPRIGHT", 2, rowMid)
        atlas(deco.button, isFolded and "QuestTracker-Expand" or "QuestTracker-Collapse")
        deco.button:Show()
        deco.buttonGlow:Show()
    else
        block.title:SetText("|cffc8c8c8" .. (block.title:GetText() or "") .. "|r")
        deco.band:ClearAllPoints()
        deco.band:SetPoint("TOPLEFT", block, "TOPLEFT", -4, 1)
        deco.band:SetPoint("BOTTOMRIGHT", block, "TOPRIGHT", 0, -15)
        deco.band:Show()
        deco.rule:ClearAllPoints()
        deco.rule:SetPoint("TOPLEFT", block, "TOPLEFT", -4, -15)
        deco.rule:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -15)
        deco.rule:Show()
        deco.sign:ClearAllPoints()
        deco.sign:SetPoint("RIGHT", block, "TOPRIGHT", -2, rowMid)
        deco.sign:SetText(isFolded and "+" or "-")
        deco.sign:Show()
    end
    deco.glow:ClearAllPoints()
    deco.glow:SetPoint("TOPLEFT", block, "TOPLEFT", -6, 2)
    deco.glow:SetPoint("BOTTOMRIGHT", block, "TOPRIGHT", 0, -16)
    deco.glow:Show()
end

-- Blocks are the Buttons (with .title and .lines) under the tracker's content frame.
local function styleAll()
    local tracker = _G.DragonUIObjectiveTracker
    if not tracker then return end
    for _, holder in ipairs({ tracker:GetChildren() }) do
        for _, block in ipairs({ holder:GetChildren() }) do
            if block.title and block.lines and block:IsShown() then styleBlock(block) end
        end
    end
end

-- DragonUI spaces every block like a quest (at least a POI badge tall, then a 10px gap). Header rows are
-- one line, so the shown blocks are re-stacked from the top with tighter rows for headers.
local SECTION_H, GROUP_H, HEADER_GAP, SECTION_TOP, QUEST_GAP = 20, 16, 3, 6, 10

local function restack(tracker)
    local shown = {}
    for _, holder in ipairs({ tracker:GetChildren() }) do
        for _, block in ipairs({ holder:GetChildren() }) do
            if block.title and block.lines and block:IsShown() then
                local _, rel, _, _, y = block:GetPoint(1)
                if rel and y then shown[#shown + 1] = { block = block, rel = rel, y = -y } end
            end
        end
    end
    if #shown == 0 then return 0 end
    table.sort(shown, function(a, b) return a.y < b.y end)
    local y = shown[1].y
    local oldBottom = shown[#shown].y + shown[#shown].block:GetHeight()
    for index, item in ipairs(shown) do
        local block, kind = item.block, item.block.kind
        if kind == "dsynSection" and index > 1 then y = y + SECTION_TOP end
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", item.rel, "TOPLEFT", 0, -y)
        if kind == "dsynSection" then
            block:SetHeight(SECTION_H)
            y = y + SECTION_H + HEADER_GAP
        elseif kind == "dsynGroup" then
            block:SetHeight(GROUP_H)
            y = y + GROUP_H + HEADER_GAP
        else
            y = y + block:GetHeight() + QUEST_GAP
        end
    end
    -- How much shorter the list got (the last block carries no gap after it).
    local last = shown[#shown].block
    local newBottom = y - (last.kind == "dsynSection" and HEADER_GAP or last.kind == "dsynGroup" and HEADER_GAP or QUEST_GAP)
    return math.max(0, oldBottom - newBottom)
end

-- "Objectives (n)" should count quests, perks and achievements, not section lines.
local function fixHeaderCount(tracker)
    local label = OBJECTIVES_TRACKER_LABEL or ""
    for _, child in ipairs({ tracker:GetChildren() }) do
        for _, region in ipairs({ child:GetRegions() }) do
            if region:GetObjectType() == "FontString" and (region:GetText() or ""):find(label, 1, true) == 1 then
                if enabled() then region:SetText(label .. " (" .. totalItems .. ")") end
                return
            end
        end
    end
end

local hookedFrame
local function hookTracker()
    local tracker = _G.DragonUIObjectiveTracker
    if hookedFrame or not tracker then return end
    hookedFrame = true
    hooksecurefunc(tracker, "SetSize", function(self, width, height)
        if self._dsynSizing then return end
        styleAll()
        fixHeaderCount(self)
        if not enabled() then return end
        local saved = restack(self)
        if saved > 0 and height then
            -- Shrink the frame (and its drag anchor) by what the tighter rows saved.
            self._dsynSizing = true
            self:SetSize(width, height - saved)
            local anchor = self:GetParent()
            if anchor and anchor.GetName and anchor:GetName() == "DragonUI_QuestTrackerFrame" then
                anchor:SetSize(width, height - saved)
            end
            self._dsynSizing = nil
        end
    end)
    -- The tracker sizes its anchor right after the frame; keep the anchor at the shrunk height.
    local anchor = tracker:GetParent()
    if anchor and anchor.SetSize then
        hooksecurefunc(anchor, "SetSize", function(self)
            if self._dsynSizing or not enabled() then return end
            local h = tracker:GetHeight()
            if h and h > 0 and math.abs((self:GetHeight() or 0) - h) > 0.5 then
                self._dsynSizing = true
                self:SetSize(tracker:GetWidth(), h)
                self._dsynSizing = nil
            end
        end)
    end
    refresh()
end

function NS.RefreshTrackerGroups()
    refresh()
end

function Part.Init()
    OT = NS.D and NS.D.ObjectiveTracker
    if not (OT and OT.AddCollector) then return end
    -- Registered after Perks.lua's collector (file order), so perk blocks are already in the list.
    OT.AddCollector(regroup)
    hookTracker()
end

function Part.Check()
    if OT and not hookedFrame then hookTracker() end
end

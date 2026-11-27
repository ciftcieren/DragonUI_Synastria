local _, NS = ...

-- The quest log opens as DragonUI's Map & Quest Log, the way the Forever (retail) UI does it: whenever
-- Blizzard's QuestLogFrame shows (L key, micro menu, the objective tracker's quest click...), it is
-- closed again and the world map opens with its quest panel, on the selected quest when there is one.
-- Forcing the panel open is temporary: the saved collapsed/expanded choice is put back when the map
-- closes, so opening the map with M keeps the user's own layout. A toggle by the user in between wins.
-- In combat the map can't be opened by an addon, so the plain quest log stays.
local Part = {}
NS.Register(Part)

local WM
local restoreTo      -- panel state to put back on map close; nil = nothing to restore
local ours           -- true while this file itself calls SetPanelShown
local pendingRestore -- restore postponed by combat

local function enabled()
    return NS.db and NS.db.questLogMap ~= false
end

local function usable()
    return WM and WM.IsApplied and WM.IsApplied() and WM.SetPanelShown and WM.PanelShown
end

local function setPanel(shown)
    ours = true
    local ok, err = pcall(WM.SetPanelShown, shown)
    ours = nil
    if not ok then NS.Report(err) end
end

local function restore()
    if restoreTo == nil then return end
    if InCombatLockdown() then
        pendingRestore = true
        return
    end
    local value = restoreTo
    restoreTo, pendingRestore = nil, nil
    if WM.PanelShown() ~= value then setPanel(value) end
end

-- The quest the log had selected, if it is a quest and not a zone header.
local function selectedQuest()
    local index = GetQuestLogSelection and GetQuestLogSelection()
    if not index or index <= 0 then return end
    local title, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    if not title or isHeader then return end
    return index, questID
end

local function openMap()
    local index, questID = selectedQuest()
    if not WM.PanelShown() then
        if restoreTo == nil then restoreTo = false end
        setPanel(true)
    end
    local opened = questID and WM.OpenToQuest and WM.OpenToQuest(questID)
    if not opened and not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
    if index and WM.ShowQuestDetail then pcall(WM.ShowQuestDetail, index) end
end

-- Opening Blizzard's log can make the UI panel manager close the map first, so "was the map open" is
-- remembered from the map's own hide in the same instant. The tracker selects its quest just before it
-- opens the log (while the log is still hidden); L and the micro button don't, so with the map open
-- those close it, and a tracker click goes to its quest.
local mapHiddenAt, panelWhenHidden, pickedAt = -1, false, -1
-- Set by ToggleFrame(QuestLogFrame), which L and the micro button call; read in the deferred step.
local toggled

local function onQuestLogShow(frame)
    if not (enabled() and usable()) or InCombatLockdown() then return end
    local now = GetTime()
    -- A small window rather than "same frame": the map can be closed a frame before the log shows.
    local mapWasOpen = (WorldMapFrame:IsShown() and WM.PanelShown()) or (now - mapHiddenAt < 0.1 and panelWhenHidden)
    toggled = nil
    -- Hidden on the next frame: hiding a UI panel from inside its own OnShow upsets the panel layout.
    frame:SetAlpha(0)
    NS.After(0, function()
        frame:SetAlpha(1)
        if frame:IsShown() then HideUIPanel(frame) end
        if InCombatLockdown() then
            ShowUIPanel(frame)
            return
        end
        -- ToggleFrame is the sure sign of L / micro button; a quest picked just before is a tracker click.
        local isToggle = toggled or pickedAt ~= now
        toggled = nil
        if mapWasOpen and isToggle then
            -- L / micro button again: a toggle, so the map closes.
            if WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) end
            restore()
            return
        end
        local ok, err = pcall(openMap)
        if not ok then NS.Report(err) end
    end)
end

function Part.Init()
    WM = NS.D and NS.D.WorldMap
    if not (WM and QuestLogFrame and WorldMapFrame) then return end
    QuestLogFrame:HookScript("OnShow", onQuestLogShow)
    hooksecurefunc("ToggleFrame", function(frame)
        if frame == QuestLogFrame then toggled = true end
    end)
    hooksecurefunc("SelectQuestLogEntry", function()
        -- The log's own OnShow selects too; only a pick made before it opens counts.
        if not QuestLogFrame:IsShown() then pickedAt = GetTime() end
    end)
    WorldMapFrame:HookScript("OnHide", function()
        mapHiddenAt, panelWhenHidden = GetTime(), WM.PanelShown()
        restore()
    end)
    -- The user flipping the panel while it is forced open makes that their choice; nothing is put back.
    hooksecurefunc(WM, "SetPanelShown", function()
        if not ours then restoreTo = nil end
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        if pendingRestore and not WorldMapFrame:IsShown() then restore() end
    end)
end

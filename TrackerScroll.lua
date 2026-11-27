local _, NS = ...

-- Scrolling for DragonUI's objective tracker. When the list is longer than the room the tracker has
-- (screen space or its custom height), DragonUI drops the entries that don't fit. This scrolls by entry:
-- the mouse wheel (or a click on the bar) moves where the list starts, and the entries before that are
-- left out of the list, so DragonUI lays out the next stretch. A slim bar on the tracker's right shows
-- where you are. It only appears, and the wheel is only taken from the camera, while there is more to see.
-- Runs as the last tracker collector (after the grouping), so it trims the final list.
local Part = {}
NS.Register(Part)

local OT
local offset, total, shown = 0, 0, 0
local bar, scrollable

local function enabled()
    return NS.db and NS.db.trackerScroll ~= false
end

local function refresh()
    if OT and OT.Refresh then OT.Refresh() end
end

local function trim(blocks)
    total = #blocks
    if not enabled() then offset = 0 return end
    if offset > total - 1 then offset = math.max(0, total - 1) end
    for _ = 1, offset do table.remove(blocks, 1) end
end

local function scrollBy(steps)
    local maxOffset = math.max(0, total - shown)
    local new = math.max(0, math.min(maxOffset, offset + steps))
    if new ~= offset then
        offset = new
        refresh()
    end
end

local function onWheel(_, delta)
    scrollBy(-delta)
end

local function buildBar(tracker)
    bar = CreateFrame("Button", nil, tracker)
    bar:SetWidth(8)
    bar:SetFrameLevel(tracker:GetFrameLevel() + 10)

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0, 0, 0, 0.35)
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    track:SetWidth(4)

    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.thumb:SetGradientAlpha("HORIZONTAL", 0.75, 0.6, 0.1, 0.9, 1, 0.82, 0.2, 0.9)
    bar.thumb:SetWidth(4)

    bar.glow = bar:CreateTexture(nil, "HIGHLIGHT")
    bar.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.glow:SetBlendMode("ADD")
    bar.glow:SetVertexColor(1, 0.82, 0, 0.25)
    bar.glow:SetAllPoints(bar.thumb)

    -- A click above or below the thumb pages by what is on screen.
    bar:RegisterForClicks("LeftButtonUp")
    bar:SetScript("OnClick", function(self)
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local mid = (bar.thumb:GetTop() + bar.thumb:GetBottom()) / 2
        scrollBy(cy > mid and -math.max(1, shown - 1) or math.max(1, shown - 1))
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", onWheel)
end

local function blocksOf(tracker)
    local list = {}
    for _, holder in ipairs({ tracker:GetChildren() }) do
        for _, block in ipairs({ holder:GetChildren() }) do
            if block.title and block.lines and block:IsShown() then list[#list + 1] = block end
        end
    end
    return list
end

local function afterLayout(tracker)
    if not bar then buildBar(tracker) end
    local list = blocksOf(tracker)
    shown = #list
    scrollable = enabled() and not OT.collapsed and (offset > 0 or offset + shown < total)

    tracker:EnableMouseWheel(scrollable and true or false)
    tracker:SetScript("OnMouseWheel", scrollable and onWheel or nil)
    -- Entries take the mouse for clicks; they pass the wheel on while there is something to scroll.
    for _, block in ipairs(list) do
        block:EnableMouseWheel(scrollable and true or false)
        block:SetScript("OnMouseWheel", scrollable and onWheel or nil)
    end

    if not scrollable then bar:Hide() return end
    -- Just right of the tracker, unless that is off the screen edge (the usual spot): then just inside.
    local right, screen = tracker:GetRight(), UIParent:GetRight()
    local outside = right and screen and (right * tracker:GetEffectiveScale() + 14 < screen * UIParent:GetEffectiveScale())
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", tracker, "TOPRIGHT", outside and 4 or -8, -30)
    bar:SetPoint("BOTTOMLEFT", tracker, "BOTTOMRIGHT", outside and 4 or -8, 4)
    bar:Show()
    local height = bar:GetHeight()
    if not height or height <= 0 then return end
    local thumbH = math.max(12, height * shown / math.max(1, total))
    local room = height - thumbH
    local maxOffset = math.max(1, total - shown)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("TOP", bar, "TOP", 0, -room * math.min(1, offset / maxOffset))
    bar.thumb:SetHeight(thumbH)
end

function NS.RefreshTrackerScroll()
    if not enabled() then offset = 0 end
    refresh()
end

local hooked
local function hookTracker()
    local tracker = _G.DragonUIObjectiveTracker
    if hooked or not tracker then return end
    hooked = true
    hooksecurefunc(tracker, "SetSize", function(self)
        if self._dsynSizing then return end
        afterLayout(self)
    end)
    refresh()
end

function Part.Init()
    OT = NS.D and NS.D.ObjectiveTracker
    if not (OT and OT.AddCollector) then return end
    -- Registered after TrackerGroups.lua (file order): trims the final, grouped list.
    OT.AddCollector(trim)
    hookTracker()
end

function Part.Check()
    if OT and not hooked then hookTracker() end
end

local _, NS = ...

-- The server's Finder ("Tracking") panel on the world map.
-- Server layout (from /dsyn dump): 224x512 at WorldMapFrame TOPRIGHT -24 -14; lists FindThingFrame-Scroll1
-- (16,-30, 129x128) and -Scroll2 (16,-170, 129x200), each with a "-Slider"; FindThingFrame-Search (28,-380, 128x20).
-- DragonUI draws its map border inside WorldMapFrame, so that anchor overlaps the map. Here the panel docks to the
-- right of DragonUI's border at the same height, with the search on top like the map's quest log, and the lists
-- filling the rest. Alt+drag still moves it freely.
local NAME = "FindThingFrame"
local DOCK_GAP = 0         -- both metal frames keep their visible edge on the frame line, so 0 makes them touch
local SNAP = 40            -- an Alt+drag dropped this close to the map's edge docks again
local SIDE, SLIDER_W = 16, 20
local TOP = 30             -- below the 21px title band
local SEARCH_H, LIST_GAP = 20, 12
local LIST1_H = 128

local Part = {}
NS.Register(Part)
NS.parts = NS.parts or {}
NS.parts.finder = Part

local finder

local function mapBorder()
    return _G.DragonUIWorldMapBorder
end

-- Collapsing hides the whole panel and moves "-Close" out of it, so that one button stays up to reopen it.
local function collapsed()
    return finder ~= nil and not finder:IsShown()
end

-- Expanded: the map's ↙ in our title band. Collapsed: a red ↗ beside the map's top-right corner.
local function syncCollapseButton()
    local button = _G[NAME .. "-Close"]
    if not (button and finder and finder._dsynSkinned) then return end
    if collapsed() then
        local border = mapBorder()
        button:SetFrameStrata("HIGH")
        button:SetFrameLevel(30)
        NS.SetRedIcon(button, "expand")
        if border then NS.Pin(button, { { "TOPLEFT", border, "TOPRIGHT", 1, 0 } }) end
    else
        button:SetFrameStrata(finder:GetFrameStrata())
        button:SetFrameLevel(finder:GetFrameLevel() + 10)
        NS.SetRedIcon(button, "condense")
        NS.Pin(button, { { "TOPRIGHT", finder, "TOPRIGHT", 1, 0 } })
    end
end

local function place()
    if not finder or finder._dsynMoving then return end
    syncCollapseButton()
    local pos, parent = NS.db.finder, finder:GetParent() or WorldMapFrame
    if pos.x ~= nil then
        NS.Pin(finder, { { "TOPLEFT", parent, "TOPLEFT", pos.x, pos.y } })
    elseif mapBorder() and mapBorder():IsShown() then
        local border = mapBorder()
        NS.Pin(finder, {
            { "TOPLEFT", border, "TOPRIGHT", DOCK_GAP, 0 },
            { "BOTTOMLEFT", border, "BOTTOMRIGHT", DOCK_GAP, 0 },
        })
    end
end

-- Screen-space distance from the finder's left edge to the map border's right edge.
local function distanceToMap()
    local border = mapBorder()
    if not (border and border:IsVisible() and border:GetRight() and finder:GetLeft()) then return nil end
    return math.abs(finder:GetLeft() * finder:GetEffectiveScale() - border:GetRight() * border:GetEffectiveScale())
        / UIParent:GetEffectiveScale()
end

local function save()
    local near = distanceToMap()
    if near and near <= SNAP then
        NS.db.finder.x, NS.db.finder.y = nil, nil
        return place()
    end
    local parent = finder:GetParent() or WorldMapFrame
    local left, top, pLeft, pTop = finder:GetLeft(), finder:GetTop(), parent:GetLeft(), parent:GetTop()
    if not (left and pLeft) then return end
    local r = parent:GetEffectiveScale() / finder:GetEffectiveScale()
    NS.db.finder.x, NS.db.finder.y = left - pLeft * r, top - pTop * r
    place()
end

function Part.Reset()
    NS.db.finder.x, NS.db.finder.y = nil, nil
    place()
end

-- The server sizes each scroll range for its own list heights (rows are 20px; bars from 120 / 190px), so after
-- each of its updates the range is redone for the height the list really has here.
local ROW_H, WHEEL_STEP = 20, 40

local function fixRange(scroll)
    local slider = _G[scroll:GetName() .. "-Slider"]
    local content = _G[scroll:GetName() .. "-Content"]
    if not (slider and content) then return end
    local rows = 0
    for _, row in ipairs({ content:GetChildren() }) do
        if row:IsShown() then rows = rows + 1 end
    end
    local overflow = math.ceil(rows * ROW_H - scroll:GetHeight())
    if overflow > 0 then
        slider:SetMinMaxValues(0, overflow)
        if slider:GetValue() > overflow then slider:SetValue(overflow) end
        slider:Show()
    else
        slider:SetValue(0)
        slider:Hide()
    end
end

local function fixRanges()
    for id = 1, 2 do
        local scroll = _G[NAME .. "-Scroll" .. id]
        if scroll then fixRange(scroll) end
    end
end

-- UpdateWorldmapFilter ends every redraw of both lists; re-hooked if the server ever redefines it.
local hookedUpdate
local function hookUpdates()
    local fn = _G.UpdateWorldmapFilter
    if type(fn) == "function" and fn ~= hookedUpdate then
        hooksecurefunc("UpdateWorldmapFilter", fixRanges)
        hookedUpdate = _G.UpdateWorldmapFilter
    end
end

local function enableWheel(scroll)
    if scroll._dsynWheel then return end
    scroll._dsynWheel = true
    local slider = _G[scroll:GetName() .. "-Slider"]
    scroll:EnableMouseWheel(true)
    scroll:HookScript("OnMouseWheel", function(_, delta)
        if not (slider and slider:IsShown()) then return end
        local low, high = slider:GetMinMaxValues()
        slider:SetValue(math.max(low, math.min(high, slider:GetValue() - delta * WHEEL_STEP)))
    end)
    scroll:HookScript("OnSizeChanged", function(self) fixRange(self) end)
end

-- A list's slider rides in the right gutter along the list's whole height.
local function layoutList(scroll, points)
    enableWheel(scroll)
    NS.Pin(scroll, points)
    local slider = _G[scroll:GetName() .. "-Slider"]
    if slider then
        NS.Pin(slider, {
            { "TOPRIGHT", scroll, "TOPRIGHT", SLIDER_W, -16 },
            { "BOTTOMRIGHT", scroll, "BOTTOMRIGHT", SLIDER_W, 16 },
        })
    end
    local content = _G[scroll:GetName() .. "-Content"]
    if content and not content._dsynWidth then
        content._dsynWidth = true
        content:SetWidth(scroll:GetWidth())
        scroll:HookScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)
    end
end

local function layout(frame)
    local right = -(SIDE + SLIDER_W)
    local search = _G[NAME .. "-Search"]
    local listBottom = SIDE
    if search then
        search:SetHeight(SEARCH_H)
        -- Bottom of the panel, as the server had it; the input border's left cap hangs 5px out of the box.
        NS.Pin(search, {
            { "BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE + 5, SIDE - 2 },
            { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE, SIDE - 2 },
        })
        listBottom = SIDE + SEARCH_H + LIST_GAP
    end
    local listTop = TOP
    local list1, list2 = _G[NAME .. "-Scroll1"], _G[NAME .. "-Scroll2"]
    if list1 then
        list1:SetHeight(LIST1_H)
        layoutList(list1, {
            { "TOPLEFT", frame, "TOPLEFT", SIDE, -listTop },
            { "TOPRIGHT", frame, "TOPRIGHT", right, -listTop },
        })
    end
    if list2 then
        local top2 = list1 and (listTop + LIST1_H + LIST_GAP) or listTop
        layoutList(list2, {
            { "TOPLEFT", frame, "TOPLEFT", SIDE, -top2 },
            { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, listBottom },
        })
        -- The map's thin gold rule between the two lists.
        if list1 and not frame._dsynDivider then
            local rule = frame._dsynRing:CreateTexture(nil, "ARTWORK")
            if rule.SetAtlasTexture then rule:SetAtlasTexture("_UI-Frame-InnerTopTile") end
            rule:SetHeight(3)
            rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(top2 - LIST_GAP / 2 - 1))
            rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(top2 - LIST_GAP / 2 - 1))
            frame._dsynDivider = rule
        end
    end
    place()
    fixRanges()
end

local wasCollapsed

function Part.Check()
    if NS.db.finderSkin == false then return end
    hookUpdates()
    local frame = _G[NAME]
    if frame and frame == finder then
        -- Collapse can also come from the server's own code (its menu, a reload of its state).
        local now = collapsed()
        if now ~= wasCollapsed then
            wasCollapsed = now
            if frame:IsVisible() then NS.Skin(frame, { layout = layout }) end
            place()
        end
        return
    end
    if not frame then return end
    finder = frame

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:HookScript("OnDragStart", function(self)
        if self == finder and IsAltKeyDown() then
            self._dsynMoving = true
            self._dsynPoints = nil -- let the drag move it
            self:StartMoving()
        end
    end)
    frame:HookScript("OnDragStop", function(self)
        if self._dsynMoving then
            self._dsynMoving = nil
            self:StopMovingOrSizing()
            save()
        end
    end)
    frame:HookScript("OnShow", place)
    frame:HookScript("OnHide", function(self)
        if self == finder then NS.After(0, syncCollapseButton) end
    end)
    -- Collapse/expand shows or hides the lists (and may redraw the server's art): redo ours a frame later,
    -- once the server's click handler has finished.
    local collapse = _G[NAME .. "-Close"]
    if collapse then
        collapse:HookScript("OnClick", function()
            NS.After(0, function()
                if frame ~= finder then return end
                NS.Skin(frame, { layout = layout })
                place()
            end)
        end)
    end
    -- DragonUI's map can switch windowed/maximized, which moves its border.
    local border = mapBorder()
    if border and not border._dsynHooked then
        border._dsynHooked = true
        border:HookScript("OnSizeChanged", place)
        border:HookScript("OnShow", place)
    end

    if not NS.Skin(frame, { layout = layout }) then place() end
end

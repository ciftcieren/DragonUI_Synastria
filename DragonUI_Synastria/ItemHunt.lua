local _, NS = ...

-- DragonUI look for the server's Item Hunt tracker (ItemHuntFrame, from container_46/47/48), matching the
-- DragonUI objective tracker: header bar art with a gold title and the red collapse button, gold source
-- lines, a thin dark ring round each item icon, a dark panel with DragonUI's inset trim instead of the
-- tooltip box (only when the server's own "show background" option is on), DragonUI's scrollbar.
-- It stays free-floating and keeps all its own behaviour (drag, lock, resize, menu, collapse, rows that
-- brighten on hover). The server can send the frame again, so everything is re-checked every second.
local Part = {}
NS.Register(Part)

local NAME = "ItemHuntFrame"
local frame

local function enabled()
    return NS.db and NS.db.itemHunt ~= false
end

local function atlas(tex, name, blend)
    local unpackAtlas = NS.D.functions and NS.D.functions.UnpackAtlas
    if not unpackAtlas then return end
    local file, _, _, l, r, t, b = unpackAtlas(name)
    if not (file and l) then return end
    tex:SetTexture(file)
    tex:SetTexCoord(l, r, t, b)
    if blend then tex:SetBlendMode(blend) end
end

-- The server only ever recolours its tooltip box; the box goes and its alpha drives our panel instead.
local function dressBackground(bgf)
    if bgf._dsyn then return end
    bgf._dsyn = true
    bgf:SetBackdrop(nil)
    local fill = bgf:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetPoint("TOPLEFT", bgf, "TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", bgf, "BOTTOMRIGHT", -4, 4)
    fill:SetVertexColor(0, 0, 0, 0.5)
    local trim = CreateFrame("Frame", nil, bgf)
    trim:SetAllPoints(bgf)
    trim:EnableMouse(false)
    local slicer = _G.DragonUI_NineSlice
    if slicer and slicer.ApplyLayout and slicer.GetLayout then
        local layout = slicer.GetLayout("InsetFrameTemplate")
        if layout then slicer.ApplyLayout(trim, layout) end
    end
    hooksecurefunc(bgf, "SetBackdropColor", function(_, r, g, b, a)
        -- The server's default is white at half alpha: that becomes black at half alpha. A colour the
        -- player picked is kept, darkened to sit behind the text.
        if r == 1 and g == 1 and b == 1 then
            fill:SetVertexColor(0, 0, 0, a or 0.5)
        else
            fill:SetVertexColor((r or 0) * 0.35, (g or 0) * 0.35, (b or 0) * 0.35, a or 0.5)
        end
    end)
end

local function dressCollapse(button)
    if not button then return end
    local folded = button.cele and button.cele.collapsed
    for _, kind in ipairs({ "Normal", "Pushed" }) do
        local tex = button["Get" .. kind .. "Texture"](button)
        if tex then
            local name = folded and "QuestTracker-Expand" or "QuestTracker-Collapse"
            if kind == "Pushed" then name = name .. "-Pressed" end
            atlas(tex, name)
        end
    end
    local glow = button:GetHighlightTexture()
    if glow then atlas(glow, "QuestTracker-Red-Highlight", "ADD") end
    button:SetSize(16, 17)
end

local function dressHeader(f)
    local header = _G[NAME .. "Header"]
    local text = _G[NAME .. "HeaderText"]
    local collapse = _G[NAME .. "Collapse0"]
    if not header then return end
    if not header._dsyn then
        header._dsyn = true
        local bar = header:CreateTexture(nil, "BACKGROUND")
        atlas(bar, "QuestTracker-Header")
        bar:SetAlpha(0.9)
        header._dsynBar = bar
        if text then
            text:SetFontObject(GameFontNormal)
            text:SetTextColor(1, 0.82, 0)
        end
        if collapse then
            collapse:HookScript("OnClick", function(self) dressCollapse(self) end)
        end
    end
    -- Sized from the header each time: the frame can be resized.
    -- A fixed 30px bar centred on the title (the art's own 8:1 grows with the frame's width).
    local width = (header:GetWidth() or 200) + 26
    header._dsynBar:ClearAllPoints()
    header._dsynBar:SetSize(width, 30)
    header._dsynBar:SetPoint("LEFT", header, "TOPLEFT", -12, -17)
    if collapse then dressCollapse(collapse) end
end

-- Rows are pooled and made as needed: ItemHuntFrameObjN (sources) and ItemHuntFrameItemN (items).
-- A 1px dark edge drawn above the icon (four strips), so the icon itself is never covered or dimmed.
local function edge(owner, icon)
    local function strip(p1, p2, x1, y1, x2, y2, horizontal)
        local t = owner:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(0, 0, 0, 0.9)
        t:SetPoint(p1, icon, p1, x1, y1)
        t:SetPoint(p2, icon, p2, x2, y2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    end
    strip("TOPLEFT", "TOPRIGHT", 0, 0, 0, 0, true)
    strip("BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, 0, 0, true)
    strip("TOPLEFT", "BOTTOMLEFT", 0, 0, 0, 0, false)
    strip("TOPRIGHT", "BOTTOMRIGHT", 0, 0, 0, 0, false)
end

-- A faint gold rule above every source except the first, so each source with its items reads as a group.
local function placeRule(obj)
    local rule = obj._dsynRule
    if not rule then return end
    local _, _, _, _, y = obj:GetPoint(1)
    if y and math.abs(y) < 1 then rule:Hide() else rule:Show() end
end

local function dressRows()
    for i = 1, 400 do
        local item = _G[NAME .. "Item" .. i]
        if not item then break end
        if not item._dsyn then
            item._dsyn = true
            local icon = _G[NAME .. "Item" .. i .. "Icon"]
            if icon then
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                edge(item, icon)
            end
        end
    end
    for i = 1, 400 do
        local obj = _G[NAME .. "Obj" .. i]
        if not obj then break end
        if not obj._dsynRule then
            local rule = obj:CreateTexture(nil, "BACKGROUND")
            rule:SetTexture("Interface\\Buttons\\WHITE8X8")
            rule:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.55, 1, 0.82, 0, 0)
            rule:SetHeight(1)
            rule:SetPoint("BOTTOMLEFT", obj, "TOPLEFT", 0, 1)
            rule:SetPoint("BOTTOMRIGHT", obj, "TOPRIGHT", -20, 1)
            obj._dsynRule = rule
            hooksecurefunc(obj, "SetPoint", placeRule)
        end
        placeRule(obj)
    end
end

-- The list starts right under the 30px header; a few pixels more so the bar doesn't touch the first row.
local LIST_DROP = 12

local function dressScroll()
    local scroll = _G[NAME .. "-ScrollFrame"]
    if scroll and NS.Kit and not scroll._dsynPinned then
        scroll._dsynPinned = true
        -- Top and bottom both pinned: the server gives the list a fixed height (frame minus its 30px
        -- header), so moving only the top down would push the last row out under the frame. 16px on the
        -- right is the server's own room for the scrollbar.
        NS.Kit.Pin(scroll, {
            { "TOPLEFT", _G[NAME], "TOPLEFT", 0, -30 - LIST_DROP },
            { "BOTTOMRIGHT", _G[NAME], "BOTTOMRIGHT", -16, 0 },
        })
    end
    local UI = NS.D.ForeverUI
    if scroll and not scroll._dsyn and UI and UI.SkinScrollBar then
        scroll._dsyn = true
        pcall(UI.SkinScrollBar, scroll)
    end
end

local function dressResize()
    local grip = _G[NAME .. "Resize"]
    if not grip or grip._dsyn then return end
    grip._dsyn = true
    -- Silver like the rest of the DragonUI chrome instead of the chat window's gold grip.
    for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture(), grip:GetHighlightTexture() }) do
        if tex then tex:SetDesaturated(true) end
    end
end

function Part.Check()
    if not enabled() then return end
    local f = _G[NAME]
    if not f then return end
    if f ~= frame then frame = f end
    local bgf = _G[NAME .. "Background"]
    if bgf then dressBackground(bgf) end
    dressHeader(f)
    dressScroll()
    dressResize()
    if f:IsShown() then dressRows() end
end

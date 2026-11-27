local _, NS = ...

-- Shared DragonUI look for Scoots windows (same pieces DragonUI uses on its own merchant and map).
local S = {}
NS.Kit = S

function S.Dir()
    return NS.D._dir
end

function S.UI()
    return NS.D and NS.D.ForeverUI
end

-- Keeps a region at our anchors even when the addon re-anchors it later.
-- points: list of { point, relativeTo, relativePoint, x, y }.
function S.Pin(region, points)
    region._dscPoints = points
    local function place()
        region._dscPlacing = true
        region:ClearAllPoints()
        for _, p in ipairs(region._dscPoints) do region:SetPoint(unpack(p)) end
        region._dscPlacing = nil
    end
    if not region._dscPinned then
        region._dscPinned = true
        hooksecurefunc(region, "SetPoint", function(self)
            if not self._dscPlacing and self._dscPoints then place() end
        end)
    end
    place()
end

function S.Place(region, point, anchor, relativePoint, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, anchor, relativePoint, x, y)
end

function S.NineSlice(frame, layout)
    local slicer = _G.DragonUI_NineSlice
    if slicer and slicer.GetLayout and slicer.ApplyLayout then
        local def = slicer.GetLayout(layout)
        if def then slicer.ApplyLayout(frame, def) end
    end
end

-- Tiled rock ground inside the metal frame, as DragonUI's merchant and map windows.
function S.Rock(frame)
    local rock = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    rock:SetTexture(S.Dir() .. "UI\\ui-background-rock")
    rock:SetHorizTile(true)
    rock:SetVertTile(true)
    rock:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
    rock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    return rock
end

function S.Streaks(frame)
    local streaks = frame:CreateTexture(nil, "BORDER")
    streaks:SetAtlasTexture("_UI-Frame-TopTileStreaks", false)
    streaks:SetHorizTile(true)
    streaks:SetHeight(43)
    streaks:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -21)
    streaks:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -21)
    return streaks
end

-- A recessed marble panel with the thin gold inset trim. Same level as its parent: the parent's own
-- art stays below it and every child frame of the parent stays above it.
function S.Inset(parent)
    local inset = CreateFrame("Frame", nil, parent)
    inset:EnableMouse(false)
    inset:SetFrameLevel(parent:GetFrameLevel())
    S.NineSlice(inset, "InsetFrameTemplate")
    local ground = inset:CreateTexture(nil, "BACKGROUND", nil, -5)
    ground:SetTexture(S.Dir() .. "UI\\ui-background-marble")
    ground:SetHorizTile(true)
    ground:SetVertTile(true)
    ground:SetAllPoints(inset)
    return inset
end

-- Red buttons from DragonUI's redbutton2x sheet (columns per icon, rows per state).
local RED_COLUMNS = { close = { 39, 75 }, expand = { 77, 113 }, condense = { 1, 37 } }
local RED_ROWS = { Normal = { 1, 39 }, Pushed = { 81, 119 }, Disabled = { 41, 79 } }

function S.RedIcon(button, kind)
    local sheet = S.Dir() .. "UI\\redbutton2x"
    local col = RED_COLUMNS[kind]
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    for state, row in pairs(RED_ROWS) do
        button["Set" .. state .. "Texture"](button, sheet)
        local tex = button["Get" .. state .. "Texture"](button)
        tex:SetTexCoord(col[1] / 256, col[2] / 256, row[1] / 128, row[2] / 128)
        tex:SetAlpha(1)
    end
    button:SetHighlightTexture(sheet, "ADD")
    local glow = button:GetHighlightTexture()
    glow:SetTexCoord(115 / 256, 151 / 256, 1 / 128, 39 / 128)
    glow:SetAlpha(1)
    button:SetSize(24, 24)
end

-- The quest log's settings cog, for a button that opens options.
function S.Cog(button)
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" or region:GetObjectType() == "FontString" then region:SetAlpha(0) end
    end
    -- A button redraws its label on state changes, so alpha alone doesn't keep it hidden.
    button:SetText("")
    local label = button:GetFontString()
    if label then label:Hide() end
    local blank = "Interface\\Buttons\\WHITE8X8"
    button:SetNormalTexture(blank)
    button:SetPushedTexture(blank)
    button:SetDisabledTexture(blank)
    button:SetHighlightTexture(blank, "ADD")
    for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture(), button:GetHighlightTexture() }) do
        tex:SetAtlasTexture("questlog-icon-setting")
        tex:SetVertexColor(1, 1, 1)
        tex:SetAlpha(1)
    end
    button:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
    button:GetDisabledTexture():SetDesaturated(true)
    button:GetHighlightTexture():SetAlpha(0.4)
    button:SetSize(18, 18)
end

-- DragonUI's red panel button (ForeverUI), keeping the size the addon gave it.
function S.Button(button)
    local UI = S.UI()
    if not (UI and UI.SkinButton) then return end
    local w, h = button:GetWidth(), button:GetHeight()
    pcall(UI.SkinButton, button)
    button:SetSize(w, math.max(h, 22))
end

-- DragonUI's minimal checkbox in silver; the check mark keeps its colour.
-- keepSize: the addon chains its rows off the box, so a bigger box would push them apart.
function S.Check(button, keepSize)
    local UI = S.UI()
    if not (UI and UI.SkinCheckButton) or button._dscCheck then return end
    button._dscCheck = true
    local w, h = button:GetWidth(), button:GetHeight()
    pcall(UI.SkinCheckButton, button)
    if keepSize then button:SetSize(w, h) end
    for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetHighlightTexture() }) do
        if tex then tex:SetDesaturated(true) end
    end
    -- Radio rows disable the picked box; show it as plainly checked rather than greyed out.
    local check = button:GetCheckedTexture()
    local picked = button:GetDisabledCheckedTexture()
    if check and picked then
        picked:SetTexture(check:GetTexture())
        picked:SetTexCoord(check:GetTexCoord())
        picked:SetDesaturated(false)
        picked:SetVertexColor(1, 1, 1)
    end
end

-- The world map's quest search look: magnifier, grey hint while empty.
function S.SearchBox(box, hintText, oldLabel)
    if box._dscSearch then return end
    box._dscSearch = true
    if oldLabel then
        oldLabel:SetAlpha(0)
    end
    box:SetTextInsets(18, 6, 0, 0)
    local glass = box:CreateTexture(nil, "OVERLAY")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", box, "LEFT", 3, -1)
    glass:SetTexture(S.Dir() .. "Collections\\UI-Searchbox-Icon")
    local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", box, "LEFT", 20, 0)
    hint:SetText(hintText or SEARCH)
    local function refresh(self)
        if (self:GetText() or "") == "" and not self._dscFocused then hint:Show() else hint:Hide() end
    end
    box:HookScript("OnTextChanged", refresh)
    box:HookScript("OnEditFocusGained", function(self) self._dscFocused = true refresh(self) end)
    box:HookScript("OnEditFocusLost", function(self) self._dscFocused = nil refresh(self) end)
    refresh(box)
end

-- DragonUI's dropdown (text holder + round arrow) on a stock UIDropDownMenuTemplate. The arrow button
-- keeps its parent: its OnClick opens the menu of GetParent().
function S.DropDown(dropdown, width)
    local UI = S.UI()
    if not (UI and UI.SetAtlas) or dropdown._dscDrop then return end
    dropdown._dscDrop = true
    local name = dropdown:GetName()
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        local tex = _G[name .. part]
        if tex then tex:SetAlpha(0) end
    end
    UIDropDownMenu_SetWidth(dropdown, width)

    local left = dropdown:CreateTexture(nil, "BACKGROUND")
    local middle = dropdown:CreateTexture(nil, "BACKGROUND")
    local right = dropdown:CreateTexture(nil, "BACKGROUND")
    UI.SetAtlas(left, "common-dropdown-textholder-left", true)
    UI.SetAtlas(right, "common-dropdown-textholder-right", true)
    UI.SetAtlas(middle, "common-dropdown-textholder-middle", false)
    left:SetPoint("LEFT", dropdown, "LEFT", 7, 0)
    right:SetPoint("RIGHT", dropdown, "RIGHT", -13, 0)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
    dropdown._dscLeft, dropdown._dscRight, dropdown._dscMiddle = left, right, middle

    local button = _G[name .. "Button"]
    if button then
        local blank = "Interface\\Buttons\\WHITE8X8"
        local looks = {
            { "Normal", "common-dropdown-a-button" },
            { "Pushed", "common-dropdown-a-button-pressed" },
            { "Disabled", "common-dropdown-a-button-disabled" },
            { "Highlight", "common-dropdown-a-button-hover" },
        }
        for _, look in ipairs(looks) do
            button["Set" .. look[1] .. "Texture"](button, blank)
            local tex = button["Get" .. look[1] .. "Texture"](button)
            UI.SetAtlas(tex, look[2], false)
            tex:SetVertexColor(1, 1, 1)
            tex:ClearAllPoints()
            tex:SetAllPoints(button)
        end
        button:GetHighlightTexture():SetBlendMode("BLEND")
        button:SetSize(27, 27)
        S.Place(button, "RIGHT", right, "RIGHT", -7, -2)
    end

    local text = _G[name .. "Text"]
    if text then
        -- Pinned: UIDropDownMenu code can put the text back at Blizzard's right-aligned spot.
        S.Pin(text, {
            { "LEFT", left, "LEFT", 12, 0 },
            { "RIGHT", button or right, button and "LEFT" or "RIGHT", -2, 0 },
        })
        text:SetJustifyH("LEFT")
        hooksecurefunc(text, "SetJustifyH", function(self, how)
            if how ~= "LEFT" and not self._dscJustify then
                self._dscJustify = true
                self:SetJustifyH("LEFT")
                self._dscJustify = nil
            end
        end)
        text:SetFontObject(GameFontHighlightSmall)
    end
    S.HookMenuList()
end

-- Keeps the list at the height Blizzard gave it but centres it under the box, and centres each entry's
-- text. The texts go back to auto width when another dropdown reuses the list.
function S.CenterMenuList(list, dropdown)
    local box = dropdown._dscMiddle
    local top, boxBottom = list:GetTop(), box and box:GetBottom()
    if not (top and boxBottom) then return end
    list:ClearAllPoints()
    list:SetPoint("TOP", box, "BOTTOM", 0, top - boxBottom)
    local name = list:GetName()
    for i = 1, (list.numButtons or 0) do
        local button = _G[name .. "Button" .. i]
        local text = _G[name .. "Button" .. i .. "NormalText"]
        if button and text then
            -- Only width and justification change; the anchor stays Blizzard's.
            local _, _, _, x = text:GetPoint(1)
            text:SetWidth(button:GetWidth() - 2 * (x or 0))
            text:SetJustifyH("CENTER")
        end
    end
    list._dscCentered = true
end

function S.UncenterMenuList(list)
    if not list._dscCentered then return end
    list._dscCentered = nil
    local name = list:GetName()
    for i = 1, (list.numButtons or 0) do
        local text = _G[name .. "Button" .. i .. "NormalText"]
        if text then
            text:SetWidth(0)
            text:SetJustifyH("LEFT")
        end
    end
end

-- DropDownList1/2 are shared by every dropdown in the game, so the DragonUI menu art goes on only while
-- one of our skinned dropdowns owns the list, and comes off when anything else opens it.
local listHooked
function S.HookMenuList()
    if listHooked then return end
    listHooked = true
    hooksecurefunc("ToggleDropDownMenu", function(level, _, frame)
        local UI = S.UI()
        level = level or 1
        frame = frame or UIDROPDOWNMENU_OPEN_MENU
        if type(frame) == "string" then frame = _G[frame] end
        local list = _G["DropDownList" .. level]
        if not (UI and list) then return end
        local name = list:GetName()
        if frame and frame._dscDrop and list:IsShown() then
            -- Blizzard re-picks Backdrop/MenuBackdrop on every open, so hiding both here is undone next time.
            for _, suffix in ipairs({ "Backdrop", "MenuBackdrop" }) do
                local back = _G[name .. suffix]
                if back then back:Hide() end
            end
            UI.SkinMenuBackground(list, "bg")
            list._dscMenu = true
            -- _dscNoCenter: menus with long entries (server windows) keep Blizzard's placement and widths.
            if frame._dscMiddle and not frame._dscNoCenter then S.CenterMenuList(list, frame) end
        elseif list._dscMenu then
            list._dscMenu = nil
            UI.HideMenuBackground(list)
        end
        if not (frame and frame._dscDrop) or frame._dscNoCenter then S.UncenterMenuList(list) end
    end)
end

-- Character-frame style tabs from DragonUI's uiframetabs sheet (same cuts as its merchant tabs).
local TAB_CAPS = {
    { "Left", 35, 36, "TOPLEFT", -5, 0.015625, 0.5625, 0.816406, 0.957031 },
    { "Right", 37, 36, "TOPRIGHT", 5, 0.015625, 0.59375, 0.667969, 0.808594 },
    { "LeftDisabled", 35, 42, "TOPLEFT", -4, 0.015625, 0.5625, 0.496094, 0.660156 },
    { "RightDisabled", 37, 42, "TOPRIGHT", 6, 0.015625, 0.59375, 0.324219, 0.488281 },
}
local TAB_FILLS = {
    { "Middle", "", 36, 0, 0.015625, 0.175781, 0.316406 },
    { "MiddleDisabled", "Disabled", 42, 0, 0.015625, 0.00390625, 0.167969 },
}
local GLOW_ALPHA = 0.4

local function glowPiece(tab, sheet, l, r, t, b)
    local glow = tab:CreateTexture(nil, "HIGHLIGHT")
    glow:SetTexture(sheet)
    glow:SetTexCoord(l, r, t, b)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(GLOW_ALPHA)
    glow:SetHeight(30)
    return glow
end

function S.Tab(tab)
    if tab._dscTab then return end
    local name = tab:GetName()
    local sheet = S.Dir() .. "UI\\uiframetabs"
    tab:SetNormalFontObject(GameFontNormalSmall)
    tab:SetHighlightFontObject(GameFontHighlightSmall)
    for _, cap in ipairs(TAB_CAPS) do
        local tex = _G[name .. cap[1]]
        if tex then
            tex:SetTexture(sheet)
            tex:SetTexCoord(cap[6], cap[7], cap[8], cap[9])
            tex:SetSize(cap[2], cap[3])
            S.Place(tex, cap[4], tab, cap[4], cap[5], 0)
        end
    end
    for _, fill in ipairs(TAB_FILLS) do
        local tex = _G[name .. fill[1]]
        local l, r = _G[name .. "Left" .. fill[2]], _G[name .. "Right" .. fill[2]]
        if tex and l and r then
            tex:SetTexture(sheet)
            tex:SetTexCoord(fill[4], fill[5], fill[6], fill[7])
            tex:SetHeight(fill[3])
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
            tex:SetPoint("TOPRIGHT", r, "TOPLEFT", 0, 0)
        end
    end
    local stock = tab:GetHighlightTexture()
    if stock then stock:SetTexture(nil) end
    local l, r = _G[name .. "Left"], _G[name .. "Right"]
    if l and r then
        local west = glowPiece(tab, sheet, 0.015625, 0.5625, 0.816406, 0.933594)
        west:SetWidth(35)
        west:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
        local east = glowPiece(tab, sheet, 0.015625, 0.59375, 0.667969, 0.785156)
        east:SetWidth(37)
        east:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
        local between = glowPiece(tab, sheet, 0, 0.015625, 0.175781, 0.292969)
        between:SetPoint("TOPLEFT", west, "TOPRIGHT", 0, 0)
        between:SetPoint("TOPRIGHT", east, "TOPLEFT", 0, 0)
        tab._dscGlow = { west, between, east }
    end
    local label = _G[name .. "Text"]
    tab._dscWidth = math.max(64, (label and label:GetStringWidth() or 0) + 24)
    tab._dscTab = true
    S.SyncTab(tab)
end

-- Blizzard draws the selected tab in its disabled state.
function S.SyncTab(tab)
    if not tab._dscTab then return end
    local active = not tab:IsEnabled()
    tab:SetDisabledFontObject(active and GameFontHighlightSmall or GameFontNormalSmall)
    tab:SetWidth(tab._dscWidth)
    local label = _G[tab:GetName() .. "Text"]
    if label then S.Place(label, "CENTER", tab, "CENTER", -2, active and -7 or 0) end
    for _, glow in ipairs(tab._dscGlow or {}) do
        glow:SetAlpha(active and 0 or GLOW_ALPHA)
    end
end

local tabHooked
function S.HookTabs()
    if tabHooked then return end
    tabHooked = true
    hooksecurefunc("PanelTemplates_SelectTab", S.SyncTab)
    hooksecurefunc("PanelTemplates_DeselectTab", S.SyncTab)
    hooksecurefunc("PanelTemplates_TabResize", function(tab) S.SyncTab(tab) end)
end

-- Bag-slot ring around a plain icon texture (rows that have no item button).
function S.IconRing(owner, icon)
    local size = icon:GetWidth()
    local slot = owner:CreateTexture(nil, "BACKGROUND", nil, 2)
    slot:SetTexture(S.Dir() .. "Bags\\bagsitemslot2x")
    slot:SetSize(size, size)
    slot:SetPoint("CENTER", icon, "CENTER", 0, 0)
    local ring = owner:CreateTexture(nil, "ARTWORK", nil, 2)
    ring:SetTexture(S.Dir() .. "UI\\ui-quickslot2")
    ring:SetSize(size * 64 / 37, size * 64 / 37)
    ring:SetPoint("CENTER", icon, "CENTER", 0, -size / 37)
    return ring
end

-- Flat dark box with a 1px edge, for small info panels.
function S.FlatBox(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0.35)
    frame:SetBackdropBorderColor(0, 0, 0, 0.9)
end

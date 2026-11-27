local _, NS = ...

-- ScootsCraft draws its whole window (ScootsCraft-MasterFrame, 838x438) on a child "front" frame, built on
-- first open and laid out with fixed offsets. The theme widens it a little so the three panels get gaps,
-- adds a footer strip, and moves the controls that sat in the old art's slots.
local Part = {}
NS.Register(Part)

local WIDTH, HEIGHT = 852, 456
local TOP, BOTTOM = -72, -420
local applied

local function sc()
    local SC = _G.ScootsCraft
    return SC and SC.frames and SC.interface and SC
end

-- The rightmost profession button is the one ScootsCraft anchors to the window; it goes left of
-- "Deposit resources" instead. Hooked per button because the swatch is rebuilt when professions change.
local function placeSkillButtons(SC)
    local f = SC.frames
    if not (f.skillButtons and f.depositButton) then return end
    for _, button in pairs(f.skillButtons) do
        if not button._dscSkill then
            button._dscSkill = true
            local function fix(self, _, rel)
                if rel == f.front and not self._dscPlacing then
                    self._dscPlacing = true
                    self:ClearAllPoints()
                    self:SetPoint("RIGHT", f.depositButton, "LEFT", -8, 0)
                    self._dscPlacing = nil
                end
            end
            hooksecurefunc(button, "SetPoint", fix)
            fix(button, button:GetPoint(1))
        end
    end
end

local function header(SC, m, front, S)
    local f = SC.frames
    local level = front:GetFrameLevel() + 20

    local t = f.title
    for _, key in ipairs({ "addonName", "version", "skillName" }) do
        if t[key] then t[key]:SetAlpha(0) end
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", m, "TOPLEFT", 58, 0)
    t:SetPoint("TOPRIGHT", m, "TOPRIGHT", -50, 0)
    t:SetHeight(20)
    local title = front:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", m, "TOP", 0, -5)
    local function setTitle()
        local skill = ((t.skillName and t.skillName:GetText()) or ""):gsub("^%s*%-%s*", "")
        title:SetText(skill ~= "" and skill or SC.title)
    end
    if t.skillName then hooksecurefunc(t.skillName, "SetText", setTitle) end
    setTitle()

    S.RedIcon(f.closeButton, "close")
    f.closeButton:SetFrameLevel(level)
    S.Place(f.closeButton, "TOPRIGHT", m, "TOPRIGHT", 1, 0)

    local cog = f.optionsButton
    S.Cog(cog)
    cog:SetFrameLevel(level)
    S.Place(cog, "TOPRIGHT", m, "TOPRIGHT", -26, -3)
    cog:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SC.title .. " options")
        GameTooltip:Show()
    end)
    cog:HookScript("OnLeave", GameTooltip_Hide)

    S.Button(f.depositButton)
    S.Place(f.depositButton, "TOPRIGHT", m, "TOPRIGHT", -10, -40)
    placeSkillButtons(SC)

    -- Category and slot dropdowns side by side right of the portrait.
    if f.sectionFilter then
        S.Place(f.sectionFilter, "TOPLEFT", front, "TOPLEFT", 60, -35)
        S.DropDown(f.sectionFilter, 110)
    end
    if f.invSlotFilter then
        S.DropDown(f.invSlotFilter, 110)
        -- Box to box, 6px apart (each box starts 7px into its dropdown frame).
        if f.sectionFilter and f.sectionFilter._dscRight then
            S.Place(f.invSlotFilter, "LEFT", f.sectionFilter._dscRight, "RIGHT", -1, 0)
        end
    end
end

local function filterPanel(SC, m, front, S)
    local f = SC.frames
    local inset = S.Inset(front)
    inset:SetPoint("TOPLEFT", m, "TOPLEFT", 8, TOP)
    inset:SetPoint("BOTTOMRIGHT", m, "TOPLEFT", 172, BOTTOM)

    local holder = f.filterHolder
    S.Place(holder, "TOPLEFT", front, "TOPLEFT", 14, TOP - 6)
    -- The "Search" caption above the box gives way to the in-box hint.
    S.SearchBox(f.searchFilter, SEARCH, f.searchFilter.label)

    for _, child in ipairs({ holder:GetChildren() }) do
        if child:GetObjectType() == "CheckButton" then
            S.Check(child, true)
            if child.label then child.label:SetFontObject(GameFontHighlightSmall) end
        end
    end
    -- Radio group headings in gold.
    for _, region in ipairs({ holder:GetRegions() }) do
        if region:GetObjectType() == "FontString" then region:SetFontObject(GameFontNormalSmall) end
    end
end

local function listPanels(SC, m, front, S)
    local f = SC.frames
    local UI = S.UI()

    local list = S.Inset(front)
    list:SetPoint("TOPLEFT", m, "TOPLEFT", 176, TOP)
    list:SetPoint("BOTTOMRIGHT", m, "TOPLEFT", 510, BOTTOM)
    S.Place(f.recipeFrame, "TOPLEFT", front, "TOPLEFT", 182, TOP - 6)

    local details = S.Inset(front)
    details:SetPoint("TOPLEFT", m, "TOPLEFT", 514, TOP)
    details:SetPoint("BOTTOMRIGHT", m, "TOPRIGHT", -6, BOTTOM)
    S.Place(f.craftItemScroller, "TOPLEFT", front, "TOPLEFT", 520, TOP - 6)
    if f.summaryFrame then S.Place(f.summaryFrame, "TOPLEFT", front, "TOPLEFT", 520, TOP - 6) end

    if UI and UI.SkinScrollBar then
        for _, scroller in ipairs({ f.recipeFrame, f.craftItemScroller, f.summaryFrame }) do
            if scroller then pcall(UI.SkinScrollBar, scroller) end
        end
    end
end

local function footer(SC, m, front, S)
    local f = SC.frames
    for _, button in ipairs({ f.summariseButton, f.summariseAllButton, f.createButton, f.createAllButton }) do
        if button then S.Button(button) end
    end
    S.Place(f.summariseButton, "BOTTOMLEFT", m, "BOTTOMLEFT", 12, 8)
    S.Place(f.createButton, "BOTTOMRIGHT", m, "BOTTOMRIGHT", -10, 8)
    if f.toggleAllSections then
        S.Place(f.toggleAllSections, "LEFT", m, "BOTTOMLEFT", 182, 19)
    end
    for _, check in pairs(front.forgeHelper or {}) do
        S.Check(check, true)
        local label = _G[check:GetName() .. "Text"]
        if label then label:SetFontObject(GameFontHighlightSmall) end
    end
end

local function apply()
    local SC = sc()
    local S = NS.Kit
    if applied or not SC or not SC.frames.front or not SC.frames.createButton or not _G.DragonUI_NineSlice then return end
    applied = true
    local f = SC.frames
    local m, front = f.master, f.front

    if UIPanelWindows[m:GetName()] then UIPanelWindows[m:GetName()].width = WIDTH end
    m:SetSize(WIDTH, HEIGHT)
    front:SetSize(WIDTH, HEIGHT)
    if front.background then front.background:SetAlpha(0) end
    S.NineSlice(m, "PortraitFrameTemplate")
    S.Rock(m)
    S.Streaks(m)
    if m.icon then
        m.icon:SetDrawLayer("ARTWORK")
        m.icon:SetSize(56, 56)
        S.Place(m.icon, "TOPLEFT", m, "TOPLEFT", -2, 4)
    end

    for _, step in ipairs({ header, filterPanel, listPanels, footer }) do
        local ok, err = pcall(step, SC, m, front, S)
        if not ok then NS.Report(err) end
    end
end

function Part.Init()
    if not NS.db.scootsCraft then return end
    local SC = sc()
    if not SC then return end
    hooksecurefunc(SC.interface, "build", function()
        local ok, err = pcall(apply)
        if not ok then NS.Report(err) end
    end)
    apply()
end

function Part.Check()
    if not NS.db.scootsCraft then return end
    local SC = sc()
    if not SC then return end
    if not applied then apply() end
    if applied then placeSkillButtons(SC) end
end

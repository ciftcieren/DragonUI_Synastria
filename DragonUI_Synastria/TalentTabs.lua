local _, NS = ...

-- Synastria's extra talent specs and multiclass trees in DragonUI's talent window.
--
-- The server gives up to 8 talent specs (Blizzard: 2) and, for multiclass characters, one talent set per
-- class (CMCSetSelectedTalents). It adds side tabs for both onto Blizzard's talent frame (container_24/25),
-- but DragonUI replaces that frame with its own window, which knows 2 specs and no classes, so those tabs
-- never show. Here DragonUI's window gets them back, in DragonUI's retail side-tab art:
--   right edge - one tab per spec (when there are more than 2), icon of its main tree; left click views it,
--                right click renames it (the server's own rename, saved on the server)
--   left edge  - one tab per class (multiclass only), class icon; click switches the talent trees shown
-- With more than 2 specs, DragonUI's two bottom spec tabs give way to the side tabs (its bottom tabs are
-- numbered spec 1, spec 2, pet, glyphs, so a third spec would light up "Pet").
local Part = {}
NS.Register(Part)

local TAB, GAP = 32, 17
local DEFAULT_ICON = "Interface\\Icons\\Ability_Marksmanship"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local ns, hooked
local specTabs, classTabs = {}, {}

local function enabled()
    return NS.db and NS.db.talentTabs ~= false
end

local function multiclass()
    return CMCGetClassCount and CMCIsDualSingleClass and (CMCGetClassCount() or 1) > 1 and not CMCIsDualSingleClass()
end

local function specCount()
    return ns.PlayerGroups() or 1
end

local function sideSpecs()
    return specCount() > 2
end

-- ---------------------------------------------------------------------------
-- Names: DragonUI's own rename wins, then the server's name, then a default
-- ---------------------------------------------------------------------------

local function serverName(group)
    local name = GetCustomGameDataString and GetCustomGameDataString(21, group)
    return type(name) == "string" and name ~= "" and name or nil
end

local function wrapSpecName()
    local original = ns.SpecName
    ns.SpecName = function(group)
        local char = NS.D.db and NS.D.db.char
        local own = char and char.talentSpecNames and char.talentSpecNames[group]
        if type(own) == "string" and own ~= "" then return own end
        local server = serverName(group)
        if server then return server end
        if group and group > 2 then return "Specialization " .. group end
        return original(group)
    end
    -- The equipment set pane and options read the name through this.
    NS.D.GetTalentSpecName = ns.SpecName
end

-- Icon of the tree with the most points in that spec.
local function specIcon(group)
    local best, icon = 0, nil
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        local _, tabIcon, points = GetTalentTabInfo(tab, false, false, group)
        if (points or 0) > best then best, icon = points, tabIcon end
    end
    return icon or DEFAULT_ICON
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------

local function makeTab(win, mirrored)
    local tab = CreateFrame("CheckButton", nil, win)
    tab:SetSize(TAB, TAB)
    tab:SetFrameLevel(win:GetFrameLevel() + 6)
    local border = tab:CreateTexture(nil, "BACKGROUND")
    border:SetTexture(NS.D._dir .. "UI\\sidetab")
    border:SetSize(64, 64)
    if mirrored then
        -- The left-hand tabs face the other way, as the server's class tabs do.
        border:SetTexCoord(1, 0, 0, 1)
        border:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 3, 11)
    else
        border:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 11)
    end
    tab:SetNormalTexture(DEFAULT_ICON)
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    tab:GetCheckedTexture():SetBlendMode("ADD")
    -- The active spec: a green glow round the icon.
    tab.active = tab:CreateTexture(nil, "OVERLAY")
    tab.active:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    tab.active:SetBlendMode("ADD")
    tab.active:SetVertexColor(0.2, 1, 0.2, 0.9)
    tab.active:SetSize(TAB * 1.8, TAB * 1.8)
    tab.active:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab.active:Hide()
    tab:SetScript("OnLeave", GameTooltip_Hide)
    return tab
end

local function leaveEditor()
    if ns.edit then
        ns.Call("RequestExitEditor")
        if ns.edit then return false end
    end
    return true
end

local function viewSpec(tab, button)
    local group = tab.group
    if button == "RightButton" then
        tab:SetChecked(tab.wasChecked)
        local dialog = StaticPopupDialogs.RENAME_DUALSPEC and StaticPopup_Show("RENAME_DUALSPEC")
        if dialog then dialog.arg1 = group end
        return
    end
    if not leaveEditor() then return tab:SetChecked(tab.wasChecked) end
    PlaySound("igCharacterInfoTab")
    ns.SetGlyphPage(false)
    ns.wantPet = false
    ns.viewGroup = group
    ns.Refresh()
end

local function specTooltip(tab)
    ns.SpecTooltip(tab, tab.group)
    GameTooltip:AddLine("Right-click to rename", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function switchClass(tab)
    if not leaveEditor() then return tab:SetChecked(tab.wasChecked) end
    PlaySound("igCharacterInfoTab")
    if GetSelectedTalentClassIndex and GetSelectedTalentClassIndex() == tab.index then
        return tab:SetChecked(1)
    end
    if CMCSetSelectedTalents and not CMCSetSelectedTalents(tab.index) then
        UIErrorsFrame:AddMessage(ERR_GENERIC_NO_TARGET or "Can't switch talents now", 1, 0.1, 0.1)
    end
    -- The trees change once the server answers.
    for _, delay in ipairs({ 0.2, 0.8 }) do
        NS.After(delay, function() if ns.win:IsShown() then ns.Refresh() end end)
    end
end

local function classTooltip(tab)
    GameTooltip:SetOwner(tab, "ANCHOR_LEFT")
    GameTooltip:SetText(tab.className or "", 1, 1, 1)
    GameTooltip:AddLine("Show this class's talents", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function specTab(index)
    local tab = specTabs[index]
    if tab then return tab end
    tab = makeTab(ns.win, false)
    tab.group = index
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tab:SetScript("PreClick", function(self) self.wasChecked = self:GetChecked() end)
    tab:SetScript("OnClick", viewSpec)
    tab:SetScript("OnEnter", specTooltip)
    if index == 1 then
        tab:SetPoint("TOPLEFT", ns.win, "TOPRIGHT", 0, -70)
    else
        tab:SetPoint("TOPLEFT", specTab(index - 1), "BOTTOMLEFT", 0, -GAP)
    end
    specTabs[index] = tab
    return tab
end

local function classTab(index)
    local tab = classTabs[index]
    if tab then return tab end
    tab = makeTab(ns.win, true)
    tab.index = index
    tab:SetScript("PreClick", function(self) self.wasChecked = self:GetChecked() end)
    tab:SetScript("OnClick", switchClass)
    tab:SetScript("OnEnter", classTooltip)
    if index == 1 then
        tab:SetPoint("TOPRIGHT", ns.win, "TOPLEFT", 0, -70)
    else
        tab:SetPoint("TOPRIGHT", classTab(index - 1), "BOTTOMRIGHT", 0, -GAP)
    end
    classTabs[index] = tab
    return tab
end

local function hideAll(list)
    for _, tab in pairs(list) do tab:Hide() end
end

local function bottomTab(index)
    return _G["DragonUI_TalentFrameTab" .. index]
end

-- After DragonUI redraws its own tabs.
local function update()
    if not ns.win then return end
    local show = enabled() and ns.inspectUnit == nil
    local viewingSpec = not ns.GlyphView() and not ns.PetView()

    -- Specs.
    if show and sideSpecs() then
        local count = math.min(8, specCount())
        local active = ns.ActiveGroup()
        for index = 1, count do
            local tab = specTab(index)
            tab:GetNormalTexture():SetTexture(specIcon(index))
            tab:GetNormalTexture():SetTexCoord(0.06, 0.94, 0.06, 0.94)
            tab:SetChecked(viewingSpec and ns.viewGroup == index and 1 or nil)
            if index == active then tab.active:Show() else tab.active:Hide() end
            tab:Show()
        end
        for index = count + 1, #specTabs do specTabs[index]:Hide() end
        -- The side tabs stand in for DragonUI's two bottom spec tabs.
        local first, second = bottomTab(1), bottomTab(2)
        if first and second then
            first:Hide()
            second:Hide()
            for index = 1, 4 do
                local b = bottomTab(index)
                if b and viewingSpec then PanelTemplates_DeselectTab(b) end
            end
            local relayout = bottomTab(3) and bottomTab(3)._duiRelayout
            if relayout then relayout() end
        end
    else
        hideAll(specTabs)
    end

    -- Classes.
    if show and multiclass() then
        local selected = GetSelectedTalentClassIndex and GetSelectedTalentClassIndex() or 1
        for index = 1, CMCGetClassCount() do
            local tab = classTab(index)
            local cl = CMCGetClassAt(index)
            local key = cl and CMCGetClassKey(cl)
            local coords = key and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[key]
            tab:GetNormalTexture():SetTexture(CLASS_SHEET)
            if coords then tab:GetNormalTexture():SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
            tab.className = cl and CMCGetClassName(cl) or ""
            tab:SetChecked(index == selected and 1 or nil)
            tab:Show()
        end
        for index = CMCGetClassCount() + 1, #classTabs do classTabs[index]:Hide() end
    else
        hideAll(classTabs)
    end
end

function NS.RefreshTalentTabs()
    if ns and ns.win and ns.win:IsShown() then ns.Refresh() end
    if ns then pcall(update) end
end

local function hook()
    local TM = NS.D and NS.D.TalentModule
    ns = TM and TM.ns
    if not (ns and ns.RefreshTabs and ns.SpecName and ns.PlayerGroups) then return end
    hooked = true
    wrapSpecName()
    hooksecurefunc(ns, "RefreshTabs", function()
        local ok, err = pcall(update)
        if not ok then NS.Report(err) end
    end)
    -- Talent points and the active spec move outside the window too; keep the tabs current.
    local events = CreateFrame("Frame")
    for _, e in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        events:RegisterEvent(e)
    end
    events:SetScript("OnEvent", function() pcall(update) end)
end

function Part.Check()
    if not hooked then hook() end
end

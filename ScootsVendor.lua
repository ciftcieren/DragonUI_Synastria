local _, NS = ...

-- ScootsVendor replaces the merchant window with its own (ScootsVendor-Master, 512 wide). Its window is
-- built on the first vendor visit and laid out once with fixed offsets, so the theme runs right after that
-- build. Only the tabs (re-anchored on every click) and AttuneHelper's buttons need pinning.
local Part = {}
NS.Register(Part)

local HEIGHT = 456      -- was 438; the extra room is the footer strip under the two panels
local TOP = -74         -- top of both panels, under the buyback box
local BOTTOM = -420     -- bottom of both panels
local applied

local function sv()
    local SV = _G.ScootsVendor
    return SV and SV.frames and SV.interface and SV
end

local function sidePanel(SV, m, S)
    local f = SV.frames
    local inset = S.Inset(m)
    inset:SetPoint("TOPLEFT", m, "TOPLEFT", 8, TOP)
    inset:SetPoint("BOTTOMRIGHT", m, "TOPLEFT", 170, BOTTOM)

    local search = f.searchFilter
    search:SetWidth(120)
    S.Place(search, "TOPLEFT", m, "TOPLEFT", 18, -82)
    S.SearchBox(search, SEARCH, search.label)

    for _, child in ipairs({ m:GetChildren() }) do
        if child:GetObjectType() == "CheckButton" then
            S.Check(child, true)
            local label = child:GetName() and _G[child:GetName() .. "Text"]
            if label then label:SetFontObject(GameFontHighlightSmall) end
        end
    end
    -- Group headings ("Show attuneable equipment", ...) in gold, like DragonUI's section titles.
    for _, region in ipairs({ m:GetRegions() }) do
        if region:GetObjectType() == "FontString" and (region:GetText() or ""):find("^Show ") then
            region:SetFontObject(GameFontNormalSmall)
        end
    end

    local dd = f.autoForgeLevel
    if dd then
        local p, rel, rp, x, y = dd:GetPoint(1)
        if p then
            dd:ClearAllPoints()
            dd:SetPoint(p, rel, rp, x + 8, y)
        end
        S.DropDown(dd, 110)
        local button = _G[dd:GetName() .. "Button"]
        if button then button:SetHitRectInsets(-112, 0, 0, 0) end
    end
end

local function itemPanel(SV, m, S)
    local f = SV.frames
    local inset = S.Inset(m)
    inset:SetPoint("TOPLEFT", m, "TOPLEFT", 174, TOP)
    inset:SetPoint("BOTTOMRIGHT", m, "TOPRIGHT", -6, BOTTOM)

    S.Place(f.itemList, "TOPLEFT", m, "TOPLEFT", 180, -80)
    local UI = S.UI()
    if UI and UI.SkinScrollBar then pcall(UI.SkinScrollBar, f.itemList) end

    for _, row in ipairs(f.items or {}) do
        if row.icon and not row._dscRing then
            row._dscRing = S.IconRing(row, row.icon)
        end
    end
end

local function header(SV, m, S)
    local f = SV.frames
    local level = m:GetFrameLevel() + 20

    -- Title: the vendor's name centred in the top band (Scoots writes "- Name" into its own line).
    local t = f.title
    for _, key in ipairs({ "addonName", "version", "vendorName" }) do
        if t[key] then t[key]:SetAlpha(0) end
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", m, "TOPLEFT", 58, 0)
    t:SetPoint("TOPRIGHT", m, "TOPRIGHT", -50, 0)
    t:SetHeight(20)
    local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", m, "TOP", 0, -5)
    local function setTitle()
        local name = ((t.vendorName and t.vendorName:GetText()) or ""):gsub("^%-%s*", "")
        title:SetText(name ~= "" and name or SV.title)
    end
    if t.vendorName then hooksecurefunc(t.vendorName, "SetText", setTitle) end
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
        GameTooltip:SetText(SV.title .. " options")
        GameTooltip:Show()
    end)
    cog:HookScript("OnLeave", GameTooltip_Hide)

    S.FlatBox(f.quickBuyback)

    S.Button(f.autoSellButton)
    S.Place(f.autoSellButton, "TOPRIGHT", m, "TOPRIGHT", -10, -40)
end

local function footer(SV, m, S)
    local f = SV.frames
    S.Button(f.totalCost)
    S.Place(f.totalCost, "BOTTOMRIGHT", m, "BOTTOMRIGHT", -10, 8)
    S.Place(f.playerCurrencies, "LEFT", m, "BOTTOMLEFT", 14, 19)
    if m.showingTotal then
        S.Place(m.showingTotal, "RIGHT", f.totalCost, "LEFT", -10, 0)
    end

    S.HookTabs()
    S.Tab(f.switchToPurchase)
    S.Tab(f.switchToBuyback)
    S.Pin(f.switchToPurchase, { { "TOPLEFT", m, "BOTTOMLEFT", 11, 2 } })
    S.Pin(f.switchToBuyback, { { "TOPLEFT", f.switchToPurchase, "TOPRIGHT", 1, 0 } })
end

local function apply()
    local SV = sv()
    local S = NS.Kit
    if applied or not SV or not SV.interface.built or not _G.DragonUI_NineSlice then return end
    applied = true
    local m = SV.frames.master

    m:SetHeight(HEIGHT)
    if m.background then m.background:SetAlpha(0) end
    S.NineSlice(m, "PortraitFrameTemplate")
    S.Rock(m)
    S.Streaks(m)
    if m.portrait then
        m.portrait:SetDrawLayer("ARTWORK")
        m.portrait:SetSize(56, 56)
        S.Place(m.portrait, "TOPLEFT", m, "TOPLEFT", -2, 4)
    end

    for _, step in ipairs({ header, sidePanel, itemPanel, footer }) do
        local ok, err = pcall(step, SV, m, S)
        if not ok then NS.Report(err) end
    end
end

-- AttuneHelper hangs its "vendor attuned" buttons under ScootsVendor's close button; with the slimmer
-- DragonUI close button they'd sit on the title band, so they go left of Auto-sell instead.
local function placeAttuneHelper()
    local SV = sv()
    local button = _G.AttuneHelperScootsVendorButton
    if not (applied and SV and button) or button._dscPoints then return end
    NS.Kit.Pin(button, { { "RIGHT", SV.frames.autoSellButton, "LEFT", -6, 0 } })
end

function Part.Init()
    if not NS.db.scootsVendor then return end
    local SV = sv()
    if not SV then return end
    hooksecurefunc(SV.interface, "build", function()
        local ok, err = pcall(apply)
        if not ok then NS.Report(err) end
    end)
    apply()
end

function Part.Check()
    if not NS.db.scootsVendor then return end
    if not applied then apply() end
    placeAttuneHelper()
end

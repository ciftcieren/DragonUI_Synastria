local _, NS = ...

-- A "Synastria" tab in DragonUI's settings window. DragonUI_Options loads on demand, so the tab is
-- registered when it loads. Skins can't be taken off a live frame, so those switches are staged through
-- DragonUI's own reload prompt (like its reload-only settings); the others apply at once.

local staged = {}

local function stagedValue(key)
    if staged[key] ~= nil then return staged[key] end
    return NS.db[key]
end

local function stage(key, value)
    local Reload = NS.D.Reload
    value = value and true or false
    if not Reload then
        NS.db[key] = value
        return
    end
    if value == (NS.db[key] and true or false) then
        staged[key] = nil
        Reload.UnstageAction("dsyn:" .. key)
    else
        staged[key] = value
        Reload.StageAction("dsyn:" .. key, function() NS.db[key] = value end)
    end
end

-- "loaded", or why not: "missing" (not installed) / "disabled" (installed, switched off in the addon list).
local function addonState(name)
    if IsAddOnLoaded(name) then return "loaded" end
    local ok, found, _, _, enabled = pcall(GetAddOnInfo, name)
    if not ok or not found then return "missing" end
    return enabled and "loaded" or "disabled"
end

local function missingNote(name, state)
    if state == "missing" then return "|cffff5555" .. name .. " is not installed.|r" end
    return "|cffff5555" .. name .. " is disabled in the addon list.|r"
end

-- A reload-only switch for one saved key. With `needs` (an addon), it's greyed out and shown off while
-- that addon isn't loaded.
local function reloadToggle(C, parent, key, label, needs)
    local state = needs and addonState(needs) or "loaded"
    local unavailable = state ~= "loaded"
    C:AddToggle(parent, {
        label = label,
        desc = unavailable and missingNote(needs, state) or nil,
        getFunc = function() return not unavailable and stagedValue(key) and true or false end,
        setFunc = function(value) stage(key, value) end,
        disabled = unavailable,
    })
end

-- A live switch for one saved key (on unless switched off); `refresh` runs after a change.
local function liveToggle(C, parent, key, label, refresh, needs)
    local state = needs and addonState(needs) or "loaded"
    local unavailable = state ~= "loaded"
    C:AddToggle(parent, {
        label = label,
        desc = unavailable and missingNote(needs, state) or nil,
        getFunc = function() return not unavailable and NS.db[key] ~= false end,
        setFunc = function(value)
            NS.db[key] = value and true or false
            local fn = type(refresh) == "string" and NS[refresh] or refresh
            if type(fn) == "function" then fn() end
        end,
        disabled = unavailable,
    })
end

local function build(scroll)
    local C = NS.D.PanelControls
    if not (C and NS.db) then return end

    local server = C:AddSection(scroll, "Synastria windows")
    C:AddDescription(server, "Changes here apply after a reload.")
    reloadToggle(C, server, "serverWindows", "Server windows")
    reloadToggle(C, server, "attuneBarSkin", "Attune Bar")
    reloadToggle(C, server, "finderSkin", "Finder (Tracking)")
    reloadToggle(C, server, "itemHunt", "Item Hunt")

    local stats = C:AddSection(scroll, "Character stats")
    for _, group in ipairs(NS.CharStatGroups or {}) do
        C:AddToggle(stats, {
            label = group.label,
            getFunc = function() return NS.GetCharStat(group.key) end,
            setFunc = function(value) NS.SetCharStat(group.key, value) end,
        })
    end

    local tracker = C:AddSection(scroll, "Quest tracker")
    liveToggle(C, tracker, "questLogMap", "Quest log opens the map")
    liveToggle(C, tracker, "trackPerks", "Track Synastria perks", "RefreshPerks")
    liveToggle(C, tracker, "trackerGroups", "Tracker sections", "RefreshTrackerGroups")
    liveToggle(C, tracker, "trackerScroll", "Scrollable tracker", "RefreshTrackerScroll")
    C:AddDropdown(tracker, {
        label = "Group perks by",
        values = { zone = "Zone", type = "Perk type" },
        getFunc = function() return NS.db.perkGrouping or "zone" end,
        setFunc = function(value)
            NS.db.perkGrouping = value
            if NS.RefreshTrackerGroups then NS.RefreshTrackerGroups() end
        end,
        disabled = function() return NS.db.trackerGroups == false end,
    })

    local bags = C:AddSection(scroll, "Bags")
    liveToggle(C, bags, "bagAttuneBars", "Attune bars on items", function()
        if NS.Attune and NS.Attune.RefreshAll then NS.Attune.RefreshAll() end
    end)
    local noBagster = not (NS.D.BagsterModule and NS.D.BagsterModule.DB and NS.D.BagsterModule.DB.inventory)
    liveToggle(C, bags, "bagsterButtons", "Bagster buttons", "RefreshBagsterButtons")
    if noBagster then
        C:AddDescription(bags, "Bagster tabs: turn on Bagster in DragonUI's Bags settings to use them.")
    end
    for _, window in ipairs({ { "inventory", "Inventory" }, { "bank", "Bank" } }) do
        for _, name in ipairs(NS.BagsterTabs or {}) do
            C:AddToggle(bags, {
                label = window[2] .. ": " .. name .. " tab",
                relWidth = 0.5,
                getFunc = function() return NS.HasBagsterTab(window[1], name) end,
                setFunc = function(value) NS.SetBagsterTab(window[1], name, value) end,
                disabled = noBagster,
            })
        end
    end

    local extras = C:AddSection(scroll, "Synastria extras")
    liveToggle(C, extras, "attuneToasts", "Attune toast", "RefreshAttuneToast")
    liveToggle(C, extras, "talentTabs", "Talent specs and classes", "RefreshTalentTabs")
    reloadToggle(C, extras, "stanceExtra", "Stance buttons 11-20")
    reloadToggle(C, extras, "bossExtra", "Boss frames 5-8")

    local compat = C:AddSection(scroll, "Addon compatibility")
    liveToggle(C, compat, "companionSkin", "SynastriaCompanion theme", nil, "SynastriaCompanion")
    liveToggle(C, compat, "buildSuiteSkin", "Synastria Build Suite theme", nil, "SynastriaBuildSuite")
    liveToggle(C, compat, "rotationAssistSkin", "Rotation Assist theme", nil, "RotationAssist")
    reloadToggle(C, compat, "scootsVendor", "ScootsVendor", "ScootsVendor")
    reloadToggle(C, compat, "scootsCraft", "ScootsCraft", "ScootsCraft")
    liveToggle(C, compat, "spbBars", "ScootsProgressBar bars", "ApplyProgressBars", "ScootsProgressBar")
end

local registered
local function register()
    local Panel = NS.D and NS.D.OptionsPanel
    if registered or not (Panel and Panel.RegisterTab) then return end
    registered = true
    Panel:RegisterTab("synastria", "Synastria", build, 50)
    if NS.D.Reload and NS.D.Reload.OnDiscard then
        NS.D.Reload.OnDiscard(function() wipe(staged) end)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, name)
    if name == "DragonUI_Options" then register() end
end)
if IsAddOnLoaded("DragonUI_Options") then register() end

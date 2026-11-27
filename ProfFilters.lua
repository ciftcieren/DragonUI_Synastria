local _, NS = ...

-- Puts the server's profession filter menu (ProffFilterExpand -> DropDownList1) inside DragonUI's Filter menu.
-- Nothing is reimplemented: the server menu is opened unseen to read its entries, and a pick clicks the server's own
-- menu button, so the server's code still does the filtering. Both happen inside one frame, so nothing ever draws.
local BUTTON = "ProffFilterExpand"

local Part = {}
NS.Register(Part)

local P, F
local states = {}        -- [path] = checked, from the last read of the server menu
local hiddenButton

local function serverButton()
    return _G[BUTTON]
end

local function isEnabled(button)
    local on = button:IsEnabled()
    return on and on ~= 0
end

local function openServerMenu()
    local button = serverButton()
    if not button or not isEnabled(button) then return false end
    CloseDropDownMenus()
    button:Click("LeftButton")
    return DropDownList1:IsShown()
end

local function listButtons(level)
    local list = _G["DropDownList" .. level]
    local out = {}
    if not (list and list:IsShown()) then return out end
    for i = 1, (list.numButtons or 0) do
        local button = _G["DropDownList" .. level .. "Button" .. i]
        if button and button:IsShown() then out[#out + 1] = button end
    end
    return out
end

local function openSubmenu(button)
    ToggleDropDownMenu(2, button.value, nil, nil, nil, nil, button.menuList, button)
end

local function readButton(button, parentText)
    local checked = button.checked
    if type(checked) == "function" then checked = checked() end
    local text = button:GetText() or ""
    return {
        text = text,
        path = parentText and (parentText .. "\001" .. text) or text,
        checked = checked and true or false,
        checkable = not button.notCheckable,
        hasArrow = button.hasArrow and true or false,
        isTitle = not isEnabled(button) and not button.func and not button.hasArrow,
        disabled = not isEnabled(button),
    }
end

-- Returns the server menu as a tree and refreshes `states`; nil when the server button is missing.
local function snapshot()
    if not openServerMenu() then
        CloseDropDownMenus()
        return nil
    end
    local tree = {}
    for _, button in ipairs(listButtons(1)) do
        local item = readButton(button)
        if item.hasArrow then
            openSubmenu(button)
            item.children = {}
            for _, sub in ipairs(listButtons(2)) do
                item.children[#item.children + 1] = readButton(sub, item.text)
            end
            HideDropDownMenu(2)
        end
        tree[#tree + 1] = item
    end
    CloseDropDownMenus()

    wipe(states)
    for _, item in ipairs(tree) do
        if item.checkable then states[item.path] = item.checked end
        for _, sub in ipairs(item.children or {}) do
            if sub.checkable then states[sub.path] = sub.checked end
        end
    end
    return tree
end

local function findButton(level, text)
    for _, button in ipairs(listButtons(level)) do
        if button:GetText() == text then return button end
    end
end

local function afterChange()
    snapshot()
    if P then P.Fire("FiltersChanged") end
    if NS.D and NS.D.Menu and NS.D.Menu.Refresh then NS.D.Menu.Refresh() end
end

-- Clicks the server's real menu entry: parentText is set for entries in a submenu.
local function clickServer(text, parentText)
    if not openServerMenu() then return CloseDropDownMenus() end
    local button
    if parentText then
        local parent = findButton(1, parentText)
        if parent then
            openSubmenu(parent)
            button = findButton(2, text)
        end
    else
        button = findButton(1, text)
    end
    if button then button:Click("LeftButton") end
    CloseDropDownMenus()
    afterChange()
end

local function toEntry(item, parentText)
    if item.isTitle then
        return { text = item.text, isTitle = true }
    end
    local entry = { text = item.text, disabled = item.disabled }
    if item.hasArrow then
        local children = item.children or {}
        entry.menu = function()
            local list = {}
            for _, sub in ipairs(children) do list[#list + 1] = toEntry(sub, item.text) end
            return list
        end
        return entry
    end
    entry.func = function() clickServer(item.text, parentText) end
    if item.checkable then
        local path = item.path
        entry.checked = function() return states[path] end
        entry.keepShown = true
    end
    return entry
end

local function anyServerFilter()
    for _, on in pairs(states) do
        if on then return true end
    end
    return false
end

local function clearServerFilters(tree)
    for _, item in ipairs(tree or {}) do
        if not item.checkable and not item.hasArrow and item.text:lower():find("clear all") then
            return clickServer(item.text)
        end
    end
    -- No "Clear all" entry: untick each checked one.
    for _, item in ipairs(tree or {}) do
        if item.checkable and item.checked then clickServer(item.text) end
        for _, sub in ipairs(item.children or {}) do
            if sub.checkable and sub.checked then clickServer(sub.text, item.text) end
        end
    end
end

local function wrapFilters()
    local originalEntries, originalActive, originalReset = F.MenuEntries, F.IsActive, F.Reset

    F.MenuEntries = function()
        local entries = originalEntries()
        local tree = snapshot()
        if not tree or #tree == 0 then return entries end
        local insertAt = #entries + 1
        for i = #entries, 1, -1 do
            if entries[i].isDivider then insertAt = i break end
        end
        local extra = { { isDivider = true }, { text = "Synastria", isTitle = true } }
        for _, item in ipairs(tree) do extra[#extra + 1] = toEntry(item) end
        for i, entry in ipairs(extra) do table.insert(entries, insertAt + i - 1, entry) end
        return entries
    end

    F.IsActive = function()
        return originalActive() or anyServerFilter() or false
    end

    F.Reset = function()
        originalReset()
        if anyServerFilter() then clearServerFilters(snapshot()) end
    end

    -- Keep the reset "x" honest from the moment the window opens.
    local function refreshStates()
        pcall(snapshot)
    end
    P.On("Show", function()
        pcall(Part.Check)
        refreshStates()
    end)
    P.On("ProfessionChanged", refreshStates)
end

function Part.Init()
    P = NS.D and NS.D.Professions
    F = P and P.Filters
    if F and F.MenuEntries and P.On then wrapFilters() end
end

-- The server's own button is only hidden while DragonUI's window (and its Filter menu) is the one in use.
function Part.Check()
    local button = serverButton()
    if not button then return end
    local hide = F ~= nil and P.active
    if hide and (hiddenButton ~= button or button:GetAlpha() > 0) then
        button:SetAlpha(0)
        button:EnableMouse(false)
        hiddenButton = button
        if not button._dsynHooked then
            button._dsynHooked = true
            button:HookScript("OnShow", function(self)
                if hiddenButton == self then self:SetAlpha(0) self:EnableMouse(false) end
            end)
        end
    elseif not hide and hiddenButton == button then
        button:SetAlpha(1)
        button:EnableMouse(true)
        hiddenButton = nil
    end
end

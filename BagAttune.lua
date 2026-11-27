local _, NS = ...

-- Attune progress bars on item buttons, drawn the way OmniInventory's Synastria build draws them: a bar
-- up the left edge, as tall as the attune progress, coloured by forge level (green / blue titanforged /
-- red warforged / yellow lightforged) or pink-red when only another character can attune the item.
--
-- The server already puts its own attune bar on bag, bank, character panel and guild bank buttons
-- (ShowAttuneTex / HideAttuneTex, container_31), following its own settings: bars off, and whether items
-- only an alt can attune count. The server keeps deciding when a bar shows; this part only changes how:
-- the server's bar is hidden and ours drawn in its place, so there is one bar per item and the server's
-- options still apply. Bagster's buttons are DragonUI's own, which the server never sees, so they get the
-- same bar here, by the same rules. Also holds the attune/bind checks Bagster's tabs use.
local Part = {}
NS.Register(Part)

local A = {}
NS.Attune = A

local FORGE_COLORS = {
    [0] = { 0.000, 1.000, 0.000 },
    [1] = { 0.468, 0.532, 1.000 },
    [2] = { 0.872, 0.206, 0.145 },
    [3] = { 1.000, 1.000, 0.506 },
}
local OTHER_COLOR = { 1.000, 0.267, 0.392 }
local MIN_H, MAX_H = 0.10, 0.92

-- Bits of the server's item-button options (GetCustomGameData(25, 1)).
local OPT_NO_BARS, OPT_ACCOUNT = 1, 4

-- ---------------------------------------------------------------------------
-- Attune checks (same calls OmniInventory uses)
-- ---------------------------------------------------------------------------

function A.ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

function A.ForCharacter(id)
    return id and CanAttuneItemHelper and CanAttuneItemHelper(id) >= 1 or false
end

function A.ForAccount(id)
    if not id then return false end
    if IsAttunableBySomeone then
        local check = IsAttunableBySomeone(id)
        return check ~= nil and check ~= 0 and check ~= false
    end
    if GetItemTagsCustom then
        local tags = GetItemTagsCustom(id)
        return tags ~= nil and bit.band(tags, 96) == 64
    end
    return false
end

function A.Progress(link)
    local value = link and GetItemLinkAttuneProgress and GetItemLinkAttuneProgress(link)
    return type(value) == "number" and value or 0
end

function A.Forge(link)
    local value = link and GetItemLinkTitanforge and GetItemLinkTitanforge(link)
    return FORGE_COLORS[value] and value or 0
end

-- Lua container/slot -> the server's own bag/slot numbers that Custom_IsItemSoulbound expects.
local NATIVE_BAG = { [0] = 0xFF, [1] = 0x13, [2] = 0x14, [3] = 0x15, [4] = 0x16, [-1] = 0xFF, [-2] = 0xFF,
    [5] = 0x43, [6] = 0x44, [7] = 0x45, [8] = 0x46, [9] = 0x47, [10] = 0x48, [11] = 0x49 }

local function tooltipBound(bag, slot)
    local scanTip = NS.ScanTip()
    if bag == -1 then
        scanTip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
    else
        scanTip:SetBagItem(bag, slot)
    end
    for i = 2, math.min(6, scanTip:NumLines()) do
        local line = _G["DragonUISynastriaScanTipTextLeft" .. i]
        local text = line and line:GetText()
        if text == ITEM_SOULBOUND or text == ITEM_BIND_ON_PICKUP or text == ITEM_ACCOUNTBOUND then
            return true
        end
    end
    return false
end

-- true / false, or nil when it can't be told (an item that isn't live in this character's bags).
function A.Soulbound(bag, slot)
    if not (bag and slot) then return nil end
    local native = NATIVE_BAG[bag]
    if native and Custom_IsItemSoulbound then
        local nativeSlot
        if bag == 0 then nativeSlot = 23 + slot - 1
        elseif bag == -1 then nativeSlot = 39 + slot - 1
        elseif bag == -2 then nativeSlot = 86 + slot - 1
        else nativeSlot = slot - 1 end
        return Custom_IsItemSoulbound(native, nativeSlot) == 1
    end
    if not GetContainerItemLink(bag, slot) then return nil end
    return tooltipBound(bag, slot)
end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------

local function enabled()
    return NS.db and NS.db.bagAttuneBars ~= false
end

local function serverOptions()
    return GetCustomGameData and GetCustomGameData(25, 1) or 0
end

local function hideBar(button)
    if button._dsynAttune then button._dsynAttune:Hide() end
end

-- progress 0-100; forge 0-3; other = only another character can attune it.
local function drawBar(button, progress, forge, other)
    local bar = button._dsynAttune
    if not bar then
        bar = button:CreateTexture(nil, "OVERLAY", nil, 6)
        bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        button._dsynAttune = bar
    end
    local size = math.min(button:GetWidth() or 37, button:GetHeight() or 37)
    if size <= 0 then size = 37 end
    local inset = math.max(1, math.floor(size * 0.06 + 0.5))
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", inset, inset)
    bar:SetWidth(math.max(3, math.floor(size * 0.16 + 0.5)))
    bar:SetHeight(size * (MIN_H + math.max(0, math.min(100, progress)) / 100 * (MAX_H - MIN_H)))
    local color = other and OTHER_COLOR or FORGE_COLORS[forge] or FORGE_COLORS[0]
    bar:SetVertexColor(color[1], color[2], color[3], 1)
    bar:Show()
end

-- ---------------------------------------------------------------------------
-- The server's bar (bags, bank, character panel, guild bank): its timing, our look
-- ---------------------------------------------------------------------------

local function serverParts(button)
    local name = button and button:GetName()
    if not name then return end
    return _G[name .. "AttTexFg"], _G[name .. "AttTexBg"]
end

local function setServerAlpha(button, alpha)
    local fg, bg = serverParts(button)
    if fg then fg:SetAlpha(alpha) end
    if bg then bg:SetAlpha(alpha) end
end

-- After ShowAttuneTex(button, pct, tf): tf is the forge level, or -1 when only an alt can attune it.
local function onServerShow(button, pct, tf)
    if not button then return end
    if not enabled() then
        setServerAlpha(button, 1)
        return hideBar(button)
    end
    setServerAlpha(button, 0)
    drawBar(button, tonumber(pct) or 0, tf, tf == -1)
end

local function onServerHide(button)
    if button then hideBar(button) end
end

-- The server defines both functions when its UI arrives after login; hooked once they exist (and again
-- if it ever replaces them).
local hookedShow, hookedHide
local function hookServer()
    local changed
    if type(_G.ShowAttuneTex) == "function" and _G.ShowAttuneTex ~= hookedShow then
        hooksecurefunc("ShowAttuneTex", function(...)
            local ok, err = pcall(onServerShow, ...)
            if not ok then NS.Report(err) end
        end)
        hookedShow = _G.ShowAttuneTex
        changed = true
    end
    if type(_G.HideAttuneTex) == "function" and _G.HideAttuneTex ~= hookedHide then
        hooksecurefunc("HideAttuneTex", function(button) pcall(onServerHide, button) end)
        hookedHide = _G.HideAttuneTex
        changed = true
    end
    return changed
end

-- ---------------------------------------------------------------------------
-- Bagster: the server's rule, applied here
-- ---------------------------------------------------------------------------

-- Mirrors the server's Custom_UpdateItemButton: no bars when its option says so; bars for items this
-- character can attune, or (option on) unbound items only an alt can attune; none once fully attuned.
local function paintBagster(slot, link)
    if not (enabled() and link) then return hideBar(slot) end
    local options = serverOptions()
    if bit.band(options, OPT_NO_BARS) ~= 0 then return hideBar(slot) end
    local id = A.ItemID(link)
    local attunable = id and CanAttuneItemHelper and CanAttuneItemHelper(id, true) or -1
    local other = false
    if attunable <= 0 then
        if attunable < 0 or bit.band(options, OPT_ACCOUNT) == 0 then return hideBar(slot) end
        -- Only the character's own live bags can be checked for binding; a cached alt's can't.
        if slot.IsCached and slot:IsCached() then return hideBar(slot) end
        if A.Soulbound(slot:GetBag(), slot:GetID()) ~= false then return hideBar(slot) end
        other = true
    end
    local progress = A.Progress(link)
    if progress >= 100 then return hideBar(slot) end
    drawBar(slot, progress, A.Forge(link), other)
end

local bagsterHooked
local function hookBagster()
    local mod = NS.D and NS.D.BagsterModule
    local slot = mod and mod.ItemSlot
    if bagsterHooked or not (slot and slot.Update) then return end
    bagsterHooked = true
    local update = slot.Update
    slot.Update = function(self, ...)
        update(self, ...)
        local ok, err = pcall(paintBagster, self, self:GetItem())
        if not ok then NS.Report(err) end
    end
end

-- ---------------------------------------------------------------------------

local function refreshBagster()
    if NS.D.RefreshBagsterFrames and bagsterHooked then pcall(NS.D.RefreshBagsterFrames) end
end

-- Redraw everything: when the setting is flipped or the server hooks are first in place. The server
-- re-runs its own buttons (which comes back through the hooks above); Bagster redraws its slots.
function A.RefreshAll()
    if type(_G.Custom_UpdateItemButtons) == "function" then pcall(_G.Custom_UpdateItemButtons) end
    -- Turned off: the server's bars come back on every button it has drawn one on.
    if not enabled() and type(_G._citemhighlightall) == "table" then
        for _, entry in ipairs(_G._citemhighlightall) do
            if entry.btn then
                setServerAlpha(entry.btn, 1)
                hideBar(entry.btn)
            end
        end
    end
    refreshBagster()
end

-- Attune progress moved: the server updates its own buttons; Bagster's need a redraw.
local pending
local function refreshSoon()
    if pending then return end
    pending = true
    NS.After(0.3, function()
        pending = nil
        refreshBagster()
    end)
end

-- The server's event system arrives with its UI after login, so this waits until it exists.
local eventsRegistered
local function registerEvents()
    if eventsRegistered or not RegisterForCustomEvent then return end
    eventsRegistered = true
    for _, e in ipairs({ "SYNASTRIA_ITEM_ATTUNE_PCT_CHANGED", "SYNASTRIA_ITEM_ATTUNED" }) do
        pcall(RegisterForCustomEvent, e, refreshSoon)
    end
end

function Part.Init()
    hookBagster()
    registerEvents()
    if hookServer() then A.RefreshAll() end
end

function Part.Check()
    if not bagsterHooked then hookBagster() end
    registerEvents()
    if hookServer() then A.RefreshAll() end
end

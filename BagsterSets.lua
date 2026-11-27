local _, NS = ...

-- Extra Bagster side tabs (inventory and bank), like OmniInventory's Synastria categories:
--   Attunable  - items still to attune: All / Character (this character can) / Account (only an alt can)
--   BoE        - unbound equipment: All / Attunable (someone on the account can attune it)
-- Bagster's set rules get the item but not its bag slot, which the bind check needs, so the slot being
-- tested is noted when Bagster asks whether a slot belongs in the grid. The tabs are added to the
-- inventory and bank tab lists once; after that they're managed from the Synastria settings tab.
local Part = {}
NS.Register(Part)

local SET_ALL = ALL or "All"
local ATTUNABLE, BOE = "Attunable", "BoE"
local ICONS = {
    [ATTUNABLE] = [[Interface\Icons\INV_Enchant_EssenceMagicLarge]],
    [BOE] = [[Interface\Icons\INV_Misc_Bag_10_Blue]],
}
NS.BagsterTabs = { ATTUNABLE, BOE }

local A
local current = { bag = nil, slot = nil, live = false }
local registered

local function mod()
    return NS.D and NS.D.BagsterModule
end

local function isEquipment(equipLoc)
    return equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" and equipLoc ~= "INVTYPE_QUIVER"
end

local function unfinished(link)
    return A.Progress(link) < 100
end

-- Rule arguments: player, bagType, name, link, quality, level, ilvl, itemType, subType, stackCount, equipLoc
local function attuneChar(_, _, _, link)
    local id = A.ItemID(link)
    return id and A.ForCharacter(id) and unfinished(link) or false
end

local function attuneAccount(_, _, _, link)
    local id = A.ItemID(link)
    return id and not A.ForCharacter(id) and A.ForAccount(id) and unfinished(link) or false
end

local function attuneAny(...)
    return attuneChar(...) or attuneAccount(...)
end

local function boe(_, _, _, link, _, _, _, _, _, _, equipLoc)
    if not (link and isEquipment(equipLoc)) then return false end
    -- Only the character's own live bags can be checked; a cached alt or offline bank can't.
    if not current.live then return false end
    return A.Soulbound(current.bag, current.slot) == false
end

local function boeAttunable(...)
    local link = select(4, ...)
    return boe(...) and A.ForAccount(A.ItemID(link)) or false
end

local function register()
    local m = mod()
    local Sets = m and m("Sets")
    if registered or not (Sets and Sets.Register and m.ItemFrame and m.ItemFrame.HasItem) then return end
    registered = true
    A = NS.Attune

    -- Note which slot is being tested, for the bind check.
    local hasItem = m.ItemFrame.HasItem
    m.ItemFrame.HasItem = function(self, bag, slot, ...)
        current.bag, current.slot = bag, slot
        current.live = self:GetPlayer() == m.playerName
        return hasItem(self, bag, slot, ...)
    end

    Sets:Register(ATTUNABLE, ICONS[ATTUNABLE], attuneAny)
    Sets:Register(SET_ALL, nil, nil, ATTUNABLE)
    Sets:Register("Character", nil, attuneChar, ATTUNABLE)
    Sets:Register("Account", nil, attuneAccount, ATTUNABLE)

    Sets:Register(BOE, ICONS[BOE], boe)
    Sets:Register(SET_ALL, nil, nil, BOE)
    Sets:Register(ATTUNABLE, nil, boeAttunable, BOE)
end

-- ---------------------------------------------------------------------------
-- Tab lists (Bagster keeps one per window in DragonUI's profile)
-- ---------------------------------------------------------------------------

local function lists()
    local m = mod()
    local db = m and m.DB
    return db and db.inventory and db.inventory.sets, db and db.bank and db.bank.sets
end

local function listFor(key)
    local inventory, bank = lists()
    return key == "bank" and bank or inventory
end

function NS.HasBagsterTab(key, name)
    local list = listFor(key)
    if not list then return false end
    for _, s in ipairs(list) do if s == name then return true end end
    return false
end

function NS.SetBagsterTab(key, name, on)
    local list = listFor(key)
    if not list then return end
    for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
    if on then table.insert(list, name) end
    if NS.D.RefreshBagsterFrames then pcall(NS.D.RefreshBagsterFrames) end
end

-- Once per tab and window. A window with no tabs at all is left alone: its first tab would become the
-- default view, and a bag that opens on "Attunable" only would look empty.
local function addOnce()
    local inventory, bank = lists()
    if not inventory then return false end
    NS.db.bagsterTabsAdded = NS.db.bagsterTabsAdded or {}
    local added = NS.db.bagsterTabsAdded
    local changed
    for key, list in pairs({ inventory = inventory, bank = bank }) do
        for _, name in ipairs(NS.BagsterTabs) do
            local flag = key .. ":" .. name
            if not added[flag] and #list > 0 then
                added[flag] = true
                if not NS.HasBagsterTab(key, name) then
                    table.insert(list, name)
                    changed = true
                end
            end
        end
    end
    if changed and NS.D.RefreshBagsterFrames then pcall(NS.D.RefreshBagsterFrames) end
    return true
end

local done
function Part.Init()
    if NS.db.bagsterTabs == false then return end
    register()
end

function Part.Check()
    if NS.db.bagsterTabs == false or done then return end
    if not registered then register() end
    if registered and addOnce() then done = true end
end

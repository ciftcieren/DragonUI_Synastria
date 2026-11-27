local _, NS = ...

-- A "Synastria" section at the end of DragonUI's character stats: movement speed, attunement progress and the
-- prestige numbers. Each group is ticked on/off in DragonUI's character settings cog (under Gear summary).
-- Formulas follow ScootsStats by Scoots (same Synastria server calls), so the numbers match it without needing it.
local Part = {}
NS.Register(Part)

local CP
local HEADER_H, ROW_H, ROW_INSET, SECTION_GAP = 40, 15, 2, 3
local SLOT_IDS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
local GROUPS = {
    { key = "speed", label = "Movement Speed" },
    { key = "attune", label = "Attunement" },
    { key = "prestige", label = "Prestige" },
}

local function enabled(key)
    return NS.db.charstats[key] ~= false
end

-- ---------------------------------------------------------------------------
-- Data (Synastria server API)
-- ---------------------------------------------------------------------------

local D = { dirty = true }

local function fmtItems(count, progress)
    if count == 0 then return "0 items" end
    return string.format("%d item%s (%d%%)", count, count ~= 1 and "s" or "", progress)
end

-- Expensive (walks every item id): once per session, on first show.
local function countTotals()
    if D.totals or not (MAX_ITEMID and GetItemTagsCustom and CanAttuneItemHelper) then return end
    D.totalChar, D.totalAcc = 0, 0
    for itemId = 1, MAX_ITEMID do
        local tags = GetItemTagsCustom(itemId)
        if tags and bit.band(tags, 96) == 64 then
            D.totalAcc = D.totalAcc + 1
            if CanAttuneItemHelper(itemId) > 0 then D.totalChar = D.totalChar + 1 end
        end
    end
    if CalculateAttunableAffixCount then D.totalAffixes = CalculateAttunableAffixCount() end
    D.totals = true
end

local function readPrestige()
    D.prestiged = false
    if not (CMCGetMultiClassEnabled and GetCustomGameData) then return end
    local mc = CMCGetMultiClassEnabled()
    if bit.band(mc, 0x7f) >= 2 or bit.band(mc, 0x80) ~= 0 then
        D.prestiged = true
        D.forgePower = GetCustomGameData(29, 1494) or 0
        D.bopCoercion = GetCustomGameData(29, 1492) or 0
        D.boeCoercion = GetCustomGameData(29, 1493) or 0
        D.attuneMastery = GetCustomGameData(29, 1500) or 0
        D.luckyLoot = GetCustomGameData(29, 1557) or 0
    end
end

local function countAttunes()
    if not (D.dirty and CalculateAttunedCount) then return end
    D.charAttunes = CalculateAttunedCount(1) or 0
    D.accAttunes = CalculateAttunedCount() or 0
    D.affixAttunes = CalculateAttunedAffixCount and CalculateAttunedAffixCount() or 0
    local _, tf, wf, lf = CalculateAttunedCount(2)
    D.tf, D.wf, D.lf = tf or 0, wf or 0, lf or 0
    if CalculateAttunedCountHigh then
        D.highLF, D.earnedMastery = CalculateAttunedCountHigh(2)
    end
    D.highLF, D.earnedMastery = D.highLF or 0, D.earnedMastery or 0
    D.dirty = false
end

local function pct(part, total)
    if not total or total == 0 then return 0 end
    return 100 / total * part
end

-- 1 - (1-a)(1-b): how two chances stack, as the server combines this cycle's coercion with the current one.
local function stack(a, b)
    return (1 - (1 - a / 100) * (1 - b / 100)) * 100
end

local function equipped()
    local list = {}
    if not (GetItemLinkAttuneProgress and CanAttuneItemHelper) then return list end
    for _, slot in ipairs(SLOT_IDS) do
        local id = GetInventoryItemID("player", slot)
        if id and CanAttuneItemHelper(id) >= 1 then
            local link = GetInventoryItemLink("player", slot)
            local progress = GetItemLinkAttuneProgress(link)
            if progress < 100 then list[#list + 1] = { id = id, progress = progress } end
        end
    end
    return list
end

local function notBound(link)
    if not link then return false end
    local scanTip = NS.ScanTip()
    scanTip:SetHyperlink(link)
    for _, line in ipairs({ scanTip:GetRegions() }) do
        if line:IsObjectType("FontString") then
            local text = line:GetText()
            if text == ITEM_SOULBOUND or text == ITEM_BIND_ON_PICKUP then
                scanTip:Hide()
                return false
            end
        end
    end
    scanTip:Hide()
    return true
end

local function bagItems()
    local count, progress = 0, 0
    if not (CustomExtractItemId and GetItemLinkAttuneProgress and CanAttuneItemHelper) then return count, progress end
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = select(7, GetContainerItemInfo(bag, slot))
            local id = CustomExtractItemId(link)
            if id and (CanAttuneItemHelper(id) >= 1
                or ((IsAttunableBySomeone and IsAttunableBySomeone(id) or 0) ~= 0 and notBound(link))) then
                local p = GetItemLinkAttuneProgress(link)
                if p < 100 then
                    count, progress = count + 1, progress + p
                end
            end
        end
    end
    return count, progress
end

local function barItems()
    local list = {}
    local slots = GetCustomGameData and GetCustomGameData(42, 0) or 0
    for i = 0, slots - 1 do
        local item = CustomGetItemInAttuneBarSlot and CustomGetItemInAttuneBarSlot(i)
        if item then list[#list + 1] = { id = item.id, progress = tonumber(GetItemLinkAttuneProgress(item.link) or 0) } end
    end
    return list, slots
end

-- ---------------------------------------------------------------------------
-- Rows: { group, label, value(), tip(tooltip) [, live = refresh while shown] }
-- ---------------------------------------------------------------------------

local NORMAL, HIGHLIGHT = NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR
local function line(tip, left, right)
    tip:AddDoubleLine(left, right, NORMAL.r, NORMAL.g, NORMAL.b, HIGHLIGHT.r, HIGHLIGHT.g, HIGHLIGHT.b)
end
local function title(tip, text, body)
    tip:SetText(text, HIGHLIGHT.r, HIGHLIGHT.g, HIGHLIGHT.b)
    if body then tip:AddLine(body, nil, nil, nil, true) end
end
-- Prestiged players see their current effect and what the next cycle brings.
local function cycle(tip, current, nextValue)
    if not D.prestiged then return end
    tip:AddLine(" ")
    line(tip, "Current effect", string.format("%.2f%%", current))
    line(tip, "Effect next cycle", string.format("%.2f%%", nextValue))
end

local forgeEffect = function() return (D.tf / 100) ^ 0.7 + (D.wf / 15) ^ 0.7 + D.lf ^ 0.7 end
local bopEffect = function() return pct(D.accAttunes, D.totalAcc) end
local boeEffect = function() return pct(D.affixAttunes, D.totalAffixes) / 4 end
local luckyEffect = function() return pct(D.accAttunes, D.totalAcc) / 2 end

local ROWS = {
    { group = "speed", label = "Current Speed", live = true,
      value = function() return string.format("%.0f%%", GetUnitSpeed("player") / 7 * 100) end,
      tip = function(t) title(t, "Current Speed", "The speed you are moving at right now.") end },

    { group = "attune", label = "Attuning (Equip)",
      value = function()
          local list, sum = equipped(), 0
          for _, it in ipairs(list) do sum = sum + it.progress end
          return fmtItems(#list, #list > 0 and sum / #list or 0)
      end,
      tip = function(t)
          title(t, "Item Attunements")
          local list = equipped()
          for _, it in ipairs(list) do
              line(t, (GetItemInfoCustom and GetItemInfoCustom(it.id)) or ("item " .. it.id), string.format("%.2f%%", it.progress))
          end
          if #list == 0 then t:AddLine("Not currently attuning any equipped items.", nil, nil, nil, true) end
      end },
    { group = "attune", label = "Attuning (Inv.)",
      shown = function() return D.prestiged and (D.attuneMastery or 0) > 0 end,
      value = function() local c, p = bagItems() return fmtItems(c, c > 0 and p / c or 0) end,
      tip = function(t)
          title(t, "Inventory Attunements", string.format("Attuning equipment in your bags at %.2f%% effectiveness.", D.attuneMastery or 0))
      end },
    { group = "attune", label = "Attuning (Bar)",
      value = function()
          local list, sum = barItems(), 0
          for _, it in ipairs(list) do sum = sum + it.progress end
          return fmtItems(#list, #list > 0 and math.min(100, sum / #list) or 0)
      end,
      tip = function(t)
          title(t, "Attune Bar")
          local list, slots = barItems()
          if slots == 0 then return t:AddLine("You have not yet unlocked the Attune Bar.", nil, nil, nil, true) end
          local any
          for _, it in ipairs(list) do
              if it.progress < 100 then
                  any = true
                  line(t, (GetItemInfoCustom and GetItemInfoCustom(it.id)) or ("item " .. it.id), string.format("%.2f%%", it.progress))
              end
          end
          if not any then t:AddLine("Not currently attuning any items in the Attune Bar.", nil, nil, nil, true) end
      end },

    { group = "prestige", label = "Char. Attunes",
      value = function() return string.format("%.2f%%", pct(D.charAttunes, D.totalChar)) end,
      tip = function(t)
          title(t, "Character Attunes", "Progress towards attuning every item available to this character.")
          t:AddLine(" ")
          t:AddLine(D.charAttunes .. " of " .. (D.totalChar or 0) .. " items attuned.", nil, nil, nil, true)
      end },
    { group = "prestige", label = "Acc. Attunes",
      value = function() return string.format("%.2f%%", pct(D.accAttunes, D.totalAcc)) end,
      tip = function(t)
          title(t, "Account Attunes", "Progress towards attuning every attunable item in the game.")
          t:AddLine(" ")
          t:AddLine(D.accAttunes .. " of " .. (D.totalAcc or 0) .. " items attuned.", nil, nil, nil, true)
      end },
    { group = "prestige", label = "Forge Power",
      value = function() return string.format("%.2f%%", forgeEffect()) end,
      tip = function(t)
          title(t, "Forge Power", "Increased chance to gain forged items after prestige, from forged attunes across your account.")
          t:AddLine(" ")
          line(t, D.tf .. " titanforged", string.format("%.2f%%", (D.tf / 100) ^ 0.7))
          line(t, D.wf .. " warforged", string.format("%.2f%%", (D.wf / 15) ^ 0.7))
          line(t, D.lf .. " lightforged", string.format("%.2f%%", D.lf ^ 0.7))
          cycle(t, D.forgePower or 0, forgeEffect() + (D.forgePower or 0))
      end },
    { group = "prestige", label = "BoP Coercion",
      value = function() return string.format("%.2f%%", bopEffect()) end,
      tip = function(t)
          title(t, "Bind-on-Pickup Coercion", "Increased chance for dropped bind-on-pickup items to be useful to you after prestige.")
          t:AddLine(" ")
          t:AddLine(D.accAttunes .. " of " .. (D.totalAcc or 0) .. " items attuned.")
          cycle(t, D.bopCoercion or 0, stack(D.bopCoercion or 0, bopEffect()))
      end },
    { group = "prestige", label = "BoE Coercion",
      shown = function() return D.totalAffixes ~= nil end,
      value = function() return string.format("%.2f%%", boeEffect()) end,
      tip = function(t)
          title(t, "Bind-on-Equip Coercion", "Increased chance to drop a bind-on-equip item you have not attuned after prestige: a quarter of your affix attunes.")
          t:AddLine(" ")
          t:AddLine(D.affixAttunes .. " of " .. (D.totalAffixes or 0) .. " affixes attuned.")
          cycle(t, D.boeCoercion or 0, stack(D.boeCoercion or 0, boeEffect()))
      end },
    { group = "prestige", label = "Attune Mastery",
      value = function() return string.format("%.2f%%", D.earnedMastery) end,
      tip = function(t)
          title(t, "Attune Mastery", "After prestige, items in your bags attune at this effectiveness. Raised by attuning lightforged items above item level 200.")
          t:AddLine(" ")
          t:AddLine(D.highLF .. " high item level lightforged attune" .. (D.highLF == 1 and "" or "s") .. ".")
          cycle(t, D.attuneMastery or 0, D.earnedMastery + (D.attuneMastery or 0))
      end },
    { group = "prestige", label = "Lucky Loot",
      value = function() return string.format("%.2f%%", luckyEffect()) end,
      tip = function(t)
          title(t, "Lucky Loot", "After prestige, a failed pool drop gets this chance to roll again: half your account attune share.")
          t:AddLine(" ")
          t:AddLine(D.accAttunes .. " of " .. (D.totalAcc or 0) .. " items attuned.")
          cycle(t, D.luckyLoot or 0, luckyEffect() + (D.luckyLoot or 0))
      end },
}

-- ---------------------------------------------------------------------------
-- Drawing: DragonUI's own bar (UI-Character-Info-Title) and zebra rows, appended after its sections.
-- ---------------------------------------------------------------------------

local header, frames = nil, {}

local function visibleRows()
    local list = {}
    for _, spec in ipairs(ROWS) do
        if enabled(spec.group) and (not spec.shown or spec.shown()) then list[#list + 1] = spec end
    end
    return list
end

local function prepare()
    countTotals()
    readPrestige()
    countAttunes()
end

local function fill(frame, spec)
    local ok, text = pcall(spec.value)
    PaperDollFrame_SetLabelAndText(frame, spec.label, ok and text or "-")
end

local function buildHeader(parent)
    local h = CreateFrame("Button", "DragonUISynastriaStatsHeader", parent)
    h:SetHeight(HEADER_H)
    h.Bg = h:CreateTexture(nil, "ARTWORK")
    h.Bg:SetAllPoints(h)
    h.Bg:SetAtlasTexture("UI-Character-Info-Title")
    h.Label = h:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    h.Label:SetDrawLayer("ARTWORK", 1)
    h.Label:SetPoint("CENTER", h, "CENTER", 0, 1)
    h.Label:SetText("Synastria")
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(h)
    hl:SetAtlasTexture("UI-Character-Info-Title")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    h:SetFrameLevel(parent:GetFrameLevel() + 2)
    -- Click folds it, as DragonUI's own bars do.
    h:SetScript("OnClick", function()
        NS.db.charstats.collapsed = not NS.db.charstats.collapsed
        CP.RelayoutSidebar()
    end)
    return h
end

local function buildRow(parent, index)
    local name = "DragonUISynastriaStat" .. index
    local r = CreateFrame("Frame", name, parent)
    r:SetHeight(ROW_H)
    r.Bg = r:CreateTexture(nil, "BACKGROUND")
    r.Bg:SetTexture(1, 1, 1)
    r.Bg:SetAlpha(0.05)
    r.Bg:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.Bg:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", ROW_INSET, 0)
    r:CreateFontString(name .. "Label", "ARTWORK", "GameFontNormalSmall"):SetPoint("LEFT", r, "LEFT", 11, 0)
    r:CreateFontString(name .. "StatText", "ARTWORK", "GameFontHighlightSmall"):SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if not self.spec then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(self.spec.tip, GameTooltip)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Live rows (speed) re-read a few times a second while on screen.
    r:SetScript("OnUpdate", function(self, dt)
        if not (self.spec and self.spec.live) then return end
        self.t = (self.t or 0) + dt
        if self.t < 0.2 then return end
        self.t = 0
        fill(self, self.spec)
    end)
    frames[index] = r
    return r
end

-- Runs after DragonUI's own relayout: our block starts where its sections end. DragonUI skips a relayout that
-- re-enters itself, leaving our last total in place; then the last base is reused instead of stacking on it.
local lastBase, lastTotal

local function relayout()
    local child = _G.DragonUICharacterStatsScrollChild
    if not child then return end
    header = header or buildHeader(child)

    local base = child:GetHeight() or 0
    if lastTotal and math.abs(base - lastTotal) < 0.5 then base = lastBase end
    if base <= 1 then base = 0 end
    lastBase = base

    local list = visibleRows()
    for _, r in pairs(frames) do r:Hide() end
    if #list == 0 then
        header:Hide()
        child:SetHeight(math.max(1, base))
        lastTotal = child:GetHeight()
        return
    end

    local width = math.floor(child:GetWidth() or 0)
    if width <= 0 then width = 197 end
    local y = base

    header:SetWidth(width)
    header:ClearAllPoints()
    header:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
    header:Show()
    y = y + HEADER_H

    if not NS.db.charstats.collapsed then
        for i, spec in ipairs(list) do
            local r = frames[i] or buildRow(child, i)
            r:SetWidth(width - ROW_INSET * 2)
            r:ClearAllPoints()
            r:SetPoint("TOPRIGHT", child, "TOPRIGHT", -ROW_INSET, -y)
            if i % 2 == 0 then r.Bg:Show() else r.Bg:Hide() end
            -- Values are read only when a row gets a new stat; relayouts run every frame of an animation.
            if r.spec ~= spec then
                prepare()
                r.spec = spec
                fill(r, spec)
            end
            r:Show()
            y = y + ROW_H
        end
    end
    child:SetHeight(y + SECTION_GAP)
    lastTotal = child:GetHeight()
    if CP.SyncScrollThumb then CP.SyncScrollThumb(_G.DragonUICharacterStatsScroll) end
end

-- Values only (no re-flow), for stat refreshes and Synastria's attune events.
local function refreshValues()
    if not (header and header:IsVisible()) then return end
    D.dirty = true
    prepare()
    for _, r in pairs(frames) do
        if r:IsShown() and r.spec then fill(r, r.spec) end
    end
end

-- ---------------------------------------------------------------------------
-- Cog menu: a "Synastria" heading with one tick per group, above "Reset stat order".
-- ---------------------------------------------------------------------------

local function menuEntries()
    local list = { { text = "Synastria", isTitle = true } }
    for _, g in ipairs(GROUPS) do
        list[#list + 1] = {
            text = g.label,
            keepShown = true,
            checked = function() return enabled(g.key) end,
            func = function()
                NS.db.charstats[g.key] = not enabled(g.key)
                CP.RelayoutSidebar()
            end,
        }
    end
    return list
end

local function wrapCogMenu()
    local Menu = NS.D.Menu
    local open = Menu.Open
    Menu.Open = function(anchor, entries, options)
        if anchor == _G.DragonUICharacterSettingsCog and type(entries) == "table" then
            -- Only the paper doll's menu has the stat entries; ours go just before "Reset stat order".
            for i, entry in ipairs(entries) do
                if type(entry.text) == "string" and entry.text:find(NS.D.L["Reset stat order"], 1, true) then
                    for j, extra in ipairs(menuEntries()) do table.insert(entries, i + j - 1, extra) end
                    break
                end
            end
        end
        return open(anchor, entries, options)
    end
end

-- ---------------------------------------------------------------------------

local wrapped

-- For the DragonUI settings tab.
NS.CharStatGroups = GROUPS
function NS.SetCharStat(key, on)
    NS.db.charstats[key] = on and true or false
    if wrapped and CP and CP.RelayoutSidebar then CP.RelayoutSidebar() end
end
function NS.GetCharStat(key)
    return enabled(key)
end

function Part.Init()
    NS.db.charstats = NS.db.charstats or {}
    CP = NS.D and NS.D.CharacterPanel
    if NS.D and NS.D.Menu and NS.D.Menu.Open then wrapCogMenu() end

    local events = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "UNIT_INVENTORY_CHANGED" }) do events:RegisterEvent(e) end
    events:SetScript("OnEvent", function() NS.After(0.2, refreshValues) end)
end

-- The server's event system arrives with its UI after login, so this waits until it exists.
local customRegistered
local function registerCustom()
    if customRegistered or not RegisterForCustomEvent then return end
    customRegistered = true
    for _, e in ipairs({ "SYNASTRIA_ITEM_ATTUNE_PCT_CHANGED", "SYNASTRIA_ITEM_ATTUNED", "SYNASTRIA_ATTUNE_BAR_CHANGED" }) do
        pcall(RegisterForCustomEvent, e, function() NS.After(0.2, refreshValues) end)
    end
end

function Part.Check()
    registerCustom()
    if wrapped or not (CP and CP.RelayoutSidebar and _G.DragonUICharacterStatsScrollChild) then return end
    wrapped = true
    local original = CP.RelayoutSidebar
    CP.RelayoutSidebar = function(...)
        original(...)
        local ok, err = pcall(relayout)
        if not ok then NS.Print(err) end
    end
    if CP.RefreshSidebar then
        local refresh = CP.RefreshSidebar
        CP.RefreshSidebar = function(...)
            refresh(...)
            pcall(refreshValues)
        end
    end
    CP.RelayoutSidebar()
end

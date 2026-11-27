local _, NS = ...

-- Extra buttons in Bagster's inventory header, next to DragonUI's Sell Scrap / Clear / Sort:
--   Sell Scrap   - with ScootsVendor installed it runs ScootsVendor's auto-sell (its always/never-sell
--                  lists and options), only while a vendor is open; without it, DragonUI's own button.
--   Never sell / - (ScootsVendor) drop an item on one to put it on that ScootsVendor list (and off the
--   Always sell    other), the way ScootsVendor's own drop boxes do; drop it again to take it off. Click
--                  with nothing held to open ScootsVendor's options.
--   Deposit      - (no addon needed) the server's "deposit all eligible items to the Resource Bank",
--                  the call its own Resource Bank "Deposit All" button makes.
-- The search box gives up the room the two new buttons need (at most its normal 200px wide).
local Part = {}
NS.Register(Part)

local SELL = "DragonUI_BagsterBagSellScrapBtn"
local SEARCH_W, GAP = 200, 4

local neverSell, alwaysSell, deposit, sellButton, original
local merchantOpen

local function enabled()
    return NS.db and NS.db.bagsterButtons ~= false
end

local function scoots()
    local SV = _G.ScootsVendor
    return SV and SV.doAutoSell and SV.options and SV.options.get and SV
end

local function say(msg)
    local SV = scoots()
    if SV and SV.pushMessage then SV.pushMessage(msg) else NS.Print(msg) end
end

-- ---------------------------------------------------------------------------
-- Buttons in DragonUI's header-button look (bagsort.lua's StyleHeaderButton recipe)
-- ---------------------------------------------------------------------------

local function headerButton(parent, icon, title, lines)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b:SetFrameLevel(parent:GetFrameLevel() + 10)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(icon)
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture(NS.D._dir .. "ActionBars\\uiactionbariconframe")
    border:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2.2, 2.3)
    border:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -2.2, -2.2)
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetTexture(NS.D._dir .. "ActionBars\\uiactionbariconframehighlight")
    glow:SetAllPoints(border)
    b:SetScript("OnMouseDown", function(self) self.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- ---------------------------------------------------------------------------
-- Sell Scrap -> ScootsVendor auto-sell
-- ---------------------------------------------------------------------------

local function autoSell()
    local SV = scoots()
    if not SV then return end
    -- Auto-sell sells by using items: without a vendor that would equip or use them.
    if not merchantOpen then
        say("Open a vendor first to auto-sell.")
        return
    end
    local ok, err = pcall(SV.doAutoSell)
    if not ok then NS.Report(err) end
end

local function autoSellTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Auto-sell", 1, 1, 1)
    GameTooltip:AddLine("Sells what ScootsVendor's auto-sell would: its always-sell list, attuned or unusable bound gear, and so on. Never-sell items stay.", nil, nil, nil, true)
    GameTooltip:AddLine("A vendor must be open.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function takeOverSell()
    if not (sellButton and scoots()) or original then return end
    original = { click = sellButton:GetScript("OnClick"), enter = sellButton:GetScript("OnEnter") }
    sellButton:SetScript("OnClick", autoSell)
    sellButton:SetScript("OnEnter", autoSellTooltip)
end

local function giveBackSell()
    if not (sellButton and original) then return end
    sellButton:SetScript("OnClick", original.click)
    sellButton:SetScript("OnEnter", original.enter)
    original = nil
end

-- ---------------------------------------------------------------------------
-- Never sell / Always sell: an item dropped here toggles it on that ScootsVendor list (in it: removed;
-- not in it: added, and taken off the other list, as ScootsVendor's own drop boxes do)
-- ---------------------------------------------------------------------------

local LISTS = {
    never = { key = "never-sell", other = "always-sell", label = "never sell", otherLabel = "always sell" },
    always = { key = "always-sell", other = "never-sell", label = "always sell", otherLabel = "never sell" },
}

local function toggleOnList(which)
    local list = LISTS[which]
    local SV = scoots()
    local kind, itemId, link = GetCursorInfo()
    if kind ~= "item" then
        if SV and SV.options.open then pcall(SV.options.open) end
        return
    end
    ClearCursor()
    if not SV then return end
    local name = link or ("item " .. itemId)
    local items = SV.options.get(list.key) or {}
    if items[itemId] then
        items[itemId] = nil
        SV.options.set(list.key, items)
        say(name .. ' removed from "' .. list.label .. '" list.')
    else
        items[itemId] = true
        SV.options.set(list.key, items)
        say(name .. ' added to "' .. list.label .. '" list.')
        local other = SV.options.get(list.other)
        if other and other[itemId] then
            other[itemId] = nil
            SV.options.set(list.other, other)
            say(name .. ' removed from "' .. list.otherLabel .. '" list.')
        end
    end
    if SV.options.updateAutoSellLists then pcall(SV.options.updateAutoSellLists) end
end

-- ---------------------------------------------------------------------------
-- Deposit materials (the server's Resource Bank "Deposit All")
-- ---------------------------------------------------------------------------

local function depositAll()
    if not NotifyServer then return end
    NotifyServer(2, 9, "")
end

-- ---------------------------------------------------------------------------
-- Layout: [search][deposit][always sell][never sell][sell scrap][clear][sort][bags]
-- ---------------------------------------------------------------------------

local function search()
    local frame = sellButton and sellButton:GetParent()
    return frame and _G[(frame:GetName() or "") .. "Search"]
end

local function fitSearch()
    local box = search()
    if not box then return end
    local leftmost = sellButton
    for _, b in ipairs({ neverSell, alwaysSell, deposit }) do
        if b and b:IsShown() then leftmost = b end
    end
    local right, left = leftmost:GetLeft(), box:GetLeft()
    if not (right and left) then return end
    box:SetWidth(math.max(80, math.min(SEARCH_W, right - left - 6)))
end

local function layout()
    local anchor = sellButton
    for _, b in ipairs({ neverSell, alwaysSell }) do
        if b then
            b:ClearAllPoints()
            b:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
            if scoots() and enabled() then
                b:Show()
                anchor = b
            else
                b:Hide()
            end
        end
    end
    deposit:ClearAllPoints()
    deposit:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
    if enabled() then deposit:Show() else deposit:Hide() end
    fitSearch()
end

local function build()
    local frame = sellButton:GetParent()
    deposit = headerButton(frame, "Interface\\Icons\\INV_Crate_04", "Deposit materials",
        { "Sends every eligible item in your bags to the Resource Bank." })
    deposit:SetScript("OnClick", depositAll)
    if scoots() then
        -- Divine Intervention's bubble: kept safe. The skull: this goes.
        neverSell = headerButton(frame, "Interface\\Icons\\Spell_Holy_DivineIntervention", "Never sell",
            { "Drop an item here to add it to ScootsVendor's never-sell list; drop it again to remove it.",
              "|cff999999Click with no item: ScootsVendor options (the lists).|r" })
        alwaysSell = headerButton(frame, "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", "Always sell",
            { "Drop an item here to add it to ScootsVendor's always-sell list; drop it again to remove it.",
              "|cff999999Click with no item: ScootsVendor options (the lists).|r" })
        for which, b in pairs({ never = neverSell, always = alwaysSell }) do
            local function drop() toggleOnList(which) end
            b:RegisterForClicks("LeftButtonUp")
            b:SetScript("OnClick", drop)
            b:SetScript("OnReceiveDrag", drop)
        end
    end
    frame:HookScript("OnSizeChanged", function() NS.After(0, fitSearch) end)
    frame:HookScript("OnShow", function() NS.After(0, fitSearch) end)
end

function NS.RefreshBagsterButtons()
    if not sellButton then return end
    if enabled() then takeOverSell() else giveBackSell() end
    layout()
    if not enabled() then
        local box = search()
        if box then box:SetWidth(SEARCH_W) end
    end
end

function Part.Init()
    local events = CreateFrame("Frame")
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
    events:SetScript("OnEvent", function(_, event) merchantOpen = event == "MERCHANT_SHOW" end)
end

-- DragonUI makes its Bagster header buttons when the Bagster inventory is first built.
function Part.Check()
    if sellButton then return end
    sellButton = _G[SELL]
    if not sellButton then return end
    build()
    NS.RefreshBagsterButtons()
end

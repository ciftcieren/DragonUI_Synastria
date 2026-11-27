local _, NS = ...

-- "Item attuned" as a DragonUI toast, in the look of DragonUI's level-up banner (retail's event toast):
-- a dark shadow band between two gold lines, the item's icon in the aura ring, a gold title over the item
-- name in its quality colour and its forge level.
--
-- The server's own Attune Alerts (container_62) print a line of outlined text at an anchor for each
-- attune (SYNASTRIA_ITEM_ATTUNED_EX). While toasts are on, those lines are hidden and the toast shows
-- instead; the server's chat message is left alone. The server's "show frame" option still decides
-- whether anything shows on screen. The toast sits on a DragonUI edit-mode mover.
local Part = {}
NS.Register(Part)

local MOVER = "SynastriaAttuneToast"
local SERVER_ANCHOR = "AttuneAlerts-Main"
-- The server keeps Attune Alerts' options in custom game data 37, under its addon id 4; slot 0 bit 0 is
-- "show frame" (container_62's opts.conf).
local ALERT_ID = 4

local WIDTH, HEIGHT, BAND_W = 300, 64, 380
local ICON = 36
local FADE_IN, HOLD, HOLD_QUEUED, FADE_OUT = 0.3, 4, 2.5, 0.6

local FORGE_TEXT = {
    [1] = "|cffb5c2ffTitanforged|r",
    [2] = "|cfff07d6bWarforged|r",
    [3] = "|cfff0f0b0Lightforged|r",
}

local mover, toast
local queue = {}
local registered

local function enabled()
    return NS.db and NS.db.attuneToasts ~= false
end

local function serverShowsFrame()
    if not GetCustomGameData then return true end
    local raw = GetCustomGameData(37, bit.lshift(ALERT_ID, 16) + 0) or 0
    return bit.band(raw, 1) ~= 0
end

-- ---------------------------------------------------------------------------
-- The server's floating lines: hidden (alpha only) while toasts are on
-- ---------------------------------------------------------------------------

local function syncServerLines()
    local anchor = _G[SERVER_ANCHOR]
    if not anchor then return end
    anchor:SetAlpha(enabled() and 0 or 1)
end

-- ---------------------------------------------------------------------------
-- Item link, as the server builds it for its own line
-- ---------------------------------------------------------------------------

local function signed(v)
    if bit.band(v, 0x80000000) ~= 0 then
        return -(0x80000000 - bit.band(v, 0x7FFFFFFF))
    end
    return v
end

local function buildLink(itemId, randProp, suffix, forge)
    local name, _, rarity = GetItemInfoCustom(itemId)
    name = name or ("item " .. itemId)
    if randProp ~= 0 and GetAffixNameCustom then
        local affix = GetAffixNameCustom(randProp)
        if affix then name = name .. " " .. affix end
    end
    if rarity == 7 then rarity = 6 elseif not ITEM_QUALITY_COLORS[rarity] then rarity = -1 end
    local color = ITEM_QUALITY_COLORS[rarity] or ITEM_QUALITY_COLORS[1]
    local link = string.format("%s|Hitem:%d:0:0:0:0:0:%d:%d:%d|h[%s]|h|r", color.hex, itemId, randProp,
        bit.bor(suffix, bit.lshift(forge, 12)), UnitLevel("player"), name)
    return link, color.hex .. name .. "|r"
end

-- ---------------------------------------------------------------------------
-- The toast
-- ---------------------------------------------------------------------------

local function dir()
    return NS.D._dir
end

local function build()
    local D = NS.D
    if D.CreateUIFrame and D.RegisterEditableFrame then
        if type(D.L) == "table" and rawget(D.L, MOVER) == nil then rawset(D.L, MOVER, "Attune Toast") end
        mover = D.CreateUIFrame(WIDTH, HEIGHT, MOVER)
        local function save()
            local x, y = mover:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if not (x and ux) then return end
            NS.db.attuneToastPos = { x = x - ux, y = y - uy }
        end
        mover:HookScript("OnDragStop", save)
        D:RegisterEditableFrame({
            name = MOVER, frame = mover,
            editorVisible = function() return enabled() end,
            onNudge = save,
            resetPosition = function()
                NS.db.attuneToastPos = nil
                mover:ClearAllPoints()
                mover:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
            end,
            isDefaultPosition = function() return NS.db.attuneToastPos == nil end,
            module = Part,
        })
    else
        mover = CreateFrame("Frame", "DragonUI_" .. MOVER, UIParent)
        mover:SetSize(WIDTH, HEIGHT)
    end
    local pos = NS.db.attuneToastPos
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", pos and pos.x or 0, pos and pos.y or 230)

    toast = CreateFrame("Button", nil, UIParent)
    toast:SetFrameStrata("HIGH")
    toast:SetSize(WIDTH, HEIGHT)
    toast:SetPoint("CENTER", mover, "CENTER", 0, 0)
    toast:RegisterForClicks("LeftButtonUp")
    toast:Hide()

    -- The level-up banner's shadow and gold lines (DragonUI's NewLevelUp art).
    local shadow = toast:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(dir() .. "NewLevelUp\\levelup")
    shadow:SetTexCoord(0.00195313, 0.63867188, 0.03710938, 0.23828125)
    shadow:SetSize(WIDTH, HEIGHT + 22)
    shadow:SetPoint("CENTER", 0, -4)
    shadow:SetAlpha(0.7)
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local line = toast:CreateTexture(nil, "BORDER")
        line:SetTexture(dir() .. "NewLevelUp\\levelup_retail")
        line:SetTexCoord(2 / 512, 420 / 512, 44 / 64, 51 / 64)
        line:SetSize(BAND_W, 7)
        line:SetPoint(side, toast, side, 0, 0)
    end

    -- Icon in the aura ring, as the level-up rows draw theirs.
    local back = toast:CreateTexture(nil, "ARTWORK", nil, 1)
    back:SetSize(ICON, ICON)
    back:SetPoint("LEFT", toast, "LEFT", 34, 0)
    back:SetVertexColor(0.3, 0.3, 0.3)
    back:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    local icon = toast:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetPoint("TOPLEFT", back, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    local ring = toast:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(dir() .. "ActionBars\\uiactionbar2x_new")
    ring:SetTexCoord(359 / 512, 451 / 512, 649 / 1024, 739 / 1024)
    -- DragonUI's level-up sizing: 46x45 at ICON/45 * 1.1375, its corner 1.8px out from the icon's.
    local ringScale = ICON / 45 * 1.1375
    ring:SetSize(46 * ringScale, 45 * ringScale)
    ring:SetPoint("TOPLEFT", back, "TOPLEFT", -1.8, 1.8)
    toast.icon, toast.iconBack = icon, back

    local title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", back, "TOPRIGHT", 12, 2)
    title:SetPoint("RIGHT", toast, "RIGHT", -20, 0)
    title:SetJustifyH("LEFT")
    title:SetText("Item Attuned")
    local sub = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetPoint("RIGHT", toast, "RIGHT", -20, 0)
    sub:SetJustifyH("LEFT")
    toast.title, toast.sub = title, sub

    toast:SetScript("OnEnter", function(self)
        self.hover = true
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    toast:SetScript("OnLeave", function(self)
        self.hover = nil
        GameTooltip:Hide()
    end)
    toast:SetScript("OnClick", function(self)
        if self.link then HandleModifiedItemClick(self.link) end
    end)
end

local showNext

-- Fade in, hold (paused while the mouse is over it), fade out; then the next one in the queue.
local function animate(self, dt)
    self.t = self.t + dt
    if self.phase == "in" then
        self:SetAlpha(math.min(1, self.t / FADE_IN))
        if self.t >= FADE_IN then self.phase, self.t = "hold", 0 end
    elseif self.phase == "hold" then
        if self.hover then self.t = 0 end
        if self.t >= (#queue > 0 and HOLD_QUEUED or HOLD) then self.phase, self.t = "out", 0 end
    else
        self:SetAlpha(math.max(0, 1 - self.t / FADE_OUT))
        if self.t >= FADE_OUT then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            showNext()
        end
    end
end

showNext = function()
    local entry = table.remove(queue, 1)
    if not entry then return end
    if not toast then build() end
    toast.link = entry.link
    toast.icon:SetTexture(entry.icon)
    toast.iconBack:SetTexture(entry.icon)
    toast.title:SetText(entry.inactive and "Item Attuned |cff999999(inactive)|r" or "Item Attuned")
    toast.sub:SetText(entry.forge and (entry.name .. "  " .. entry.forge) or entry.name)
    toast.t, toast.phase = 0, "in"
    toast:SetAlpha(0)
    toast:Show()
    toast:SetScript("OnUpdate", animate)
end

-- args: itemId, inactive (1), random property (unsigned), suffix, forge level
local function onAttuned(args)
    syncServerLines()
    if not (enabled() and type(args) == "table" and args[1]) or not serverShowsFrame() then return end
    local itemId, forge = args[1], args[5] or 0
    local link, name = buildLink(itemId, signed(args[3] or 0), args[4] or 0, forge)
    queue[#queue + 1] = {
        link = link, name = name, forge = FORGE_TEXT[forge], inactive = args[2] == 1,
        icon = (GetItemIcon and GetItemIcon(itemId)) or "Interface\\Icons\\INV_Misc_QuestionMark",
    }
    if not (toast and toast:IsShown()) then showNext() end
end

function NS.RefreshAttuneToast()
    syncServerLines()
    if not enabled() then
        wipe(queue)
        if toast then toast:SetScript("OnUpdate", nil) toast:Hide() end
    end
end

-- The server's event system arrives with its UI after login.
function Part.Check()
    if not registered and RegisterForCustomEvent then
        registered = true
        RegisterForCustomEvent("SYNASTRIA_ITEM_ATTUNED_EX", function(args)
            local ok, err = pcall(onAttuned, args)
            if not ok then NS.Report(err) end
        end)
    end
    if not mover and NS.D and NS.D.CreateUIFrame then build() end
    syncServerLines()
end

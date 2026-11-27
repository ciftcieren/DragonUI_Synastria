local _, NS = ...

-- Stance buttons 11-20 on DragonUI's stance bar. Multiclass characters can have more than 10 forms, so
-- the server raises NUM_SHAPESHIFT_SLOTS to 20 and adds ShapeshiftButton11-20 (container_37). DragonUI's
-- stance bar always lays out 10 slots (it shadows the global on purpose), so the extra ones would stay
-- where Blizzard's hidden bar put them. Here they join DragonUI's bar after button 10, at its size,
-- scale and spacing, and take button 1's finished DragonUI look. Blizzard's own stance code still
-- updates their icons and states (it loops the raised global). Secure buttons: only moved out of combat.
local Part = {}
NS.Register(Part)

local FIRST = 11

local pendingCombat

local function enabled()
    return NS.db and NS.db.stanceExtra ~= false
end

local function button(index)
    return _G["ShapeshiftButton" .. index]
end

-- Copies one state texture (normal, pushed, highlight, checked) from src to dst: file, cut, colour,
-- layer, blend and anchors (anchors on src are moved to dst).
local function copyTexture(src, dst, getter, setter)
    local from = src[getter] and src[getter](src)
    if not from then return end
    local path = from:GetTexture()
    if setter then
        dst[setter](dst, path or "")
    end
    local to = dst[getter](dst)
    if not to then return end
    to:SetTexture(path)
    to:SetTexCoord(from:GetTexCoord())
    to:SetVertexColor(from:GetVertexColor())
    to:SetBlendMode(from:GetBlendMode())
    to:SetDrawLayer(from:GetDrawLayer())
    to:SetAlpha(from:GetAlpha())
    to:ClearAllPoints()
    for i = 1, from:GetNumPoints() do
        local point, rel, relPoint, x, y = from:GetPoint(i)
        to:SetPoint(point, rel == src and dst or rel, relPoint, x, y)
    end
    if from:GetNumPoints() == 0 then to:SetAllPoints(dst) end
end

local function copyRegion(src, dst, suffix)
    local from, to = _G[src:GetName() .. suffix], _G[dst:GetName() .. suffix]
    if not (from and to) then return end
    to:SetTexCoord(from:GetTexCoord())
    to:SetDrawLayer(from:GetDrawLayer())
    to:ClearAllPoints()
    for i = 1, from:GetNumPoints() do
        local point, rel, relPoint, x, y = from:GetPoint(i)
        to:SetPoint(point, rel == src and dst or rel, relPoint, x, y)
    end
end

local function copyLook(src, dst)
    copyTexture(src, dst, "GetNormalTexture", "SetNormalTexture")
    copyTexture(src, dst, "GetPushedTexture", "SetPushedTexture")
    copyTexture(src, dst, "GetHighlightTexture", "SetHighlightTexture")
    copyTexture(src, dst, "GetCheckedTexture", "SetCheckedTexture")
    copyRegion(src, dst, "Icon")
    local fromCd, toCd = _G[src:GetName() .. "Cooldown"], _G[dst:GetName() .. "Cooldown"]
    if fromCd and toCd then
        toCd:ClearAllPoints()
        toCd:SetAllPoints(dst)
    end
end

local function layout()
    if not enabled() or (NUM_SHAPESHIFT_SLOTS or 10) < FIRST then return end
    if InCombatLockdown() then
        pendingCombat = true
        return
    end
    local first, tenth, second = button(1), button(10), button(2)
    local bar = first and first:GetParent()
    if not (bar and tenth) or bar == ShapeshiftBarFrame then return end
    -- DragonUI chains its buttons LEFT to RIGHT with its spacing setting.
    local gap = 6
    if second and second:GetNumPoints() > 0 then
        local _, _, _, x = second:GetPoint(1)
        gap = x or gap
    end
    local width, height = first:GetSize()
    for index = FIRST, NUM_SHAPESHIFT_SLOTS do
        local b = button(index)
        if b then
            if b:GetParent() ~= bar then b:SetParent(bar) end
            b:SetSize(width, height)
            b:SetScale(first:GetScale())
            b:ClearAllPoints()
            b:SetPoint("LEFT", button(index - 1), "RIGHT", gap, 0)
            if not b._dsynLook then
                b._dsynLook = true
                copyLook(first, b)
            end
            if GetShapeshiftFormInfo(index) then b:Show() else b:Hide() end
        end
    end
end

local hooked
local function hook()
    if hooked or (NUM_SHAPESHIFT_SLOTS or 10) < FIRST or not button(FIRST) then return end
    hooked = true
    -- After Blizzard's and DragonUI's own stance updates.
    hooksecurefunc("ShapeshiftBar_Update", function() pcall(layout) end)
    local events = CreateFrame("Frame")
    for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORMS", "PLAYER_REGEN_ENABLED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
        events:RegisterEvent(e)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not pendingCombat then return end
        pendingCombat = nil
        NS.After(0.1, layout)
    end)
    layout()
end

function Part.Check()
    if not hooked then hook() end
end

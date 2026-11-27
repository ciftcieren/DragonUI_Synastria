local _, NS = ...

-- Boss frames 5-8. The server adds Boss5-8TargetFrame for its bigger encounters (container_36), stacked
-- under Blizzard's boss 4. DragonUI positions and restyles bosses 1-4 only (its boss module is fixed at
-- four, and its restyle can't be called from outside), so 5-8 would sit wherever Blizzard's boss 4 used
-- to be. Here each gets a holder chained under DragonUI's boss 4 holder, the same size and scale, so the
-- column continues under DragonUI's frames and moves with them in edit mode. They keep Blizzard's art.
-- Boss frames are secure: only moved out of combat.
local Part = {}
NS.Register(Part)

local FIRST, LAST = 5, 8
local holders = {}
local pendingCombat

local function enabled()
    return NS.db and NS.db.bossExtra ~= false
end

local function bossModule()
    local B = NS.D and NS.D.BossModule
    return B and B.wrapperFrames and B.wrapperFrames[4] and B
end

local function holder(index, B)
    local h = holders[index]
    if not h then
        h = CreateFrame("Frame", nil, UIParent)
        holders[index] = h
    end
    local above = index == FIRST and B.wrapperFrames[4] or holders[index - 1]
    h:SetSize(above:GetWidth(), above:GetHeight())
    h:SetScale(above:GetScale())
    h:ClearAllPoints()
    h:SetPoint("TOP", above, "BOTTOM", 0, 0)
    return h
end

local placing
local function place()
    if not enabled() then return end
    local B = bossModule()
    local four = _G.Boss4TargetFrame
    if not (B and four) then return end
    if InCombatLockdown() then
        pendingCombat = true
        return
    end
    for index = FIRST, LAST do
        local frame = _G["Boss" .. index .. "TargetFrame"]
        if frame then
            local h = holder(index, B)
            placing = true
            frame:SetScale(four:GetScale())
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
            placing = nil
            if not frame._dsynBossHooked then
                frame._dsynBossHooked = true
                -- Blizzard re-anchors boss frames when they show; put them back (outside combat).
                hooksecurefunc(frame, "SetPoint", function()
                    if placing or InCombatLockdown() then return end
                    NS.After(0, place)
                end)
            end
        end
    end
end

local hooked
local function hook()
    if hooked or not (_G.Boss5TargetFrame and bossModule()) then return end
    hooked = true
    -- DragonUI's boss scale and position settings.
    if NS.D.RefreshBossFrames then
        hooksecurefunc(NS.D, "RefreshBossFrames", function() NS.After(0, place) end)
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        if pendingCombat then
            pendingCombat = nil
            place()
        end
    end)
    place()
end

function Part.Check()
    if not hooked then hook() end
end

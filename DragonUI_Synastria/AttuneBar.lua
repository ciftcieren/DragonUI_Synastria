local _, NS = ...

-- The server's Attune Bar hangs from a DragonUI editor mover, so it moves in DragonUI's edit mode like any HUD frame.
local NAME = "AttuneBar-Main"
local ART = "AttuneBar-Artwork"
local SLOT = "AttuneBar-ItemSlot-"
local DEFAULT_X, DEFAULT_Y = 0, -150

local Part = {}
NS.Register(Part)
NS.parts = NS.parts or {}
NS.parts.attune = Part

local bar, mover, anchoring

local function anchorBar()
    if not (bar and mover) then return end
    anchoring = true
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", mover, "CENTER", 0, 0)
    anchoring = false
end

local function sizeMover()
    if not (bar and mover) then return end
    local s = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    mover:SetSize(math.max(bar:GetWidth() * s, 40), math.max(bar:GetHeight() * s, 20))
end

local function setMover(x, y)
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function save()
    local x, y = mover:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return end
    NS.db.attune.x, NS.db.attune.y = x - ux, y - uy
    setMover(NS.db.attune.x, NS.db.attune.y)
    anchorBar()
end

-- First sight with nothing saved: the mover adopts wherever the server put the bar.
local function placeMover()
    local a = NS.db.attune
    if a.x then return setMover(a.x, a.y) end
    local bx, by = bar:GetCenter()
    if bx then
        local s = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local ux, uy = UIParent:GetCenter()
        setMover(bx * s - ux, by * s - uy)
    else
        setMover(DEFAULT_X, DEFAULT_Y)
    end
end

function Part.Reset()
    NS.db.attune.x, NS.db.attune.y = nil, nil
    if mover then
        setMover(DEFAULT_X, DEFAULT_Y)
        anchorBar()
    end
end

local function createMover()
    local D = NS.D
    if not (D and D.CreateUIFrame and D.RegisterEditableFrame) then
        mover = CreateFrame("Frame", "DragonUI_SynastriaAttuneBar", UIParent)
        return
    end
    -- DragonUI labels editor boxes via L[name]; AceLocale reports unknown keys as errors, so register ours first.
    if type(D.L) == "table" and rawget(D.L, "SynastriaAttuneBar") == nil then
        rawset(D.L, "SynastriaAttuneBar", "Attune Bar")
    end
    mover = D.CreateUIFrame(200, 60, "SynastriaAttuneBar")
    mover:HookScript("OnDragStop", save)
    D:RegisterEditableFrame({
        name = "SynastriaAttuneBar",
        frame = mover,
        editorVisible = function() return bar ~= nil end,
        onShow = sizeMover,
        onNudge = save,
        resetPosition = Part.Reset,
        isDefaultPosition = function() return NS.db.attune.x == nil end,
        module = Part,
    })
end

function Part.Check()
    if NS.db.attuneBarSkin == false then return end
    local frame = _G[NAME]
    if not frame or frame == bar then return end
    bar = frame
    if not mover then createMover() end
    sizeMover()
    placeMover()
    anchorBar()

    -- Anyone else re-anchoring the bar (the server's own layout code) is put back on the mover.
    hooksecurefunc(frame, "SetPoint", function(self)
        if not anchoring and self == bar then anchorBar() end
    end)
    -- If the server lets you drag the bar itself, that drag becomes the saved position too.
    frame:HookScript("OnDragStop", function(self)
        if self ~= bar then return end
        local bx, by = self:GetCenter()
        if not bx then return end
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local ux, uy = UIParent:GetCenter()
        setMover(bx * s - ux, by * s - uy)
        save()
    end)
    frame:HookScript("OnSizeChanged", sizeMover)

    -- The server draws everything on a child (dialog border, header plate, "Attune Bar" text), not on the bar.
    -- Its own options still drive ours: "Background transparency" sets that child's alpha and "Show title"
    -- shows/hides its title, so both are mirrored onto the DragonUI chrome while the child stays invisible.
    local art = _G[ART]
    local hiding
    local function hideArt()
        if not art then return end
        hiding = true
        art:SetAlpha(0)
        hiding = nil
    end
    local function applyChromeAlpha()
        local a = NS.db.attune.chromeAlpha or 1
        if frame._dsynBack then frame._dsynBack:SetAlpha(a) end
        if frame._dsynRing then frame._dsynRing:SetAlpha(a) end
    end
    local function applyTitle()
        if frame._dsynTitle and art and art.titleText then
            if art.titleText:IsShown() then frame._dsynTitle:Show() else frame._dsynTitle:Hide() end
        end
    end
    if art and not art._dsynMirrored then
        art._dsynMirrored = true
        -- The server set its transparency at build time, before we got here.
        if art:GetAlpha() > 0 then NS.db.attune.chromeAlpha = art:GetAlpha() end
        hooksecurefunc(art, "SetAlpha", function(_, a)
            if hiding then return end
            NS.db.attune.chromeAlpha = a
            applyChromeAlpha()
            hideArt()
        end)
        if art.titleText then
            hooksecurefunc(art.titleText, "Show", applyTitle)
            hooksecurefunc(art.titleText, "Hide", applyTitle)
        end
    end

    NS.Skin(frame, {
        titleFrom = art,
        layout = function()
            hideArt()
            applyChromeAlpha()
            applyTitle()
            for i = 0, 15 do
                local slot = _G[SLOT .. i]
                if not slot then break end
                NS.SkinItemSlot(slot)
                local progress = _G[SLOT .. i .. "-Progress"]
                if progress then NS.SkinBarFrame(progress) end
            end
        end,
    })
end

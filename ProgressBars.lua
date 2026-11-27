local _, NS = ...

-- DragonUI-styled bars for ScootsProgressBar. Scoots keeps doing all the work (values, text formats,
-- colours, which bars are on, their order, single/multi mode) and keeps its own settings menu; its own
-- frame is just made invisible. These bars copy what Scoots shows: each Scoots bar's progress, rested
-- (pending) part, colours and text, and draw them with DragonUI's experience bar art, in whichever style
-- DragonUI's XP / Rep bars use:
--   RetailUI       - retail rounded XP bar (uiexperiencebar sheet, as DragonUI's retail style and qtBar)
--   DragonflightUI - DragonUI's Dragonflight XP bar strips (dark trough, metal frame with ticks)
-- The stack sits on a DragonUI edit-mode mover. Left click / right click / tooltip go to Scoots as before.
local Part = {}
NS.Register(Part)

local MOVER = "SynastriaProgressBars"
local SHEET = "XP\\uiexperiencebar"
local ROUND_TROUGH = { 0, 570 / 1024, 20 / 256, 29 / 256 }
local ROUND_FRAME = { 1 / 1024, 572 / 1024, 1 / 256, 18 / 256 }
local GAP = { round = 6, dragonflight = 3 }
local POLL = 0.25

local P, mover, holder
local rows = {}
local wantedAlpha = 1
local active, guarding

local function db()
    NS.db.spb = NS.db.spb or {}
    return NS.db.spb
end

local function enabled()
    return NS.db and NS.db.spbBars ~= false
end

-- Follows DragonUI's own XP / Rep bar style (Bars > XP & Rep Bars): RetailUI -> rounded retail bar,
-- DragonflightUI -> the Dragonflight strips.
local function style()
    local profile = NS.D.db and NS.D.db.profile
    local chosen = profile and ((profile.xprepbar and profile.xprepbar.style) or (profile.style and profile.style.xpbar))
    return chosen == "retailui" and "round" or "dragonflight"
end

local function scoots()
    local S = _G.ScootsProgressBar
    if S and S.frames and S.frames.main and S.core and S.options and S.utility and S.interface then return S end
end

local function opt(key)
    local ok, value = pcall(P.options.get, key)
    if ok then return value end
end

-- ---------------------------------------------------------------------------
-- Hiding Scoots' own frame (kept alive: it still computes everything)
-- ---------------------------------------------------------------------------

local function hideScoots()
    local main, catcher = P.frames.main, P.frames.cursorIntercept
    guarding = true
    main:SetAlpha(0)
    if catcher then catcher:EnableMouse(false) end
    guarding = nil
end

local function restoreScoots()
    local main, catcher = P.frames.main, P.frames.cursorIntercept
    guarding = true
    main:SetAlpha(wantedAlpha)
    if catcher then catcher:EnableMouse(not opt("non-interactive")) end
    guarding = nil
end

local function guardScoots()
    local main, catcher = P.frames.main, P.frames.cursorIntercept
    hooksecurefunc(main, "SetAlpha", function(self, a)
        if guarding then return end
        wantedAlpha = a
        if active then guarding = true self:SetAlpha(0) guarding = nil end
    end)
    if catcher and not catcher._dsynGuard then
        catcher._dsynGuard = true
        hooksecurefunc(catcher, "EnableMouse", function(self, on)
            if guarding or not (active and on) then return end
            guarding = true self:EnableMouse(false) guarding = nil
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Mover
-- ---------------------------------------------------------------------------

local function setMover(x, y)
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function save()
    local x, y = mover:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return end
    db().x, db().y = x - ux, y - uy
    setMover(db().x, db().y)
end

-- First run: start where Scoots' bar was.
local function placeMover()
    local d = db()
    if d.x then return setMover(d.x, d.y) end
    local mx, my = P.frames.main:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if mx and ux then
        local s = P.frames.main:GetEffectiveScale() / UIParent:GetEffectiveScale()
        setMover(mx * s - ux, my * s - uy)
    else
        setMover(0, 200)
    end
end

local function createMover()
    local D = NS.D
    if D and D.CreateUIFrame and D.RegisterEditableFrame then
        if type(D.L) == "table" and rawget(D.L, MOVER) == nil then rawset(D.L, MOVER, "Progress Bars") end
        mover = D.CreateUIFrame(300, 40, MOVER)
        mover:HookScript("OnDragStop", save)
        D:RegisterEditableFrame({
            name = MOVER, frame = mover,
            editorVisible = function() return active end,
            onNudge = save,
            resetPosition = function() db().x, db().y = nil, nil placeMover() end,
            isDefaultPosition = function() return db().x == nil end,
            module = Part,
        })
    else
        mover = CreateFrame("Frame", "DragonUI_" .. MOVER, UIParent)
    end
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetPoint("TOP", mover, "TOP", 0, 0)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function strip(owner, layer, sub, file, inset)
    local dir = NS.D._dir
    local left = owner:CreateTexture(nil, layer, nil, sub)
    left:SetTexture(dir .. file)
    left:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, inset)
    left:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, -inset)
    local right = owner:CreateTexture(nil, layer, nil, sub)
    right:SetTexture(dir .. file .. "_r")
    right:SetTexCoord(0, 113 / 128, 0, 1)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, -inset)
    owner:HookScript("OnSizeChanged", function(self)
        left:SetWidth(math.max(1, (self:GetWidth() or 0) * 1024 / 1137))
    end)
    left.pair = right
    return left
end

-- 3.3.5 has no SetShown.
local function setShown(region, on)
    if on then region:Show() else region:Hide() end
end

local function showPair(t, on)
    if on then t:Show() t.pair:Show() else t:Hide() t.pair:Hide() end
end

local function tintPair(t, r, g, b, a)
    t:SetVertexColor(r, g, b, a) t.pair:SetVertexColor(r, g, b, a)
end

local function onEnter(row)
    row.hover = true
    local catcher = P.frames.cursorIntercept
    local script = catcher and catcher:GetScript("OnEnter")
    if script then pcall(script, catcher) end
    Part.Redraw()
end

local function onLeave(row)
    row.hover = nil
    local catcher = P.frames.cursorIntercept
    local script = catcher and catcher:GetScript("OnLeave")
    if script then pcall(script, catcher) end
    Part.Redraw()
end

local function onClick(_, button)
    if IsModifierKeyDown() then return end
    if button == "RightButton" then
        pcall(P.options.open)
    else
        pcall(P.core.cycleActive)
        local catcher = P.frames.cursorIntercept
        if opt("tooltip-display") == "visible" and catcher then
            pcall(catcher:GetScript("OnLeave"), catcher)
            pcall(catcher:GetScript("OnEnter"), catcher)
        end
    end
    Part.Redraw()
end

local function newRow()
    local row = CreateFrame("Frame", nil, holder)
    row:EnableMouse(true)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row:SetScript("OnMouseUp", onClick)

    local dir = NS.D._dir
    row.trough = row:CreateTexture(nil, "BACKGROUND", nil, -6)
    row.trough:SetTexture(dir .. SHEET)
    row.trough:SetTexCoord(unpack(ROUND_TROUGH))
    row.trough:SetPoint("TOPLEFT", row, "TOPLEFT", -1, 0)
    row.trough:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 2, 0)
    row.dfTrough = strip(row, "BACKGROUND", -6, "XP\\Background", 0)

    row.fill = row:CreateTexture(nil, "BORDER")
    row.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.pending = row:CreateTexture(nil, "BORDER", nil, -1)
    row.pending:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.pending:SetPoint("TOPLEFT", row.fill, "TOPRIGHT", 0, 0)
    row.pending:SetPoint("BOTTOMLEFT", row.fill, "BOTTOMRIGHT", 0, 0)

    row.frame = row:CreateTexture(nil, "ARTWORK")
    row.frame:SetTexture(dir .. SHEET)
    row.frame:SetTexCoord(unpack(ROUND_FRAME))
    row.frame:SetPoint("TOPLEFT", row, "TOPLEFT", -3, 3)
    row.frame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 3, -6)
    row.dfFrame = strip(row, "ARTWORK", 0, "XP\\Overlay", 1)

    row.text = row:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
    row.text:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
    return row
end

-- A fill with a little shading top to bottom, in the colour Scoots gives it.
local function shade(tex, r, g, b, a)
    tex:SetGradientAlpha("VERTICAL", r * 0.65, g * 0.65, b * 0.65, a or 1, r, g, b, a or 1)
end

-- The bars Scoots is showing right now, in its order.
local function shownKeys()
    local keys = {}
    if opt("mode") == "single" then
        local ok, key = pcall(P.utility.getActiveBar)
        if ok and key then keys[1] = key end
    else
        for _, entry in ipairs(P.core.barOrder or {}) do
            local ok, valid = pcall(P.utility.isBarValid, entry.key)
            if ok and valid then keys[#keys + 1] = entry.key end
        end
    end
    return keys
end

local function paintRow(row, key, width, height, look)
    local source = P.frames.bars and P.frames.bars[key]
    local values = P.core.values and P.core.values[key]
    row:SetSize(width, height)
    row.key = key

    local round = look == "round"
    local framed = opt("borders") ~= "none"
    setShown(row.trough, round)
    showPair(row.dfTrough, not round)
    setShown(row.frame, round and framed)
    showPair(row.dfFrame, not round and framed)

    -- Colours exactly as Scoots last applied them (bars with their own colour rules included).
    local br, bg, bb, ba = 1, 1, 1, 1
    if source and source.background then br, bg, bb, ba = source.background:GetVertexColor() end
    row.trough:SetVertexColor(br, bg, bb, ba)
    tintPair(row.dfTrough, br, bg, bb, ba)

    -- Where the fill may go. The Dragonflight strips are 32 texels tall with transparent margins: the
    -- frame's inside runs from texel row 5 to 23 (the rows below are its drop shadow), drawn on a strip
    -- 1px taller than the row at each end; without the frame, the trough covers rows 3 to 25. Its rounded
    -- ends leave about 4 of 1137 texels at each side. The retail art fills the row edge to edge.
    local inX, top, bottom = 0, 0, 0
    if not round then
        inX = math.floor(width * 4 / 1137 + 0.5)
        if framed then
            top = (height + 2) * 5 / 32 - 1
            bottom = height - ((height + 2) * 23 / 32 - 1)
        else
            top = height * 3 / 32
            bottom = height - height * 25 / 32
        end
    end
    row.fill:ClearAllPoints()
    row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", inX, -top)
    row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", inX, bottom)
    local innerWidth = width - 2 * inX
    -- Text centred on the inside of the frame rather than on the whole row.
    local lift = (bottom - top) / 2
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 2 + inX, lift)
    row.text:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2 - inX, lift)

    local percent = math.min(100, math.max(0, values and values.percent or 0))
    local fillWidth = innerWidth * percent / 100
    if fillWidth >= 1 and source and source.progress then
        row.fill:SetWidth(fillWidth)
        shade(row.fill, source.progress:GetVertexColor())
        row.fill:Show()
    else
        row.fill:SetWidth(0.001)
        row.fill:Hide()
    end

    -- Rested experience and the like: Scoots' own "pending" slice, as a share of its bar.
    local pending = source and source.pending
    local total = P.frames.main:GetWidth()
    if pending and pending:IsShown() and total and total > 0 then
        local r, g, b, a = pending:GetVertexColor()
        row.pending:SetWidth(math.max(0.001, math.min(innerWidth - fillWidth, innerWidth * pending:GetWidth() / total)))
        shade(row.pending, r, g, b, (a or 1) * 0.8)
        row.pending:Show()
    else
        row.pending:Hide()
    end

    -- Text: Scoots' formatted string, font, colour and alignment; "hover" shows it while hovered.
    local text = source and source.text
    if text then
        local path, size, flags = text:GetFont()
        if path then row.text:SetFont(path, size, flags) end
        row.text:SetTextColor(text:GetTextColor())
        row.text:SetJustifyH(text:GetJustifyH() or "CENTER")
        row.text:SetText(text:GetText() or "")
    end
    local mode = opt("show-text")
    local anyHover = false
    for _, r in ipairs(rows) do if r.hover then anyHover = true end end
    setShown(row.text, mode == "always" or (mode == "hover" and anyHover))

    row:EnableMouse(not opt("non-interactive"))
    row:Show()
end

function Part.Redraw()
    if not (active and holder and P) then return end
    local keys = shownKeys()
    local look = style()
    local width = P.frames.main:GetWidth() or 300
    local height = tonumber(opt("height")) or 12
    if opt("mode") ~= "single" and opt("multi-mode-sizing") == "compress" and #keys > 0 then
        height = height / #keys
    end
    local gap = GAP[look]
    local y = 0
    for index, key in ipairs(keys) do
        local row = rows[index] or newRow()
        rows[index] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
        paintRow(row, key, width, height, look)
        y = y + height + gap
    end
    for index = #keys + 1, #rows do rows[index]:Hide() end

    local total = math.max(1, y - gap)
    holder:SetSize(width, total)
    holder:SetAlpha(math.min(1, math.max(0, (tonumber(opt("overall-opacity")) or 100) / 100)))
    holder:SetFrameStrata(P.frames.main:GetFrameStrata() or "MEDIUM")
    mover:SetSize(width, total)
end

-- ---------------------------------------------------------------------------
-- On / off
-- ---------------------------------------------------------------------------

local pending
local function redrawSoon()
    if pending then return end
    pending = true
    NS.After(0, function() pending = nil Part.Redraw() end)
end

local hooked
local function hookScoots()
    if hooked then return end
    hooked = true
    for _, name in ipairs({ "renderBarValues", "applyColours", "setBarPositions", "applyTextOptions",
                            "applyDimensions", "showAllEnabled", "hideAllExcept" }) do
        if P.interface[name] then hooksecurefunc(P.interface, name, redrawSoon) end
    end
    for _, name in ipairs({ "setActive", "setMode", "preCacheOrder" }) do
        if P.core[name] then hooksecurefunc(P.core, name, redrawSoon) end
    end
    guardScoots()
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local elapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < POLL then return end
    elapsed = 0
    Part.Redraw()
end)

function Part.Apply()
    P = P or scoots()
    if not (P and P.interface.built) then return false end
    if not mover then createMover() placeMover() end
    hookScoots()
    if enabled() then
        active = true
        hideScoots()
        holder:Show()
        ticker:Show()
        Part.Redraw()
    else
        active = false
        ticker:Hide()
        holder:Hide()
        restoreScoots()
    end
    return true
end
NS.ApplyProgressBars = function() if P or scoots() then Part.Apply() end end

local applied
function Part.Check()
    if applied or not scoots() then return end
    if Part.Apply() then applied = true end
end

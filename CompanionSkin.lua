local _, NS = ...

-- A "DragonUI" skin for SynastriaCompanion, through Companion's own skin system (its MaterialCraftUI style
-- kit: S.RegisterSkin). Pick it in Companion's settings like its other themes. Nothing in Companion is changed.
--
-- Companion picks its saved skin while it loads (its ADDON_LOADED), and drops an unknown one back to
-- Material, so the skin has to be registered before that. This addon loads first (alphabetical, and it
-- must not list Companion as a dependency), so its ADDON_LOADED handler for Companion runs before
-- Companion's own and registers the skin just in time.

local GOLD, WHITE, GRAY = { 1, 0.82, 0, 1 }, { 1, 1, 1, 1 }, { 0.5, 0.5, 0.5, 1 }
local LABEL = { primary = GOLD, secondary = GOLD, ghost = GOLD, selected = WHITE, danger = { 1, 0.4, 0.35, 1 } }
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
-- The metal frame's grey title bar is about 21px, shorter than Companion's title bar (its controls run
-- roughly 13..35px down). The bar is made taller: the three top pieces of the frame (top-left corner, top
-- edge, top-right corner, 75 texels tall, starting 16 above the frame, the grey bar being rows 16-37) are
-- each cut into three slices: rows 0-28 as they are, rows 28-30 (plain grey) stretched by BAND_EXTRA, and
-- rows 30-75 as they are, moved down by BAND_EXTRA. The metal keeps its thickness; only the grey grows.
local BAND_EXTRA = 20
local CUT_A, CUT_B, ROWS = 28, 30, 75

local function coordsOf(tex)
    local ulx, uly, llx, lly, urx, ury = tex:GetTexCoord()
    return ulx, urx, uly, lly
end

local function slice(owner, piece, fromRow, toRow, height)
    local l, r, t, b = coordsOf(piece)
    local tex = owner:CreateTexture(nil, piece:GetDrawLayer())
    tex:SetTexture(piece:GetTexture())
    -- The top edge repeats across the window rather than stretching; its slices repeat the same way.
    if piece.GetHorizTile and piece:GetHorizTile() then tex:SetHorizTile(true) end
    tex:SetTexCoord(l, r, t + (b - t) * fromRow / ROWS, t + (b - t) * toRow / ROWS)
    tex:SetHeight(height)
    return tex
end

-- piece: one of the ring's top pieces; place(top) anchors the new top slice where the piece's top was.
local function cutPiece(ring, piece, place)
    local h = piece:GetHeight()
    local l, r, t, b = coordsOf(piece)
    local top = slice(ring, piece, 0, CUT_A, h * CUT_A / ROWS)
    local mid = slice(ring, piece, CUT_A, CUT_B, h * (CUT_B - CUT_A) / ROWS + BAND_EXTRA)
    place(top)
    mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    mid:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    -- The original piece becomes the bottom slice, so the side edges that hang off it follow it down.
    piece:SetTexCoord(l, r, t + (b - t) * CUT_B / ROWS, b)
    piece:SetHeight(h * (ROWS - CUT_B) / ROWS)
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", mid, "BOTTOMLEFT")
    piece:SetPoint("TOPRIGHT", mid, "BOTTOMRIGHT")
    return top
end

local function stretchTopBand(ring)
    local left, edge, right = ring.TopLeftCorner, ring.TopEdge, ring.TopRightCorner
    if not (left and edge and right) then return end
    local lw, rw = left:GetWidth(), right:GetWidth()
    local leftTop = cutPiece(ring, left, function(tex)
        tex:SetPoint("TOPLEFT", ring, "TOPLEFT", -13, 16)
        tex:SetWidth(lw)
    end)
    local rightTop = cutPiece(ring, right, function(tex)
        tex:SetPoint("TOPRIGHT", ring, "TOPRIGHT", 4, 16)
        tex:SetWidth(rw)
    end)
    cutPiece(ring, edge, function(tex)
        tex:SetPoint("TOPLEFT", leftTop, "TOPRIGHT", -4, 0)
        tex:SetPoint("TOPRIGHT", rightTop, "TOPLEFT", 4, 0)
    end)
end

local function A()
    return NS.D and NS.D.ForeverAtlas
end

local function setAtlas(tex, name)
    local entry = A() and A()[name]
    if not entry then return end
    tex:SetTexture(entry[1])
    tex:SetTexCoord(entry[4], entry[5], entry[6], entry[7])
end

local function nineSlice(frame, layout)
    local slicer = _G.DragonUI_NineSlice
    if slicer and slicer.ApplyLayout and slicer.GetLayout then
        local def = slicer.GetLayout(layout)
        if def then slicer.ApplyLayout(frame, def) end
    end
end

-- A child at the frame's own level: over the frame's art, under everything the frame holds.
local function under(frame)
    local layer = CreateFrame("Frame", nil, frame)
    layer:SetFrameLevel(frame:GetFrameLevel())
    layer:EnableMouse(false)
    return layer
end

local function fill(frame, alpha, inset)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    t:SetTexture(WHITE8)
    t:SetVertexColor(0, 0, 0, alpha)
    t:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    t:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    return t
end

-- The tracker-style hover glow: gold fading out to the right.
local function glow(frame, layer, alpha)
    local t = frame:CreateTexture(nil, layer or "HIGHLIGHT")
    t:SetTexture(WHITE8)
    t:SetBlendMode("ADD")
    t:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, alpha or 0.2, 1, 0.82, 0, 0)
    t:SetAllPoints()
    return t
end

-- DragonUI's red panel button: three slices scaled to the button's height (as ForeverUI's buttons).
local function redButton(b)
    local parts = {}
    for i = 1, 3 do parts[i] = b:CreateTexture(nil, "BORDER") end
    parts[1]:SetPoint("TOPLEFT")
    parts[3]:SetPoint("TOPRIGHT")
    parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
    parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
    b.dsynParts = parts
    local function layout()
        local w, h = b:GetWidth(), b:GetHeight()
        if not (w and h) or h <= 0 then return end
        local scale = h / 128
        local lw, rw = 114 * scale, 292 * scale
        if lw + rw > w then local k = w / (lw + rw) lw, rw = lw * k, rw * k end
        parts[1]:SetSize(lw, h)
        parts[3]:SetSize(rw, h)
    end
    b:HookScript("OnSizeChanged", layout)
    layout()
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    setAtlas(hi, "128-redbutton-highlight")
    hi:SetBlendMode("ADD")
    hi:SetAllPoints()
    b.dsynGlow = hi
end

local function paintRedButton(b, enabled)
    local suffix = not enabled and "-disabled" or (b.down or b.kind == "selected") and "-pressed" or ""
    setAtlas(b.dsynParts[1], "128-redbutton-left" .. suffix)
    setAtlas(b.dsynParts[2], "_128-redbutton-center" .. suffix)
    setAtlas(b.dsynParts[3], "128-redbutton-right" .. suffix)
    b.dsynGlow:SetAlpha(enabled and 1 or 0)
    if b.label then b.label:SetTextColor(unpack(enabled and (LABEL[b.kind] or GOLD) or GRAY)) end
end

local function insetPanel(frame, alpha)
    fill(frame, alpha, 3)
    local trim = under(frame)
    trim:SetAllPoints(frame)
    nineSlice(trim, "InsetFrameTemplate")
end

local function threeSlice(frame, layer, left, middle, right, capW)
    local parts = {}
    for i = 1, 3 do parts[i] = frame:CreateTexture(nil, layer) end
    setAtlas(parts[1], left) setAtlas(parts[2], middle) setAtlas(parts[3], right)
    parts[1]:SetPoint("TOPLEFT") parts[1]:SetPoint("BOTTOMLEFT") parts[1]:SetWidth(capW)
    parts[3]:SetPoint("TOPRIGHT") parts[3]:SetPoint("BOTTOMRIGHT") parts[3]:SetWidth(capW)
    parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
    parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
    return parts
end

local function define(S)
    S.RegisterSkin("dragonui", {
        label = "DragonUI",
        credit = "DragonUI's metal frames, rock background, red buttons and silver checkboxes.",
        roles = {
            surfaceLowest = "000000", surface = "0b0b0b", surfaceLow = "121110", surfaceContainer = "171614",
            surfaceHigh = "26241f", onSurface = "ffffff", onSurfaceVariant = "c8c3b8", outline = "8c8577",
            outlineVariant = "4a463d", primary = "ffd100", onPrimary = "000000", error = "ff3a30",
            errorContainer = "5a1210", success = "1eff00", warning = "ff8000", red = "ff4040", blue = "40a0ff",
            green = "40ff40", yellow = "ffd100",
        },
        colors = function(c)
            c.heading = GOLD
            c.disabled = GRAY
            c.rowHover = { 1, 0.82, 0, 0.12 }
            c.rowSelected = { 1, 0.82, 0, 0.2 }
            c.navSelected = WHITE
            c.arrow = GOLD
            c.scrollThumb = { 0.75, 0.6, 0.2, 1 }
            c.scrollThumbHover = { 1, 0.82, 0.25, 1 }
            c.scrollTrack = { 0, 0, 0, 0.45 }
        end,
        metrics = { edge = 6, inset = 16, navInset = 4, wellInset = 4, menuInset = 4, tabPad = 16 },

        button = redButton,
        paintButton = paintRedButton,

        -- Windows: rock ground and the metal frame, its title band above the window. Popups: a dark panel
        -- with the inset trim. Menus: DragonUI's dropdown menu art.
        frame = function(f, role)
            if role == "menu" then
                local UI = NS.D.ForeverUI
                if UI and UI.SkinMenuBackground then UI.SkinMenuBackground(f, "bg") else fill(f, 0.92) end
                return
            end
            if role == "window" then
                -- Rock ground and the metal frame, under the window's contents so it never covers them.
                -- The frame's grey title bar is made tall enough for Companion's whole title bar (title,
                -- theme, size, Game Window, Close) to sit inside it; the bar's bottom rule is drawn as the
                -- frame's inner line (line()).
                local rock = f:CreateTexture(nil, "BACKGROUND", nil, -8)
                rock:SetTexture(NS.D._dir .. "UI\\ui-background-rock")
                rock:SetHorizTile(true)
                rock:SetVertTile(true)
                rock:SetPoint("TOPLEFT", 2, -2)
                rock:SetPoint("BOTTOMRIGHT", -2, 2)
                local ring = under(f)
                ring:SetAllPoints(f)
                nineSlice(ring, "NoPortraitFrameTemplate")
                local ok, err = pcall(stretchTopBand, ring)
                if not ok and NS.Report then NS.Report(err) end
                f.fill = rock
            else
                insetPanel(f, 0.88)
            end
        end,
        well = function(f)
            insetPanel(f, 0.45)
        end,
        -- Gold rules fading to the right, like DragonUI's section lines; none under the title bar, which the
        -- metal band already sets apart.
        -- The title bar's rule is DragonUI's inner frame line, which closes off the header band like the
        -- line under a DragonUI window's title. Other rules (tab bars, table headers, section headings) are
        -- gold, fading to the right.
        line = function(parent, kind)
            local t = parent:CreateTexture(nil, "BORDER")
            if kind == "rule" then
                t:SetAtlasTexture("_UI-Frame-InnerTopTile")
                t:SetHorizTile(true)
                return t, 3
            end
            t:SetTexture(WHITE8)
            t:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.45, 1, 0.82, 0, 0.08)
            return t, 1
        end,
        sidebar = function(side)
            fill(side, 0.3)
            local edge = side:CreateTexture(nil, "BORDER")
            edge:SetTexture(WHITE8)
            edge:SetGradientAlpha("VERTICAL", 1, 0.82, 0, 0.05, 1, 0.82, 0, 0.35)
            edge:SetWidth(1)
            edge:SetPoint("TOPRIGHT")
            edge:SetPoint("BOTTOMRIGHT")
        end,
        highlight = function(f)
            glow(f)
        end,
        navEntry = function(b)
            glow(b)
            b.selectedTex = glow(b, "BACKGROUND", 0.3)
            b.label:SetPoint("LEFT", S.PAD, 0)
        end,
        paintNav = function(b, on)
            if on then b.selectedTex:Show() else b.selectedTex:Hide() end
        end,
        row = function(r)
            glow(r, "HIGHLIGHT", 0.15)
            r.selectedTex = glow(r, "BACKGROUND", 0.25)
        end,
        paintRow = function(r, on)
            if on then r.selectedTex:Show() else r.selectedTex:Hide() end
        end,
        -- DragonUI's minimal checkbox in silver, its gold tick in colour.
        check = function(b)
            local size = math.max(b:GetWidth() or 16, 16) + 4
            local function layer(name, atlas)
                local t = b:CreateTexture(nil, name)
                setAtlas(t, atlas)
                t:SetPoint("CENTER")
                t:SetSize(size, size)
                return t
            end
            b.box = layer("BACKGROUND", "checkbox-minimal")
            b.box:SetDesaturated(true)
            b.tick = layer("ARTWORK", "checkmark-minimal")
            b.glow = layer("HIGHLIGHT", "checkbox-minimal")
            b.glow:SetBlendMode("ADD")
            b.glow:SetDesaturated(true)
        end,
        paintCheck = function(b)
            if b.on then b.tick:Show() else b.tick:Hide() end
            b.tick:SetDesaturated(not b.usable)
            b.box:SetAlpha(b.usable and 1 or 0.5)
            b.glow:SetAlpha(b.usable and 0.4 or 0)
        end,
        -- One-line fields: DragonUI's search-box border. Tall ones: a dark inset panel.
        input = function(e, tall)
            e.tall = tall
            if tall then
                insetPanel(e.box, 0.6)
            else
                e.border = threeSlice(e, "BACKGROUND", "common-search-border-left", "common-search-border-middle",
                    "common-search-border-right", 8)
            end
        end,
        paintInput = function(e)
            if e.tall then return end
            local v = (e.focused or e.hovered) and 1 or 0.75
            for _, t in ipairs(e.border) do t:SetVertexColor(v, v, v) end
        end,
    })
end

-- The same style kit (MaterialCraftUI, same author) is in SynastriaBuildSuite and RotationAssist, each
-- exposing it as <Global>.Style and applying its saved skin on its own ADDON_LOADED, so the one definition
-- registers with each. Every one of them loads after this addon (alphabetical), and none may be listed as
-- a dependency, or its handler would run first and drop the unknown skin back to Material.
local ADDONS = {
    SynastriaCompanion = "companionSkin",
    SynastriaBuildSuite = "buildSuiteSkin",
    RotationAssist = "rotationAssistSkin",
}

local registered = {}
local function register(name)
    local key = ADDONS[name]
    local host = _G[name]
    local S = host and host.Style
    if registered[name] or not (S and S.RegisterSkin) or (NS.db and NS.db[key] == false) then return end
    registered[name] = true
    local ok, err = pcall(define, S)
    if not ok and NS.Report then NS.Report(err) end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, name)
    if ADDONS[name] then register(name) end
end)
for name in pairs(ADDONS) do
    if IsAddOnLoaded(name) then register(name) end
end

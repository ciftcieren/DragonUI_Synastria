local ADDON, NS = ...

-- The server sends its UI as Lua after login and may rebuild a frame under the same name, so every
-- part checks once a second and re-applies itself to whatever frame currently holds the name.
NS.D = _G.DragonUI
NS.modules = {}

local DEFAULTS = { scootsVendor = true, scootsCraft = true, itemHunt = true, serverWindows = true, attuneBarSkin = true,
    finderSkin = true, stanceExtra = true, bossExtra = true, attune = {}, finder = {} }
-- Keys no longer used: "skin" (once one switch for server windows, Attune Bar and Finder) and "filters"
-- (the profession filters are always on now).
local RETIRED = { "skin", "filters" }

function NS.Register(part)
    NS.modules[#NS.modules + 1] = part
end

function NS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1DragonUI Synastria:|r " .. tostring(msg))
end

local reported = {}
local function report(err)
    err = tostring(err)
    if not reported[err] then
        reported[err] = true
        NS.Print("|cffff5555" .. err .. "|r")
    end
end
NS.Report = report

-- Runs fn after `delay` seconds (0 = next frame). Errors are reported once, like the parts' own.
local timers = CreateFrame("Frame")
local pending = {}
timers:SetScript("OnUpdate", function(_, dt)
    for i = #pending, 1, -1 do
        local job = pending[i]
        job.left = job.left - dt
        if job.left <= 0 then
            table.remove(pending, i)
            local ok, err = pcall(job.fn)
            if not ok then report(err) end
        end
    end
end)
function NS.After(delay, fn)
    pending[#pending + 1] = { left = delay or 0, fn = fn }
end

-- One hidden tooltip for reading item text (bind lines); shared so its line names never collide.
local scanTip
function NS.ScanTip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "DragonUISynastriaScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    return scanTip
end

function NS.Check()
    for _, part in ipairs(NS.modules) do
        if part.Check then
            local ok, err = pcall(part.Check)
            if not ok then report(err) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Skinning: drop the server's own backdrop/border art and put DragonUI's dialog chrome under it.
-- ---------------------------------------------------------------------------

local function isIcon(texture)
    local path = texture:GetTexture()
    return type(path) == "string" and path:lower():find("interface\\icons", 1, true) ~= nil
end

function NS.StripArt(frame)
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" and not isIcon(region) then
            region:SetAlpha(0)
        end
    end
end

-- Holds a region at our anchors: whenever server code re-anchors it, the anchors are put back.
-- points: list of { point, relativeTo, relativePoint, x, y }.
function NS.Pin(region, points)
    region._dsynPoints = points
    local function place()
        region._dsynPlacing = true
        region:ClearAllPoints()
        for _, p in ipairs(region._dsynPoints) do region:SetPoint(unpack(p)) end
        region._dsynPlacing = nil
    end
    if not region._dsynPinned then
        region._dsynPinned = true
        hooksecurefunc(region, "SetPoint", function(self)
            if not self._dsynPlacing and self._dsynPoints then place() end
        end)
    end
    place()
end

-- The highest text on the frame itself is its title; hand it to DragonUI's title line.
local function takeTitle(frame)
    local best, bestTop
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            local text, top = region:GetText(), region:GetTop()
            if text and text ~= "" and top and (not bestTop or top > bestTop) then
                best, bestTop = region, top
            end
        end
    end
    if best then
        best:SetAlpha(0)
        return best:GetText()
    end
end

-- Red buttons from DragonUI's redbutton2x sheet: columns per icon, rows per state (as the map's own buttons).
local RED_COLUMNS = { close = { 39, 75 }, expand = { 77, 113 }, condense = { 1, 37 } }
local RED_ROWS = { Normal = { 1, 39 }, Pushed = { 81, 119 }, Disabled = { 41, 79 } }

-- Sets a button's art to one red icon (close / expand / condense); safe to call again to switch icons.
function NS.SetRedIcon(button, kind)
    local sheet = NS.D._dir .. "UI\\redbutton2x"
    local col = RED_COLUMNS[kind]
    -- The server's own icon regions go; the state textures are replaced below.
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    for state, row in pairs(RED_ROWS) do
        button["Set" .. state .. "Texture"](button, sheet)
        local tex = button["Get" .. state .. "Texture"](button)
        tex:SetTexCoord(col[1] / 256, col[2] / 256, row[1] / 128, row[2] / 128)
        tex:SetAlpha(1)
    end
    button:SetHighlightTexture(sheet, "ADD")
    local glow = button:GetHighlightTexture()
    glow:SetTexCoord(115 / 256, 151 / 256, 1 / 128, 39 / 128)
    glow:SetAlpha(1)
    button:SetSize(24, 24)
end

-- Over the metal frame (which sits 8 levels above its window) so the title band doesn't hide it.
local function raiseOver(button, root)
    button:SetFrameLevel(root:GetFrameLevel() + 10)
end

local function dressRedButton(button, kind, anchor, root)
    NS.SetRedIcon(button, kind)
    raiseOver(button, root)
    NS.Pin(button, { anchor })
end

-- Silver instead of gold: greys the Forever checkbox frame, leaving the check mark and the icon in colour.
function NS.SilverCheckButton(button)
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() ~= "OVERLAY" then
            region:SetDesaturated(true)
        end
    end
end

-- The quest log's settings cog (questlog-icon-setting), for a button that opens an options menu.
local function dressCogButton(button, anchor)
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    local blank = "Interface\\Buttons\\WHITE8X8"
    button:SetNormalTexture(blank)
    button:SetPushedTexture(blank)
    button:SetHighlightTexture(blank, "ADD")
    for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetHighlightTexture() }) do
        tex:SetAtlasTexture("questlog-icon-setting")
        tex:SetVertexColor(1, 1, 1)
        tex:SetAlpha(1)
    end
    button:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
    button:GetHighlightTexture():SetAlpha(0.4)
    button:SetSize(18, 18)
end

-- The world map's quest search look: the stock input border, a magnifier, and a grey hint while empty.
function NS.SkinSearchBox(box, hintText)
    if box._dsynSearch then return end
    box._dsynSearch = true
    box:SetTextInsets(18, 6, 0, 0)
    box:SetAutoFocus(false)
    local glass = box:CreateTexture(nil, "OVERLAY")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", box, "LEFT", 2, -1.5)
    glass:SetTexture(NS.D._dir .. "Collections\\UI-Searchbox-Icon")
    local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", box, "LEFT", 20, 0)
    hint:SetText(hintText or SEARCH)
    local function refresh(self)
        if (self:GetText() or "") == "" and not self._dsynFocused then hint:Show() else hint:Hide() end
    end
    box:HookScript("OnTextChanged", refresh)
    box:HookScript("OnEditFocusGained", function(self) self._dsynFocused = true refresh(self) end)
    box:HookScript("OnEditFocusLost", function(self) self._dsynFocused = nil refresh(self) end)
    refresh(box)
end

-- DragonUI's bag slot look (bags_skin.lua): flat slot, quickslot ring, matching pushed/highlight.
function NS.SkinItemSlot(button)
    if button._dsynSlot then return end
    button._dsynSlot = true
    local dir = NS.D._dir
    for _, region in ipairs({ button:GetRegions() }) do
        local path = region:GetObjectType() == "Texture" and region:GetTexture()
        if type(path) == "string" and path:lower():find("emptyslot", 1, true) then region:SetAlpha(0) end
    end
    local function fit(tex, path, size, y)
        if not tex then return end
        tex:SetTexture(path)
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", button, "CENTER", 0, y or 0)
    end
    local normal = button:GetNormalTexture()
    fit(normal, dir .. "Bags\\bagsitemslot2x", 37)
    if normal then normal:SetDrawLayer("BACKGROUND") end
    local ring = button:CreateTexture(nil, "BORDER")
    fit(ring, dir .. "UI\\ui-quickslot2", 64, -1)
    fit(button:GetPushedTexture(), dir .. "UI\\ui-quickslot-depress", 37)
    fit(button:GetHighlightTexture(), dir .. "UI\\buttonhilight-square", 37)
end

-- A thin flat bar frame in place of the tooltip border the server draws around progress bars.
function NS.SkinBarFrame(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0.55)
    frame:SetBackdropBorderColor(0, 0, 0, 0.9)
end

local function skinChildren(frame, root, UI, depth)
    local rootName = root:GetName() or ""
    for _, child in ipairs({ frame:GetChildren() }) do
        local kind, name = child:GetObjectType(), child:GetName() or ""
        if child ~= root._dsynBack and child ~= root._dsynRing then
            if name == rootName .. "-Close" then
                -- The server's "-Close" collapses the panel: the map's condense button, top right.
                dressRedButton(child, "condense", { "TOPRIGHT", root, "TOPRIGHT", 1, 0 }, root)
            elseif name == rootName .. "-Expand" then
                -- The server's "-Expand" opens its options menu: the quest log's cog, left of collapse.
                dressCogButton(child)
                raiseOver(child, root)
                NS.Pin(child, { { "TOPRIGHT", root, "TOPRIGHT", -26, -3 } })
            elseif kind == "EditBox" then
                NS.SkinSearchBox(child)
            elseif kind == "CheckButton" and UI.SkinCheckButton then
                pcall(UI.SkinCheckButton, child)
                NS.SilverCheckButton(child)
            elseif kind == "Button" and UI.SkinButton and child:GetText() and child:GetText() ~= "" then
                pcall(UI.SkinButton, child)
            end
            if depth < 4 then skinChildren(child, root, UI, depth + 1) end
        end
    end
end

-- The world map's own chrome: metal nine-slice frame, tiled rock ground, gold title in the top band.
local function mapChrome(frame, title)
    local dir = NS.D._dir
    local back = CreateFrame("Frame", nil, frame)
    back:SetAllPoints(frame)
    back:SetFrameLevel(frame:GetFrameLevel())
    back:EnableMouse(false)
    frame._dsynBack = back

    local rock = back:CreateTexture(nil, "BACKGROUND")
    rock:SetTexture(dir .. "UI\\ui-background-rock", "REPEAT", "REPEAT")
    if rock.SetHorizTile then
        rock:SetHorizTile(true)
        rock:SetVertTile(true)
    end
    rock:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
    rock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    -- The metal sits above the server's children so nothing pokes over the frame's edge.
    local ring = CreateFrame("Frame", nil, frame)
    ring:SetAllPoints(frame)
    ring:SetFrameLevel(frame:GetFrameLevel() + 8)
    ring:EnableMouse(false)
    frame._dsynRing = ring
    DragonUI_NineSlice.ApplyLayout(ring, DragonUI_NineSlice.GetLayout("NoPortraitFrameTemplate"))

    local band = ring:CreateTexture(nil, "BACKGROUND", nil, -5)
    if band.SetAtlasTexture then band:SetAtlasTexture("_UI-Frame-InnerTopTile") end
    band:SetHeight(3)
    band:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -19)
    band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -19)

    local text = ring:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", frame, "TOP", 0, -5)
    text:SetText(title or "")
    frame._dsynTitle = text
end

-- opts: title (text), titleFrom (frame whose top text is the title), hide (child frame names holding the
-- server's art), layout(frame) (re-runs on every show, after the server's own OnShow).
function NS.Skin(frame, opts)
    opts = opts or {}
    local UI = NS.D and NS.D.ForeverUI
    if not (UI and _G.DragonUI_NineSlice) then return false end

    local function strip(f)
        NS.StripArt(f)
        for _, name in ipairs(opts.hide or {}) do
            local art = _G[name]
            if art then art:SetAlpha(0) end
        end
    end

    if frame._dsynSkinned then
        strip(frame)
        if opts.layout then opts.layout(frame) end
        return true
    end
    frame._dsynSkinned = true
    local title = opts.title or takeTitle(opts.titleFrom or frame)
    strip(frame)
    mapChrome(frame, title)
    skinChildren(frame, frame, UI, 1)
    if opts.layout then opts.layout(frame) end
    -- Server code may put its art back whenever it redraws.
    frame:HookScript("OnShow", function(f)
        strip(f)
        if opts.layout then opts.layout(f) end
    end)
    return true
end

-- ---------------------------------------------------------------------------
-- /dsyn dump <frame>: records a frame tree into SavedVariables, for tuning skins.
-- ---------------------------------------------------------------------------

local function round(v) return v and math.floor(v + 0.5) or nil end

local function dumpFrame(frame, depth)
    local p, rel, rp, x, y = frame:GetPoint(1)
    local node = {
        name = frame:GetName(), type = frame:GetObjectType(),
        size = string.format("%sx%s", tostring(round(frame:GetWidth())), tostring(round(frame:GetHeight()))),
        shown = frame:IsShown() and true or false,
        point = p and string.format("%s %s %s %d %d", p, rel and (rel:GetName() or "<anon>") or "nil", rp or "", round(x) or 0, round(y) or 0),
        regions = {}, children = {},
    }
    for _, r in ipairs({ frame:GetRegions() }) do
        local entry = { type = r:GetObjectType(), layer = r.GetDrawLayer and r:GetDrawLayer() or nil, name = r:GetName() }
        entry.size = string.format("%sx%s", tostring(round(r:GetWidth())), tostring(round(r:GetHeight())))
        local rp1, rrel, rrp, rx, ry = r:GetPoint(1)
        if rp1 then
            entry.point = string.format("%s %s %s %d %d", rp1, rrel and (rrel:GetName() or "<anon>") or "nil", rrp or "", round(rx) or 0, round(ry) or 0)
        end
        if entry.type == "Texture" then
            entry.texture = r:GetTexture()
            local ulx, uly, _, lly, urx = r:GetTexCoord()
            entry.coords = string.format("%.3f %.3f %.3f %.3f", ulx or 0, urx or 0, uly or 0, lly or 0)
            entry.alpha = r:GetAlpha()
        end
        if entry.type == "FontString" then
            entry.text = r:GetText()
            entry.justify = r:GetJustifyH()
        end
        node.regions[#node.regions + 1] = entry
    end
    if depth < 6 then
        for _, child in ipairs({ frame:GetChildren() }) do
            node.children[#node.children + 1] = dumpFrame(child, depth + 1)
        end
    end
    return node
end

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "dump" and arg ~= "" then
        local frame = _G[arg]
        if not frame then return NS.Print("no frame named " .. arg) end
        NS.db.dump = NS.db.dump or {}
        NS.db.dump[arg] = dumpFrame(frame, 1)
        NS.Print("dumped " .. arg .. " (saved on /reload or logout)")
    elseif cmd == "skin" then
        -- All three window skins at once (each also has its own switch in the settings tab).
        local on = (arg == "on")
        NS.db.serverWindows, NS.db.attuneBarSkin, NS.db.finderSkin = on, on, on
        NS.Print("skin " .. (on and "on" or "off") .. " - /reload to apply")
    elseif cmd == "reset" and (arg == "attune" or arg == "finder") then
        local part = NS.parts and NS.parts[arg]
        if part and part.Reset then part.Reset() end
        NS.Print(arg .. " position reset")
    else
        NS.Print("/dsyn skin on|off, /dsyn reset attune|finder, /dsyn dump <FrameName>")
        NS.Print("Attune Bar: move it in DragonUI edit mode. Finder: Alt+drag it on the world map.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        DragonUI_SynastriaDB = DragonUI_SynastriaDB or {}
        local db = DragonUI_SynastriaDB
        -- The old combined switch, if it was off, carries over to the two that split from it.
        if db.skin == false then
            if db.attuneBarSkin == nil then db.attuneBarSkin = false end
            if db.finderSkin == nil then db.finderSkin = false end
        end
        for _, key in ipairs(RETIRED) do db[key] = nil end
        for key, value in pairs(DEFAULTS) do
            if DragonUI_SynastriaDB[key] == nil then
                DragonUI_SynastriaDB[key] = type(value) == "table" and {} or value
            end
        end
        NS.db = DragonUI_SynastriaDB
        SLASH_DRAGONUISYNASTRIA1 = "/dsyn"
        SlashCmdList.DRAGONUISYNASTRIA = slash
    elseif event == "PLAYER_LOGIN" then
        for _, part in ipairs(NS.modules) do
            if part.Init then
                local ok, err = pcall(part.Init)
                if not ok then report(err) end
            end
        end
        NS.started = true
        NS.Check()
    end
end)

local elapsed = 0
events:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 or not NS.started then return end
    elapsed = 0
    NS.Check()
end)

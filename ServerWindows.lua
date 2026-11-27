local _, NS = ...

-- One DragonUI skin for every Synastria server window. The server builds them all with the same function
-- (Custom_CreateFrame in its container_19): help-window art in named pieces (<name>-UL, -U, -UR, -L, -R, -M
-- and -BL/-B/-BR or -BLB/-BB/-BRB), a title plate (<name>-Header, <name>-HeaderText), a close button
-- (<name>-Close), an optional Help button and an optional scroll area. Each window also adds its name to
-- UISpecialFrames (Escape closes it), which is how new ones are found: any name there with a <name>-UL
-- piece is one of these windows. Warp, Bounty Hunter's Guild, Select Item/Zone, Pet Aspects, Updates,
-- the druid ability picker, the server's own perk/bank/loot windows... all get the same chrome.
local Part = {}
NS.Register(Part)

local ART = { "-UL", "-U", "-UR", "-L", "-R", "-M", "-BL", "-B", "-BR", "-BLB", "-BB", "-BRB", "-Header" }
-- Where the help-window art's visible panel sits inside the frame (the art has transparent margins;
-- the server puts its close button 42px in from the right edge). The top is raised so the metal title
-- band ends above the buttons the server puts 22px down (Help, Back, ...).
local INSET = { left = 4, top = 4, right = -40, bottom = 8 }

local skinned = {}

local function enabled()
    return NS.db and NS.db.serverWindows ~= false
end

local function isServerWindow(name)
    return type(name) == "string" and _G[name] and _G[name .. "-UL"] and _G[name .. "-Close"]
end

local function chrome(frame, name)
    local K, dir = NS.Kit, NS.D._dir
    local box = CreateFrame("Frame", nil, frame)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET.left, INSET.top)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", INSET.right, INSET.bottom)
    -- Same level as the window: above the window's own (hidden) art, under every child it has.
    box:SetFrameLevel(frame:GetFrameLevel())
    box:EnableMouse(false)
    local rock = box:CreateTexture(nil, "BACKGROUND", nil, -6)
    rock:SetTexture(dir .. "UI\\ui-background-rock")
    rock:SetHorizTile(true)
    rock:SetVertTile(true)
    rock:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -21)
    rock:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    K.NineSlice(box, "NoPortraitFrameTemplate")
    local band = box:CreateTexture(nil, "BORDER")
    band:SetAtlasTexture("_UI-Frame-InnerTopTile")
    band:SetHeight(3)
    band:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -19)
    band:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -19)
    frame._dsynBox = box
    return box
end

local WHITE8 = "Interface\\Buttons\\WHITE8X8"

local function texPath(tex)
    local path = tex and tex.GetTexture and tex:GetTexture()
    return type(path) == "string" and path:lower() or ""
end

local function isPanelButton(button)
    return texPath(button.GetNormalTexture and button:GetNormalTexture()):find("ui%-panel%-button") ~= nil
end

-- The skill-frame category header (SkillLabelTemplate): a +/- button with a label.
local function isHeader(button)
    -- The same template is also used as a bare 16px +/- button (loot filter's move up/down).
    if (button:GetWidth() or 0) < 100 then return false end
    local path = texPath(button:GetNormalTexture())
    return path:find("ui%-minusbutton") ~= nil or path:find("ui%-plusbutton") ~= nil
end

-- Tracker-style gold glow fading out to the right (Companion's row hover / selection).
local function goldGlow(tex, alpha)
    tex:SetTexture(WHITE8)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetBlendMode("ADD")
    tex:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, alpha, 1, 0.82, 0, 0)
end

-- A list row's hover (and LockHighlight selection) becomes the gold glow, sized to `area`.
local function rowGlow(button, area)
    button:SetHighlightTexture(WHITE8, "ADD")
    local hi = button:GetHighlightTexture()
    if not hi then return end
    goldGlow(hi, 0.22)
    hi:ClearAllPoints()
    hi:SetPoint("TOPLEFT", area or button, "TOPLEFT", -3, 1)
    hi:SetPoint("BOTTOMRIGHT", area or button, "BOTTOMRIGHT", 3, -1)
end

-- SkillStatusBarTemplate rows (the perk list): no bar border, background or fill; the gold glow instead.
local function skinSkillBar(row, name)
    for _, suffix in ipairs({ "Background", "FillBar" }) do
        local part = _G[name .. suffix]
        if part then part:SetAlpha(0) end
    end
    local border = _G[name .. "Border"]
    if border then
        local normal = border:GetNormalTexture()
        if normal then normal:SetAlpha(0) end
        rowGlow(border, row)
    end
end

-- Category headers keep their +/- and label; a gold rule fading to the right runs under them.
local function skinHeader(button)
    local rule = button:CreateTexture(nil, "BORDER")
    rule:SetTexture(WHITE8)
    rule:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.5, 1, 0.82, 0, 0.05)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 20, -1)
    rule:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", -40, -1)
    local hi = button:GetHighlightTexture()
    if hi and texPath(hi):find("hilight") == nil then goldGlow(hi, 0.15) end
end

-- Input fields drawn with Common-Input-Border pieces or InputBoxTemplate get DragonUI's field border.
local function inputArt(box)
    local found = {}
    for _, region in ipairs({ box:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            local path = texPath(region)
            if path:find("common%-input%-border") or path:find("ui%-common%-input") then found[#found + 1] = region end
        end
    end
    return found
end

local function skinInput(box)
    local UI = NS.D.ForeverUI
    if not (UI and UI.SkinEditBox) then return end
    for _, tex in ipairs(inputArt(box)) do tex:SetAlpha(0) end
    pcall(UI.SkinEditBox, box, { font = box:GetFontObject() })
end

-- Lists sit in a recessed panel (Companion's "well"): dark ground and the thin inset trim, covering the
-- scroll area and its scrollbar. It follows the scroll frame's visibility (some windows swap two lists
-- in the same spot).
local function skinWell(window, scroll)
    local box = window._dsynBox
    if not box then return end
    local bar = _G[(scroll:GetName() or "") .. "ScrollBar"] or _G[(scroll:GetName() or ""):gsub("Scrollable", "Slider")]
    local well = CreateFrame("Frame", nil, box)
    well:SetFrameLevel(box:GetFrameLevel() + 1)
    well:EnableMouse(false)
    well:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 6)
    well:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", bar and 22 or 6, -6)
    local ground = well:CreateTexture(nil, "BACKGROUND", nil, -4)
    ground:SetTexture(WHITE8)
    ground:SetVertexColor(0, 0, 0, 0.45)
    ground:SetPoint("TOPLEFT", 3, -3)
    ground:SetPoint("BOTTOMRIGHT", -3, 3)
    NS.Kit.NineSlice(well, "InsetFrameTemplate")
    scroll:HookScript("OnShow", function() well:Show() end)
    scroll:HookScript("OnHide", function() well:Hide() end)
    if not scroll:IsShown() then well:Hide() end
    scroll._dsynWell = well
end

-- Label boxes: Synastria's client draws stock dropdowns (UIDropDownMenuTemplate) with the character-create
-- label frame and a small scroll-down arrow, and the server's own "pick" boxes (loot filter conditions,
-- affix manager) copy that look. Both get the DragonUI dropdown art, laid exactly over the original art:
-- the new box is anchored to the old (hidden) left and right caps, and the text and arrow button stay
-- where the server put them. Sizes and gaps between controls stay the server's own, so rows line up as
-- they did. (The frames themselves can't be used for this: an unsized dropdown's frame is only 40px wide
-- and its art hangs outside it.)
local LABEL_INSET = 17   -- transparent margin inside each 25px label-frame cap
local BOX_HEIGHT = 30    -- DragonUI text holder height that matches the old box's visible height
local ARROW_INSET = 4    -- the red arrow art fills its square; the old icon didn't

local function labelArrow(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "Button" and texPath(child:GetNormalTexture()):find("ui%-chaticon%-scrolldown") then
            return child
        end
    end
end

-- Returns the old left and right caps (by texture coordinates: the left cap starts at u = 0, the right
-- one ends at u = 1) when the frame is a label box.
local function labelCaps(frame)
    local left, right
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" and texPath(region):find("charactercreate%-labelframe") then
            local ulx, _, _, _, urx = region:GetTexCoord()
            if ulx and ulx < 0.01 then left = region
            elseif urx and urx > 0.99 then right = region end
        end
    end
    if left and right and labelArrow(frame) then return left, right end
end

local function skinLabelBox(frame, oldLeft, oldRight)
    local UI = NS.D.ForeverUI
    if not (UI and UI.SetAtlas) then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" and texPath(region):find("charactercreate%-labelframe") then
            region:SetAlpha(0)
        end
    end
    local capW = math.floor(14 * BOX_HEIGHT / 41 + 0.5)
    local left = frame:CreateTexture(nil, "BACKGROUND")
    local middle = frame:CreateTexture(nil, "BACKGROUND")
    local right = frame:CreateTexture(nil, "BACKGROUND")
    UI.SetAtlas(left, "common-dropdown-textholder-left", false)
    UI.SetAtlas(right, "common-dropdown-textholder-right", false)
    UI.SetAtlas(middle, "common-dropdown-textholder-middle", false)
    left:SetSize(capW, BOX_HEIGHT)
    right:SetSize(capW, BOX_HEIGHT)
    left:SetPoint("LEFT", oldLeft, "LEFT", LABEL_INSET, 0)
    right:SetPoint("RIGHT", oldRight, "RIGHT", -LABEL_INSET, 0)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

    -- Same button, same place and size; only its art changes.
    local button = labelArrow(frame)
    local blank = WHITE8
    for _, look in ipairs({ { "Normal", "common-dropdown-a-button" }, { "Pushed", "common-dropdown-a-button-pressed" },
        { "Disabled", "common-dropdown-a-button-disabled" }, { "Highlight", "common-dropdown-a-button-hover" } }) do
        button["Set" .. look[1] .. "Texture"](button, blank)
        local tex = button["Get" .. look[1] .. "Texture"](button)
        UI.SetAtlas(tex, look[2], false)
        tex:SetVertexColor(1, 1, 1)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", ARROW_INSET, -ARROW_INSET)
        tex:SetPoint("BOTTOMRIGHT", -ARROW_INSET, ARROW_INSET)
    end
    button:GetHighlightTexture():SetBlendMode("BLEND")

    -- A real dropdown: DragonUI's menu art on its list (Kit's shared list hook), Blizzard's placement.
    if frame:GetName() and _G[frame:GetName() .. "Button"] == button then
        frame._dscDrop = true
        frame._dscNoCenter = true
        NS.Kit.HookMenuList()
    end
end

-- Small +/- buttons whose meaning DragonUI has better art for. The server keeps swapping their texture
-- (the loot filter's first button is "remove" with a minus, "add" with a plus), so the art follows
-- every SetNormalTexture call. role: "toggle" (minus = remove ✕, plus = add +), "up", "down".
local ICONS = {
    close = { sheet = "UI\\redbutton2x", size = 15, coords = { 39 / 256, 75 / 256, 1 / 128, 39 / 128 },
        glow = { 115 / 256, 151 / 256, 1 / 128, 39 / 128 } },
    up = { atlas = "minimal-scrollbar-arrow-top", glowAtlas = "minimal-scrollbar-arrow-top-over", scale = 0.8 },
    down = { atlas = "minimal-scrollbar-arrow-bottom", glowAtlas = "minimal-scrollbar-arrow-bottom-over", scale = 0.8 },
}

local function plusIcon()
    local P = NS.D.Professions
    local entry = P and P.Atlas and P.Atlas["header-plus"]
    if entry then
        return { file = entry[1], size = 13, coords = { entry[4], entry[5], entry[6], entry[7] } }
    end
    return { file = "Interface\\Buttons\\UI-PlusButton-Up", size = 16, coords = { 0, 1, 0, 1 } }
end

local function paintIcon(tex, icon, isGlow)
    local UI = NS.D.ForeverUI
    if icon.atlas then
        local name = isGlow and icon.glowAtlas or icon.atlas
        local entry = NS.D.ForeverAtlas and NS.D.ForeverAtlas[name]
        if entry then
            tex:SetTexture(entry[1])
            tex:SetTexCoord(entry[4], entry[5], entry[6], entry[7])
            tex:SetSize(entry[2] * (icon.scale or 1), entry[3] * (icon.scale or 1))
        elseif UI and UI.SetAtlas then
            UI.SetAtlas(tex, name, true)
        end
        tex:SetBlendMode("BLEND")
        tex:SetAlpha(1)
        return
    end
    tex:SetTexture(icon.file or (NS.D._dir .. icon.sheet))
    local c = isGlow and icon.glow or icon.coords
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
    tex:SetSize(icon.size, icon.size)
    tex:SetBlendMode(isGlow and "ADD" or "BLEND")
    tex:SetAlpha(isGlow and (icon.glow == icon.coords and 0.5 or 1) or 1)
end

local function applyIcon(button, path)
    local icon
    if button._dsynRole == "up" then
        icon = ICONS.up
    elseif button._dsynRole == "down" then
        icon = ICONS.down
    else
        path = type(path) == "string" and path:lower() or texPath(button:GetNormalTexture())
        if path:find("plus") then
            icon = plusIcon()
            icon.glow = icon.coords
        else
            icon = ICONS.close
        end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local tex = button[getter](button)
        if tex then tex:SetAlpha(0) end
    end
    paintIcon(button._dsynIcon, icon, false)
    paintIcon(button._dsynGlow, icon, true)
end

local function skinIconButton(button, role)
    if not button or button._dsynRole then return end
    button._dsynRole = role
    button._dsynIcon = button:CreateTexture(nil, "ARTWORK")
    button._dsynIcon:SetPoint("CENTER")
    button._dsynGlow = button:CreateTexture(nil, "HIGHLIGHT")
    button._dsynGlow:SetPoint("CENTER")
    button._dsynCtl = true
    -- An error here would surface inside the server's own code and stop the rest of its row update.
    hooksecurefunc(button, "SetNormalTexture", function(self, path)
        local ok, err = pcall(applyIcon, self, path)
        if not ok then NS.Report(err) end
    end)
    applyIcon(button)
end

-- The loot filter keeps its condition buttons in frame.cele (built by the server for every row).
local function skinConditionButtons(window)
    local cele = window.cele
    if not (cele and cele.condbtn) then return end
    for _, b in pairs(cele.condbtn) do skinIconButton(b, "toggle") end
    for _, b in pairs(cele.condmvu or {}) do skinIconButton(b, "up") end
    for _, b in pairs(cele.condmvd or {}) do skinIconButton(b, "down") end
end

local rescan

-- Selection highlights some windows draw themselves (UI-Listbox-Highlight, blue) turn gold.
local function skinRegions(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if not region._dsynCtl and region:GetObjectType() == "Texture" and texPath(region):find("ui%-listbox%-highlight") then
            region._dsynCtl = true
            goldGlow(region, 0.3)
        end
    end
end

-- Every control anywhere in the window. Lists add rows later, so this runs again when the window shows,
-- when a list's content resizes, and once a second while it is open; each control is only done once.
local function skinControls(window, parent, depth, inList)
    local K, UI = NS.Kit, NS.D.ForeverUI
    skinRegions(parent)
    for _, child in ipairs({ parent:GetChildren() }) do
        local kind, cname = child:GetObjectType(), child:GetName() or ""
        if not child._dsynCtl then
            if kind == "Button" and isPanelButton(child) then
                child._dsynCtl = true
                K.Button(child)
            elseif (kind == "Button" or kind == "StatusBar") and _G[cname .. "Border"] and _G[cname .. "SkillName"] then
                child._dsynCtl = true
                skinSkillBar(child, cname)
            elseif kind == "Button" and isHeader(child) then
                child._dsynCtl = true
                skinHeader(child)
            elseif kind == "Button" and inList and not _G[cname .. "IconTexture"] and not _G[cname .. "Icon"] then
                -- A row-shaped button inside a list: gold hover/selection glow.
                local w, h = child:GetWidth(), child:GetHeight()
                if w and h and h > 0 and h <= 24 and w >= 80 then
                    child._dsynCtl = true
                    rowGlow(child)
                end
            elseif kind == "CheckButton" and child.GetCheckedTexture and child:GetCheckedTexture() then
                child._dsynCtl = true
                K.Check(child, true)
            elseif kind == "EditBox" and #inputArt(child) > 0 then
                child._dsynCtl = true
                skinInput(child)
            elseif kind == "Frame" and labelCaps(child) then
                child._dsynCtl = true
                skinLabelBox(child, labelCaps(child))
            elseif kind == "Frame" and _G[cname .. "Button"] and _G[cname .. "Middle"] and _G[cname .. "Text"] then
                child._dsynCtl = true
                local middle = _G[cname .. "Middle"]
                child._dscNoCenter = true
                K.DropDown(child, math.max(40, (middle:GetWidth() or 115)))
            elseif kind == "Slider" and _G[cname .. "ScrollUpButton"] and UI and UI.SkinScrollBar then
                child._dsynCtl = true
                pcall(UI.SkinScrollBar, child)
            elseif kind == "ScrollFrame" then
                child._dsynCtl = true
                if _G[cname .. "ScrollBar"] and UI and UI.SkinScrollBar then pcall(UI.SkinScrollBar, child) end
                if child:GetScrollChild() then
                    skinWell(window, child)
                    child:GetScrollChild():HookScript("OnSizeChanged", function() rescan(window) end)
                end
            end
        end
        if depth < 6 then
            local list = inList or (kind == "ScrollFrame" and child:GetScrollChild() ~= nil)
            skinControls(window, child, depth + 1, list)
        end
    end
end

local queued = {}
rescan = function(window)
    if queued[window] then return end
    queued[window] = true
    NS.After(0, function()
        queued[window] = nil
        local ok, err = pcall(skinConditionButtons, window)
        if not ok then NS.Report(err) end
        ok, err = pcall(skinControls, window, window, 1, false)
        if not ok then NS.Report(err) end
    end)
end

local function skin(name)
    local frame = _G[name]
    if skinned[frame] then return end
    skinned[frame] = true
    local K = NS.Kit

    for _, suffix in ipairs(ART) do
        local tex = _G[name .. suffix]
        if tex then tex:SetAlpha(0) end
    end
    local box = chrome(frame, name)

    local title = _G[name .. "-HeaderText"]
    if title then
        -- The title belongs to the window, which draws under the new frame; it moves onto the frame.
        title:SetParent(box)
        title:SetDrawLayer("OVERLAY")
        title:ClearAllPoints()
        title:SetPoint("TOP", box, "TOP", 0, -5)
        title:SetFontObject(GameFontNormal)
    end

    local close = _G[name .. "-Close"]
    if close then
        K.RedIcon(close, "close")
        close:SetFrameLevel(frame:GetFrameLevel() + 20)
        K.Pin(close, { { "TOPRIGHT", box, "TOPRIGHT", 1, 0 } })
    end

    skinConditionButtons(frame)
    skinControls(frame, frame, 1, false)
    -- Lists and tabs make their rows later; pick them up each time the window opens.
    frame:HookScript("OnShow", rescan)
end

function Part.Check()
    if not enabled() then return end
    for _, name in ipairs(UISpecialFrames) do
        local frame = isServerWindow(name) and _G[name]
        if frame and not skinned[frame] then
            local ok, err = pcall(skin, name)
            if not ok then NS.Report(err) end
        elseif frame and frame:IsShown() then
            -- Rows added while the window stays open (expanding a category, filtering...).
            rescan(frame)
        end
    end
end

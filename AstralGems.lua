-- Slot schema frozen; MUST mirror AstralGemMgr.h LOADOUT_SLOTS.

local PA = ProjectAstral
local UI = PA.UI

local AG = {}
PA.AstralGems = AG

local C_GREEN, C_BLUE, C_PURPLE, C_ORANGE = 2, 3, 4, 5

local SLOT_SCHEMA = {
    { ord = 0, equipSlot = 0,  label = "Head",   colors = { C_BLUE } },
    { ord = 1, equipSlot = 1,  label = "Neck",   colors = { C_PURPLE } },
    { ord = 2, equipSlot = 4,  label = "Chest",  colors = { C_GREEN, C_BLUE, C_PURPLE } },
    { ord = 3, equipSlot = 6,  label = "Legs",   colors = { C_GREEN, C_BLUE, C_PURPLE } },
    { ord = 4, equipSlot = 7,  label = "Boots",  colors = { C_GREEN } },
    { ord = 5, equipSlot = 15, label = "Weapon", colors = { C_GREEN, C_BLUE, C_PURPLE, C_ORANGE } },
}

local COLOR_RGB = {
    [C_GREEN]  = { 0.20, 1.00, 0.20 },  -- Super vibrant green
    [C_BLUE]   = { 0.10, 0.50, 1.00 },  -- Super vibrant blue
    [C_PURPLE] = { 0.80, 0.20, 1.00 },  -- Super vibrant purple
    [C_ORANGE] = { 1.00, 0.50, 0.00 },  -- Super vibrant orange
}

local COLOR_NAME = {
    [C_GREEN]  = "Uncommon",
    [C_BLUE]   = "Rare",
    [C_PURPLE] = "Epic",
    [C_ORANGE] = "Legendary",
}

local COLOR_SLOT_TEX = {
    [C_GREEN]  = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_green",
    [C_BLUE]   = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_blue",
    [C_PURPLE] = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_purple",
    [C_ORANGE] = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_legendary",
}
local SLOT_LOCK_TEX     = "Interface\\Buttons\\WHITE8X8"
local SLOT_CHROME_EXTRA = 10
local SLOT_LOCK_INSET   = -2

local function GetGemTexture(itemId)
    if not itemId or itemId <= 0 then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if PA.ItemCache and PA.ItemCache.Register then PA.ItemCache.Register(itemId) end
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
    if texture and texture ~= "" then return texture end
    if GetItemIcon then
        local icon = GetItemIcon(itemId)
        if icon and icon ~= "" then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ApplySocketGemIcon(icon, itemId)
    if not icon then return end

    local texture = GetGemTexture(itemId)
    if texture and texture ~= "" and texture ~= "Interface\\Buttons\\WHITE8X8" and texture ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
        icon:SetTexture(texture)
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetAlpha(1)
        icon:SetDrawLayer("ARTWORK", 7)
        icon:Show()
        return
    end

    icon:SetTexture(nil)
    icon:SetAlpha(0)
    icon:Hide()
end

local function CreateModernLockGlyph(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder:SetPoint("CENTER", parent, "CENTER", 0, 0)
    holder:SetFrameLevel(parent:GetFrameLevel() + 30)

    local mark = holder:CreateFontString(nil, "OVERLAY")
    mark:SetFont("Fonts\\FRIZQT__.TTF", size * 0.75, "OUTLINE")
    mark:SetPoint("CENTER", holder, "CENTER", 0, 0)
    mark:SetText("X")
    mark:SetTextColor(0.25, 0.65, 1.00, 1)
    mark:SetJustifyH("CENTER")
    mark:SetJustifyV("MIDDLE")

    return holder
end

AG.loadout    = {}
AG.inspect    = {}
AG.inspecting = nil

local function Send(cmd) SendChatMessage("." .. cmd, "SAY") end

local function Split(s, sep)
    local t, i = {}, 1
    while true do
        local j = s:find(sep, i, true)
        if j then t[#t + 1] = s:sub(i, j - 1); i = j + 1
        else      t[#t + 1] = s:sub(i); break end
    end
    return t
end

local function ClearTable(t) for k in pairs(t) do t[k] = nil end end

local function PutSocket(tbl, ord, idx, gemId, active)
    if not tbl[ord] then tbl[ord] = {} end
    tbl[ord][idx] = { gemId = gemId, active = active }
    if gemId and gemId > 0 and PA.ItemCache then
        PA.ItemCache.Register(gemId)
    end
end

local LOADOUT_SLOT_OK_ERR_MSG = {
    BAD_SLOT   = "That slot has no sockets.",
    IN_COMBAT  = "You cannot change your gem loadout while in combat.",
    USAGE      = "Command syntax error.",
}

local function RegisterAstralGemsHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local ClientHandler = _G.AIO.AddHandlers("AstralGemsClient", {})

    ClientHandler.Loadout = function(_, payload)
        if type(payload) ~= "table" then return end
        ClearTable(AG.loadout)
        for _, slot in ipairs(payload.slots or {}) do
            local ord = tonumber(slot.ord)
            for _, sock in ipairs(slot.sockets or {}) do
                if ord and sock.idx then
                    PutSocket(AG.loadout, ord, sock.idx,
                              tonumber(sock.gem) or 0,
                              sock.active and true or false)
                end
            end
        end
        AG.inspecting = nil
        AG.Render()
    end

    ClientHandler.InspectResult = function(_, status, targetOrName, slots)
        if status == "OK" then
            AG.inspecting = targetOrName
            ClearTable(AG.inspect)
            for _, slot in ipairs(slots or {}) do
                local ord = tonumber(slot.ord)
                for _, sock in ipairs(slot.sockets or {}) do
                    if ord and sock.idx then
                        PutSocket(AG.inspect, ord, sock.idx,
                                  tonumber(sock.gem) or 0,
                                  sock.active and true or false)
                    end
                end
            end
            AG.Render()
        elseif status == "OFFLINE" then
            UIErrorsFrame:AddMessage((targetOrName or "Player") ..
                " is not online.", 1, 0.5, 0.5, 53, 5)
        else
            UIErrorsFrame:AddMessage("Inspect failed: " .. tostring(status),
                1, 0.5, 0.5, 53, 5)
        end
    end

    local function ForwardSocketOp(op, status, equipSlot, socketIdx, gemEntry)
        if status == "OK" then
            if op == "socket" then
                SendChatMessage(string.format(".gem socket %d %d %d",
                                              equipSlot, socketIdx, gemEntry or 0), "SAY")
                UIErrorsFrame:AddMessage("Loadout SOCKET", 0.6, 1.0, 0.6, 53, 4)
            else
                SendChatMessage(string.format(".gem unsocket %d %d",
                                              equipSlot, socketIdx), "SAY")
                UIErrorsFrame:AddMessage("Loadout UNSOCKET", 0.6, 1.0, 0.6, 53, 4)
            end
            if AIO and AIO.Handle then
                AIO.Handle("AstralgemServer", "RequestLoadout")
            end
        else
            local m = LOADOUT_SLOT_OK_ERR_MSG[status] or ("Loadout error: " .. tostring(status))
            UIErrorsFrame:AddMessage(m, 1, 0.4, 0.4, 53, 5)
        end
    end

    ClientHandler.SocketResult = function(_, status, equipSlot, socketIdx)
        ForwardSocketOp("socket", status, equipSlot, socketIdx,
                        AG._pendingGemEntry)
        AG._pendingGemEntry = nil
        if AG.OnApplySocketResult then AG.OnApplySocketResult(status) end
    end

    ClientHandler.UnsocketResult = function(_, status, equipSlot, socketIdx)
        ForwardSocketOp("unsocket", status, equipSlot, socketIdx)
        if AG.OnApplyUnsocketResult then AG.OnApplyUnsocketResult(status) end
    end
    return true
end

local aioInit = CreateFrame("Frame")
aioInit:RegisterEvent("PLAYER_LOGIN")
aioInit:SetScript("OnEvent", function(self)
    if RegisterAstralGemsHandlers() then
        self:UnregisterAllEvents()
        if _G.AIO and _G.AIO.Handle then
            _G.AIO.Handle("AstralgemServer", "RequestLoadout")
        end
    end
end)

local PICKER_TIER_FILTERS = {
    { label = "All Tiers", match = function(c) return true end },
    { label = "T1",     match = function(c) return not c.isMythic and c.tier == 1 end },
    { label = "T2",     match = function(c) return not c.isMythic and c.tier == 2 end },
    { label = "T3",     match = function(c) return not c.isMythic and c.tier == 3 end },
    { label = "T4",     match = function(c) return not c.isMythic and c.tier == 4 end },
    { label = "T5",     match = function(c) return not c.isMythic and c.tier == 5 end },
    { label = "T6",     match = function(c) return not c.isMythic and c.tier == 6 end },
    { label = "T7",     match = function(c) return not c.isMythic and c.tier == 7 end },
    { label = "T8",     match = function(c) return not c.isMythic and c.tier == 8 end },
    { label = "Mythic", match = function(c) return c.isMythic end },
}

local PICKER_EVENT_FILTERS = {
    { label = "All Triggers",   match = function(c) return true end },
    { label = "Proc on Hit",    match = function(c) return c.eventType == 0 end },
    { label = "Proc on Cast",   match = function(c) return c.eventType == 1 end },
    { label = "Proc on Heal",   match = function(c) return c.eventType == 2 end },
    { label = "Proc on Struck", match = function(c) return c.eventType == 3 end },
}

local pickerTier   = 1
local pickerEvent  = 1
local pickerSearch = ""

local function MatchesPickerFilter(cat)
    if not cat then
        return pickerTier == 1 and pickerEvent == 1
    end
    local tf = PICKER_TIER_FILTERS[pickerTier]
    local ef = PICKER_EVENT_FILTERS[pickerEvent]
    return (tf and tf.match(cat)) and (ef and ef.match(cat))
end

local function InitPickerDropdown(dd, list, getCurrentIdx, onChoose)
    UIDropDownMenu_Initialize(dd, function(self, level)
        local cur = getCurrentIdx()
        for i, item in ipairs(list) do
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = item.label
            info.checked = (i == cur)
            info.func    = function()
                onChoose(i)
                UIDropDownMenu_SetSelectedID(dd, i)
                UIDropDownMenu_SetText(dd, list[i].label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local cur = getCurrentIdx()
    UIDropDownMenu_SetSelectedID(dd, cur)
    UIDropDownMenu_SetText(dd, list[cur].label)
end

local picker
local pickerCtx
local RebuildPickerRows

local SCROLL_IDS = { [99998] = true, [99999] = true }

local function CollectActiveFamilies()
    local active = {}
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    for ord = 0, 5 do
        local slot = AG.loadout[ord]
        if slot then
            for idx = 0, 3 do
                local data = slot[idx]
                if data and data.gemId and data.gemId > 0 then
                    local cat = catalog[data.gemId]
                    if cat and cat.family and cat.family ~= "" then
                        active[cat.family] = true
                    end
                end
            end
        end
    end
    return active
end

local function GetSortedStashGems()
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local catalogReady = next(catalog) ~= nil
    local activeFamilies = CollectActiveFamilies()
    local out = {}
    for entry, count in pairs(stock) do
        local isGem
        if catalogReady then
            isGem = catalog[entry] ~= nil
        else
            isGem = not SCROLL_IDS[entry]
        end

        local familyOk = true
        if isGem and catalogReady then
            local cat = catalog[entry]
            local family = cat and cat.family or ""
            if family ~= "" and activeFamilies[family] then
                familyOk = false
            end
        end

        local filterOk = true
        if isGem and catalogReady then
            filterOk = MatchesPickerFilter(catalog[entry])
        end

        if isGem and familyOk and filterOk and count > 0 then
            if PA.ItemCache then PA.ItemCache.Register(entry) end
            local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(entry)
            local shownName = PA.CleanGemTierMarker(name or ("Item " .. entry))
            local cat = catalog[entry]
            local searchOk = pickerSearch == ""
                or shownName:lower():find(pickerSearch, 1, true)
                or (cat and cat.family and cat.family:lower():find(pickerSearch, 1, true))
            if searchOk then
                out[#out + 1] = {
                    entry = entry, count = count,
                    name = shownName,
                    texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                    quality = quality or 1,
                    tier = (cat and cat.tier) or 0,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

local function BuildPicker()
    if picker then return picker end
    local f = CreateFrame("Frame", "AstralGemsPicker", UIParent)
    f:SetSize(560, 620)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    UI.AstralBackdrop(f)
    UI.AddStarfield(f, 0.3)
    f:Hide()
    tinsert(UISpecialFrames, "AstralGemsPicker")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Pick a gem from the stash")
    title:SetTextColor(unpack(UI.Color.textTitle))
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(close)
    close:SetPoint("TOPRIGHT", -2, -2)

    local tierLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tierLbl:SetPoint("TOPLEFT", 22, -44)
    tierLbl:SetText("Tier")

    local tierDd = CreateFrame("Frame", "AstralGemsPickerTierDD", f, "UIDropDownMenuTemplate")
    tierDd:SetPoint("TOPLEFT", tierLbl, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(tierDd, 90)
    InitPickerDropdown(tierDd, PICKER_TIER_FILTERS,
        function() return pickerTier end,
        function(i)
            pickerTier = i
            if RebuildPickerRows then RebuildPickerRows() end
        end)
    f.tierDd = tierDd

    local evtLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    evtLbl:SetPoint("TOPLEFT", tierLbl, "TOPRIGHT", 120, 0)
    evtLbl:SetText("Trigger")

    local evtDd = CreateFrame("Frame", "AstralGemsPickerEventDD", f, "UIDropDownMenuTemplate")
    evtDd:SetPoint("TOPLEFT", evtLbl, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(evtDd, 130)
    InitPickerDropdown(evtDd, PICKER_EVENT_FILTERS,
        function() return pickerEvent end,
        function(i)
            pickerEvent = i
            if RebuildPickerRows then RebuildPickerRows() end
        end)
    f.evtDd = evtDd

    local search = UI.MakeSearchBox(f, {
        width       = 560 - 22 - 24,
        height      = 24,
        placeholder = "Search gems by name or family…",
        onChanged   = function(text)
            pickerSearch = (text or ""):lower()
            if RebuildPickerRows then RebuildPickerRows() end
        end,
    })
    search:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -96)
    f.search = search

    local scroll = CreateFrame("ScrollFrame", "AstralGemsPickerScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -130)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560 - 12 - 28, 1)
    scroll:SetScrollChild(content)
    f.content = content
    content._rows = {}

    if UI.SkinTree then UI.SkinTree(f) end
    picker = f
    return f
end

RebuildPickerRows = function()
    if not picker then return end
    local content = picker.content
    if not content then return end

    for _, r in ipairs(content._rows) do r:Hide() end

    local rows = GetSortedStashGems()
    local rowH = 38
    content:SetHeight(math.max(1, #rows * rowH))

    for i, gem in ipairs(rows) do
        local r = content._rows[i]
        if not r then
            r = CreateFrame("Button", nil, content)
            r:SetSize(content:GetWidth() - 10, rowH - 2)
            local bg = r:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.06, 0.06, 0.07, 0.55)
            r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(rowH - 6, rowH - 6)
            r.icon:SetPoint("LEFT", 4, 0)
            r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.count:SetPoint("RIGHT", -6, 0)
            r:SetScript("OnEnter", function(self)
                if self._entry then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. self._entry)
                    GameTooltip:Show()
                end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            content._rows[i] = r
        end
        r._entry = gem.entry
        r.icon:SetTexture(gem.texture)
        local q = ITEM_QUALITY_COLORS[gem.quality]
        local nameColor = q and string.format("|cff%02x%02x%02x", q.r * 255, q.g * 255, q.b * 255) or "|cffffffff"
        r.name:SetText(nameColor .. gem.name .. "|r  |cff888888T" .. gem.tier .. "|r")
        r.count:SetText("|cffffffffx" .. gem.count .. "|r")
        r:SetScript("OnClick", function()
            if IsModifiedClick("CHATLINK") then
                if ProjectAstral.InsertChatLink then
                    ProjectAstral.InsertChatLink(select(2, GetItemInfo(gem.entry)))
                end
                return
            end
            if not pickerCtx then return end
            local schema = SLOT_SCHEMA[pickerCtx.ord + 1]
            if AIO and AIO.Handle then
                AG._pendingGemEntry = gem.entry
                AIO.Handle("AstralgemServer", "Socket", schema.equipSlot, pickerCtx.idx, gem.entry)
            else
                Send(string.format("gem socket %d %d %d", schema.equipSlot, pickerCtx.idx, gem.entry))
            end
            picker:Hide()
        end)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r:Show()
    end

    if #rows == 0 then
        if not content.empty then
            content.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            content.empty:SetPoint("TOP", 0, -10)
        end
        content.empty:SetText("No gems match your filters or search.")
        content.empty:Show()
    elseif content.empty then
        content.empty:Hide()
    end
end

local function OpenPicker(ord, idx)
    pickerCtx = { ord = ord, idx = idx }
    local f = BuildPicker()
    if f.search then f.search:Clear() end
    pickerSearch = ""
    RebuildPickerRows()
    f:Show()
    f:Raise()
end

local SOCKET_SIZE = 52
local SOCKET_GAP = 10

-- Vertical slot box (sockets stacked vertically)
local function BuildSlotBox(parent, schemaIdx, opts)
    opts = opts or {}
    local socketSize = opts.socketSize or SOCKET_SIZE
    local socketGap = opts.socketGap or SOCKET_GAP
    local nameWidth = opts.showGemNames and (opts.gemNameWidth or 140) or 0
    local schema = SLOT_SCHEMA[schemaIdx]
    local nSockets = #schema.colors
    local labelHeight = 26
    local labelGap = 12
    local socketAreaHeight = nSockets * socketSize + (nSockets - 1) * socketGap
    local w = socketSize + 20 + nameWidth
    local h = labelHeight + labelGap + socketAreaHeight
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    box.gemNameWidth = nameWidth
    function box:SetGemNameWidth(width)
        if not opts.showGemNames then return end
        self.gemNameWidth = math.max(60, width)
        self:SetWidth(socketSize + 20 + self.gemNameWidth)
        for _, socket in ipairs(self.sockets) do
            if socket.gemName then socket.gemName:SetWidth(self.gemNameWidth - 8) end
        end
    end

    -- Label ABOVE the socket area - bigger and cleaner
    local label = box:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    if opts.showGemNames then
        label:SetPoint("TOP", box, "TOPLEFT", socketSize / 2 + 8, -2)
    else
        label:SetPoint("TOP", 0, -2)
    end
    label:SetText(schema.label)
    -- Apply brightness to label color
    local labelColor = {0.85, 0.95, 1.00, 1}
    if PA.Brightness then
        local r, g, b, a = PA.Brightness.Brighten(labelColor)
        label:SetTextColor(r, g, b, a)
    else
        label:SetTextColor(unpack(labelColor))
    end
    label:SetShadowColor(0.05, 0.10, 0.25, 1.0)
    label:SetShadowOffset(1, -1)
    box.label = label

    -- FIX: Full black background ONLY around the sockets (below the label) - tight fit
    -- This hides any gem icon overflow
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 1)  -- Full black to hide overflow
    bg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(labelHeight + labelGap))
    bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)

    box.sockets = {}
    box.schema = schema

    for i, color in ipairs(schema.colors) do
        local s = CreateFrame("Button", nil, box)
        s:SetSize(socketSize, socketSize)
        -- Vertical positioning (stacked top to bottom, starting below label with gap)
        local yOffset = -(labelHeight + labelGap + socketSize/2 + 4)
            - (i - 1) * (socketSize + socketGap)
        if opts.showGemNames then
            s:SetPoint("CENTER", box, "TOPLEFT", socketSize / 2 + 8, yOffset)
        else
            s:SetPoint("CENTER", box, "TOP", 0, yOffset)
        end

        local edges = {}
        local edgePoints = {
            { "TOPLEFT", "TOPRIGHT", 0, 0, 0, 0, "height" },
            { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, 0, 0, "height" },
            { "TOPLEFT", "BOTTOMLEFT", 0, -2, 0, 2, "width" },
            { "TOPRIGHT", "BOTTOMRIGHT", 0, -2, 0, 2, "width" },
        }
        for edgeIndex, points in ipairs(edgePoints) do
            local edge = s:CreateTexture(nil, "ARTWORK")
            edge:SetTexture("Interface\\Buttons\\WHITE8X8")
            edge:SetPoint(points[1], s, points[1], points[3], points[4])
            edge:SetPoint(points[2], s, points[2], points[5], points[6])
            if points[7] == "height" then
                edge:SetHeight(2)
            else
                edge:SetWidth(2)
            end
            -- Super vibrant full-brightness colors
            edge:SetVertexColor(COLOR_RGB[color][1], COLOR_RGB[color][2], COLOR_RGB[color][3], 1.0)
            edges[edgeIndex] = edge
        end
        s.edges = edges

        local face = s:CreateTexture(nil, "BACKGROUND")
        face:SetDrawLayer("BORDER", 1)
        face:SetTexture("Interface\\Buttons\\WHITE8X8")
        face:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2)
        face:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -2, 2)
        face:SetVertexColor(0, 0, 0, 1)  -- Full black
        face:SetDrawLayer("BACKGROUND", 0)

        local icon = s:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("TOPLEFT", s, "TOPLEFT", 5, -5)
        icon:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -5, 5)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture("Interface\\Buttons\\WHITE8X8")
        icon:SetVertexColor(0.8, 0.8, 1.0, 1)
        icon:SetDrawLayer("ARTWORK", 7)
        s.icon = icon
        icon:Hide()

        local emptyMark = s:CreateFontString(nil, "OVERLAY")
        emptyMark:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
        emptyMark:SetPoint("CENTER", s, "CENTER", 0, 0)
        emptyMark:SetText("+")
        -- Apply brightness to empty socket "+" color
        local plusColor = COLOR_RGB[color]
        if PA.Brightness then
            local r, g, b = PA.Brightness.BrightenRGB(plusColor[1], plusColor[2], plusColor[3])
            emptyMark:SetTextColor(r, g, b, 1.0)
            emptyMark:SetShadowColor(r, g, b, 0.8)
        else
            emptyMark:SetTextColor(plusColor[1], plusColor[2], plusColor[3], 1.0)
            emptyMark:SetShadowColor(plusColor[1], plusColor[2], plusColor[3], 0.8)
        end
        emptyMark:SetShadowOffset(0, 0)
        emptyMark:Hide()
        s.emptyMark = emptyMark

        local dim = CreateModernLockGlyph(s, socketSize - 4)
        dim:Hide()
        s.dim = dim
        s.dim:SetFrameLevel(s:GetFrameLevel() + 20)

        s._color = color
        s._idx = i - 1
        s._ord = schema.ord
        s._readonly = opts.readonly

        if opts.showGemNames then
            local gemName = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            gemName:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            gemName:SetPoint("LEFT", s, "RIGHT", 7, 0)
            gemName:SetWidth(math.max(52, nameWidth - 8))
            gemName:SetJustifyH("LEFT")
            gemName:SetWordWrap(false)
            if gemName.SetMaxLines then gemName:SetMaxLines(1) end
            gemName:SetTextColor(unpack(UI.Color.textPrimary))
            s.gemName = gemName
        end

        s:SetScript("OnEnter", function(self)
            if self.glow then
                self.glow:SetAlpha(0.55)
            end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local source = self._readonly and AG.inspect or AG.loadout
            local data = source[self._ord] and source[self._ord][self._idx]
            local qName = COLOR_NAME[self._color] or ""
            GameTooltip:AddLine(qName .. " Socket", 1, 1, 1)
            if data and data.gemId and data.gemId > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:SetHyperlink("item:" .. data.gemId)
                if not data.active then
                    GameTooltip:AddLine("|cffff5555Inactive|r — item quality too low.", 1, 0.4, 0.4, true)
                end
            else
                if not data or not data.active then
                    GameTooltip:AddLine("|cffaaaaaaInactive|r — needs at least " .. qName .. " quality item.", 0.6, 0.6, 0.6, true)
                else
                    GameTooltip:AddLine("|cffaaaaaaEmpty|r — click to socket a gem.", 0.6, 0.6, 0.6, true)
                end
            end
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function(self)
            if self.glow then
                self.glow:SetAlpha(0.16)
            end
            GameTooltip:Hide()
        end)

        s:SetScript("OnClick", function(self)
            if self._readonly then return end
            local data = AG.loadout[self._ord] and AG.loadout[self._ord][self._idx]
            if IsModifiedClick("CHATLINK") then
                if data and data.gemId and data.gemId > 0 and ProjectAstral.InsertChatLink then
                    ProjectAstral.InsertChatLink(select(2, GetItemInfo(data.gemId)))
                end
                return
            end
            if data and data.gemId and data.gemId > 0 then
                if AIO and AIO.Handle then
                    AIO.Handle("AstralgemServer", "Unsocket",
                               SLOT_SCHEMA[self._ord + 1].equipSlot, self._idx)
                else
                    Send(string.format("gem unsocket %d %d",
                                       SLOT_SCHEMA[self._ord + 1].equipSlot, self._idx))
                end
            else
                if data and not data.active then
                    UIErrorsFrame:AddMessage("Slot inactive — item quality too low.", 1, 0.5, 0.5, 53, 4)
                    return
                end
                OpenPicker(self._ord, self._idx)
            end
        end)

        box.sockets[i] = s
    end

    return box
end

local function RenderTo(panel, source)
    if not panel or not panel.boxes then return end
    for schemaIdx = 1, 6 do
        local box = panel.boxes[schemaIdx]
        local schema = SLOT_SCHEMA[schemaIdx]
        if box then
            for i, s in ipairs(box.sockets) do
                local idx = i - 1
                local data = source[schema.ord] and source[schema.ord][idx]
                local filled = data and data.gemId and data.gemId > 0
                local active = data and data.active
                if filled then
                    ApplySocketGemIcon(s.icon, data.gemId)
                    if s.icon:IsShown() then
                        s.icon:SetAlpha(active and 1 or 0.72)
                    end
                else
                    s.icon:Hide()
                end

                if s.icon then
                    s.icon:SetDrawLayer("ARTWORK", 5)
                end
                local tint = COLOR_RGB[s._color]
                for _, edge in ipairs(s.edges) do
                    -- Super vibrant: full brightness when active, slightly dimmed when inactive
                    -- Apply brightness to socket edge colors
                    if PA.Brightness then
                        local r, g, b = PA.Brightness.BrightenRGB(tint[1], tint[2], tint[3])
                        edge:SetVertexColor(r, g, b, active and 1.0 or 0.5)
                    else
                        edge:SetVertexColor(tint[1], tint[2], tint[3], active and 1.0 or 0.5)
                    end
                end
                if s.emptyMark then
                    if not filled and active then s.emptyMark:Show()
                    else s.emptyMark:Hide() end
                end
                if s.dim then
                    if active or filled then
                        s.dim:Hide()
                    else
                        s.dim:Show()
                    end
                end
                if s.gemName then
                    if filled then
                        local category = PA.GemFusion and PA.GemFusion.catalog
                            and PA.GemFusion.catalog[data.gemId]
                        local name, _, quality = GetItemInfo(data.gemId)
                        name = PA.CleanGemTierMarker(name or (category and category.name)
                            or ("Item " .. data.gemId))
                        local spellName = category and category.family
                        if not spellName or spellName == "" then
                            spellName = name:match("[Oo]f%s+(.+)$") or name
                            spellName = spellName:gsub("^[Yy]ellow Astral Gem of%s+", "")
                        end
                        spellName = spellName:gsub("^%s*%[?T%d+%]?%s*", "")
                        spellName = spellName:gsub("%s*%[?T%d+%]?%s*$", "")
                        local qualityColor = ITEM_QUALITY_COLORS[quality or 1]
                        local color = qualityColor and string.format("|cff%02x%02x%02x",
                            qualityColor.r * 255, qualityColor.g * 255, qualityColor.b * 255)
                            or "|cffffffff"
                        local tier = category and tonumber(category.tier)
                        local inactive = active and "" or "  |cffff5555(inactive)|r"
                        s.gemName:SetText(color .. (tier and ("T" .. tier .. " ") or "") ..
                                          spellName .. "|r" .. inactive)
                        -- Apply brightness to gem name color
                        if PA.Brightness then
                            local r, g, b, a = PA.Brightness.Brighten(UI.Color.textPrimary)
                            s.gemName:SetTextColor(r, g, b, a)
                        else
                            s.gemName:SetTextColor(unpack(UI.Color.textPrimary))
                        end
                    else
                        -- Apply brightness to empty socket text color
                        local emptyColor = {0.47, 0.47, 0.50}
                        if PA.Brightness then
                            local r, g, b = PA.Brightness.BrightenRGB(emptyColor[1], emptyColor[2], emptyColor[3])
                            s.gemName:SetText(string.format("|cff%02x%02x%02xEmpty socket|r", r * 255, g * 255, b * 255))
                        else
                            s.gemName:SetText("|cff777780Empty socket|r")
                        end
                    end
                end
                if s.icon then
                    s.icon:SetDrawLayer("ARTWORK", 7)
                end
            end
        end
    end
end
AG.RenderTo = RenderTo

function AG.Render()
    if AG.panel then
        RenderTo(AG.panel, AG.loadout)
        if AG.panel.statusText then
            AG.panel.statusText:SetText("")
        end
    end
    if AG.inspectFramePanel and AG.inspectFramePanel:IsShown() then
        RenderTo(AG.inspectFramePanel, AG.inspect)
    end
end

local LOADOUT_PREFIX = "AGEMS:1:"

local function EncodeLoadout()
    local parts = {}
    for _, schema in ipairs(SLOT_SCHEMA) do
        local slot = AG.loadout[schema.ord]
        for idx = 0, #schema.colors - 1 do
            local data = slot and slot[idx]
            if data and data.gemId and data.gemId > 0 then
                parts[#parts + 1] = string.format("%d.%d=%d", schema.ord, idx, data.gemId)
            end
        end
    end
    return LOADOUT_PREFIX .. table.concat(parts, ","), #parts
end
AG.EncodeLoadout = EncodeLoadout
AG.SLOT_SCHEMA   = SLOT_SCHEMA

local function DecodeLoadout(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", "")
    local body = text:match("^AGEMS:%d+:(.*)$")
    if not body then return nil end
    local wanted = {}
    for ord, idx, entry in body:gmatch("(%d+)%.(%d+)=(%d+)") do
        wanted[#wanted + 1] = { ord = tonumber(ord), idx = tonumber(idx), entry = tonumber(entry) }
    end
    return wanted
end

local function TiersByFamily(catalog)
    local byFamily = {}
    for entry, cat in pairs(catalog) do
        local family = cat.family or ""
        if family ~= "" then
            local list = byFamily[family]
            if not list then
                list = {}
                byFamily[family] = list
            end
            list[#list + 1] = { entry = entry, tier = tonumber(cat.tier) or 0 }
        end
    end
    for _, list in pairs(byFamily) do
        table.sort(list, function(a, b) return a.tier > b.tier end)
    end
    return byFamily
end

local function PickOwnedTier(wantedEntry, catalog, byFamily, left)
    if (left[wantedEntry] or 0) > 0 then return wantedEntry end
    local cat  = catalog[wantedEntry]
    local list = cat and byFamily[cat.family or ""]
    if not list then return nil end
    local maxTier = tonumber(cat.tier) or 0
    for _, g in ipairs(list) do
        if g.tier < maxTier and (left[g.entry] or 0) > 0 then return g.entry end
    end
    return nil
end

local function PlanLoadout(wanted, replace)
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local catalogReady = next(catalog) ~= nil
    local byFamily = catalogReady and TiersByFamily(catalog) or {}
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    local left = {}
    for entry, n in pairs(stock) do left[entry] = n end

    local function FamilyOf(entry)
        local cat = catalogReady and catalog[entry]
        return (cat and cat.family) or ""
    end

    local current, holderOf = {}, {}
    for _, schema in ipairs(SLOT_SCHEMA) do
        local slot = AG.loadout[schema.ord]
        for idx = 0, #schema.colors - 1 do
            local data = slot and slot[idx]
            if data and data.gemId and data.gemId > 0 then
                local key = schema.ord .. "." .. idx
                local family = FamilyOf(data.gemId)
                current[key] = { ord = schema.ord, idx = idx, gemId = data.gemId, family = family }
                if family ~= "" then holderOf[family] = key end
            end
        end
    end

    local wantedAt = {}
    for _, w in ipairs(wanted) do wantedAt[w.ord .. "." .. w.idx] = w.entry end

    local plan = { fill = {}, unsocket = {}, replaced = 0, already = 0, occupied = 0,
                   inactive = 0, missing = 0, family = 0, invalid = 0, lowerTier = 0 }
    local freed = {}

    local function Free(key)
        local c = current[key]
        freed[key] = true
        plan.unsocket[#plan.unsocket + 1] = { op = "unsocket",
            equipSlot = SLOT_SCHEMA[c.ord + 1].equipSlot, idx = c.idx }
        if c.family ~= "" and holderOf[c.family] == key then holderOf[c.family] = nil end
    end

    for _, w in ipairs(wanted) do
        local schema = SLOT_SCHEMA[w.ord + 1]
        local key  = w.ord .. "." .. w.idx
        local data = AG.loadout[w.ord] and AG.loadout[w.ord][w.idx]
        local c    = (not freed[key]) and current[key] or nil
        if not schema or w.idx >= #schema.colors then
            plan.invalid = plan.invalid + 1
        elseif c and c.gemId == w.entry then
            plan.already = plan.already + 1
        elseif not (data and data.active) then
            plan.inactive = plan.inactive + 1
        elseif c and not replace then
            plan.occupied = plan.occupied + 1
        else
            local family = FamilyOf(w.entry)
            local holder = (family ~= "") and holderOf[family] or nil
            local freeHolder
            if holder and holder ~= key then
                local h = current[holder]
                local keep = (holder == "placed") or (h and wantedAt[holder] == h.gemId)
                if replace and not keep then freeHolder = holder end
            end

            if holder and holder ~= key and not freeHolder then
                plan.family = plan.family + 1
            else
                local returned = {}
                if freeHolder then returned[#returned + 1] = current[freeHolder].gemId end
                if c then returned[#returned + 1] = c.gemId end
                for _, g in ipairs(returned) do left[g] = (left[g] or 0) + 1 end

                local pick
                if catalogReady then
                    pick = PickOwnedTier(w.entry, catalog, byFamily, left)
                elseif (left[w.entry] or 0) > 0 then
                    pick = w.entry
                end

                if not pick or (c and pick == c.gemId) then
                    for _, g in ipairs(returned) do left[g] = left[g] - 1 end
                    if pick then
                        plan.already = plan.already + 1
                    else
                        plan.missing = plan.missing + 1
                    end
                else
                    if freeHolder then Free(freeHolder) end
                    if c then
                        Free(key)
                        plan.replaced = plan.replaced + 1
                    end
                    if family ~= "" then holderOf[family] = "placed" end
                    left[pick] = left[pick] - 1
                    if pick ~= w.entry then plan.lowerTier = plan.lowerTier + 1 end
                    plan.fill[#plan.fill + 1] = { equipSlot = schema.equipSlot, idx = w.idx, entry = pick }
                end
            end
        end
    end
    return plan
end

local function DescribePlan(plan)
    local n = #plan.fill
    local notes = {}
    if plan.replaced > 0 then
        notes[#notes + 1] = plan.replaced .. " replacing a socketed gem"
    end
    local movedOut = #plan.unsocket - plan.replaced
    if movedOut > 0 then
        notes[#notes + 1] = movedOut .. " same-family gem(s) removed from other sockets"
    end
    if plan.lowerTier > 0 then
        notes[#notes + 1] = plan.lowerTier .. " at a lower tier"
    end
    local head = (n > 0)
        and string.format("|cff80e090Ready to socket %d gem%s from your stash%s.|r", n, n == 1 and "" or "s",
            #notes > 0 and (" (" .. table.concat(notes, ", ") .. ")") or "")
        or "|cffffcc66Nothing to socket.|r"
    local skipped = {}
    local function add(count, text)
        if count > 0 then skipped[#skipped + 1] = string.format(text, count) end
    end
    add(plan.already,  "%d already in place")
    add(plan.occupied, "%d socket(s) still hold another gem")
    add(plan.inactive, "%d socket(s) inactive")
    add(plan.missing,  "%d gem(s) not in your stash at any tier")
    add(plan.family,   "%d share a family with an equipped gem")
    add(plan.invalid,  "%d unknown socket(s)")
    if #skipped == 0 then return head end
    return head .. "  Skipped: " .. table.concat(skipped, " · ")
end

local applyQueue
local applyDone, applyRemoved, applyFailed = 0, 0, 0
local applyWait, applyAcc = 0, 0
local applyDriver = CreateFrame("Frame")
applyDriver:SetSize(1, 1)
applyDriver:Hide()

local function FinishApply()
    applyDriver:Hide()
    applyQueue = nil
    AG._applyWaiting = nil
    local parts = { applyDone .. " socketed" }
    if applyRemoved > 0 then parts[#parts + 1] = applyRemoved .. " removed" end
    if applyFailed  > 0 then parts[#parts + 1] = applyFailed .. " failed" end
    local msg = "Gem loadout applied: " .. table.concat(parts, ", ") .. "."
    DEFAULT_CHAT_FRAME:AddMessage("|cffa335ee[Astral Gems]|r " .. msg)
    if UI.GainPopup then UI.GainPopup(msg, applyFailed > 0 and "warn" or "gems") end
    if AIO and AIO.Handle then AIO.Handle("AstralgemServer", "RequestLoadout") end
end

local function ApplyNext()
    local step = applyQueue and table.remove(applyQueue, 1)
    if not step then FinishApply(); return end
    local hasAIO = AIO and AIO.Handle

    if step.op == "refresh" then
        if hasAIO then AIO.Handle("AstralgemServer", "RequestLoadout") end
        if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
        applyWait, applyAcc = 1.5, 0
    elseif step.op == "replan" then
        local plan = PlanLoadout(DecodeLoadout(step.text) or {}, false)
        for _, s in ipairs(plan.fill) do applyQueue[#applyQueue + 1] = s end
        applyWait, applyAcc = 0, 0
    elseif step.op == "unsocket" then
        if hasAIO then
            AG._applyWaiting = "unsocket"
            AIO.Handle("AstralgemServer", "Unsocket", step.equipSlot, step.idx)
            applyWait, applyAcc = 4.0, 0
        else
            Send(string.format("gem unsocket %d %d", step.equipSlot, step.idx))
            applyRemoved = applyRemoved + 1
            applyWait, applyAcc = 0.6, 0
        end
    elseif hasAIO then
        AG._pendingGemEntry = step.entry
        AG._applyWaiting = "socket"
        AIO.Handle("AstralgemServer", "Socket", step.equipSlot, step.idx, step.entry)
        applyWait, applyAcc = 4.0, 0
    else
        Send(string.format("gem socket %d %d %d", step.equipSlot, step.idx, step.entry))
        applyDone = applyDone + 1
        applyWait, applyAcc = 0.6, 0
    end
    applyDriver:Show()
end

applyDriver:SetScript("OnUpdate", function(_, dt)
    applyAcc = applyAcc + dt
    if applyAcc < applyWait then return end
    if AG._applyWaiting then
        AG._applyWaiting = nil
        applyFailed = applyFailed + 1
    end
    ApplyNext()
end)

function AG.OnApplySocketResult(status)
    if AG._applyWaiting ~= "socket" then return end
    AG._applyWaiting = nil
    if status == "OK" then
        applyDone = applyDone + 1
    else
        applyFailed = applyFailed + 1
        if status == "IN_COMBAT" then applyQueue = {} end
    end
    applyWait, applyAcc = 0.6, 0
end

function AG.OnApplyUnsocketResult(status)
    if AG._applyWaiting ~= "unsocket" then return end
    AG._applyWaiting = nil
    if status == "OK" then
        applyRemoved = applyRemoved + 1
    else
        applyFailed = applyFailed + 1
        if status == "IN_COMBAT" then applyQueue = {} end
    end
    applyWait, applyAcc = 0.6, 0
end

function AG.ApplyLoadoutText(text)
    if applyQueue then
        UIErrorsFrame:AddMessage("A gem loadout is already being applied.", 1, 0.5, 0.5, 53, 4)
        return
    end
    local wanted = DecodeLoadout(text)
    if not wanted then return end
    local plan = PlanLoadout(wanted, true)
    if #plan.fill == 0 then
        UIErrorsFrame:AddMessage("No gems to socket from that loadout.", 1, 0.8, 0.3, 53, 4)
        return
    end
    applyQueue = {}
    applyDone, applyRemoved, applyFailed = 0, 0, 0
    if #plan.unsocket > 0 then
        for _, s in ipairs(plan.unsocket) do applyQueue[#applyQueue + 1] = s end
        applyQueue[#applyQueue + 1] = { op = "refresh" }
        applyQueue[#applyQueue + 1] = { op = "replan", text = text }
    else
        for _, s in ipairs(plan.fill) do applyQueue[#applyQueue + 1] = s end
    end
    ApplyNext()
end

AG.DecodeLoadout = DecodeLoadout

function AG.DescribeLoadoutText(text)
    local wanted = DecodeLoadout(text)
    if not wanted then return nil end
    local plan = PlanLoadout(wanted, true)
    return DescribePlan(plan), #plan.fill
end

function AG.IsApplyingLoadout()
    return applyQueue ~= nil
end

function AG.LoadoutGemStatus(text)
    local wanted = DecodeLoadout(text)
    if not wanted then return nil end
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local catalogReady = next(catalog) ~= nil
    local byFamily = catalogReady and TiersByFamily(catalog) or {}

    local left = {}
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    for entry, n in pairs(stock) do left[entry] = n end
    for _, schema in ipairs(SLOT_SCHEMA) do
        local slot = AG.loadout and AG.loadout[schema.ord]
        for idx = 0, #schema.colors - 1 do
            local data = slot and slot[idx]
            if data and data.gemId and data.gemId > 0 then
                left[data.gemId] = (left[data.gemId] or 0) + 1
            end
        end
    end

    local st = { total = #wanted, exact = 0, lower = 0, missing = 0, byIndex = {} }
    local pending = {}
    for i, w in ipairs(wanted) do
        if (left[w.entry] or 0) > 0 then
            left[w.entry] = left[w.entry] - 1
            st.exact = st.exact + 1
            st.byIndex[i] = "exact"
        else
            pending[#pending + 1] = i
        end
    end
    for _, i in ipairs(pending) do
        local pick = catalogReady and PickOwnedTier(wanted[i].entry, catalog, byFamily, left)
        if pick then
            left[pick] = left[pick] - 1
            st.lower = st.lower + 1
            st.byIndex[i] = "lower"
        else
            st.missing = st.missing + 1
            st.byIndex[i] = "missing"
        end
    end
    return st
end

local exportDialog, importDialog

local function ShowLoadoutExport()
    if not (UI.MakeTextDialog) then return end
    if not exportDialog then
        exportDialog = UI.MakeTextDialog({
            name         = "AstralGemsExportDialog",
            title        = "Export Gem Loadout",
            subtitle     = "Ctrl+A to select all, Ctrl+C to copy, then share it.",
            button1Label = "Close",
        })
    end
    local text, count = EncodeLoadout()
    exportDialog:Show()
    exportDialog.editBox:SetText(text)
    exportDialog.editBox:HighlightText()
    exportDialog.editBox:SetFocus()
    exportDialog.status:SetText(count > 0
        and string.format("%d socketed gem%s in this loadout.", count, count == 1 and "" or "s")
        or "No gems socketed — the loadout is empty.")
end

local function ShowLoadoutImport()
    if not (UI.MakeTextDialog) then return end
    if not importDialog then
        importDialog = UI.MakeTextDialog({
            name         = "AstralGemsImportDialog",
            title        = "Import Gem Loadout",
            subtitle     = "Paste a loadout (AGEMS:1:...). Missing gems fall back to the best lower tier you own.",
            button1Label = "Import",
            onAccept     = function(text, dlg)
                if applyQueue then
                    dlg.status:SetText("|cffffcc66A gem loadout is already being applied — wait for it to finish.|r")
                    return true
                end
                local wanted = DecodeLoadout(text)
                if not wanted then
                    dlg.status:SetText("|cffff6060That isn't a gem loadout (it should start with AGEMS:1:).|r")
                    return true
                end
                local plan = PlanLoadout(wanted, true)
                if #plan.fill == 0 then
                    dlg.status:SetText(DescribePlan(plan))
                    return true
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cffa335ee[Astral Gems]|r " .. DescribePlan(plan))
                AG.ApplyLoadoutText(text)
                return false
            end,
        })
    end
    importDialog.status:SetText("Paste a loadout and click Import. Gems you own are socketed right away.")
    importDialog.editBox:SetText("")
    importDialog:Show()
    importDialog.editBox:SetFocus()
    if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
end

local function AddButtonTip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local gemOutlineFrames = {}

local function AddGemOutline(frame)
    local glow = UI.Color.accent
    local themeTextures = {}
    local function addGlowBand(size, inset, alpha)
        local tint = { glow[1], glow[2], glow[3], alpha }
        local function edge(width, height, first, second, firstX, firstY, secondX, secondY)
            local texture = UI.SolidFill(frame, tint, "OVERLAY")
            texture:SetBlendMode("ADD")
            texture:SetPoint(first, frame, first, firstX, firstY)
            texture:SetPoint(second, frame, second, secondX, secondY)
            if width then texture:SetWidth(width) else texture:SetHeight(height) end
            themeTextures[#themeTextures + 1] = { texture = texture, alpha = alpha }
        end
        edge(nil, size, "TOPLEFT", "TOPRIGHT", 0, -inset, 0, -inset)
        edge(nil, size, "BOTTOMLEFT", "BOTTOMRIGHT", 0, inset, 0, inset)
        edge(size, nil, "TOPLEFT", "BOTTOMLEFT", inset, 0, inset, 0)
        edge(size, nil, "TOPRIGHT", "BOTTOMRIGHT", -inset, 0, -inset, 0)
    end

    addGlowBand(8, 0, 0.30)
    addGlowBand(5, 2, 0.45)
    addGlowBand(2, 3, 0.70)
    for _, texture in ipairs(UI.Outline(frame, frame, "OVERLAY", glow, 1)) do
        themeTextures[#themeTextures + 1] = { texture = texture, alpha = 1 }
    end
    gemOutlineFrames[frame] = themeTextures
end

function AG.RefreshTheme()
    local color = UI.Color.accent
    for _, textures in pairs(gemOutlineFrames) do
        for _, entry in ipairs(textures) do
            entry.texture:SetVertexColor(color[1], color[2], color[3], entry.alpha)
        end
    end
end

local function CreateAstralGemsPanel(host)
    local panel = CreateFrame("Frame", nil, host)
    panel:SetAllPoints()
    AG.panel = panel
    panel.boxes = {}
    local base = panel:CreateTexture(nil, "BACKGROUND")
    base:SetTexture("Interface\\Buttons\\WHITE8X8")
    base:SetAllPoints()
    base:SetVertexColor(0.002, 0.002, 0.004, 1)
    UI.AddStarfield(panel, 0.06)

    local exportBtn = UI.MakeButton(panel, "Export", {
        w = 96, h = 30, variant = "secondary", onClick = ShowLoadoutExport,
    })
    exportBtn:SetPoint("TOPLEFT", 16, -16)
    AddButtonTip(exportBtn, "Export Loadout",
        "Copy your socketed gems as text to share with other players.")

    local importBtn = UI.MakeButton(panel, "Import", {
        w = 96, h = 30, variant = "secondary", onClick = ShowLoadoutImport,
    })
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
    exportBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    importBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    AddButtonTip(importBtn, "Import Loadout",
        "Paste someone's loadout. Gems from your stash are socketed automatically, replacing gems that are in the way. If you don't have a gem, the highest lower tier of it that you own is used instead.")

    local refreshBtn = UI.MakeButton(panel, "Refresh", { w = 120, h = 30 })
    refreshBtn:SetPoint("TOPRIGHT", -16, -16)
    refreshBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    refreshBtn:SetScript("OnClick", function()
        if AIO and AIO.Handle then
            AIO.Handle("AstralgemServer", "RequestLoadout")
        else
            Send("gem loadout")
        end
    end)

    local header = panel:CreateFontString(nil, "OVERLAY")
    header:SetFont("Fonts\\MORPHEUS.TTF", 26)
    header:SetPoint("TOP", 0, -14)
    header:SetText("Astral Gems")
    -- Apply brightness to title color
    if PA.Brightness then
        local r, g, b, a = PA.Brightness.Brighten(UI.Color.textTitle)
        header:SetTextColor(r, g, b, a)
    else
        header:SetTextColor(unpack(UI.Color.textTitle))
    end
    header:SetShadowColor(0.05, 0.10, 0.25, 0.9)
    panel.header = header
    header:SetShadowOffset(1, -1)

    local sub = panel:CreateFontString(nil, "OVERLAY")
    sub:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    sub:SetPoint("TOP", header, "BOTTOM", 0, -2)
    sub:SetText("Sockets unlock based on equipped item quality.")
    -- Apply brightness to subtitle color
    if PA.Brightness then
        local r, g, b, a = PA.Brightness.Brighten(UI.Color.textAccent)
        sub:SetTextColor(r, g, b, a)
    else
        sub:SetTextColor(unpack(UI.Color.textAccent))
    end
    sub:SetShadowColor(0.05, 0.10, 0.25, 0.75)
    panel.sub = sub
    sub:SetShadowOffset(1, -1)

    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    statusText:SetPoint("TOP", sub, "BOTTOM", 0, -4)
    statusText:SetText("")
    panel.statusText = statusText

    -- Two-column socket layout leaves room for names beside every socket.
    local grid = CreateFrame("Frame", nil, panel)
    grid:SetSize(536, 480)
    grid:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -100)
    UI.AstralBackdrop(grid, {
        thin = true,
        bg = { 0.002, 0.002, 0.004, 0.96 },
        border = UI.Color.borderDim,
    })
    grid:SetBackdropColor(0.002, 0.002, 0.004, 0.96)
    AddGemOutline(grid)

    -- Slot boxes are laid out responsively after the equipped list is created.
    local slotOptions = {
        socketSize = 36,
        socketGap = 6,
        showGemNames = true,
        gemNameWidth = 142,
    }
    local boxHead = BuildSlotBox(grid, 1, slotOptions)
    panel.boxes[1] = boxHead

    local boxNeck = BuildSlotBox(grid, 2, slotOptions)
    panel.boxes[2] = boxNeck

    local boxBoots = BuildSlotBox(grid, 5, slotOptions)
    panel.boxes[5] = boxBoots

    local boxChest = BuildSlotBox(grid, 3, slotOptions)
    panel.boxes[3] = boxChest

    local boxLegs = BuildSlotBox(grid, 4, slotOptions)
    panel.boxes[4] = boxLegs

    local boxWeapon = BuildSlotBox(grid, 6, slotOptions)
    panel.boxes[6] = boxWeapon

    local slotRows = {
        { boxHead, boxNeck },
        { boxChest, boxLegs },
        { boxBoots, boxWeapon },
    }
    local function LayoutPanel()
        local width, height = panel:GetWidth() or 0, panel:GetHeight() or 0
        if width <= 0 or height <= 0 then return end
        local gridWidth = math.max(360, math.min(540, math.floor(width - 20)))
        grid:ClearAllPoints()
        grid:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -100)
        grid:SetSize(gridWidth, 480)

        local boxWidth = math.min(198, math.floor((gridWidth - 12) / 2))
        local labelWidth = math.max(60, boxWidth - 56)
        for _, box in ipairs({ boxHead, boxNeck, boxBoots, boxChest, boxLegs, boxWeapon }) do
            box:SetGemNameWidth(labelWidth)
        end
        boxWidth = boxHead:GetWidth()
        local columnGap = math.max(4, math.floor((gridWidth - boxWidth * 2) / 3))
        local xPositions = { columnGap, columnGap * 2 + boxWidth }
        local y = 14
        for rowIndex, boxes in ipairs(slotRows) do
            local rowHeight = math.max(boxes[1]:GetHeight(), boxes[2]:GetHeight())
            for columnIndex, box in ipairs(boxes) do
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", grid, "TOPLEFT", xPositions[columnIndex], -y)
            end
            y = y + rowHeight + 10
        end
    end
    panel:SetScript("OnSizeChanged", LayoutPanel)
    LayoutPanel()

    return panel
end

local function BuildAstralGemsTab(host)
    if not AG.panel then CreateAstralGemsPanel(host) end
    host:SetScript("OnShow", function()
        if AIO and AIO.Handle then
            AIO.Handle("AstralgemServer", "RequestLoadout")
        else
            Send("gem loadout")
        end
        if not (PA.GemFusion and PA.GemFusion.catalog and next(PA.GemFusion.catalog)) then
            if PA.GemFusion and PA.GemFusion.RequestInfo then
                PA.GemFusion.RequestInfo()
            else
                Send("gem info")
            end
        end
        if not (PA.GemStash and PA.GemStash.GetStock and next(PA.GemStash.GetStock())) then
            SendChatMessage(".astralstash list", "SAY")
        end
        AG.Render()
    end)
end

local function ToggleFrame()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "AstralGems" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("AstralGems")
        if mf._tabBar then mf._tabBar:SelectTab("AstralGems") end
    end
end

local function CompactSlotGrid(parent)
    local boxOpts = { socketSize = 20, readonly = true }

    local grid = CreateFrame("Frame", nil, parent)
    grid:SetSize(200, 380)  -- Increased height for better spacing
    grid:SetPoint("TOP", parent, "TOP", 0, -56)
    parent.boxes = {}

    local col1X = 5
    local col2X = 65
    local col3X = 125
    local startY = 0
    local boxGap = -8  -- Gap between boxes in same column

    -- Column 1: Head, Neck, Boots
    local boxHead = BuildSlotBox(grid, 1, boxOpts)
    boxHead:SetPoint("TOPLEFT", grid, "TOPLEFT", col1X, startY)
    parent.boxes[1] = boxHead

    local boxNeck = BuildSlotBox(grid, 2, boxOpts)
    boxNeck:SetPoint("TOP", boxHead, "BOTTOM", 0, boxGap)
    parent.boxes[2] = boxNeck

    local boxBoots = BuildSlotBox(grid, 5, boxOpts)
    boxBoots:SetPoint("TOP", boxNeck, "BOTTOM", 0, boxGap)
    parent.boxes[5] = boxBoots

    -- Column 2: Chest, Legs
    local boxChest = BuildSlotBox(grid, 3, boxOpts)
    boxChest:SetPoint("TOPLEFT", grid, "TOPLEFT", col2X, startY)
    parent.boxes[3] = boxChest

    local boxLegs = BuildSlotBox(grid, 4, boxOpts)
    boxLegs:SetPoint("TOP", boxChest, "BOTTOM", 0, boxGap)
    parent.boxes[4] = boxLegs

    -- Column 3: Weapon
    local boxWeapon = BuildSlotBox(grid, 6, boxOpts)
    boxWeapon:SetPoint("TOPLEFT", grid, "TOPLEFT", col3X, startY)
    parent.boxes[6] = boxWeapon
end

local function HideInspectContentFrames()
    if InspectPaperDollFrame then InspectPaperDollFrame:Hide() end
    if InspectPVPFrame       then InspectPVPFrame:Hide()       end
    if InspectTalentFrame    then InspectTalentFrame:Hide()    end
    if InspectModelFrame     then InspectModelFrame:Hide()     end
end

local function ShowInspectGemsContent()
    if not (InspectFrame and InspectFrame.gemsPanel) then return end
    HideInspectContentFrames()
    InspectFrame.gemsPanel:Show()
    local unit = (InspectFrame.unit) or "target"
    local name = UnitName(unit)

    if InspectFrame.gemsPanel._portraitCopy and UnitExists(unit) then
        SetPortraitTexture(InspectFrame.gemsPanel._portraitCopy, unit)
    end
    if InspectFrame.gemsPanel._titleCopy and InspectFrameTitleText then
        InspectFrame.gemsPanel._titleCopy:SetText(
            InspectFrameTitleText:GetText() or "")
    end
    if name and name ~= "" then
        AG.inspecting = name
        ClearTable(AG.inspect)
        if AIO and AIO.Handle then
            AIO.Handle("AstralgemServer", "RequestInspect", name)
        else
            Send("gem inspect " .. name)
        end
        if InspectFrame.gemsPanel.statusText then
            InspectFrame.gemsPanel.statusText:SetText(
                "|cffffd000Inspect:|r " .. name)
        end
    else
        if InspectFrame.gemsPanel.statusText then
            InspectFrame.gemsPanel.statusText:SetText(
                "|cffff5555No target selected.|r")
        end
    end
    AG.Render()
end

local function HideInspectGemsContent()
    if InspectFrame and InspectFrame.gemsPanel then
        InspectFrame.gemsPanel:Hide()
    end
end

local inspectTabHooked = false
local function BuildInspectFrameGemsTab()
    if inspectTabHooked then return end
    if not InspectFrame then return end

    local existingCount = InspectFrame.numTabs or 3
    local lastTab = _G["InspectFrameTab" .. existingCount]
    if not lastTab then return end

    local newIdx = existingCount + 1
    local newTab = CreateFrame("Button", "InspectFrameTab" .. newIdx,
                                InspectFrame, "CharacterFrameTabButtonTemplate")
    newTab:SetID(newIdx)
    newTab:SetText("Gems")
    newTab:SetPoint("LEFT", lastTab, "RIGHT", -16, 0)
    PanelTemplates_TabResize(newTab, 0)
    InspectFrame.numTabs = newIdx

    local panel = CreateFrame("Frame", "InspectFrameGemsPanel", InspectFrame)
    panel:SetFrameLevel((InspectFrame:GetFrameLevel() or 0) + 10)
    panel:SetPoint("TOPLEFT",     InspectFrame, "TOPLEFT",     10,  -20)
    panel:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT", -32,  76)

    if UI and UI.AstralBackdrop then
        UI.AstralBackdrop(panel, { cosmic = true })
    end

    local topOver = CreateFrame("Frame", nil, panel)
    topOver:SetAllPoints(InspectFrame)
    topOver:SetFrameLevel((panel:GetFrameLevel() or 0) + 10)

    local portraitCopy = topOver:CreateTexture(nil, "OVERLAY")
    if InspectFramePortrait then
        portraitCopy:SetSize(InspectFramePortrait:GetWidth(),
                             InspectFramePortrait:GetHeight())
        portraitCopy:SetPoint("TOPLEFT", InspectFramePortrait, "TOPLEFT", 0, 0)
    else
        portraitCopy:SetSize(60, 60)
        portraitCopy:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 7, -6)
    end
    panel._portraitCopy = portraitCopy

    local titleCopy = topOver:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if InspectFrameTitleText then
        titleCopy:SetPoint("TOP", InspectFrameTitleText, "TOP", 0, 0)
    else
        titleCopy:SetPoint("TOP", InspectFrame, "TOP", 0, -15)
    end
    titleCopy:SetTextColor(1, 0.82, 0)
    panel._titleCopy = titleCopy

    panel:Hide()
    InspectFrame.gemsPanel = panel
    AG.inspectFramePanel = panel

    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", 0, -30)
    statusText:SetText("")
    panel.statusText = statusText

    CompactSlotGrid(panel)

    newTab:SetScript("OnClick", function(self)
        PanelTemplates_Tab_OnClick(self, InspectFrame)
        ShowInspectGemsContent()
    end)

    for i = 1, existingCount do
        local t = _G["InspectFrameTab" .. i]
        if t and not t._astralGemsTabHook then
            t._astralGemsTabHook = true
            t:HookScript("OnClick", function() HideInspectGemsContent() end)
        end
    end

    InspectFrame:HookScript("OnHide", function()
        HideInspectGemsContent()
        AG.inspecting = nil
        ClearTable(AG.inspect)
    end)

    inspectTabHooked = true
end

if PA.ItemCache and PA.ItemCache.Subscribe then
    PA.ItemCache.Subscribe(function()
        if AG.panel and AG.panel:IsShown() then AG.Render() end
        if picker and picker:IsShown() and RebuildPickerRows then
            RebuildPickerRows()
        end
        if AG.inspectFramePanel and AG.inspectFramePanel:IsShown() then
            AG.Render()
        end
    end)
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("ADDON_LOADED")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("UNIT_INVENTORY_CHANGED")
local pendingReqAt = 0
evt:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then
            BuildInspectFrameGemsTab()
        end
    elseif event == "PLAYER_LOGIN" then
        if AIO and AIO.Handle then
            AIO.Handle("AstralgemServer", "RequestInfo")
            AIO.Handle("AstralgemServer", "RequestLoadout")
        end
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
        pendingReqAt = GetTime() + 0.1
        evt:SetScript("OnUpdate", function(self)
            if GetTime() < pendingReqAt then return end
            self:SetScript("OnUpdate", nil)
            if AIO and AIO.Handle then
                AIO.Handle("AstralgemServer", "RequestLoadout")
            end
        end)
    end
end)

if IsAddOnLoaded and IsAddOnLoaded("Blizzard_InspectUI") then
    BuildInspectFrameGemsTab()
end

PA:RegisterModule("AstralGems", "Astral Gems", ToggleFrame, {
    subtitle = "Place gems in loadout sockets — item quality unlocks slots.",
})
PA:RegisterTabContent("AstralGems", BuildAstralGemsTab)

-- Register with brightness system to update colors when brightness changes
if PA.Brightness then
    PA.Brightness.Register("AstralGems", function()
        -- Update main title
        if AG.panel and AG.panel.header then
            local r, g, b, a = PA.Brightness.Brighten(UI.Color.textTitle)
            AG.panel.header:SetTextColor(r, g, b, a)
        end

        -- Update subtitle
        if AG.panel and AG.panel.sub then
            local r, g, b, a = PA.Brightness.Brighten(UI.Color.textAccent)
            AG.panel.sub:SetTextColor(r, g, b, a)
        end

        -- Update all slot box labels
        if AG.panel and AG.panel.boxes then
            for _, box in pairs(AG.panel.boxes) do
                if box.label then
                    local labelColor = {0.85, 0.95, 1.00, 1}
                    local r, g, b, a = PA.Brightness.Brighten(labelColor)
                    box.label:SetTextColor(r, g, b, a)
                end

                -- Update socket edges and empty marks
                if box.sockets then
                    for _, socket in ipairs(box.sockets) do
                        if socket.edges then
                            local tint = COLOR_RGB[socket._color]
                            local r, g, b = PA.Brightness.BrightenRGB(tint[1], tint[2], tint[3])
                            for _, edge in ipairs(socket.edges) do
                                edge:SetVertexColor(r, g, b, 1.0)
                            end
                        end

                        if socket.emptyMark then
                            local plusColor = COLOR_RGB[socket._color]
                            local r, g, b = PA.Brightness.BrightenRGB(plusColor[1], plusColor[2], plusColor[3])
                            socket.emptyMark:SetTextColor(r, g, b, 1.0)
                            socket.emptyMark:SetShadowColor(r, g, b, 0.8)
                        end

                        -- Update gem names
                        if socket.gemName then
                            local source = AG.inspecting and AG.inspect or AG.loadout
                            local data = source[socket._ord] and source[socket._ord][socket._idx]
                            if data and data.gemId and data.gemId > 0 then
                                local r, g, b, a = PA.Brightness.Brighten(UI.Color.textPrimary)
                                socket.gemName:SetTextColor(r, g, b, a)
                            else
                                local emptyColor = {0.47, 0.47, 0.50}
                                local r, g, b = PA.Brightness.BrightenRGB(emptyColor[1], emptyColor[2], emptyColor[3])
                                socket.gemName:SetText(string.format("|cff%02x%02x%02xEmpty socket|r", r * 255, g * 255, b * 255))
                            end
                        end
                    end
                end
            end
        end
    end)
end

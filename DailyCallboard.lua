
local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local M = {}
M.slots        = {}
M.tokensToday  = 0
M.softCap      = 0
M.overCapPct   = 100
M.activeCount  = 0
M.maxAccept    = 3
M.slotCount    = 15
M.resetEpoch   = 0
M.rangeYards   = 12
M.boardOpen    = false
M.filter       = { category = 0, hideCd = false, sortBy = "tokens" }

local frame, gridFrame, headerF, footerF, filterPanel, resetText
local tiles = {}

local CAT_LABEL = {
    [1] = "Slay",  [2] = "Rare",  [3] = "Elite", [4] = "Skin",
    [5] = "Herb",  [6] = "Mine",  [7] = "Fish",  [8] = "Cloth",
    [9] = "Craft", [10] = "Quests", [11] = "LFG",
}

local ZONE_NAMES = {
    [1]  = "Elwynn Forest",       [2]  = "Westfall",
    [3]  = "Duskwood",            [4]  = "Redridge Mountains",
    [5]  = "Stranglethorn Vale",  [6]  = "Swamp of Sorrows",
    [7]  = "Blasted Lands",       [8]  = "Burning Steppes",
    [9]  = "Searing Gorge",       [10] = "Badlands",
    [11] = "Loch Modan",          [12] = "Dun Morogh",
    [13] = "Wetlands",            [14] = "Arathi Highlands",
    [15] = "Hillsbrad Foothills", [16] = "Alterac Mountains",
    [17] = "Silverpine Forest",   [18] = "Tirisfal Glades",
    [19] = "Western Plaguelands", [20] = "Eastern Plaguelands",
    [30] = "Durotar",             [31] = "The Barrens",
    [32] = "Mulgore",             [33] = "Stonetalon Mountains",
    [34] = "Ashenvale",           [35] = "Darkshore",
    [36] = "Teldrassil",          [37] = "Felwood",
    [38] = "Winterspring",        [39] = "Moonglade",
    [40] = "Azshara",             [41] = "Dustwallow Marsh",
    [42] = "Thousand Needles",    [43] = "Tanaris",
    [44] = "Un'Goro Crater",      [45] = "Silithus",
    [46] = "Desolace",             [47] = "Feralas",
    [99] = "Eastern Kingdoms",   [100] = "Kalimdor",
    [201] = "Shadowfang Keep",       [202] = "The Stockade",
    [203] = "The Deadmines",         [204] = "Wailing Caverns",
    [205] = "Razorfen Kraul",        [206] = "Blackfathom Deeps",
    [207] = "Uldaman",               [208] = "Gnomeregan",
    [209] = "Sunken Temple",         [210] = "Razorfen Downs",
    [211] = "Scarlet Monastery",     [212] = "Zul'Farrak",
    [213] = "Blackrock Spire",       [214] = "Blackrock Depths",
    [215] = "Scholomance",           [216] = "Stratholme",
    [217] = "Maraudon",              [218] = "Ragefire Chasm",
    [219] = "Dire Maul",
}

local PROFESSION_NAMES = {
    [129] = "First Aid",      [164] = "Blacksmithing",
    [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism",      [185] = "Cooking",
    [186] = "Mining",         [197] = "Tailoring",
    [202] = "Engineering",    [333] = "Enchanting",
    [356] = "Fishing",        [393] = "Skinning",
    [755] = "Jewelcrafting",  [773] = "Inscription",
}
local CRAFT_PHANTOM_CRAFT    = 5020024
local CRAFT_PHANTOM_COOKING  = 5020025
local CRAFT_PHANTOM_FIRSTAID = 5020026
local function professionLabelFor(slot)
    local skill = slot.skill or 0
    if PROFESSION_NAMES[skill] then return PROFESSION_NAMES[skill] end
    if slot.cat == 9 then
        if slot.reqNpc == CRAFT_PHANTOM_COOKING  then return "Cooking"   end
        if slot.reqNpc == CRAFT_PHANTOM_FIRSTAID then return "First Aid" end
        return "Crafting"
    end
    return nil
end
local function isProfessionCategory(cat)
    return cat == 4 or cat == 5 or cat == 6 or cat == 7 or cat == 9
end
local CAT_COLOR = {
    [1]  = { 0.92, 0.62, 0.55 },
    [2]  = { 0.92, 0.55, 0.92 },
    [3]  = { 0.65, 0.55, 0.92 },
    [4]  = { 0.82, 0.66, 0.55 },
    [5]  = { 0.55, 0.92, 0.55 },
    [6]  = { 0.66, 0.66, 0.66 },
    [7]  = { 0.55, 0.82, 0.92 },
    [8]  = { 0.92, 0.92, 0.92 },
    [9]  = { 0.92, 0.82, 0.55 },
    [10] = { 0.65, 0.82, 1.00 },
    [11] = { 0.85, 0.55, 1.00 },
}

local function send(cmd) SendChatMessage("." .. cmd, "SAY") end

local function DelayedRequestState(ms)
    if frame and frame.loadingOverlay then
        frame.loadingOverlay:Show()
    end
    local delay = (ms or 250) / 1000
    local acc = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc >= delay then
            self:SetScript("OnUpdate", nil)
            if _G.AIO and _G.AIO.Handle then
                _G.AIO.Handle("AstralDailyCallboardServer", "RequestState")
            end
        end
    end)
end

function M:Accept(idx)
    send("dailycallboard accept " .. tostring(idx))
    local s = M.slots[idx]
    if s then s._pending = "accept" end
    if frame and frame:IsShown() then M:_renderGrid() end
    DelayedRequestState(280)
end

function M:TurnIn(idx)
    send("dailycallboard turnin " .. tostring(idx))
    local s = M.slots[idx]
    if s then s._pending = "turnin" end
    if frame and frame:IsShown() then M:_renderGrid() end
    DelayedRequestState(400)
end

function M:Abandon(idx)
    send("dailycallboard abandon " .. tostring(idx))
    local s = M.slots[idx]
    if s then s._pending = "abandon" end
    if frame and frame:IsShown() then M:_renderGrid() end
    DelayedRequestState(280)
end

function M:Refresh()
    send("dailycallboard refresh")
    DelayedRequestState(280)
end

function M:CloseServer()
    send("dailycallboard close")
end

function M:RequestState()
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralDailyCallboardServer", "RequestState")
    end
end

local FRAME_W, FRAME_H = 980, 720
local TILE_H = 70
local TILE_GAP = 6
local FILTER_H = 32
local SCROLLBAR_W = 22

local function makeFrame()
    if frame then return end
    frame = CreateFrame("Frame", "ProjectAstralDailyCallboardFrame", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    UI.FlatBackdrop(frame)
    UI.AddStarfield(frame, 0.05)

    headerF = UI.MakeHeader(frame, "Daily Callboard",
                            "Daily tasks — fresh picks after every turn-in")

    if headerF and headerF.closeBtn then
        headerF.closeBtn:SetScript("OnClick", function()
            if frame then frame:Hide() end
            M:CloseServer()
        end)
    end

    footerF = UI.MakeFooter(frame, { height = 34 })
    footerF:SetHeight(34)
    footerF.text:Hide()
    footerF.reset = footerF:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerF.reset:SetPoint("LEFT", footerF, "LEFT", 0, -4)
    footerF.softCap = footerF:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerF.softCap:SetPoint("CENTER", footerF, "CENTER", 0, -4)
    footerF.active = footerF:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerF.active:SetPoint("RIGHT", footerF, "RIGHT", 0, -4)

    filterPanel = CreateFrame("Frame", nil, frame)
    filterPanel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     16, -80)
    filterPanel:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",   -16, -80)
    filterPanel:SetHeight(FILTER_H)
    resetText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("TOP", frame, "TOP", 0, -58)
    resetText:SetTextColor(unpack(UI.Color.textMuted))
    local baseline = filterPanel:CreateTexture(nil, "BACKGROUND")
    baseline:SetTexture("Interface\\Buttons\\WHITE8X8")
    baseline:SetVertexColor(unpack(UI.Color.borderDim))
    baseline:SetPoint("BOTTOMLEFT")
    baseline:SetPoint("BOTTOMRIGHT")
    baseline:SetHeight(1)

    M:_buildFilterButtons()

    local scroll = CreateFrame("ScrollFrame",
                               "ProjectAstralDailyCallboardScroll",
                               frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     filterPanel, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",   -14 - SCROLLBAR_W, 50)

    if UI and UI.MakeLoadingOverlay then
        frame.loadingOverlay = UI.MakeLoadingOverlay(frame,
            { text = "Loading callboard" .. string.char(0xE2, 0x80, 0xA6) })
    end

    gridFrame = CreateFrame("Frame", nil, scroll)
    gridFrame:SetWidth(FRAME_W - 56)
    gridFrame:SetHeight(1)
    scroll:SetScrollChild(gridFrame)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local step = (TILE_H + TILE_GAP) * 1.5
        local maxScroll = math.max(0, self:GetVerticalScrollRange())
        local target = math.max(0, math.min(maxScroll, cur - delta * step))
        self:SetVerticalScroll(target)
    end)

    if UI.SkinTree then UI.SkinTree(frame) end
end

function M:_buildFilterButtons()
    local labels = {
        { 0,         "All" },
        { "SLAY",    "Slay" },
        { "PROF",    "Gather" },
        { 9,         "Craft" },
        { 10,        "Quests" },
        { "DUNGEON", "Dungeon" },
    }
    local x = 8
    local buttons = {}
    local activeLine = filterPanel:CreateTexture(nil, "OVERLAY")
    activeLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    activeLine:SetHeight(2)
    activeLine:SetVertexColor(unpack(UI.Color.borderHot))

    local function Paint()
        for _, entry in ipairs(buttons) do
            if entry.cat == M.filter.category then
                entry.label:SetTextColor(unpack(UI.Color.textTitle))
                activeLine:ClearAllPoints()
                activeLine:SetPoint("BOTTOMLEFT", filterPanel, "BOTTOMLEFT", entry.x, 0)
                activeLine:SetWidth(entry.width)
                activeLine:Show()
            else
                entry.label:SetTextColor(unpack(UI.Color.textMuted))
            end
        end
    end

    for _, row in ipairs(labels) do
        local cat, label = row[1], row[2]
        local width = math.max(64, string.len(label) * 8 + 24)
        local b = CreateFrame("Button", nil, filterPanel)
        b:SetSize(width, FILTER_H - 8)
        b:SetPoint("BOTTOMLEFT", filterPanel, "BOTTOMLEFT", x, 0)
        local hover = b:CreateTexture(nil, "BACKGROUND")
        hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        hover:SetAllPoints()
        hover:SetVertexColor(1, 1, 1, 0.05)
        hover:Hide()
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(label)
        text:SetTextColor(unpack(UI.Color.textMuted))
        b:SetScript("OnEnter", function()
            hover:Show()
            text:SetTextColor(unpack(UI.Color.textTitle))
        end)
        b:SetScript("OnLeave", function()
            hover:Hide()
            Paint()
        end)
        b:SetScript("OnClick", function()
            M.filter.category = cat
            Paint()
            M:_renderGrid()
        end)
        buttons[#buttons + 1] = { cat = cat, label = text, x = x, width = width }
        x = x + width + 4
    end

    local sortWidth = 112
    local sort = CreateFrame("Button", nil, filterPanel)
    sort:SetSize(sortWidth, FILTER_H - 8)
    sort:SetPoint("BOTTOMRIGHT", filterPanel, "BOTTOMRIGHT", -8, 0)
    local sortHover = sort:CreateTexture(nil, "BACKGROUND")
    sortHover:SetTexture("Interface\\Buttons\\WHITE8X8")
    sortHover:SetAllPoints()
    sortHover:SetVertexColor(1, 1, 1, 0.05)
    sortHover:Hide()
    local sortLabel = sort:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sortLabel:SetPoint("CENTER")
    sortLabel:SetText("Sort: Tokens")
    sortLabel:SetTextColor(unpack(UI.Color.textMuted))
    sort:SetScript("OnEnter", function()
        sortHover:Show()
        sortLabel:SetTextColor(unpack(UI.Color.textTitle))
    end)
    sort:SetScript("OnLeave", function()
        sortHover:Hide()
        sortLabel:SetTextColor(unpack(UI.Color.textMuted))
    end)
    sort:SetScript("OnClick", function()
        if M.filter.sortBy == "tokens" then
            M.filter.sortBy = "level"
            sortLabel:SetText("Sort: Level")
        else
            M.filter.sortBy = "tokens"
            sortLabel:SetText("Sort: Tokens")
        end
        M:_renderGrid()
    end)
    Paint()
end

local function makeTile(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(TILE_H)
    UI.AstralBackdrop(t, { thin = true, bg = UI.Color.bgRowAlt,
                            border = UI.Color.borderDim })

    t.catBar = t:CreateTexture(nil, "ARTWORK")
    t.catBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    t.catBar:SetPoint("TOPLEFT", 6, -5)
    t.catBar:SetPoint("BOTTOMLEFT", 6, 5)
    t.catBar:SetWidth(4)

    t.catTag = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.catTag:SetPoint("TOPLEFT", 18, -5)
    if t.catTag.SetWordWrap then t.catTag:SetWordWrap(false) end

    t.title = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t.title:SetPoint("TOPLEFT",  18, -18)
    t.title:SetPoint("TOPRIGHT", t, "TOPRIGHT", -235, -18)
    t.title:SetJustifyH("LEFT")
    if t.title.SetWordWrap then t.title:SetWordWrap(false) end

    t.objective = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.objective:SetPoint("TOPLEFT",  18, -36)
    t.objective:SetPoint("TOPRIGHT", t, "TOPRIGHT", -235, -36)
    t.objective:SetJustifyH("LEFT")
    t.objective:SetTextColor(unpack(UI.Color.textMuted))
    if t.objective.SetWordWrap then t.objective:SetWordWrap(false) end

    t.location = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.location:SetPoint("TOPLEFT",  18, -53)
    t.location:SetPoint("TOPRIGHT", t, "TOPRIGHT", -235, -53)
    t.location:SetJustifyH("LEFT")
    t.location:SetTextColor(unpack(UI.Color.textAccent))
    if t.location.SetWordWrap then t.location:SetWordWrap(false) end

    t.rewardLabel = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.rewardLabel:SetPoint("RIGHT", t, "RIGHT", -130, 22)
    t.rewardLabel:SetText("REWARD")
    t.rewardLabel:SetTextColor(unpack(UI.Color.textMuted))

    t.tokens = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t.tokens:SetPoint("RIGHT", t, "RIGHT", -130, 5)
    t.tokens:SetTextColor(unpack(UI.Color.textHi))

    t.levelLabel = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.levelLabel:SetPoint("RIGHT", t, "RIGHT", -130, -10)
    t.levelLabel:SetText("LEVEL")
    t.levelLabel:SetTextColor(unpack(UI.Color.textMuted))

    t.lvl = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.lvl:SetPoint("RIGHT", t, "RIGHT", -130, -20)
    t.lvl:SetTextColor(unpack(UI.Color.textMuted))

    t.btn = CreateFrame("Button", nil, t)
    t.btn:SetSize(104, 24)
    t.btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    t.btn:SetBackdropColor(0.015, 0.015, 0.018, 0.96)
    t.btn:SetBackdropBorderColor(unpack(UI.Color.borderMid))
    t.btn.label = t.btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.btn.label:SetPoint("CENTER")
    t.btn.label:SetTextColor(unpack(UI.Color.textTitle))
    t.btn.SetLabel = function(self, text) self.label:SetText(text) end
    t.btn:SetLabel("Accept")
    t.btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.17, 1)
        self:SetBackdropBorderColor(unpack(UI.Color.borderHot))
    end)
    t.btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.015, 0.015, 0.018, 0.96)
        self:SetBackdropBorderColor(unpack(UI.Color.borderMid))
    end)
    t.btn:SetPoint("RIGHT", t, "RIGHT", -12, 0)
    return t
end

local function statusButtonState(slot)
    if slot._pending then
        if     slot._pending == "accept"  then return "Accepting...", false, "accept"
        elseif slot._pending == "turnin"  then return "Turning in...", false, "turnin"
        elseif slot._pending == "abandon" then return "Abandoning...", false, "abandon" end
    end
    if slot.status == 1 then
        if slot.serverComplete then
            return "Get Reward", true, "turnin"
        end
        return "Abandon", true, "abandon"
    end
    if slot.status == 0 and slot.qid and slot.qid > 0 then
        return "Accept", true, "accept"
    end
    return "-", false, "accept"
end

function M:_renderGrid()
    if not gridFrame then return end

    local list = {}
    local fc = M.filter.category
    local function passesFilter(s)
        if fc == 0 then return true end
        if fc == "SLAY" then
            return s.cat == 1 or s.cat == 3
        end
        if fc == "PROF" then
            return s.cat == 4 or s.cat == 5 or s.cat == 6 or s.cat == 7
        end
        if fc == "DUNGEON" then
            return s.cat == 2 or s.cat == 11
        end
        return s.cat == fc
    end
    for _, s in pairs(M.slots) do
        local hasQuest = s.qid and s.qid > 0
        if hasQuest and passesFilter(s) then
            table.insert(list, s)
        end
    end
    table.sort(list, function(a, b)
        if M.filter.sortBy == "level" then
            if a.lvlMin ~= b.lvlMin then return a.lvlMin < b.lvlMin end
            return a.tokens > b.tokens
        end
        if a.tokens ~= b.tokens then return a.tokens > b.tokens end
        return a.idx < b.idx
    end)

    for _, t in ipairs(tiles) do t:Hide() end

    for i, slot in ipairs(list) do
        local t = tiles[i]
        if not t then
            t = makeTile(gridFrame)
            tiles[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT",  gridFrame, "TOPLEFT",  0, -(i - 1) * (TILE_H + TILE_GAP))
        t:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -(i - 1) * (TILE_H + TILE_GAP))

        local col = CAT_COLOR[slot.cat] or { 0.55, 0.55, 0.55 }
        t.catBar:SetVertexColor(col[1], col[2], col[3], 0.95)
        t.catTag:SetText("|cff" .. string.format("%02x%02x%02x",
                                                  math.floor(col[1]*255),
                                                  math.floor(col[2]*255),
                                                  math.floor(col[3]*255))
                         .. (CAT_LABEL[slot.cat] or "?") .. "|r")

        t.title:SetText(slot.title or "")
        t.objective:SetText(slot.objective or "")

        local locText = ""
        local profLabel = isProfessionCategory(slot.cat) and professionLabelFor(slot)
        if profLabel then
            locText = "Profession: " .. profLabel
        end
        t.location:SetText(locText)

        t.tokens:SetText((slot.tokens or 0) .. " Tokens")
        t.lvl:SetText(("Level %d-%d"):format(slot.lvlMin or 0, slot.lvlMax or 0))

        local label, enabled, action = statusButtonState(slot)
        if action == "accept" and slot.status == 0
           and M.maxAccept and M.activeCount
           and M.activeCount >= M.maxAccept
           and not slot._pending then
            enabled = false
        end
        t.btn:SetLabel(label)
        if enabled then t.btn:Enable() else t.btn:Disable() end
        t.btn:SetScript("OnClick", function()
            if     action == "accept"  then M:Accept(slot.idx)
            elseif action == "abandon" then M:Abandon(slot.idx)
            elseif action == "turnin"  then M:TurnIn(slot.idx) end
        end)

        t:Show()
    end

    local total = math.max(1, #list) * (TILE_H + TILE_GAP)
    gridFrame:SetHeight(total)
end

local function paintFooter()
    if not (footerF and footerF.reset and footerF.softCap and footerF.active) then return end
    local secLeft = M.resetEpoch - time()
    local h = math.max(0, math.floor(secLeft / 3600))
    local m = math.max(0, math.floor((secLeft % 3600) / 60))
    local capText = "Soft cap unavailable"
    if M.softCap and M.softCap > 0 then
        local pct = math.floor(((M.tokensToday or 0) / M.softCap) * 100)
        capText = ("Soft cap  %d / %d  (%d%%)"):format(M.tokensToday or 0, M.softCap, pct)
    end
    local resetLabel = ("Reset in %dh %dm"):format(h, m)
    footerF.reset:SetText(resetLabel)
    if resetText then resetText:SetText(resetLabel) end
    footerF.softCap:SetText(capText)
    footerF.active:SetText(("Active quests  %d / %d"):format(M.activeCount or 0,
                                                               M.maxAccept or 3))
    footerF.reset:SetTextColor(unpack(UI.Color.textMuted))
    footerF.softCap:SetTextColor(unpack(UI.Color.textHi))
    footerF.active:SetTextColor(unpack(UI.Color.textMuted))
end

function M:Show()
    makeFrame()
    paintFooter()
    M:_renderGrid()
    frame:Show()
end

local function ApplyState(payload)
    if not payload then return end
    M.tokensToday = payload.tokensToday or 0
    M.softCap     = payload.softCap     or 0
    M.overCapPct  = payload.overCapPct  or 100
    M.activeCount = payload.activeCount or 0
    M.maxAccept   = payload.maxAccept   or 3
    M.slotCount   = payload.slotCount   or 15
    M.resetEpoch  = payload.resetEpoch  or 0
    M.rangeYards  = payload.rangeYards  or 12

    M.slots = {}
    for _, s in ipairs(payload.slots or {}) do
        s.cdExpires = (s.cdSec and s.cdSec > 0) and (GetTime() + s.cdSec) or 0
        s._pending = nil
        M.slots[s.idx] = s
    end

    if frame and frame:IsShown() then
        M:_renderGrid()
        paintFooter()
    end
    if frame and frame.loadingOverlay then
        frame.loadingOverlay:Hide()
    end
end

local function RegisterDCHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local Client = _G.AIO.AddHandlers("AstralDailyCallboard", {})

    Client.OpenFrame = function(_, goGuid, rangeYards)
        M.boardOpen  = true
        M.rangeYards = tonumber(rangeYards) or M.rangeYards
        makeFrame()
        frame:Show()
        M:_renderGrid()
        paintFooter()
        if frame.loadingOverlay then frame.loadingOverlay:Show() end
        DelayedRequestState(350)
    end

    Client.State = function(_, payload) ApplyState(payload) end

    return true
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    if RegisterDCHandlers() then
        self:UnregisterAllEvents()
    end
end)

local ticker = CreateFrame("Frame")
ticker.acc = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.acc = self.acc + elapsed
    if self.acc < 1.0 then return end
    self.acc = 0
    if frame and frame:IsShown() then
        M:_renderGrid()
        paintFooter()
    end
end)

function M:Open()
    makeFrame()
    frame:Show()
    M:_renderGrid()
    paintFooter()
    M:RequestState()
end

PA.DailyCallboard = M


local PA = ProjectAstral
local UI = PA.UI

-- Stats tab: every bonus the Astral Tree gives you, from unlocked nodes plus spent
-- Paragon points, in one column per bonus group. Totals come from Skilltree.lua
-- (AT.NodeTotals / AT.ParagonTotals) so this always matches the tree's Total
-- Bonuses panel.

local SOLID  = "Interface\\Buttons\\WHITE8X8"
local ROW_H  = 24
local COLS   = 3     -- Offensive / Defensive / Quality of Life (+ anything ungrouped)
local GAP    = 10
local HEAD_H = 52

local host
local columns = {}
local counters = {}

local function Round(v)
    if math.abs(v - math.floor(v + 0.5)) < 0.05 then
        return tostring(math.floor(v + 0.5))
    end
    return string.format("%.1f", v)
end

-- same sign rules as the tree's FormatEffect, without the label
local function ValueText(meta, v)
    if meta and meta.unit == "flag" then return "Unlocked" end
    local sign
    if meta and meta.invert then
        sign = v > 0 and "-" or (v < 0 and "+" or "")
    else
        sign = v < 0 and "-" or "+"
    end
    local text = sign .. Round(math.abs(v))
    if meta and meta.unit == "pct" then text = text .. "%" end
    return text
end

local function FriendlyLabel(effectType)
    local label = effectType:gsub("_PCT$", ""):gsub("_ALLOWED$", "")
        :gsub("_UNLOCKED$", ""):gsub("_", " ")
    return label:gsub("%S+", function(word)
        return word:sub(1, 1) .. word:sub(2):lower()
    end)
end

local function MakeCurrencyRow(parent, label, value, iconPath, tint)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(38)
    row:SetBackdrop({ bgFile = SOLID, tile = false })
    row:SetBackdropColor(0.06, 0.07, 0.10, 0.50)
    UI.MakeRowChrome(row, { accentColor = tint })

    local iconPanel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    iconPanel:SetTexture(SOLID)
    iconPanel:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    iconPanel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    iconPanel:SetWidth(32)
    iconPanel:SetVertexColor(tint[1], tint[2], tint[3], 0.18)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER", iconPanel, "CENTER")
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    name:SetPoint("TOPLEFT", iconPanel, "TOPRIGHT", 7, -4)
    name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    name:SetText(label)
    name:SetTextColor(unpack(UI.Color.textPrimary))
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    count:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    count:SetText(tostring(value))
    count:SetTextColor(tint[1], tint[2], tint[3])
    count:SetJustifyH("LEFT")

    row.value = count
    return row
end

local function MakeColumn(parent)
    local col = CreateFrame("Frame", nil, parent)
    UI.AstralBackdrop(col, { thin = true, bg = UI.Color.bgDeep, border = UI.Color.borderDim })

    col.title = col:CreateFontString(nil, "OVERLAY")
    col.title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    col.title:SetPoint("TOPLEFT", col, "TOPLEFT", 12, -11)
    col.title:SetTextColor(unpack(UI.Color.textTitle))

    col.count = col:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    col.count:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    col.count:SetPoint("TOPRIGHT", col, "TOPRIGHT", -12, -12)

    local rule = UI.SolidFill(col, UI.Color.borderDim, "ARTWORK")
    rule:SetPoint("TOPLEFT",  col, "TOPLEFT",  10, -30)
    rule:SetPoint("TOPRIGHT", col, "TOPRIGHT", -10, -30)
    rule:SetHeight(1)

    col.body = CreateFrame("Frame", nil, col)
    col.body:SetPoint("TOPLEFT",     col, "TOPLEFT",     6, -36)
    col.body:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -6, 8)

    col.empty = col.body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    col.empty:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    col.empty:SetPoint("TOPLEFT", col.body, "TOPLEFT", 8, -6)
    col.empty:SetText("Nothing unlocked here yet.")

    col.rows = {}
    return col
end

local function GetRow(col, i)
    local r = col.rows[i]
    if r then return r end

    r = CreateFrame("Frame", nil, col.body)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT",  col.body, "TOPLEFT",  0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", col.body, "TOPRIGHT", 0, -(i - 1) * ROW_H)

    local stripe = r:CreateTexture(nil, "BACKGROUND")
    stripe:SetTexture(SOLID)
    stripe:SetAllPoints()
    stripe:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.03 or 0)

    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.value:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    r.value:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.value:SetJustifyH("RIGHT")
    r.value:SetTextColor(unpack(UI.Color.textGood))

    -- how much of the total comes from Paragon points
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.note:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    r.note:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.note:SetJustifyH("RIGHT")

    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    r.label:SetPoint("LEFT",  r,      "LEFT", 8, 0)
    r.label:SetPoint("RIGHT", r.note, "LEFT", -8, 0)
    r.label:SetJustifyH("LEFT")
    if r.label.SetWordWrap then r.label:SetWordWrap(false) end
    r.label:SetTextColor(unpack(UI.Color.textPrimary))

    col.rows[i] = r
    return r
end

local function Layout()
    if not host then return end
    local w = host:GetWidth() or 0
    if w <= 0 then return end
    local colW = math.floor((w - GAP * (COLS - 1)) / COLS)
    for i, col in ipairs(columns) do
        local x = (i - 1) * (colW + GAP)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT",    host, "TOPLEFT",    x, -HEAD_H)
        col:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", x, 0)
        col:SetWidth(colW)
    end
end

local function Refresh()
    if not (host and host:IsVisible()) then return end
    local AT = PA.AT
    if not (AT and AT.NodeTotals) then return end

    local nodeTotals = AT.NodeTotals()
    local pgTotals   = AT.ParagonTotals and AT.ParagonTotals() or {}
    local meta       = AT.EffectMeta or {}
    local groups     = AT.SummaryGroups or {}

    local totals = {}
    for t, v in pairs(nodeTotals) do totals[t] = v end
    for t, v in pairs(pgTotals)   do totals[t] = (totals[t] or 0) + v end

    -- bonus types outside the first COLS groups are listed in the last column
    local placed = {}
    for gi = 1, COLS do
        for _, t in ipairs((groups[gi] and groups[gi].types) or {}) do placed[t] = true end
    end
    local extra = {}
    for t in pairs(totals) do
        if not placed[t] then extra[#extra + 1] = t end
    end
    table.sort(extra)

    local bonuses = 0
    for gi, col in ipairs(columns) do
        local group = groups[gi]
        local types = {}
        for _, t in ipairs((group and group.types) or {}) do types[#types + 1] = t end
        if gi == COLS then
            for _, t in ipairs(extra) do types[#types + 1] = t end
        end
        col.title:SetText(group and group.name or "Other")

        local n = 0
        for _, t in ipairs(types) do
            local v = totals[t]
            if v and v ~= 0 then
                n = n + 1
                local r = GetRow(col, n)
                local m = meta[t]
                r.label:SetText(m and m.label or FriendlyLabel(t))
                r.value:SetText(ValueText(m, v))
                local pg = pgTotals[t]
                if pg and pg ~= 0 then
                    r.note:SetText(nodeTotals[t] and ("incl. " .. ValueText(m, pg) .. " Paragon") or "Paragon")
                else
                    r.note:SetText("")
                end
                r:Show()
            end
        end
        for i = n + 1, #col.rows do col.rows[i]:Hide() end
        col.count:SetText(n > 0 and (n .. (n == 1 and " bonus" or " bonuses")) or "")
        if n == 0 then col.empty:Show() else col.empty:Hide() end
        bonuses = bonuses + n
    end

    local unlocked = 0
    for _ in pairs(AT.unlocked or {}) do unlocked = unlocked + 1 end
    local pg = (PA.Paragon and PA.Paragon.state) or {}
    counters.nodes.value:SetText(unlocked)
    counters.paragon.value:SetText(string.format("%d / %d", pg.level or 0, pg.max or 0))
    counters.points.value:SetText(pg.available or 0)
    counters.bonuses.value:SetText(bonuses)
end

local function BuildStatsTab(panel)
    host = panel

    counters.nodes = MakeCurrencyRow(panel, "Nodes", 0,
        "Interface\\Icons\\Spell_Nature_Starfall", { 0.40, 0.78, 1.00 })
    counters.paragon = MakeCurrencyRow(panel, "Paragon", "0 / 0",
        "Interface\\Icons\\Spell_Holy_PowerInfusion", { 1.00, 0.84, 0.29 })
    counters.points = MakeCurrencyRow(panel, "Points", 0,
        "Interface\\Icons\\Spell_ChargePositive", { 0.35, 0.90, 0.70 })
    counters.bonuses = MakeCurrencyRow(panel, "Bonuses", 0,
        "Interface\\Icons\\Spell_Holy_WordFortitude", { 0.80, 0.55, 1.00 })

    local treeBtn = UI.MakeButton(panel, "Open Astral Tree", {
        w = 140, h = 24, variant = "secondary",
        onClick = function()
            local mf = PA.mainFrame
            if mf and mf.SwitchTab then mf:SwitchTab("astral_tree") end
        end,
    })
    treeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -6)
    treeBtn:SetSize(140, 28)
    treeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")

    local function LayoutCounters()
        local width = panel:GetWidth() or 0
        if width <= 0 then return end
        local gap, actionW, actionGap = 8, 140, 8
        local cardW = math.floor((width - actionW - actionGap - gap * 3) / 4)
        for i, counter in ipairs({ counters.nodes, counters.paragon,
                                   counters.points, counters.bonuses }) do
            counter:ClearAllPoints()
            counter:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * (cardW + gap), -2)
            counter:SetSize(cardW, 38)
        end
    end

    for i = 1, COLS do columns[i] = MakeColumn(panel) end
    panel:SetScript("OnSizeChanged", function()
        Layout()
        LayoutCounters()
    end)
    Layout()
    LayoutCounters()

    local acc = 0
    panel:SetScript("OnShow", function()
        Layout()
        local AT = PA.AT
        if AT then
            if AT.RequestParagonStateAIO then AT.RequestParagonStateAIO() end
            -- the tree only loads its state when the Skills tab opens; fetch it if
            -- the player came here first
            if not next(AT.unlocked or {}) and AT.RequestInitialStateAIO then
                AT.RequestInitialStateAIO()
            end
        end
        acc = 0
        Refresh()
    end)

    -- cheap fallback refresh while visible (one pass over unlocked nodes a second)
    panel:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc >= 1 then
            acc = 0
            Refresh()
        end
    end)
end

-- live updates: node unlock/remove/reset and Paragon changes (Skilltree.lua loads first)
if PA.AT and PA.AT.OnStatsChanged then PA.AT.OnStatsChanged(Refresh) end
if PA.OnTokensChanged then PA:OnTokensChanged(function() Refresh() end) end

local function ToggleStats()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "astral_stats" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("astral_stats")
    end
end

PA:RegisterModule("astral_stats", "Astral Stats", ToggleStats, {
    subtitle = "Bonuses from unlocked nodes and spent Paragon points.",
})
PA:RegisterTabContent("astral_stats", BuildStatsTab)

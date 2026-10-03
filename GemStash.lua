-- GemStash.lua - MERGED VERSION
-- Live GitHub version + Dynamic rows + Removed tier badges

local _, PA = ...
PA = ProjectAstral or {}
local GS  = {}
PA.GemStash = GS

local SCROLL_SOCKET  = 99998
local SCROLL_REMOVAL = 99999
local SCROLL_ENTRIES = { [SCROLL_SOCKET] = true, [SCROLL_REMOVAL] = true }

local stock = {}
local stockLoaded = false
local itemMeta = {}

local QUALITY_COLOR = {
    [0] = "|cff9d9d9d",
    [1] = "|cffffffff",
    [2] = "|cff1eff00",
    [3] = "|cff0070dd",
    [4] = "|cffa335ee",
    [5] = "|cffff8000",
    [6] = "|cffe6cc80",
    [7] = "|cffe6cc80",
}

local function ItemName(entry)
    local m = itemMeta[entry]
    if m and m.name and m.name ~= "" then return m.name end
    return (select(1, GetItemInfo(entry))) or ("Item " .. tostring(entry))
end

local DelayedRequestState

local stashTier  = 1
local stashEvent = 1
local stashName  = ""

local stashFrame
-- MERGED: Dynamic row calculation instead of fixed 10
local STASH_ROW_H = 38

local function CalculateVisibleRows()
    if not stashFrame then return 10 end
    local frameH = stashFrame:GetHeight() or 560
    local availableH = frameH - 190
    local rows = math.floor(availableH / STASH_ROW_H)
    return math.max(8, math.min(rows, 30))
end

local TIER_FILTERS = {
    { label = "All",     match = function(cat, entry) return true end },
    { label = "Scrolls", match = function(cat, entry) return SCROLL_ENTRIES[entry] == true end },
    { label = "T1",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 1 end },
    { label = "T2",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 2 end },
    { label = "T3",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 3 end },
    { label = "T4",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 4 end },
    { label = "T5",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 5 end },
    { label = "T6",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 6 end },
    { label = "T7",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 7 end },
    { label = "T8",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 8 end },
    { label = "Mythic",  match = function(cat, entry) return cat and cat.isMythic end },
}

local EVENT_FILTERS = {
    { label = "All",            match = function(cat, entry) return true end },
    { label = "Proc on Hit",    match = function(cat, entry) return cat and cat.eventType == 0 end },
    { label = "Proc on Cast",   match = function(cat, entry) return cat and cat.eventType == 1 end },
    { label = "Proc on Heal",   match = function(cat, entry) return cat and cat.eventType == 2 end },
    { label = "Proc on Struck", match = function(cat, entry) return cat and cat.eventType == 3 end },
}

local EVENT_LABEL = {
    [0] = "Hit", [1] = "Cast", [2] = "Heal",
    [3] = "Struck", [4] = "Crit", [5] = "DoT/HoT", [6] = "Any",
}

local TIER_COLOR = {
    [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd",
    [4] = "|cffa335ee", [5] = "|cffff8000", [6] = "|cffe6cc80",
    [7] = "|cffff6080", [8] = "|cffff2020",
}

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

local GS_DEBUG = false

local StartStashIconWarmup
local NotifyStockChanged

local function ApplyState(payload)
    if type(payload) ~= "table" then return end
    stock = {}
    itemMeta = (type(payload.itemMeta) == "table") and payload.itemMeta or {}
    for _, e in ipairs(payload.entries or {}) do
        local entry, count = e.entry, e.count
        if entry and count and count > 0 then
            stock[entry] = count
            if PA and PA.ItemCache then PA.ItemCache.Register(entry) end
        end
    end
    stockLoaded = true
    GS.Refresh()
    if NotifyStockChanged then NotifyStockChanged() end
    if stashFrame and stashFrame:IsVisible() and StartStashIconWarmup then
        StartStashIconWarmup()
    end
    if GS_DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffaaffaa[GemStash dbg]|r State applied, " ..
            tostring(#(payload.entries or {})) .. " entries")
    end
end

local function InitDropdown(dd, options, getCurrent, onSelect)
    UIDropDownMenu_SetWidth(dd, 110)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for i, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = opt.label
            info.value    = i
            info.checked  = (i == getCurrent())
            info.func     = function() onSelect(i) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(dd, getCurrent())
end

local function MatchesStashFilter(catEntry, entry)
    local tf = TIER_FILTERS[stashTier]
    local ef = EVENT_FILTERS[stashEvent]
    if not (tf and ef) then return false end
    local tierEvtOk
    if SCROLL_ENTRIES[entry] then
        tierEvtOk = tf.match(catEntry, entry) and stashEvent == 1
    else
        tierEvtOk = tf.match(catEntry, entry) and ef.match(catEntry, entry)
    end
    if not tierEvtOk then return false end

    if stashName ~= "" then
        local rawName = (GetItemInfo(entry)) or ("Item " .. tostring(entry))
        rawName = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if not rawName:lower():find(stashName, 1, true) then
            return false
        end
    end
    return true
end

local function BuildPanel(embedParent)
    if stashFrame then return stashFrame end

    local f
    if embedParent then
        f = CreateFrame("Frame", "PA_GemStashFrame", embedParent)
        f:SetAllPoints(embedParent)
        f.header = CreateFrame("Frame", nil, f)
        f.header:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, 11)
        f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, 11)
        f.header:SetHeight(1)
    else
        f = PA.UI.MakePanel(UIParent, 580, 560, {
            name    = "PA_GemStashFrame",
            strata  = "DIALOG",
            movable = true,
            point   = { "CENTER", UIParent, "CENTER", 0, 60 },
        })
        f:SetFrameLevel(100)
        f:Hide()
        tinsert(UISpecialFrames, "PA_GemStashFrame")

        f.header = PA.UI.MakeHeader(f, "Astral Gem Stash",
            "Account-wide storage · gem drops auto-deposit here")
    end

    local pill = CreateFrame("Frame", nil, f)
    pill:SetHeight(46)
    pill:SetPoint("TOPLEFT",  f.header, "BOTTOMLEFT",  -6, -10)
    pill:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT",  6, -10)
    PA.UI.AstralBackdrop(pill, { thin = true })
    pill:SetBackdropColor(PA.UI.Color.bgPanel[1], PA.UI.Color.bgPanel[2],
                          PA.UI.Color.bgPanel[3], 0.85)
    pill:SetBackdropBorderColor(PA.UI.Color.borderDim[1], PA.UI.Color.borderDim[2],
                                PA.UI.Color.borderDim[3], 1)

    local tierLabel = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tierLabel:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    tierLabel:SetPoint("LEFT", pill, "LEFT", 12, 1)
    tierLabel:SetText("Tier")
    tierLabel:SetTextColor(PA.UI.Color.textAccent[1], PA.UI.Color.textAccent[2],
                           PA.UI.Color.textAccent[3])

    local tierDd = CreateFrame("Frame", "PA_GemStashTierDD", pill, "UIDropDownMenuTemplate")
    tierDd:SetPoint("LEFT", tierLabel, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(tierDd, 112)
    local tierText = _G[tierDd:GetName() .. "Text"]
    if tierText then tierText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE") end

    local evtLabel = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    evtLabel:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    evtLabel:SetPoint("LEFT", tierDd, "RIGHT", -6, 3)
    evtLabel:SetText("Trigger")
    evtLabel:SetTextColor(PA.UI.Color.textAccent[1], PA.UI.Color.textAccent[2],
                          PA.UI.Color.textAccent[3])

    local evtDd = CreateFrame("Frame", "PA_GemStashEvtDD", pill, "UIDropDownMenuTemplate")
    evtDd:SetPoint("LEFT", evtLabel, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(evtDd, 150)
    local evtText = _G[evtDd:GetName() .. "Text"]
    if evtText then evtText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE") end

    local searchBox = PA.UI.MakeSearchBox(pill, {
        width       = 240,
        height      = 30,
        placeholder = "Search by name…",
        onChanged   = function(text)
            stashName = (text or ""):lower()
            if f.scroll then
                FauxScrollFrame_SetOffset(f.scroll, 0)
                if f.scroll:GetName() then
                    local sb = _G[f.scroll:GetName() .. "ScrollBar"]
                    if sb then sb:SetValue(0) end
                end
            end
            GS.Refresh()
        end,
    })
    searchBox.edit:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    searchBox:SetPoint("LEFT", evtDd, "RIGHT", -8, 0)
    searchBox:SetPoint("RIGHT", pill, "RIGHT", -10, 0)
    f.searchBox = searchBox

    local function repaint()
        UIDropDownMenu_SetSelectedValue(tierDd, stashTier)
        UIDropDownMenu_SetSelectedValue(evtDd,  stashEvent)
        if f.scroll then
            FauxScrollFrame_SetOffset(f.scroll, 0)
            if f.scroll:GetName() then
                local sb = _G[f.scroll:GetName() .. "ScrollBar"]
                if sb then sb:SetValue(0) end
            end
        end
        GS.Refresh()
    end

    local function ApplyTriggerEnabledState()
        local isScroll = TIER_FILTERS[stashTier] and TIER_FILTERS[stashTier].label == "Scrolls"
        if isScroll then
            UIDropDownMenu_DisableDropDown(evtDd)
        else
            UIDropDownMenu_EnableDropDown(evtDd)
        end
    end

    InitDropdown(tierDd, TIER_FILTERS, function() return stashTier end, function(i)
        stashTier = i
        if TIER_FILTERS[i] and TIER_FILTERS[i].label == "Scrolls" then
            stashEvent = 1
        end
        ApplyTriggerEnabledState()
        repaint()
    end)
    InitDropdown(evtDd, EVENT_FILTERS, function() return stashEvent end, function(i)
        stashEvent = i
        repaint()
    end)
    ApplyTriggerEnabledState()

    local inventoryLabel = PA.UI.MakeSectionLabel(f, "Inventory")
    inventoryLabel.label:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    inventoryLabel:SetPoint("TOPLEFT",  pill, "BOTTOMLEFT",  4, -6)
    inventoryLabel:SetPoint("TOPRIGHT", pill, "BOTTOMRIGHT", -60, -6)

    -- MERGED: List frame stretches to fill available space
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT",     inventoryLabel, "BOTTOMLEFT", -2, -8)
    list:SetPoint("BOTTOMLEFT",  f,              "BOTTOMLEFT",  18, 50)
    list:SetPoint("BOTTOMRIGHT", f,              "BOTTOMRIGHT", -20, 50)
    PA.UI.AstralBackdrop(list, { thin = true })
    list:SetBackdropColor(0.010, 0.020, 0.045, 0.85)
    list:SetBackdropBorderColor(PA.UI.Color.borderDim[1], PA.UI.Color.borderDim[2],
                                PA.UI.Color.borderDim[3], 1)

    local scroll = CreateFrame("ScrollFrame", "PA_GemStashScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     list, "TOPLEFT",      6, -6)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, STASH_ROW_H, GS.Refresh)
    end)
    f.scroll = scroll

    -- MERGED: Create rows dynamically based on window size
    f.rows = {}
    local function CreateRows()
        local visibleRows = CalculateVisibleRows()

        for i = 1, #f.rows do
            if f.rows[i] then
                f.rows[i]:Hide()
                f.rows[i] = nil
            end
        end

        for i = 1, visibleRows do
            local row = CreateFrame("Button", nil, list)
            row:SetHeight(STASH_ROW_H)
            row:SetPoint("LEFT",  list, "LEFT",  6, 0)
            row:SetPoint("RIGHT", list, "RIGHT", -28, 0)
            row:SetPoint("TOP",   list, "TOP",   0, -((i - 1) * STASH_ROW_H) - 6)

            PA.UI.MakeRowChrome(row, { alt = (i % 2 == 0) })

            row:SetScript("OnEnter", function(self)
                if self.entry then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. self.entry .. ":0:0:0:0:0:0:0:0")
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            local iconFrame = PA.UI.MakeIconFrame(row, { size = 32 })
            iconFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.iconFrame = iconFrame

            -- MERGED: Removed tier badge
            -- No tierBadge created here

            local wAll = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            PA.UI.CosmicButton(wAll)
            wAll:SetSize(48, 26)
            wAll:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            wAll:SetText("All")
            if wAll:GetFontString() then
                wAll:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            end
            row.wAll = wAll

            local w5 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            PA.UI.CosmicButton(w5)
            w5:SetSize(34, 26)
            w5:SetPoint("RIGHT", wAll, "LEFT", -2, 0)
            w5:SetText("5")
            if w5:GetFontString() then
                w5:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            end
            row.w5 = w5

            local w1 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            PA.UI.CosmicButton(w1)
            w1:SetSize(34, 26)
            w1:SetPoint("RIGHT", w5, "LEFT", -2, 0)
            w1:SetText("1")
            if w1:GetFontString() then
                w1:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            end
            row.w1 = w1

            local countChip = CreateFrame("Frame", nil, row)
            countChip:SetSize(58, 24)
            countChip:SetPoint("RIGHT", w1, "LEFT", -8, 0)
            PA.UI.AstralBackdrop(countChip, { thin = true })
            countChip:SetBackdropColor(PA.UI.Color.bgDeep[1], PA.UI.Color.bgDeep[2],
                                       PA.UI.Color.bgDeep[3], 0.85)
            countChip:SetBackdropBorderColor(PA.UI.Color.borderDim[1], PA.UI.Color.borderDim[2],
                                             PA.UI.Color.borderDim[3], 1)
            local countText = countChip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            countText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            countText:SetPoint("CENTER", countChip, "CENTER", 0, 0)
            countText:SetTextColor(PA.UI.Color.textTitle[1], PA.UI.Color.textTitle[2],
                                   PA.UI.Color.textTitle[3])
            countChip.text = countText
            row.countChip = countChip
            row.countText = countText

            local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            name:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
            -- MERGED: Name starts right after icon (no tier badge gap)
            name:SetPoint("LEFT",  iconFrame, "RIGHT", 10, 0)
            name:SetPoint("RIGHT", countChip, "LEFT", -8, 0)
            name:SetJustifyH("LEFT")
            row.name = name

            f.rows[i] = row
        end
    end

    CreateRows()
    f.CreateRows = CreateRows

    local depAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(depAll)
    depAll:SetSize(320, 32)
    depAll:SetPoint("BOTTOM", 0, 16)
    depAll:SetText("Deposit All Astral Gems and Scrolls")
    if depAll:GetFontString() then
        depAll:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    end
    depAll:SetScript("OnClick", function() Send("astralstash depositall") end)

    f.depositAllBtn = depAll

    local pollAcc = 0
    f:HookScript("OnUpdate", function(self, dt)
        pollAcc = pollAcc + dt
        if pollAcc < 0.5 then return end
        pollAcc = 0
        GS.RequestState()
    end)

    -- MERGED: Resize handler to recreate rows when window resizes
    f:HookScript("OnSizeChanged", function(self, width, height)
        if f.CreateRows then
            f.CreateRows()
            GS.Refresh()
        end
    end)

    stashFrame = f
    return f
end

function GS.Refresh()
    if not (stashFrame and stashFrame:IsVisible()) then return end

    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or _G.GF and _G.GF.catalog or {}
    if GS_DEBUG then
        local stockCount = 0
        for _ in pairs(stock) do stockCount = stockCount + 1 end
        local catCount = 0
        for _ in pairs(catalog) do catCount = catCount + 1 end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffaaffaa[GemStash dbg]|r Refresh stock=%d catalog=%d filter=tier%d/event%d",
            stockCount, catCount, stashTier, stashEvent))
    end
    local rows = {}
    for entry, count in pairs(stock) do
        local cat = catalog[entry]
        if MatchesStashFilter(cat, entry) then
            local name = ItemName(entry)
            local icon = (select(10, GetItemInfo(entry))) or "Interface\\Icons\\INV_Misc_QuestionMark"
            local meta = itemMeta[entry]
            rows[#rows+1] = {
                entry   = entry, count = count, cat = cat,
                name    = name,  icon  = icon,
                quality = meta and meta.quality or nil,
            }
        end
    end

    table.sort(rows, function(a, b)
        local aScroll = SCROLL_ENTRIES[a.entry] and 1 or 0
        local bScroll = SCROLL_ENTRIES[b.entry] and 1 or 0
        if aScroll ~= bScroll then return aScroll < bScroll end
        if a.cat and b.cat then
            if a.cat.isMythic ~= b.cat.isMythic then return b.cat.isMythic end
            if a.cat.tier   ~= b.cat.tier   then return (a.cat.tier or 0) < (b.cat.tier or 0) end
            if a.cat.family ~= b.cat.family then return (a.cat.family or "") < (b.cat.family or "") end
        end
        return (a.name or "") < (b.name or "")
    end)

    -- MERGED: Use dynamic visible rows
    local visibleRows = #stashFrame.rows
    local offset = FauxScrollFrame_GetOffset(stashFrame.scroll) or 0
    FauxScrollFrame_Update(stashFrame.scroll, #rows, visibleRows, STASH_ROW_H)

    for i = 1, visibleRows do
        local row  = stashFrame.rows[i]
        local data = rows[offset + i]
        if data then
            row.entry = data.entry
            row.iconFrame:SetTexture(data.icon)
            row.iconFrame:SetQuality(data.quality or 1)

            local link = select(2, GetItemInfo(data.entry))
            local coloredName = data.name
            if not link and data.quality and QUALITY_COLOR[data.quality] then
                coloredName = QUALITY_COLOR[data.quality] .. data.name .. "|r"
            end
            row.name:SetText(PA.CleanGemTierMarker(link or coloredName))

            -- MERGED: No tier badge to show
            -- tierBadge logic removed

            row.countText:SetText("×" .. data.count)

            local entry = data.entry
            local count = data.count
            row.w1:SetScript("OnClick", function()
                Send("astralstash withdraw " .. entry .. " 1")
                DelayedRequestState(300)
            end)
            row.w5:SetScript("OnClick", function()
                Send("astralstash withdraw " .. entry .. " " .. math.min(5, count))
                DelayedRequestState(300)
            end)
            row.wAll:SetScript("OnClick", function()
                Send("astralstash withdraw " .. entry .. " " .. count)
                DelayedRequestState(300)
            end)

            row:SetScript("OnClick", function()
                if IsModifiedClick("CHATLINK") and PA.InsertChatLink then
                    PA.InsertChatLink(select(2, GetItemInfo(entry)))
                end
            end)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

local queryTip = CreateFrame("GameTooltip", "PA_GemStashItemQueryTip", UIParent, "GameTooltipTemplate")
queryTip:SetOwner(UIParent, "ANCHOR_NONE")
queryTip:Hide()

local function ForceQueryItem(entry)
    if not entry then return end
    GetItemInfo(entry)
    queryTip:ClearLines()
    queryTip:SetHyperlink("item:" .. entry .. ":0:0:0:0:0:0:0:0")
    queryTip:Hide()
end

StartStashIconWarmup = function()
    if not stashFrame then return end
    for entry in pairs(stock) do
        ForceQueryItem(entry)
    end
    stashFrame._warmupLeft = 150
    stashFrame._warmupT    = 0
    stashFrame:SetScript("OnUpdate", function(self, elapsed)
        self._warmupT = (self._warmupT or 0) + elapsed
        if self._warmupT < 0.10 then return end
        self._warmupT = 0
        self._warmupLeft = (self._warmupLeft or 0) - 1

        local stillMissing = false
        for entry in pairs(stock) do
            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(entry)
            if not texture then
                stillMissing = true
                ForceQueryItem(entry)
            end
        end

        GS.Refresh()

        if not stillMissing or self._warmupLeft <= 0 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local itemInfoEvt = CreateFrame("Frame")
itemInfoEvt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemInfoEvt:SetScript("OnEvent", function()
    if stashFrame and stashFrame:IsVisible() then
        GS.Refresh()
    end
end)

function GS.GetStock()
    return stock
end

function GS.IsLoaded()
    return stockLoaded
end

local subscribers = {}
function GS.OnStockChanged(fn)
    if type(fn) == "function" then subscribers[#subscribers+1] = fn end
end

NotifyStockChanged = function()
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn)
        if not ok and GS_DEBUG then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff8888[GemStash]|r subscriber error: " .. tostring(err))
        end
    end
end

function GS.RequestState()
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralStashServer", "RequestState")
    end
end

DelayedRequestState = function(ms)
    local delay = (ms or 300) / 1000
    local acc = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc >= delay then
            self:SetScript("OnUpdate", nil)
            GS.RequestState()
        end
    end)
end
function GS.DelayedRequestState(ms) DelayedRequestState(ms) end

function GS.Toggle()
    local mf = PA.mainFrame
    if mf and mf.SwitchTab and PA._tabContent and PA._tabContent.GemStash then
        if mf:IsShown() and mf._activeTabId == "GemStash" then
            mf:Hide()
        else
            mf:Show()
            mf:SwitchTab("GemStash")
        end
        return
    end

    local f = BuildPanel()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        GS.RequestState()
        GS.Refresh()
        StartStashIconWarmup()
    end
end

local function BuildStashTab(panel)
    BuildPanel(panel)
    panel:SetScript("OnShow", function()
        GS.RequestState()
        GS.Refresh()
        StartStashIconWarmup()
    end)
end

PA:RegisterModule("GemStash", "Gem Stash", GS.Toggle, {
    subtitle = "Account-wide storage · gem drops auto-deposit here.",
})
PA:RegisterTabContent("GemStash", BuildStashTab)

local function RegisterStashHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local Client = _G.AIO.AddHandlers("AstralStash", {})
    Client.State = function(_, payload) ApplyState(payload) end
    return true
end

local bagBurstAcc = 0
local bagBurstFrame = CreateFrame("Frame")
bagBurstFrame:Hide()
bagBurstFrame:SetScript("OnUpdate", function(self, dt)
    bagBurstAcc = bagBurstAcc + dt
    if bagBurstAcc >= 0.30 then
        self:Hide()
        bagBurstAcc = 0
        GS.RequestState()
    end
end)
local function KickBagBurst()
    bagBurstAcc = 0
    bagBurstFrame:Show()
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("BAG_UPDATE")
evt:RegisterEvent("CHAT_MSG_SYSTEM")
evt:SetScript("OnEvent", function(self, event, msg)
    if event == "PLAYER_LOGIN" then
        if RegisterStashHandlers() then
            DelayedRequestState(300)
        end
        return
    end
    if event == "BAG_UPDATE" then
        if stashFrame and stashFrame:IsVisible() then
            KickBagBurst()
        end
        return
    end
    if event == "CHAT_MSG_SYSTEM" and msg then
        if msg:sub(1, 12) == "Astral Gem: " then
            local body = msg:match("^Astral Gem:%s*(.-)%s*dropped")
            if body and body ~= "" and PA.UI and PA.UI.GainPopup then
                PA.UI.GainPopup("Gem drop: " .. body, "gems",
                    { fontSize = 10 })
            end
        end
        return
    end
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(_, _, msg, author)
    return msg and msg:sub(1, 12) == ".astralstash"
        and author == UnitName("player")
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    return msg and msg:sub(1, 12) == "Astral Gem: "
end)

local AIO = AIO or (require and require("AIO"))
if AIO and AIO.AddAddon and AIO.AddAddon() then return end

local PA = ProjectAstral

local GF = {}
PA.GemFusion = GF
GF.info        = {}
GF.catalog     = {}
GF.scrolls     = {}
GF.bagsByEntry = {}
GF.receiving   = false
GF.statusText  = ""
GF.statusUntil = 0

local frame, FlashStatus, browseFrame
local RefreshBrowsePanel

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

function GF.RequestInfo()
    if AIO and AIO.Handle then
        AIO.Handle("AstralgemServer", "RequestInfo")
    else
        Send("gem info")
    end
end

if AIO and AIO.AddHandlers then
    local ClientHandler = AIO.AddHandlers("Astralgem", {})

    ClientHandler.Info = function(_, payload)
        if type(payload) ~= "table" then return end
        GF.catalog = {}
        GF.scrolls = {}
        for k, v in pairs(payload.info or {}) do
            GF.info[k] = tostring(v)
        end
        local prefetchIds = {}
        for _, g in ipairs(payload.gems or {}) do
            if g.entry then
                GF.catalog[g.entry] = {
                    tier      = g.tier,
                    family    = g.family,
                    eventType = tonumber(g.eventType) or 6,
                    name      = g.name    or "",
                    quality   = g.quality or 0,
                }
                prefetchIds[#prefetchIds + 1] = g.entry
            end
        end
        for _, s in ipairs(payload.scrolls or {}) do
            if s.entry then
                GF.scrolls[s.entry] = {
                    kind    = s.kind,
                    pool    = s.pool,
                    name    = s.name    or "",
                    quality = s.quality or 0,
                }
                prefetchIds[#prefetchIds + 1] = s.entry
            end
        end
        if PA.ItemCache and PA.ItemCache.RegisterMany then
            PA.ItemCache.RegisterMany(prefetchIds)
        else
            for _, e in ipairs(prefetchIds) do GetItemInfo(e) end
        end
        GF.receiving = false
        if GF.KickAutoFuse then GF.KickAutoFuse() end   -- catalog + unlocks just arrived
        if frame and frame:IsShown() then
            local hooks = GF._refresh_hooks or {}
            if hooks.ScanBags       then hooks.ScanBags() end
            if frame.gemListPanel and hooks.RefreshGemList then
                hooks.RefreshGemList(frame.gemListPanel)
            end
            if hooks.Refresh        then hooks.Refresh() end
        end
        if browseFrame and browseFrame:IsShown() and RefreshBrowsePanel then
            RefreshBrowsePanel()
        end
    end

    local FUSE_FAIL_MSG = {
        USAGE            = "Internal: missing item entry.",
        NOT_FOUND        = "You don't have 3 of that gem in the stash.",
        T1_ONLY_INPUTS   = "Only T1-T7 gems can be fused. T8 is the top of the chain.",
        NOT_SAME_FAMILY  = "This gem has no family — cannot fuse.",
        NOT_ENOUGH_GOLD  = "Not enough gold to fuse this tier.",
        NO_PERMISSION    = "This fusion tier is locked — unlock it in the Astral Tree first.",
        NO_RECIPE        = "No fusion output for this family/tier.",
        DISABLED         = "Fusion is disabled by the realm operator.",
    }
    ClientHandler.FuseResult = function(_, status, entry)
        if status == "OK" then
            SendChatMessage(".gem fuse " .. tostring(entry or 0), "SAY")

            local srcCat  = GF.catalog and GF.catalog[entry]
            local srcTier = srcCat and srcCat.tier or 0
            local family  = srcCat and srcCat.family or ""
            local outTier = srcTier > 0 and (srcTier + 1) or nil

            local outEntry, outLink, outName
            if GF.catalog and family ~= "" and outTier then
                for e, c in pairs(GF.catalog) do
                    if c.family == family and c.tier == outTier and not c.isMythic then
                        outEntry = e
                        break
                    end
                end
            end
            if outEntry then
                outLink = select(2, GetItemInfo(outEntry))
                outName = outLink or (select(1, GetItemInfo(outEntry)))
                          or ("T" .. tostring(outTier) .. " " .. family)
            else
                outName = outTier
                          and ("T" .. tostring(outTier) .. " " .. family)
                          or  ("item " .. tostring(entry))
            end

            FlashStatus("Added to Astral Gem Stash: " .. outName, "|cff80e090")

            -- Auto Fuse shows one summary popup at the end instead of one per fusion
            if PA.UI and PA.UI.GainPopup and not GF._autoFusing then
                PA.UI.GainPopup("Fusion complete: " .. outName,
                    "gems", { fontSize = 10 })
            end

            if GF.RequestInfo then GF.RequestInfo() end

            if PA.GemStash and PA.GemStash.DelayedRequestState then
                PA.GemStash.DelayedRequestState(400)
            end
        else
            local msg = FUSE_FAIL_MSG[status] or ("Fusion failed: " .. tostring(status))
            FlashStatus(msg, "|cffff6060")
        end
        if GF.OnAutoFuseResult then GF.OnAutoFuseResult(status, entry) end
    end
end

local function Split(str, sep)
    local t, i = {}, 1
    while true do
        local j = str:find(sep, i, true)
        if j then t[#t+1] = str:sub(i, j-1); i = j+1
        else      t[#t+1] = str:sub(i); break end
    end
    return t
end

local function FormatMoney(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 and s == 0 and c == 0 then return string.format("%dg", g) end
    if g > 0 and c == 0              then return string.format("%dg %ds", g, s) end
    if g > 0                         then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 and c == 0              then return string.format("%ds", s) end
    if s > 0                         then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end

FlashStatus = function(text, color)
    GF.statusText = (color or "|cffffd000") .. text .. "|r"
    GF.statusUntil = time() + 4
    if frame and frame.status then
        frame.status:SetText(GF.statusText)
        frame.status:Show()
    end
end

local function ScanBags()
    GF.bagsByEntry = {}
    if not (PA.GemStash and PA.GemStash.GetStock) then return end
    for entry, count in pairs(PA.GemStash.GetStock()) do
        if GF.catalog[entry] then
            GF.bagsByEntry[entry] = (GF.bagsByEntry[entry] or 0) + count
        end
    end
end

local function SubscribeToStashUpdates()
    if not (PA.GemStash and PA.GemStash.OnStockChanged) then return end
    PA.GemStash.OnStockChanged(function()
        ScanBags()
        if GF._RefreshGemList then GF._RefreshGemList() end
    end)
end

local PANEL_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local PANEL_BG_COLOR     = { 0.012, 0.018, 0.032, 0.94 }
local PANEL_BORDER_COLOR = { 0.30, 0.23, 0.48, 0.82 }

local function MakeStatBox(parent, anchor, x, y, label, sublabel)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(120, 78)
    box:SetPoint("TOPLEFT", parent, anchor, x, y or -84)
    box:SetBackdrop(PANEL_BACKDROP)
    PA.UI.CosmicCorners(box)
    box:SetBackdropColor(unpack(PANEL_BG_COLOR))
    box:SetBackdropBorderColor(unpack(PANEL_BORDER_COLOR))

    local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    lbl:SetPoint("TOP", box, "TOP", 0, -6)
    lbl:SetText(label)

    if sublabel then
        local sub = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        sub:SetPoint("TOP", lbl, "BOTTOM", 0, -2)
        sub:SetText(sublabel)
        sub:SetTextColor(unpack(PA.UI.Color.textMuted))
    end

    local val = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    val:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    val:SetPoint("BOTTOM", box, "BOTTOM", 0, 8)
    val:SetText("—")
    val:SetTextColor(unpack(PA.UI.Color.textTitle))
    return val
end

local function MakeCostCard(parent, x, y, w, h, header)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(w, h)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card:SetBackdrop(PANEL_BACKDROP)
    PA.UI.CosmicCorners(card)
    card:SetBackdropColor(unpack(PANEL_BG_COLOR))
    card:SetBackdropBorderColor(unpack(PANEL_BORDER_COLOR))

    local hdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    hdr:SetPoint("TOP", card, "TOP", 0, -5)
    hdr:SetText(header)
    hdr:SetTextColor(unpack(PA.UI.Color.textMuted))

    local val = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    val:SetPoint("BOTTOM", card, "BOTTOM", 0, 6)
    val:SetText("—")
    val:SetTextColor(unpack(PA.UI.Color.textTitle))
    return val
end

local function ApplyUnlockFlag(label, isAllowed)
    if isAllowed then label:SetTextColor(0.50, 0.85, 0.35)
    else              label:SetTextColor(0.85, 0.30, 0.30)
    end
end

local W, H = 540, 720

local function FusionCostForTier(srcTier)
    if not srcTier or srcTier < 1 or srcTier > 7 then return 0 end
    local key = string.format("FUSION_COST_T%d_T%d_COPPER", srcTier, srcTier + 1)
    return tonumber(GF.info[key]) or 0
end

local function FuseEntry(entry)
    if AIO and AIO.Handle then
        AIO.Handle("AstralgemServer", "Fuse", entry)
    else
        Send("gem fuse " .. tostring(entry))
    end
    local cat = GF.catalog[entry]
    if cat then
        FlashStatus(string.format("Fusing 3× %s (T%d) for %s…",
            cat.family or "?", cat.tier or 0,
            FormatMoney(FusionCostForTier(cat.tier))), "|cffc8a951")
    end
end

-- ── Auto Fuse ───────────────────────────────────────────────────────
-- Optional: keeps fusing 3x same gem -> 1x next tier from the Gem Stash, lowest
-- tier first (so fresh results cascade upward), until nothing is left to fuse
-- without going past the chosen target tier. One request at a time: each waits
-- for FuseResult plus the stash refresh. Pauses in combat, pauses when gold runs
-- short, and skips tiers that aren't unlocked in the Astral Tree.

local AUTO_TIERS = {}
for t = 2, 8 do AUTO_TIERS[#AUTO_TIERS + 1] = { label = "T" .. t, tier = t } end

local auto = { busy = false, waiting = false, fused = 0, notFound = 0,
               wait = 0, acc = 0, noGold = false, blocked = {} }
local autoDriver = CreateFrame("Frame")
autoDriver:SetSize(1, 1)   -- sized so the 3.3.5 client ticks its OnUpdate
autoDriver:Hide()

local function AutoSettings()
    local s = PA.Settings or {}
    local maxTier = tonumber(s.autoFuseMaxTier) or 8
    return s.autoFuse == true, math.max(2, math.min(8, maxTier))
end

-- lowest-tier stack of 3+ whose fused result stays at or below maxTier
local function NextAutoFuse(maxTier)
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    local best, bestTier
    for entry, count in pairs(stock) do
        local cat  = GF.catalog[entry]
        local tier = cat and tonumber(cat.tier)
        if tier and tier >= 1 and tier < maxTier and (count or 0) >= 3
           and cat.family and cat.family ~= ""
           and GF.info["GEM_FUSION_T" .. (tier + 1) .. "_ALLOWED"] == "1"
           and not auto.blocked[tier + 1]
           and (not bestTier or tier < bestTier or (tier == bestTier and entry < best)) then
            best, bestTier = entry, tier
        end
    end
    return best, bestTier
end

local function FinishAutoFuse(reason)
    local fused = auto.fused
    auto.busy, auto.waiting, auto.fused, auto.notFound = false, false, 0, 0
    GF._autoFusing = false
    autoDriver:Hide()
    if fused > 0 and PA.UI and PA.UI.GainPopup then
        PA.UI.GainPopup(string.format("Auto Fuse: %d fusion%s complete", fused,
            fused == 1 and "" or "s"), "gems")
    end
    if reason then FlashStatus(reason, "|cffffcc66") end
end

local function AutoFuseStep()
    local enabled, maxTier = AutoSettings()
    if not enabled or InCombatLockdown() then   -- combat: PLAYER_REGEN_ENABLED restarts it
        FinishAutoFuse()
        return
    end
    local entry, tier = NextAutoFuse(maxTier)
    if not entry then
        FinishAutoFuse()
        return
    end
    local cost = FusionCostForTier(tier)
    if cost > 0 and GetMoney() < cost then
        auto.noGold = true                       -- cleared by PLAYER_MONEY
        FinishAutoFuse(string.format("Auto Fuse paused: T%d -> T%d needs %s.",
            tier, tier + 1, FormatMoney(cost)))
        return
    end
    auto.busy, auto.waiting = true, true
    GF._autoFusing = true
    auto.wait, auto.acc = 6.0, 0                 -- stop if the server never answers
    FuseEntry(entry)
    autoDriver:Show()
end

autoDriver:SetScript("OnUpdate", function(_, dt)
    auto.acc = auto.acc + dt
    if auto.acc < auto.wait then return end
    if auto.waiting then
        FinishAutoFuse("Auto Fuse stopped: no reply from the server.")
        return
    end
    AutoFuseStep()
end)

function GF.OnAutoFuseResult(status, entry)
    if not auto.waiting then return end          -- a manual Fuse click
    auto.waiting = false
    if status == "OK" then
        auto.fused = auto.fused + 1
        auto.notFound = 0
        auto.wait, auto.acc = 1.2, 0             -- let the stash refresh land first
    elseif status == "NOT_FOUND" then
        -- stash counts were stale; refresh and retry once before giving up
        auto.notFound = auto.notFound + 1
        if auto.notFound >= 2 then FinishAutoFuse(); return end
        if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
        auto.wait, auto.acc = 2.0, 0
    elseif status == "NO_PERMISSION" then
        local cat  = GF.catalog[entry]
        local tier = cat and tonumber(cat.tier)
        if tier then auto.blocked[tier + 1] = true end
        auto.wait, auto.acc = 0.3, 0
    elseif status == "NOT_ENOUGH_GOLD" then
        auto.noGold = true
        FinishAutoFuse("Auto Fuse paused: not enough gold.")
    else
        FinishAutoFuse("Auto Fuse stopped: " .. tostring(status))
    end
end

function GF.KickAutoFuse()
    local enabled = AutoSettings()
    if not enabled or auto.busy or auto.noGold or not next(GF.catalog) then return end
    AutoFuseStep()
end

local autoEvents = CreateFrame("Frame")
autoEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
autoEvents:RegisterEvent("PLAYER_MONEY")
autoEvents:RegisterEvent("CHAT_MSG_SYSTEM")
autoEvents:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_MONEY" then
        if not auto.busy then auto.noGold = false end
        GF.KickAutoFuse()
    elseif event == "PLAYER_REGEN_ENABLED" then
        GF.KickAutoFuse()
    elseif msg and msg:sub(1, 12) == "Astral Gem: " and (AutoSettings()) then
        -- a gem drop goes straight into the stash server-side: refresh counts,
        -- and the stock-changed callback below starts fusing
        if PA.GemStash and PA.GemStash.DelayedRequestState then
            PA.GemStash.DelayedRequestState(800)
        end
    end
end)

if PA.GemStash and PA.GemStash.OnStockChanged then
    PA.GemStash.OnStockChanged(function() GF.KickAutoFuse() end)
end

-- Lazy row-pool: WoW 3.3.5 cannot destroy frames, so allocating fresh
local function GetGemRow(host, index)
    host._rowPool = host._rowPool or {}
    if host._rowPool[index] then return host._rowPool[index] end

    local row = CreateFrame("Button", nil, host)
    PA.UI.MakeRowChrome(row, { alt = (index % 2 == 0) })

    local iconFrame = PA.UI.MakeIconFrame(row, { size = 32 })
    iconFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.iconFrame = iconFrame
    row.icon = iconFrame.icon   -- alias for legacy code

    row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(row.btn)
    row.btn:SetSize(126, 28)
    row.btn:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    local countChip = CreateFrame("Frame", nil, row)
    countChip:SetSize(56, 24)
    countChip:SetPoint("RIGHT", row.btn, "LEFT", -8, 0)
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

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    row.label:SetPoint("LEFT",  iconFrame, "RIGHT", 12, 0)
    row.label:SetPoint("RIGHT", countChip, "LEFT", -8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    host._rowPool[index] = row
    return row
end

-- nil (crash on first tab open). Same tables reused by the Catalog

local TIER_FILTERS = {
    { label = "All", match = function(c) return true end },
    { label = "T1",  match = function(c) return c.tier == 1 end },
    { label = "T2",  match = function(c) return c.tier == 2 end },
    { label = "T3",  match = function(c) return c.tier == 3 end },
    { label = "T4",  match = function(c) return c.tier == 4 end },
    { label = "T5",  match = function(c) return c.tier == 5 end },
    { label = "T6",  match = function(c) return c.tier == 6 end },
    { label = "T7",  match = function(c) return c.tier == 7 end },
    { label = "T8",  match = function(c) return c.tier == 8 end },
}

local EVENT_FILTERS = {
    { label = "All",            match = function(c) return true end },
    { label = "Proc on Hit",    match = function(c) return c.eventType == 0 end },
    { label = "Proc on Cast",   match = function(c) return c.eventType == 1 end },
    { label = "Proc on Heal",   match = function(c) return c.eventType == 2 end },
    { label = "Proc on Struck", match = function(c) return c.eventType == 3 end },
}

local fuseTier  = 1
local fuseEvent = 1
local fuseName  = ""
local fuseReadyOnly = false

local function RefreshGemList(panel)
    local host = panel.child or panel
    host._rowPool = host._rowPool or {}

    local entries = {}
    local tf = TIER_FILTERS[fuseTier]
    local ef = EVENT_FILTERS[fuseEvent]
    for entry, count in pairs(GF.bagsByEntry) do
        local cat = GF.catalog[entry]
        -- FIX: Changed cat.tier <= 7 to cat.tier <= 8 to include T8 gems in the list
        if cat and cat.tier and cat.tier >= 1 and cat.tier <= 8
              and (not fuseReadyOnly or (count or 0) >= 3) then
            local passTier = (not tf) or tf.match(cat)
            local passEvt  = (not ef) or ef.match(cat)
            local passName = true
            if fuseName ~= "" then
                local rawName = (cat.name ~= "" and cat.name)
                             or (select(1, GetItemInfo(entry)))
                             or ""
                rawName = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                passName = rawName:lower():find(fuseName, 1, true) ~= nil
            end
            if passTier and passEvt and passName then
                local name = cat.name ~= "" and cat.name or (select(1, GetItemInfo(entry)) or "")
                table.insert(entries, {
                    entry = entry, count = count, tier = cat.tier,
                    family = cat.family, name = name,
                })
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.family ~= b.family then return (a.family or "") < (b.family or "") end
        if a.name ~= b.name then return (a.name or ""):lower() < (b.name or ""):lower() end
        return a.entry < b.entry
    end)

    if not host._emptyText then
        host._emptyText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        host._emptyText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        host._emptyText:SetPoint("TOPLEFT", host, "TOPLEFT", 12, -12)
    end

    if #entries == 0 then
        host._emptyText:SetText(fuseReadyOnly
            and "No gems ready to fuse. You need at least 3 copies of the same T1-T7 gem."
            or "No eligible T1-T8 gems in your stash.")
        host._emptyText:Show()
        for _, row in ipairs(host._rowPool) do row:Hide() end
        if host.SetHeight then host:SetHeight(40) end
        return
    end
    host._emptyText:Hide()

    local rowH = 42
    local rowGap = 2
    local y = -4
    local hostW = panel.scroll and panel.scroll:GetWidth() or host:GetWidth()
    if hostW and hostW > 0 then host:SetWidth(hostW) end

    for i, e in ipairs(entries) do
        local cat = e
        local row = GetGemRow(host, i)
        row:SetSize((hostW or 520) - 8, rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", host, "TOPLEFT", 4, y)

        local _, link, quality, _, _, _, _, _, _, texture = GetItemInfo(cat.entry)
        row.iconFrame:SetTexture(texture or "Interface\\Icons\\INV_Misc_Gem_Variety_01")
        row.iconFrame:SetQuality(quality or 3)   -- default blue if uncached

        row.label:SetText(PA.CleanGemTierMarker(link or ("item:" .. cat.entry)))
        row.countText:SetText("×" .. (cat.count or 0))

        local isFusableTier = cat.tier and cat.tier >= 1 and cat.tier <= 7
        local hasEnough     = (cat.count or 0) >= 3

        row.btn:SetScript("OnClick", nil)
        row.btn:SetScript("OnEnter", nil)
        row.btn:SetScript("OnLeave", nil)
        -- FIX: Always show the button instead of hiding it for non-fusable tiers
        row.btn:Show()

        if isFusableTier and hasEnough then
            local cost   = FusionCostForTier(cat.tier)
            local entry  = cat.entry
            local tier   = cat.tier
            local family = cat.family
            row.btn:SetText(string.format("Fuse -> T%d", tier + 1))
            row.btn:Enable()
            row.btn:SetScript("OnClick", function() FuseEntry(entry) end)
            row.btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(string.format("Fuse 3x T%d %s -> 1x T%d %s",
                    tier, family or "", tier + 1, family or ""))
                GameTooltip:AddLine("Cost: " .. FormatMoney(cost), 0.78, 0.78, 0.40)
                GameTooltip:AddLine("Astraltree node required: GEM_FUSION_T" .. (tier + 1) .. "_ALLOWED", 0.55, 0.62, 0.85)
                GameTooltip:Show()
            end)
            row.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        elseif isFusableTier and not hasEnough then
            row.btn:SetText("Need 3+")
            row.btn:Disable()
        else
            -- FIX: Show button as disabled with "Max Tier" text instead of hiding
            row.btn:SetText("Max Tier")
            row.btn:Disable()
            row.btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("T8 is the maximum tier — cannot be fused further.")
                GameTooltip:Show()
            end)
            row.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        row:Show()
        y = y - (rowH + rowGap)
    end

    for i = #entries + 1, #host._rowPool do
        host._rowPool[i]:Hide()
    end

    host:SetHeight(math.max(60, -y + 8))
end

GF._RefreshGemList = function()
    if frame and frame.gemListPanel and frame:IsShown() then
        RefreshGemList(frame.gemListPanel)
    end
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    local normalPct = tonumber(GF.info.GEM_NORMAL_CHANCE_PCT or 0) or 0
    frame.t1Box:SetText(string.format("%.2f%%", normalPct))

    if frame.costCards then
        for n = 1, 7 do
            local card = frame.costCards[n]
            if card then
                local key  = string.format("FUSION_COST_T%d_T%d_COPPER", n, n + 1)
                local cost = tonumber(GF.info[key]) or 0
                card:SetText(FormatMoney(cost))
            end
        end
    end

    local function isOn(key) return GF.info[key] == "1" end
    if frame.unlockTier and frame.unlockTier[1] then
        ApplyUnlockFlag(frame.unlockTier[1], isOn("GEM_NORMAL_ALLOWED"))
        for n = 2, 8 do
            if frame.unlockTier[n] then
                ApplyUnlockFlag(frame.unlockTier[n],
                    isOn("GEM_FUSION_T" .. n .. "_ALLOWED"))
            end
        end
    end
end

-- RefreshGemList to fix the read-before-declared crash.

local EVENT_LABEL = {
    [0] = "Hit", [1] = "Cast", [2] = "Heal",
    [3] = "Struck", [4] = "Crit", [5] = "DoT/HoT", [6] = "Any",
}

local TIER_COLOR = {
    [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd",
    [4] = "|cffa335ee", [5] = "|cffff8000", [6] = "|cffe6cc80",
    [7] = "|cffff6080", [8] = "|cffff2020",
}

local browseTier  = 1   -- index into TIER_FILTERS
local browseEvent = 1   -- index into EVENT_FILTERS
local browseName  = ""  -- free-text name filter (lower-cased substring)
local BROWSE_ROWS = 10
local BROWSE_ROW_H = 34

local function MatchesBrowseFilter(catEntry, entry)
    if not catEntry then return false end
    local tf = TIER_FILTERS[browseTier]
    local ef = EVENT_FILTERS[browseEvent]
    if not ((tf and tf.match(catEntry)) and (ef and ef.match(catEntry))) then
        return false
    end
    if browseName ~= "" then
        local rawName = (catEntry.name ~= "" and catEntry.name)
                     or (entry and select(1, GetItemInfo(entry)))
                     or ""
        rawName = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if not rawName:lower():find(browseName, 1, true) then
            return false
        end
    end
    return true
end

local BROWSE_QUALITY_COLOR = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
    [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
    [6] = "|cffe6cc80", [7] = "|cffe6cc80",
}

RefreshBrowsePanel = function()
    if not (browseFrame and browseFrame:IsShown()) then return end

    local rows = {}
    for entry, cat in pairs(GF.catalog) do
        if MatchesBrowseFilter(cat, entry) then
            local name = (cat.name ~= "" and cat.name)
                      or (select(1, GetItemInfo(entry)))
                      or ("Item " .. tostring(entry))
            local icon = (select(10, GetItemInfo(entry))) or "Interface\\Icons\\INV_Misc_QuestionMark"
            rows[#rows+1] = {
                entry   = entry,
                cat     = cat,
                name    = name,
                icon    = icon,
                quality = cat.quality,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.cat.tier   ~= b.cat.tier   then return a.cat.tier < b.cat.tier end
        if a.cat.family ~= b.cat.family then return (a.cat.family or "") < (b.cat.family or "") end
        return (a.name or "") < (b.name or "")
    end)

    browseFrame.countText:SetText(string.format("%d gem%s",
        #rows, #rows == 1 and "" or "s"))

    local offset = FauxScrollFrame_GetOffset(browseFrame.scroll) or 0
    for i = 1, BROWSE_ROWS do
        local row  = browseFrame.rows[i]
        local data = rows[offset + i]
        if data then
            row.iconFrame:SetTexture(data.icon)
            row.iconFrame:SetQuality(data.quality or 1)

            local link = select(2, GetItemInfo(data.entry))
            local coloredName = data.name
            if not link and data.quality
               and BROWSE_QUALITY_COLOR[data.quality] then
                coloredName = BROWSE_QUALITY_COLOR[data.quality]
                           .. data.name .. "|r"
            end
            row.name:SetText(PA.CleanGemTierMarker(link or coloredName))
            row.event:SetText(EVENT_LABEL[data.cat.eventType] or "?")
            row.entry = data.entry
            row:Show()
        else
            row:Hide()
            row.entry = nil
        end
    end
    FauxScrollFrame_Update(browseFrame.scroll, #rows, BROWSE_ROWS, BROWSE_ROW_H)
end

local function InitDropdown(dropdown, list, getCurrentIdx, onChoose)
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local cur = getCurrentIdx()
        for i, item in ipairs(list) do
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = item.label
            info.checked = (i == cur)
            info.func    = function()
                onChoose(i)
                UIDropDownMenu_SetSelectedID(dropdown, i)
                UIDropDownMenu_SetText(dropdown, list[i].label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local cur = getCurrentIdx()
    UIDropDownMenu_SetSelectedID(dropdown, cur)
    UIDropDownMenu_SetText(dropdown, list[cur].label)
end

local function CreateBrowsePanel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 1)

    f.header = PA.UI.MakeHeader(f, "Astral Gem Catalog",
        "Browse every gem by tier, trigger, or name")
    local pill = CreateFrame("Frame", nil, f)
    pill:SetHeight(38)
    pill:SetPoint("TOPLEFT",  f.header, "BOTTOMLEFT",  -6, -10)
    pill:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT",  6, -10)
    PA.UI.AstralBackdrop(pill, { thin = true })
    pill:SetBackdropColor(PA.UI.Color.bgPanel[1], PA.UI.Color.bgPanel[2],
                          PA.UI.Color.bgPanel[3], 0.85)
    pill:SetBackdropBorderColor(PA.UI.Color.borderDim[1], PA.UI.Color.borderDim[2],
                                PA.UI.Color.borderDim[3], 1)

    local tierLbl = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tierLbl:SetPoint("LEFT", pill, "LEFT", 12, 1)
    tierLbl:SetText("Tier")
    tierLbl:SetTextColor(PA.UI.Color.textAccent[1], PA.UI.Color.textAccent[2],
                         PA.UI.Color.textAccent[3])
    local tierDd = CreateFrame("Frame", "PAGemBrowseTierDD", pill, "UIDropDownMenuTemplate")
    tierDd:SetPoint("LEFT", tierLbl, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(tierDd, 96)
    InitDropdown(tierDd, TIER_FILTERS, function() return browseTier end, function(i)
        browseTier = i
        RefreshBrowsePanel()
    end)

    local evtLbl = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    evtLbl:SetPoint("LEFT", tierDd, "RIGHT", -6, 3)
    evtLbl:SetText("Trigger")
    evtLbl:SetTextColor(PA.UI.Color.textAccent[1], PA.UI.Color.textAccent[2],
                        PA.UI.Color.textAccent[3])
    local evtDd = CreateFrame("Frame", "PAGemBrowseEventDD", pill, "UIDropDownMenuTemplate")
    evtDd:SetPoint("LEFT", evtLbl, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(evtDd, 130)
    InitDropdown(evtDd, EVENT_FILTERS, function() return browseEvent end, function(i)
        browseEvent = i
        RefreshBrowsePanel()
    end)

    local searchBox = PA.UI.MakeSearchBox(pill, {
        width       = 190,
        placeholder = "Search by name…",
        onChanged   = function(text)
            browseName = (text or ""):lower()
            if f.scroll then
                FauxScrollFrame_SetOffset(f.scroll, 0)
                if f.scroll:GetName() then
                    local sb = _G[f.scroll:GetName() .. "ScrollBar"]
                    if sb then sb:SetValue(0) end
                end
            end
            RefreshBrowsePanel()
        end,
    })
    searchBox:SetPoint("LEFT", evtDd, "RIGHT", -8, 0)
    searchBox:SetPoint("RIGHT", pill, "RIGHT", -10, 0)
    f.searchBox = searchBox

    local catalogLabel = PA.UI.MakeSectionLabel(f, "Catalog")
    catalogLabel:SetPoint("TOPLEFT",  pill, "BOTTOMLEFT",  4, -6)
    catalogLabel:SetPoint("TOPRIGHT", pill, "BOTTOMRIGHT", -60, -6)

    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.countText:SetPoint("TOPRIGHT", pill, "BOTTOMRIGHT", -4, -4)
    f.countText:SetTextColor(PA.UI.Color.textMuted[1], PA.UI.Color.textMuted[2],
                             PA.UI.Color.textMuted[3])
    local listPanel = CreateFrame("Frame", nil, f)
    listPanel:SetPoint("TOPLEFT",     catalogLabel, "BOTTOMLEFT", -2, -8)
    listPanel:SetPoint("BOTTOMRIGHT", f,            "BOTTOMRIGHT", -20, 24)
    PA.UI.AstralBackdrop(listPanel, { thin = true })
    listPanel:SetBackdropColor(0.010, 0.020, 0.045, 0.85)
    listPanel:SetBackdropBorderColor(PA.UI.Color.borderDim[1], PA.UI.Color.borderDim[2],
                                     PA.UI.Color.borderDim[3], 1)

    local scroll = CreateFrame("ScrollFrame", "PAGemBrowseScroll", listPanel,
                                "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",     4, -4)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -26, 4)
    scroll:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, BROWSE_ROW_H, RefreshBrowsePanel)
    end)
    f.scroll = scroll

    f.rows = {}
    for i = 1, BROWSE_ROWS do
        local row = CreateFrame("Button", nil, listPanel)
        row:SetHeight(BROWSE_ROW_H)
        row:SetPoint("LEFT",  listPanel, "LEFT",  6, 0)
        row:SetPoint("RIGHT", listPanel, "RIGHT", -28, 0)
        if i == 1 then
            row:SetPoint("TOP", listPanel, "TOP", 0, -6)
        else
            row:SetPoint("TOP", f.rows[i-1], "BOTTOM", 0, -2)
        end

        PA.UI.MakeRowChrome(row, { alt = (i % 2 == 0) })

        local iconFrame = PA.UI.MakeIconFrame(row, { size = 28 })
        iconFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.iconFrame = iconFrame

        local eventChip = CreateFrame("Frame", nil, row)
        eventChip:SetSize(64, 20)
        eventChip:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        PA.UI.AstralBackdrop(eventChip, { thin = true })
        eventChip:SetBackdropColor(PA.UI.Color.bgDeep[1], PA.UI.Color.bgDeep[2],
                                   PA.UI.Color.bgDeep[3], 0.85)
        eventChip:SetBackdropBorderColor(PA.UI.Color.borderDim[1], PA.UI.Color.borderDim[2],
                                         PA.UI.Color.borderDim[3], 1)
        local eventText = eventChip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        eventText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        eventText:SetPoint("CENTER", eventChip, "CENTER", 0, 0)
        eventText:SetTextColor(PA.UI.Color.textAccent[1], PA.UI.Color.textAccent[2],
                               PA.UI.Color.textAccent[3])
        eventChip.text = eventText
        row.eventChip = eventChip
        row.event = eventText   -- alias so RefreshBrowsePanel:SetText still works

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        row.name:SetPoint("LEFT",  iconFrame, "RIGHT", 10, 0)
        row.name:SetPoint("RIGHT", eventChip, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")

        row.tier = { SetText = function() end }

        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink("item:" .. self.entry)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:RegisterForClicks("AnyUp")
        row:SetScript("OnClick", function(self)
            -- Shift-click links the gem into the chat box in use (not always General's)
            if self.entry and IsModifiedClick("CHATLINK") and ProjectAstral.InsertChatLink then
                ProjectAstral.InsertChatLink(select(2, GetItemInfo(self.entry)))
            end
        end)

        f.rows[i] = row
    end

    return f
end

local function StartBrowseIconWarmup()
    if not browseFrame then return end
    for entry in pairs(GF.catalog) do
        GetItemInfo(entry)
    end
    browseFrame._warmupLeft = 50   -- 50 * 0.10s = 5s cap
    browseFrame._warmupT    = 0
    browseFrame:SetScript("OnUpdate", function(self, elapsed)
        self._warmupT = (self._warmupT or 0) + elapsed
        if self._warmupT < 0.10 then return end
        self._warmupT = 0
        self._warmupLeft = (self._warmupLeft or 0) - 1
        RefreshBrowsePanel()
        if self._warmupLeft <= 0 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function CreateFusionFrame(embedParent)
    if not GF._stashSubscribed then
        GF._stashSubscribed = true
        SubscribeToStashUpdates()
    end

    local f = CreateFrame("Frame", "PAGemFusionFrame", embedParent or UIParent)
    if embedParent then
        f:SetAllPoints(embedParent)
        f:SetFrameLevel(embedParent:GetFrameLevel() + 1)
    else
        f:SetSize(W, H)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        f:SetFrameStrata("HIGH")
        f:Hide()

        PA.UI.AstralBackdrop(f, { thin = false })
        PA.UI.CosmicCorners(f)
        f:SetBackdropColor(PA.UI.Color.bgDeep[1], PA.UI.Color.bgDeep[2],
                           PA.UI.Color.bgDeep[3], 0.97)
        f:SetBackdropBorderColor(PA.UI.Color.borderMid[1], PA.UI.Color.borderMid[2],
                                 PA.UI.Color.borderMid[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", f, "TOP", 0, -16)
        f.title:SetText("Astral Gem Fusion")
        f.title:SetTextColor(PA.UI.Color.textTitle[1], PA.UI.Color.textTitle[2],
                             PA.UI.Color.textTitle[3])

        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
        sub:SetText("Combine 3x same-family same-tier gems into 1x of the next tier (T1->T8 chain).")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        PA.UI.CosmicCloseButton(closeBtn)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    end

    local W = embedParent and math.max(568, embedParent:GetWidth() or 0) or W
    local Y_SHIFT = embedParent and 70 or 0
    local statY  = -84  + Y_SHIFT
    local costY  = -180 + Y_SHIFT

    local boxW = 120
    local startX = (W - boxW) / 2
    f.t1Box = MakeStatBox(f, "TOPLEFT", startX, statY, "GEM DROP", "T1 chance")

    -- ── Auto Fuse controls (top-left, beside the gem-drop box) ──
    local autoBox = CreateFrame("Frame", nil, f)
    autoBox:SetSize(200, 78)
    autoBox:SetPoint("TOPLEFT", f, "TOPLEFT", 14, statY)
    autoBox:SetBackdrop(PANEL_BACKDROP)
    PA.UI.CosmicCorners(autoBox)
    autoBox:SetBackdropColor(unpack(PANEL_BG_COLOR))
    autoBox:SetBackdropBorderColor(unpack(PANEL_BORDER_COLOR))
    f.autoBox = autoBox

    local autoLbl = autoBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    autoLbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    autoLbl:SetPoint("TOPLEFT", autoBox, "TOPLEFT", 10, -7)
    autoLbl:SetText("AUTO FUSE")

    local autoCheck = CreateFrame("CheckButton", "PAGemAutoFuseCheck", autoBox,
        "InterfaceOptionsCheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", autoBox, "TOPLEFT", 6, -18)
    _G[autoCheck:GetName() .. "Text"]:SetText("Enabled")
    autoCheck.tooltipText = "Automatically fuse 3 of the same gem from your Gem Stash into the next tier, "
        .. "lowest tiers first, up to the tier chosen below. Each fusion costs gold; "
        .. "pauses in combat or when gold runs short."
    autoCheck:SetChecked(AutoSettings())
    autoCheck:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if PA.SaveSetting then PA.SaveSetting("autoFuse", on) end
        if on then
            wipe(auto.blocked)
            auto.noGold = false
            local _, maxTier = AutoSettings()
            FlashStatus("Auto Fuse on: fusing up to T" .. maxTier .. ".", "|cff80e090")
            GF.KickAutoFuse()
        else
            FlashStatus("Auto Fuse off.", "|cffffcc66")
        end
    end)
    f.autoCheck = autoCheck

    local upToLbl = autoBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    upToLbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    upToLbl:SetPoint("TOPLEFT", autoBox, "TOPLEFT", 12, -52)
    upToLbl:SetText("Fuse up to")

    local autoDd = CreateFrame("Frame", "PAGemAutoFuseTierDD", autoBox, "UIDropDownMenuTemplate")
    autoDd:SetPoint("LEFT", upToLbl, "RIGHT", -10, -3)
    UIDropDownMenu_SetWidth(autoDd, 60)
    InitDropdown(autoDd, AUTO_TIERS,
        function() local _, maxTier = AutoSettings(); return maxTier - 1 end,   -- AUTO_TIERS[1] = T2
        function(i)
            if PA.SaveSetting then PA.SaveSetting("autoFuseMaxTier", AUTO_TIERS[i].tier) end
            wipe(auto.blocked)
            if AutoSettings() then
                FlashStatus("Auto Fuse: fusing up to T" .. AUTO_TIERS[i].tier .. ".", "|cff80e090")
            end
            GF.KickAutoFuse()
        end)
    f.autoTierDd = autoDd

    local costRowY = costY
    local cardCount = 7
    local cardGap   = 4
    local sideMargin = 14
    local innerW   = W - 2 * sideMargin
    local cardW    = math.floor((innerW - cardGap * (cardCount - 1)) / cardCount)
    local cardH    = 62

    f.fusionCostHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.fusionCostHeader:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    f.fusionCostHeader:SetPoint("TOP", f, "TOP", 0, costRowY + 16)
    f.fusionCostHeader:SetText("Fusion Cost")
    f.fusionCostHeader:SetTextColor(0.65, 0.78, 1.00)

    f.costCards = {}
    for n = 1, cardCount do
        local x = sideMargin + (n - 1) * (cardW + cardGap)
        local header = string.format("T%d->T%d", n, n + 1)
        f.costCards[n] = MakeCostCard(f, x, costRowY, cardW, cardH, header)
    end
    local unlockY = costRowY - cardH - 18
    f.unlockBox = CreateFrame("Frame", nil, f)
    f.unlockBox:SetSize(W - 30, 36)
    f.unlockBox:SetPoint("TOPLEFT", f, "TOPLEFT", 15, unlockY)
    f.unlockBox:SetBackdrop(PANEL_BACKDROP)
    PA.UI.CosmicCorners(f.unlockBox)
    f.unlockBox:SetBackdropColor(unpack(PANEL_BG_COLOR))
    f.unlockBox:SetBackdropBorderColor(unpack(PANEL_BORDER_COLOR))

    local tiersLbl = f.unlockBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tiersLbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    tiersLbl:SetPoint("TOPLEFT", f.unlockBox, "TOPLEFT", 14, -10)
    tiersLbl:SetText("Tiers:")
    tiersLbl:SetTextColor(0.65, 0.78, 1.00)

    f.unlockTier = {}
    local tierStep = (f.unlockBox:GetWidth() - 100) / 7
    for n = 1, 8 do
        local lbl = f.unlockBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        lbl:SetWidth(34)
        lbl:SetJustifyH("CENTER")
        lbl:SetPoint("CENTER", f.unlockBox, "LEFT", 80 + (n - 1) * tierStep, 0)
        lbl:SetText("T" .. n)
        f.unlockTier[n] = lbl
    end
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    f.status:SetPoint("TOP", f.unlockBox, "BOTTOM", 0, -10)
    f.status:Hide()
    -- ── Filter bar (Row 1: above the list, clearly visible) ──
    local fusePill = CreateFrame("Frame", nil, f)
    fusePill:SetHeight(34)
    fusePill:SetPoint("TOPLEFT",  f.unlockBox, "BOTTOMLEFT",   4, -38)
    fusePill:SetPoint("TOPRIGHT", f.unlockBox, "BOTTOMRIGHT", -60, -38)
    -- FIX: Give filter bar a brighter, distinct background so it doesn't blend
    -- into the dark panel backdrop. Uses a lighter purple-tinted color.
    PA.UI.AstralBackdrop(fusePill, { thin = true })
    fusePill:SetBackdropColor(0.06, 0.04, 0.12, 0.95)
    fusePill:SetBackdropBorderColor(0.45, 0.32, 0.72, 0.9)
    -- FIX: Raise frame level so the filter bar renders ABOVE the panel backdrop
    fusePill:SetFrameLevel(f:GetFrameLevel() + 10)

    local fuseTierLbl = fusePill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fuseTierLbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fuseTierLbl:SetPoint("LEFT", fusePill, "LEFT", 10, 1)
    fuseTierLbl:SetText("Tier")
    fuseTierLbl:SetTextColor(PA.UI.Color.textAccent[1], PA.UI.Color.textAccent[2],
                             PA.UI.Color.textAccent[3])
    local fuseTierDd = CreateFrame("Frame", "PAGemFusionTierDD", fusePill, "UIDropDownMenuTemplate")
    fuseTierDd:SetPoint("LEFT", fuseTierLbl, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(fuseTierDd, 80)
    InitDropdown(fuseTierDd, TIER_FILTERS, function() return fuseTier end, function(i)
        fuseTier = i
        if GF._RefreshGemList then GF._RefreshGemList() end
    end)

    local fuseEvtLbl = fusePill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fuseEvtLbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fuseEvtLbl:SetPoint("LEFT", fuseTierDd, "RIGHT", -6, 3)
    fuseEvtLbl:SetText("Trigger")
    fuseEvtLbl:SetTextColor(PA.UI.Color.textAccent[1], PA.UI.Color.textAccent[2],
                            PA.UI.Color.textAccent[3])
    local fuseEvtDd = CreateFrame("Frame", "PAGemFusionEvtDD", fusePill, "UIDropDownMenuTemplate")
    fuseEvtDd:SetPoint("LEFT", fuseEvtLbl, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(fuseEvtDd, 120)
    InitDropdown(fuseEvtDd, EVENT_FILTERS, function() return fuseEvent end, function(i)
        fuseEvent = i
        if GF._RefreshGemList then GF._RefreshGemList() end
    end)

    -- FIX: "Ready to fuse" checkbox — placed in its own highlighted chip so
    -- the checkmark is clearly visible and not hidden by any backdrop.
    local readyChip = CreateFrame("Frame", nil, fusePill)
    readyChip:SetSize(140, 26)
    readyChip:SetPoint("LEFT", fuseEvtDd, "RIGHT", 4, 0)
    PA.UI.AstralBackdrop(readyChip, { thin = true })
    readyChip:SetBackdropColor(0.10, 0.06, 0.18, 0.95)
    readyChip:SetBackdropBorderColor(0.50, 0.35, 0.80, 0.9)
    readyChip:SetFrameLevel(fusePill:GetFrameLevel() + 2)

    f.fuseReadyCheck = CreateFrame("CheckButton", "PAGemFusionReadyOnly", readyChip,
        "InterfaceOptionsCheckButtonTemplate")
    f.fuseReadyCheck:SetSize(24, 24)
    f.fuseReadyCheck:SetPoint("LEFT", readyChip, "LEFT", 6, 0)
    local readyLabel = _G[f.fuseReadyCheck:GetName() .. "Text"]
    readyLabel:SetText("Ready")
    readyLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    readyLabel:SetTextColor(0.85, 0.85, 1.0)
    f.fuseReadyCheck:SetChecked(fuseReadyOnly)
    f.fuseReadyCheck:SetScript("OnClick", function(self)
        fuseReadyOnly = self:GetChecked() and true or false
        if GF._RefreshGemList then GF._RefreshGemList() end
    end)

    f.fuseSearchBox = PA.UI.MakeSearchBox(fusePill, {
        width       = 160,
        height      = 24,
        placeholder = "Search…",
        onChanged   = function(text)
            fuseName = (text or ""):lower()
            if GF._RefreshGemList then GF._RefreshGemList() end
        end,
    })
    f.fuseSearchBox.edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    f.fuseSearchBox:SetPoint("LEFT", readyChip, "RIGHT", 8, 0)
    f.fuseSearchBox:SetPoint("RIGHT", fusePill, "RIGHT", -8, 0)

    -- ── Section label + gem list panel (below the filter bar) ──
    f.listHeader = PA.UI.MakeSectionLabel(f, "Your Gems")
    f.listHeader.label:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    f.listHeader:SetPoint("TOPLEFT",  fusePill, "BOTTOMLEFT",  0, -8)
    f.listHeader:SetPoint("TOPRIGHT", fusePill, "BOTTOMRIGHT", 0, -8)

    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT",     f.listHeader, "BOTTOMLEFT",  -4, -6)
    panel:SetPoint("BOTTOMRIGHT", f,            "BOTTOMRIGHT", -14, 14)
    PA.UI.AstralBackdrop(panel, { thin = true })
    panel:SetBackdropColor(0.008, 0.012, 0.026, 0.92)
    panel:SetBackdropBorderColor(unpack(PANEL_BORDER_COLOR))

    panel.scroll = CreateFrame("ScrollFrame", "PAGemFusionListScroll", panel,
                               "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT",     panel, "TOPLEFT",     4, -4)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)

    panel.child = CreateFrame("Frame", nil, panel.scroll)
    panel.child:SetSize(panel.scroll:GetWidth() > 0 and panel.scroll:GetWidth() or 520, 100)
    panel.scroll:SetScrollChild(panel.child)

    f.gemListPanel = panel

    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t > 0.5 then
            self._t = 0
            if GF.statusUntil and time() >= GF.statusUntil and self.status:IsShown() then
                self.status:Hide()
            end
        end
        self._pollT = (self._pollT or 0) + elapsed
        if self._pollT >= 0.5 then
            self._pollT = 0
            if PA.GemStash and PA.GemStash.RequestState then
                PA.GemStash.RequestState()
            end
        end
    end)

    f:SetScript("OnShow", function()
        GF.RequestInfo()
        Refresh()
    end)

    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:HookScript("OnEvent", function(self, event)
        if event == "BAG_UPDATE_DELAYED" and self:IsShown() then
            ScanBags()
            RefreshGemList(self.gemListPanel)
            Refresh()
        end
    end)

    frame = f
end

local function BuildGemFusionTab(panel)
    if not frame then CreateFusionFrame(panel) end
    panel:SetScript("OnShow", function()
        GF.RequestInfo()
        ScanBags()
        if frame and frame.gemListPanel then
            RefreshGemList(frame.gemListPanel)
        end
        Refresh()
    end)
end

local function BuildGemCatalogTab(panel)
    browseFrame = CreateBrowsePanel(panel)
    panel:SetScript("OnShow", function()
        GF.RequestInfo()
        RefreshBrowsePanel()
        StartBrowseIconWarmup()
    end)
end

local function ToggleFrame()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "GemFusion" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("GemFusion")
        if mf._tabBar then mf._tabBar:SelectTab("GemFusion") end
    end
end

local function ToggleCatalog()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    mf:Show()
    mf:SwitchTab("GemCatalog")
    if mf._tabBar then mf._tabBar:SelectTab("GemCatalog") end
end

GF._refresh_hooks = {
    ScanBags       = ScanBags,
    RefreshGemList = RefreshGemList,
    Refresh        = Refresh,
}

local infoEvt = CreateFrame("Frame")
infoEvt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
infoEvt:SetScript("OnEvent", function()
    if browseFrame and browseFrame:IsShown() then RefreshBrowsePanel() end
    if GF._refresh_hooks and GF._refresh_hooks.RefreshGemList then
        pcall(GF._refresh_hooks.RefreshGemList)
    end
end)

PA:RegisterModule("GemFusion", "Gem Fusion", ToggleFrame, {
    subtitle = "Combine 3× same-family same-tier gems into 1× of the next tier.",
})
PA:RegisterTabContent("GemFusion", BuildGemFusionTab)
PA:RegisterModule("GemCatalog", "Gem Catalog", ToggleCatalog, {
    subtitle = "Browse gems by tier, trigger, and name.",
})
PA:RegisterTabContent("GemCatalog", BuildGemCatalogTab)

do
    local mods = PA.modules
    if type(mods) == "table" and #mods > 0 then
        local gIdx, anchorIdx
        for i, m in ipairs(mods) do
            if m.name == "GemFusion" then gIdx = i end
            if m.name == "AstralGems" or m.name == "gems" or m.name == "astralgems" then
                anchorIdx = i
            end
        end
        if gIdx and anchorIdx and gIdx ~= anchorIdx + 1 then
            local entry = table.remove(mods, gIdx)
            local insertAt = anchorIdx + (gIdx < anchorIdx and 0 or 1)
            table.insert(mods, insertAt, entry)
        end
    end
end

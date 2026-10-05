--[[
    TipOff — информация о применении предметов в тултипе,
    автопродажа хлама, авторемонт, автоквесты (Quests.lua) и окно настроек (Options.lua).
    Клиент: WoW 3.3.5a (Interface 30300).
]]

local L = LibStub("AceLocale-3.0"):GetLocale("TipOff")

TipOff = LibStub("AceAddon-3.0"):NewAddon("TipOff", "AceConsole-3.0")
local TipOff = TipOff

local DB_ITEMS, SPELL_ICONS, PROF_ICONS

-- Квесты, которые скрывает опция "бесполезные квесты" (репутация Картеля Хитрой Шестерёнки)
local USELESS_QUESTS = { [9268] = true, [9267] = true, [9259] = true, [9266] = true }

local HEADER_R, HEADER_G, HEADER_B = 0.31, 0.52, 0.83
local QUEST_HEADER = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. L["TOOLTIP_QUEST_OBJECTIVE"]
local ICON_LEARNED = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local MONEY_ICONS = {
    "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

---------------------------------------------------------------------------
-- Утилиты
---------------------------------------------------------------------------

-- Мини-таймер (C_Timer в 3.3.5 нет)
local timerFrame = CreateFrame("Frame")
local timers = {}
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    for i = #timers, 1, -1 do
        local t = timers[i]
        t.left = t.left - elapsed
        if t.left <= 0 then
            table.remove(timers, i)
            t.fn()
        end
    end
    if #timers == 0 then self:Hide() end
end)
local function After(delay, fn)
    timers[#timers + 1] = { left = delay, fn = fn }
    timerFrame:Show()
end
TipOff.After = After

local function Icon(texture)
    if not texture or texture == "" then return "" end
    if not texture:find("\\") then texture = "Interface\\Icons\\" .. texture end
    return "|T" .. texture .. ":0|t"
end

local function FormatMoney(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%d%s %d%s %d%s", g, MONEY_ICONS[1], s, MONEY_ICONS[2], c, MONEY_ICONS[3])
end

local function Msg(text, isError)
    DEFAULT_CHAT_FRAME:AddMessage((isError and "|cffff3333" or "|cff228B22") .. text .. "|r")
end
TipOff.Msg = Msg

-- Перевод названия из локали (локаль "тихая": если перевода нет — английское название)
local function T(name)
    if not name or name == "" then return L["TOOLTIP_UNKNOWN"] end
    return L[name]
end

local function ProfKey(profName)
    return "PROF_" .. string.upper((profName:gsub("%s+", "")))
end

-- Имя и иконка заклинания рецепта: из клиента (уже на языке клиента), иначе из базы
local spellCache = {}
local function SpellNameIcon(entry)
    local id = entry[1]
    if id and id > 0 then
        local c = spellCache[id]
        if not c then
            local name, _, icon = GetSpellInfo(id)
            c = { name = name, icon = SPELL_ICONS and SPELL_ICONS[id] or icon }
            spellCache[id] = c
        end
        if c.name then return c.name, c.icon end
    end
    return T(entry[3]), nil
end

---------------------------------------------------------------------------
-- Клавиши
---------------------------------------------------------------------------
local KEY_CHECK = {
    SHIFT = IsShiftKeyDown,
    CTRL = IsControlKeyDown,
    ALT = IsAltKeyDown,
    ALWAYS = function() return true end,
}
-- Клавиша, которая раскрывает полный список (не совпадает с клавишей показа)
function TipOff:GetExpandKey()
    return self.db.profile.tooltipKey == "SHIFT" and "ALT" or "SHIFT"
end

---------------------------------------------------------------------------
-- Профессии игрока: [локализованное имя] = уровень навыка
---------------------------------------------------------------------------
local playerSkills

local function RefreshPlayerSkills()
    playerSkills = {}
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if name and not isHeader then playerSkills[name] = rank or 0 end
    end
end

local function PlayerSkillRank(profName) -- profName английский из базы
    if not playerSkills then RefreshPlayerSkills() end
    return playerSkills[L[ProfKey(profName)]] or playerSkills[profName]
end

---------------------------------------------------------------------------
-- Изученные рецепты (сохраняются для каждого персонажа при открытии окна профессии)
---------------------------------------------------------------------------
local function ScanTradeSkill()
    if IsTradeSkillLinked and IsTradeSkillLinked() then return end -- чужая профессия по ссылке
    local learned = TipOff.db.char.learned
    local names = TipOff.db.char.learnedNames
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" then
            names[name] = true
            local link = GetTradeSkillRecipeLink(i)
            local id = link and tonumber(link:match("enchant:(%d+)"))
            if id then learned[id] = true end
        end
    end
end

local function IsRecipeLearned(entry, localizedName)
    local char = TipOff.db.char
    return (entry[1] and char.learned[entry[1]]) or (localizedName and char.learnedNames[localizedName]) or false
end

function TipOff:CountLearned()
    local n = 0
    for _ in pairs(self.db.char.learned) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Выполненные квесты (в 3.3.5 нет IsQuestFlaggedCompleted)
---------------------------------------------------------------------------
local completedQuests = {}
local questQueryPending = false

local function RequestCompletedQuests()
    if QueryQuestsCompleted and not questQueryPending then
        questQueryPending = true
        QueryQuestsCompleted()
        -- если сервер не ответил, разрешаем повторный запрос позже
        After(30, function() questQueryPending = false end)
    end
end

local function IsQuestCompleted(questId)
    if not questId then return false end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(questId) and true or false end
    return completedQuests[questId] and true or false
end

---------------------------------------------------------------------------
-- Тултип
---------------------------------------------------------------------------
local function SortByName(a, b) return a.name < b.name end
-- По уровню; рецепты с неизвестным уровнем ("?") — в конец
local function SortByLevel(a, b)
    local la = a.level > 0 and a.level or 100000
    local lb = b.level > 0 and b.level or 100000
    if la == lb then return a.name < b.name end
    return la < lb
end

local function GetQuestColor(level)
    if not level or level <= 0 then return "ffffffff" end
    local c = GetQuestDifficultyColor(level)
    return string.format("ff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

local function StartBlock(state, tooltip, header)
    if state.blocks > 0 then tooltip:AddLine(" ") end
    state.blocks = state.blocks + 1
    tooltip:AddLine(header, HEADER_R, HEADER_G, HEADER_B)
end

-- Строка "…ещё N (Alt — все)"
local function AddMoreLine(state, tooltip, hidden)
    tooltip:AddLine(string.format(L["TOOLTIP_MORE"], hidden, L["KEY_" .. state.expandKey]), 0.6, 0.6, 0.6)
end

-- Список с ограничением длины
local function Limit(state, count)
    local max = TipOff.db.profile.maxLines or 0
    if state.full or max <= 0 or count <= max then return count end
    return max
end

local function RenderRecipes(state, tooltip, header, data)
    if not data then return end
    local profile = TipOff.db.profile
    local profs = {}
    for profName, recipes in pairs(data) do
        local rank = PlayerSkillRank(profName)
        if not profile.filterProfs or rank then
            profs[#profs + 1] = { name = L[ProfKey(profName)], key = profName, recipes = recipes, rank = rank }
        end
    end
    if #profs == 0 then return end
    table.sort(profs, SortByName)

    StartBlock(state, tooltip, header)
    for _, prof in ipairs(profs) do
        local profTitle = Icon(PROF_ICONS and PROF_ICONS[prof.key]) .. " " .. prof.name
        if prof.rank then profTitle = profTitle .. string.format(" |cff888888(%d)|r", prof.rank) end
        tooltip:AddLine(profTitle, HEADER_R, HEADER_G, HEADER_B)

        local rows = {}
        for i, r in ipairs(prof.recipes) do
            local name, icon = SpellNameIcon(r)
            rows[i] = { entry = r, name = name, icon = icon, level = r[2] or 0 }
        end
        table.sort(rows, SortByLevel)

        local shown = Limit(state, #rows)
        for i = 1, shown do
            local row = rows[i]
            local levelText = row.level > 0 and row.level or "?"
            local color, mark = "ffffffff", ""
            if profile.markLearned and prof.rank then
                if IsRecipeLearned(row.entry, row.name) then
                    mark = " " .. ICON_LEARNED
                    color = "ff80ff80"
                elseif row.level > prof.rank then
                    color = "ffff5050" -- не хватает навыка
                end
            end
            tooltip:AddLine(string.format("[%s]%s[|c%s%s|r]%s", levelText, Icon(row.icon), color, row.name, mark))
        end
        if shown < #rows then AddMoreLine(state, tooltip, #rows - shown) end
    end
end

local function RenderSpells(state, tooltip, data)
    if not data then return end
    local _, playerClass = UnitClass("player")
    local classes = {}
    for class, spells in pairs(data) do
        if not TipOff.db.profile.filterClass or class == playerClass then
            classes[#classes + 1] = { key = class, spells = spells,
                name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class }
        end
    end
    if #classes == 0 then return end
    table.sort(classes, SortByName)

    StartBlock(state, tooltip, L["TOOLTIP_SPELLS"])
    for _, cls in ipairs(classes) do
        local color = RAID_CLASS_COLORS[cls.key]
        if color then tooltip:AddLine(cls.name, color.r, color.g, color.b) else tooltip:AddLine(cls.name) end
        local rows = {}
        for i, s in ipairs(cls.spells) do
            local name, icon = SpellNameIcon(s)
            rows[i] = { name = name, icon = icon, level = s[2] or 0 }
        end
        table.sort(rows, SortByLevel)
        local shown = Limit(state, #rows)
        for i = 1, shown do
            local s = rows[i]
            tooltip:AddLine(string.format("[%s]%s[|cffffffff%s|r]", s.level > 0 and s.level or "?", Icon(s.icon), s.name))
        end
        if shown < #rows then AddMoreLine(state, tooltip, #rows - shown) end
    end
end

local SIDE_TAG = { A = "|cff3399ff[A]|r", H = "|cffff3333[H]|r", N = "|cffaaaaaa[N]|r" }
local FACTION_SIDE = { Alliance = "A", Horde = "H" }

local function RenderQuests(state, tooltip, quests)
    if not quests or #quests == 0 then return end
    local profile = TipOff.db.profile
    local mySide = FACTION_SIDE[UnitFactionGroup("player") or ""]

    -- Квест: {id, название, уровень, треб. уровень, фракция A/H/B}.
    -- Одноимённые квесты одного уровня (обычно версии для Альянса и Орды) объединяем.
    local groups, order = {}, {}
    for _, q in ipairs(quests) do
        local id, name, level, req, side = q[1], q[2], q[3] or 0, q[4] or 0, q[5] or "B"
        local skip = profile.filterUselessQuests and USELESS_QUESTS[id]
        if not skip and profile.filterFaction and mySide and side ~= "B" and side ~= mySide then skip = true end
        if not skip then
            local key = name .. "\0" .. level
            local g = groups[key]
            if not g then
                g = { name = name, level = level, req = req, sides = {}, ids = {} }
                groups[key] = g
                order[#order + 1] = g
            end
            g.sides[side] = true
            g.ids[#g.ids + 1] = id
            if req > 0 and (g.req == 0 or req < g.req) then g.req = req end
        end
    end
    if #order == 0 then return end

    table.sort(order, function(a, b)
        local la = a.req > 0 and a.req or a.level
        local lb = b.req > 0 and b.req or b.level
        if la == lb then return a.name < b.name end
        return la < lb
    end)

    StartBlock(state, tooltip, QUEST_HEADER)
    local shown = Limit(state, #order)
    for i = 1, shown do
        local g = order[i]
        local tag
        if g.sides.B then tag = SIDE_TAG.N
        elseif g.sides.A and g.sides.H then tag = SIDE_TAG.A .. SIDE_TAG.H
        else tag = g.sides.A and SIDE_TAG.A or SIDE_TAG.H end

        local level = g.level > 0 and g.level or g.req
        local line = tag .. " |c" .. GetQuestColor(level) ..
            string.format(L["TOOLTIP_QUEST_LEVEL"], level > 0 and level or "?") .. " " .. T(g.name) .. "|r"
        for _, id in ipairs(g.ids) do
            if IsQuestCompleted(id) then
                line = line .. " " .. ICON_LEARNED
                break
            end
        end
        if g.level > 0 and g.req > 0 and g.req ~= g.level then
            line = line .. " " .. string.format(L["TOOLTIP_QUEST_REQ_LVL"], g.req)
        end
        tooltip:AddLine(line)
    end
    if shown < #order then AddMoreLine(state, tooltip, #order - shown) end
end

local markers
-- Уже добавляли строки в этот тултип? (у рецептов OnTooltipSetItem срабатывает дважды)
local function AlreadyAdded(tooltip)
    local name = tooltip:GetName()
    if not name then return false end
    markers = markers or {
        [L["TOOLTIP_JUNK"]] = true, [L["TOOLTIP_KEPT"]] = true, [L["TOOLTIP_CREATED_BY"]] = true,
        [L["TOOLTIP_USED_IN"]] = true, [L["TOOLTIP_SPELLS"]] = true, [QUEST_HEADER] = true,
    }
    for i = 2, tooltip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        local text = line and line:GetText()
        if text and markers[text] then return true end
    end
    return false
end

function TipOff:SetItemTooltip(tooltip)
    if AlreadyAdded(tooltip) then return end
    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end
    local itemId = tonumber(itemLink:match("item:(%d+)"))
    if not itemId then return end
    local profile = self.db.profile

    local _, _, itemRarity, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemLink)
    if itemRarity == 0 and sellPrice and sellPrice > 0 then
        if profile.keepItems[itemId] then
            tooltip:AddLine(L["TOOLTIP_KEPT"], 0.6, 0.6, 0.6)
        else
            tooltip:AddLine(L["TOOLTIP_JUNK"], 0.13, 0.55, 0.13)
        end
    end

    -- Ссылка из чата показывается всегда и целиком; обычный тултип — по выбранной клавише
    local isRef = tooltip == ItemRefTooltip
    local showCheck = KEY_CHECK[profile.tooltipKey] or IsShiftKeyDown
    if not isRef and not showCheck() then return end

    local itemData = DB_ITEMS and DB_ITEMS[itemId]
    if not itemData then return end

    local expandKey = self:GetExpandKey()
    local state = { blocks = 0, expandKey = expandKey, full = isRef or (KEY_CHECK[expandKey] or IsAltKeyDown)() }
    RenderRecipes(state, tooltip, L["TOOLTIP_CREATED_BY"], itemData.created_by)
    RenderRecipes(state, tooltip, L["TOOLTIP_USED_IN"], itemData.used_in)
    RenderSpells(state, tooltip, itemData.spells)
    RenderQuests(state, tooltip, itemData.quests)

    if state.blocks > 0 then tooltip:Show() end
end

---------------------------------------------------------------------------
-- Белый список автопродажи
---------------------------------------------------------------------------
function TipOff:ToggleKeepItem(link)
    link = link and tostring(link)
    local id = link and tonumber(link:match("item:(%d+)") or link:match("^%s*(%d+)%s*$"))
    if not id then
        Msg(L["MSG_BAD_ITEM"], true)
        return
    end
    if not link:find("item:") then link = select(2, GetItemInfo(id)) or ("item:" .. id) end
    local keep = self.db.profile.keepItems
    if keep[id] then
        keep[id] = nil
        Msg(string.format(L["MSG_KEEP_REMOVED"], link))
    else
        keep[id] = link
        Msg(string.format(L["MSG_KEEP_ADDED"], link))
    end
    if self.UpdateOptions then self:UpdateOptions() end
end

-- Alt + правый клик по предмету в сумке — добавить в исключения / убрать
hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
    if button == "RightButton" and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
        TipOff:ToggleKeepItem(GetContainerItemLink(self:GetParent():GetID(), self:GetID()))
    end
end)

---------------------------------------------------------------------------
-- Торговец: авторемонт и автопродажа
---------------------------------------------------------------------------
local merchantOpen = false
local SELL_PER_TICK = 6

local sellFrame = CreateFrame("Frame")
sellFrame:Hide()
local sellQueue, sellTotal, sellPos = {}, 0, 1

sellFrame:SetScript("OnUpdate", function(self)
    if not merchantOpen then self:Hide() return end
    local sold = 0
    while sellPos <= #sellQueue and sold < SELL_PER_TICK do
        local e = sellQueue[sellPos]
        sellPos = sellPos + 1
        if GetContainerItemLink(e.bag, e.slot) == e.link then
            local _, _, locked = GetContainerItemInfo(e.bag, e.slot)
            if not locked then
                UseContainerItem(e.bag, e.slot)
                sellTotal = sellTotal + e.price
                sold = sold + 1
            end
        end
    end
    if sellPos > #sellQueue then
        self:Hide()
        if sellTotal > 0 then Msg(string.format(L["MSG_SOLD"], FormatMoney(sellTotal))) end
    end
end)

local function SellGrayItems()
    wipe(sellQueue)
    sellTotal, sellPos = 0, 1
    local keep = TipOff.db.profile.keepItems
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id and not keep[id] then
                local _, _, rarity, _, _, _, _, _, _, _, price = GetItemInfo(link)
                if rarity == 0 and price and price > 0 then
                    local _, count = GetContainerItemInfo(bag, slot)
                    sellQueue[#sellQueue + 1] = { bag = bag, slot = slot, link = link, price = price * (count or 1) }
                end
            end
        end
    end
    if #sellQueue > 0 then sellFrame:Show() end
end

local function RepairSelf(cost)
    if GetMoney() >= cost then
        RepairAllItems()
        Msg(string.format(L["MSG_REPAIRED_SELF"], FormatMoney(cost)))
    else
        Msg(L["MSG_REPAIR_NO_MONEY"], true)
    end
end

local function AutoRepair()
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost <= 0 then return end

    if TipOff.db.profile.guildRepair and IsInGuild() and CanGuildBankRepair() then
        local withdraw = GetGuildBankWithdrawMoney() -- лимит снятия игрока, -1 = без лимита
        if withdraw == -1 or withdraw >= cost then
            -- На некоторых серверах для ремонта за счёт гильдии нужна такая же сумма у игрока
            if GetMoney() >= cost then
                RepairAllItems(1)
                After(1, function()
                    if not merchantOpen then return end
                    local left, stillCan = GetRepairAllCost()
                    if stillCan and left > 0 then
                        Msg(L["MSG_REPAIR_GUILD_FAILED"], true)
                        RepairSelf(left)
                    else
                        Msg(string.format(L["MSG_REPAIRED_GUILD"], FormatMoney(cost)))
                    end
                end)
                return
            else
                Msg(L["MSG_REPAIR_GUILD_NEEDS_OWN"], true)
            end
        end
    end
    RepairSelf(cost)
end

---------------------------------------------------------------------------
-- События
---------------------------------------------------------------------------
local REFRESH_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

local eventFrame = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD",
    "QUEST_QUERY_COMPLETE", "MODIFIER_STATE_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE" }) do
    eventFrame:RegisterEvent(e)
end
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "MERCHANT_SHOW" then
        merchantOpen = true
        local profile = TipOff.db.profile
        if profile.autoRepair then AutoRepair() end -- сначала ремонт, потом продажа
        if profile.autoSellGray then SellGrayItems() end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
    elseif event == "SKILL_LINES_CHANGED" then
        playerSkills = nil
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        ScanTradeSkill()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        After(5, RequestCompletedQuests)
    elseif event == "QUEST_QUERY_COMPLETE" then
        questQueryPending = false
        wipe(completedQuests)
        GetQuestsCompleted(completedQuests)
    elseif event == "MODIFIER_STATE_CHANGED" then
        -- Перерисовать тултип при нажатии/отпускании модификатора
        if REFRESH_KEYS[arg1] and GameTooltip:IsShown() and GameTooltip:GetItem() then
            local owner = GameTooltip:GetOwner()
            local onEnter = owner and owner.GetScript and owner:GetScript("OnEnter")
            if onEnter then onEnter(owner) end
        end
    end
end)

hooksecurefunc("GetQuestReward", function() After(2, RequestCompletedQuests) end)

---------------------------------------------------------------------------
-- Инициализация и команды
---------------------------------------------------------------------------
local OPTIONS = {
    { "sell",    "autoSellGray",        "OPT_SELL" },
    { "repair",  "autoRepair",          "OPT_REPAIR" },
    { "profs",   "filterProfs",         "OPT_PROFS" },
    { "learned", "markLearned",         "OPT_LEARNED" },
    { "quests",  "filterUselessQuests", "OPT_QUESTS" },
    { "faction", "filterFaction",       "OPT_FACTION" },
    { "class",   "filterClass",         "OPT_CLASS" },
    { "accept",  "autoAcceptQuests",    "OPT_AUTO_ACCEPT" },
    { "turnin",  "autoTurnInQuests",    "OPT_AUTO_TURNIN" },
    { "trivial", "skipTrivialQuests",   "OPT_SKIP_TRIVIAL" },
}
TipOff.OPTIONS = OPTIONS
local LEGACY = {
    autosellon = { "autoSellGray", true }, autoselloff = { "autoSellGray", false },
    autorepairon = { "autoRepair", true }, autorepairoff = { "autoRepair", false },
}

function TipOff:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("TipOffDB", {
        profile = {
            tooltipKey = "SHIFT",
            maxLines = 10,
            filterProfs = false,
            markLearned = true,
            filterUselessQuests = true,
            filterFaction = false,
            filterClass = true,
            autoSellGray = false,
            autoRepair = false,
            guildRepair = true,
            keepItems = {},
            autoAcceptQuests = false,
            autoTurnInQuests = false,
            skipTrivialQuests = false,
            skipQuests = {},
            minimap = { hide = false, angle = 200 },
        },
        char = {
            learned = {},
            learnedNames = {},
        },
    }, true)

    DB_ITEMS = TipOff_LoadedDB
    SPELL_ICONS = TipOff_SpellIcons
    PROF_ICONS = TipOff_Icons

    local function hook(tooltip) TipOff:SetItemTooltip(tooltip) end
    GameTooltip:HookScript("OnTooltipSetItem", hook)
    ItemRefTooltip:HookScript("OnTooltipSetItem", hook)

    self:RegisterChatCommand("tipoff", "ChatCommandHandler")
    self:Print(L["MSG_LOADED"])
end

local function State(v) return v and L["STATE_ON"] or L["STATE_OFF"] end

function TipOff:ChatCommandHandler(input)
    input = strtrim(input or "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local profile = self.db.profile

    local legacy = LEGACY[cmd]
    if legacy then
        profile[legacy[1]] = legacy[2]
        for _, o in ipairs(OPTIONS) do
            if o[2] == legacy[1] then self:Printf(L["MSG_TOGGLED"], L[o[3]], State(legacy[2])) end
        end
        return
    end

    for _, o in ipairs(OPTIONS) do
        if cmd == o[1] then
            profile[o[2]] = not profile[o[2]]
            self:Printf(L["MSG_TOGGLED"], L[o[3]], State(profile[o[2]]))
            if self.UpdateOptions then self:UpdateOptions() end
            return
        end
    end

    if cmd == "keep" and rest ~= "" then
        self:ToggleKeepItem(rest)
        return
    end

    if cmd == "" or cmd == "config" or cmd == "options" then
        if self.ToggleOptions then self:ToggleOptions() end
        return
    end

    if cmd == "help" or cmd == "?" or cmd == "помощь" or cmd == "status" then
        self:Print(L["MSG_HELP_HEADER"])
        self:Print(L["MSG_HELP_CONFIG"])
        for _, o in ipairs(OPTIONS) do
            self:Printf(L["MSG_HELP_LINE"], o[1], L[o[3]], State(profile[o[2]]))
        end
        self:Print(L["MSG_HELP_KEEP"])
        return
    end
    self:Print(L["MSG_UNKNOWN_COMMAND"])
end

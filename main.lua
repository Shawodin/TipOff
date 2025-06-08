--[[
    Данный файл реализует основной функционал аддона TipOff:
    - Добавляет информацию о применении предметов в тултип.
    - Использует AceAddon, AceDB, AceHook, AceConsole, AceLocale.
    - Вся логика работы с базой предметов и отображения информации в тултипах.
    - Все slash-команды и их обработчики убраны по требованию.
]]

local AddonName = ...;
-- В начале main.lua
_MissingLocaleKeys = _MissingLocaleKeys or {}

-- Загружаем накопленные ключи из SavedVariables (если есть)
if type(TipOffDB_MissingLocaleKeys) == "table" then
    for _, k in ipairs(TipOffDB_MissingLocaleKeys) do
        _MissingLocaleKeys[k] = true
    end
end

-- Безопасная локализация: L["..."] всегда возвращает строку
local rawL = LibStub("AceLocale-3.0"):GetLocale("TipOff")
local L = setmetatable({}, {
    __index = function(t, k)
        if not rawL[k] then
            _MissingLocaleKeys[k] = true
        end
        return rawL[k] or tostring(k)
    end
})

-- Создаём основной объект аддона TipOff
TipOff = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceHook-3.0", "AceConsole-3.0");
-- Console = LibStub("AceConsole-3.0"); -- Временно закомментировано
-- Config = LibStub("AceConfig-3.0"); -- Временно закомментировано
-- ConfigDialog = LibStub("AceConfigDialog-3.0"); -- Временно закомментировано

-- ItemDB используется AceDB для настроек, и для Icons.lua.
ItemDB = ItemDB or {};
-- ItemDB.Items = ItemDB.Items or {}; -- Больше не используется для основной базы предметов

local steamwheedleRepQuests = {9268, 9267, 9259, 9266}; -- Оставляем на случай, если понадобится для фильтрации квестов

-- Инициализация аддона
function TipOff:OnInitialize()
    -- Создаём SavedVariables для настроек
    self.db = LibStub("AceDB-3.0"):New("TipOffDB", {
        profile = {
            filterProfs = false,
            filterUselessQuests = true,
            autoSellGray = false,
            autoRepair = false
        }
    }, true);
    
    -- Хук на тултип предмета
    GameTooltip:HookScript("OnTooltipSetItem", function(...) TipOff:SetItemTooltip(...) end)
    ItemRefTooltip:HookScript("OnTooltipSetItem", function(...) TipOff:SetItemTooltip(...) end)

    -- Удалена регистрация команд и обработчик команд
    -- self:RegisterChatCommand("itemfor", "ChatCommandHandler")
    print("|cff00ff00TipOff загружен|r");
    
    TipOff.recipeIconMap = nil -- Инициализируем карту иконок рецептов
    self:RegisterChatCommand("tipoff", "ChatCommandHandler")
end

-- Удалён обработчик ChatCommandHandler и все связанные с ним сообщения

local function GetIcon(name)
    if not name then return "" end;
    return "|TInterface\\Icons\\" .. name .. ":0|t";
end

local function IsQuestCompleted(questId)
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(questId)
    end
    -- Если вы хотите видеть предупреждение в чате, когда функция не найдена, раскомментируйте следующую строку:
    -- print("TipOff Warning: API function IsQuestFlaggedCompleted not found. Quest completion status might be inaccurate.")
    return false -- Возвращаем false по умолчанию, если функция недоступна
end

local function PlayerProfessions()
    local skills = {};
    for i = 1, GetNumSkillLines() do
        local name, _, _, skillRank = GetSkillLineInfo(i) -- name здесь локализовано
        -- ВНИМАНИЕ: ItemDB.Icons["Professions"][name] может не работать, если ключи в ItemDB.Icons английские,
        -- а 'name' здесь локализовано. Нужно убедиться, что ключи в ItemDB.Icons соответствуют языку клиента
        -- или также использовать механизм локализации/сопоставления для них.
        if (ItemDB.Icons and ItemDB.Icons["Professions"] and ItemDB.Icons["Professions"][name]) then
            skills[name] = skillRank;
        end
    end
    return skills;
end

local function PlayerHasProfession(profNameFromDB) -- profNameFromDB английское из базы, например "Alchemy", "First Aid"
    local key = "PROF_" .. string.upper(profNameFromDB:gsub("%s+", ""))
    local targetLocalizedProfName = L[key] or profNameFromDB -- Получаем локализованное имя для сравнения

    for i = 1, GetNumSkillLines() do
        local skillName, _, _, skillRank = GetSkillLineInfo(i) -- skillName уже локализовано клиентом
        if skillName == targetLocalizedProfName then
            return true
        end
    end
    return false;
end

-- Импорт вспомогательных функций как локальных
local function DumpTable(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. DumpTable(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

local function ArrayContains(table, val)
   for i=1, #table do
      if table[i] == val then
         return true
      end
   end
   return false
end

local function CountTableElements(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- Функция для безопасного получения перевода с логированием отсутствующих ключей
local function SafeL(key)
    local val = L[key]
    if not val then
        return tostring(key)
    end
    return val
end

-- Функция для заполнения карты иконок рецептов (имя -> файл иконки)
function TipOff:EnsureRecipeIconMap()
  if (not TipOff.recipeIconMap or next(TipOff.recipeIconMap) == nil) and TipOff_LoadedDB then
    TipOff.recipeIconMap = {}
    for _, itemData in pairs(TipOff_LoadedDB) do
        if itemData.name and itemData.icon then
            TipOff.recipeIconMap[itemData.name] = itemData.icon
        end
    end
    -- DEFAULT_CHAT_FRAME:AddMessage("[TipOff] Recipe Icon Map populated: " .. CountTableElements(TipOff.recipeIconMap) .. " entries.")
  end
end

function TipOff:SetItemTooltip(tooltip, ...)
    local _, itemLink = tooltip:GetItem();
    if (not itemLink) then return end;
    local itemId = tonumber(string.match(itemLink, "item:(%d+)") ) or 0;
    if (itemId == 0) then return end;

    -- Добавляем надпись для серых предметов (качество 0)
    local itemName, _, itemRarity = GetItemInfo(itemLink)
    if itemRarity == 0 then
        tooltip:AddLine("|cff228B22Хлам – можно продать!|r")
    end

    if (not TipOff_LoadedDB) then 
        return 
    end;

    TipOff:EnsureRecipeIconMap() -- Убедимся, что карта иконок рецептов заполнена

    local recipeIconCache = {} 

    -- Принудительно показываем расширенный тултип для ItemRefTooltip (чата)
    local forceShowFull = false
    if tooltip == ItemRefTooltip then
        forceShowFull = true
    end

    if IsShiftKeyDown() or forceShowFull then
        local itemsAdded = 0;
        local questsAdded = 0;
        local itemData = TipOff_LoadedDB[itemId];
        if not itemData then 
            return 
        end;
        local displayItemName = SafeL(itemData.name or "")
        local isFirstAddonBlockBeingRendered = true

        -- СЕКЦИЯ 1: ИНФОРМАЦИЯ О ТОМ, КАК СОЗДАЁТСЯ ПРЕДМЕТ
        if itemData.created_by and next(itemData.created_by) then
            local sectionHeaderPrinted = false
            local sortedProfessions = {}
            for profName, recipes in pairs(itemData.created_by) do
                if type(profName) == "string" and not profName:match("^%d+$") then
                    table.insert(sortedProfessions, {name=profName, data=recipes})
                end
            end
            table.sort(sortedProfessions, function(a,b) return a.name < b.name end)
            for _, profEntry in ipairs(sortedProfessions) do
                local profName = profEntry.name -- This is the English name from DB, e.g., "Alchemy", "First Aid"
                local recipes = profEntry.data
                if profName ~= "None" then
                    if (not TipOff.db.profile.filterProfs or PlayerHasProfession(profName)) then -- PlayerHasProfession needs to handle this
                        if not sectionHeaderPrinted then
                            if isFirstAddonBlockBeingRendered then isFirstAddonBlockBeingRendered = false else tooltip:AddLine("\n") end
                            tooltip:AddLine(L["TOOLTIP_CREATED_BY"], 0.31, 0.52, 0.83)
                            sectionHeaderPrinted = true
                        end
                        local profIcon = GetIcon(ItemDB.Icons and ItemDB.Icons["Professions"] and ItemDB.Icons["Professions"][profName] or "")
                        local localizedProfName = L["PROF_" .. string.upper(profName:gsub("%s+", ""))] or profName
                        tooltip:AddLine(profIcon .. " " .. localizedProfName, 0.31, 0.52, 0.83)
                        local sortedRecipes = {}
                        for _, recipe in ipairs(recipes) do table.insert(sortedRecipes, recipe) end
                        table.sort(sortedRecipes, function(a,b) return (a.level or 0) < (b.level or 0) end)
                        for _, recipe in ipairs(sortedRecipes) do
                            if recipe.name and recipe.level and recipe.level > 0 then
                                local displayRecipeName = SafeL(recipe.name)
                                local coloredDisplayRecipeName = "|cffffffff" .. displayRecipeName .. "|r" -- Окрашиваем в белый
                                local iconKey = recipe.name 
                                local iconFilename = ""
                                if TipOff.recipeIconMap and TipOff.recipeIconMap[iconKey] then
                                    iconFilename = TipOff.recipeIconMap[iconKey]
                                end
                                local iconString = ""
                                if iconFilename ~= "" then
                                    iconString = GetIcon(iconFilename) 
                                end
                                local recipeText = string.format("[%s]%s[%s]", recipe.level, iconString, coloredDisplayRecipeName)
                                tooltip:AddLine(recipeText)
                                itemsAdded = itemsAdded + 1;
                            end
                        end
                    end
                end
            end
        end
        -- СЕКЦИЯ 2: ИНФОРМАЦИЯ О ТОМ, ГДЕ ИСПОЛЬЗУЕТСЯ ПРЕДМЕТ
        if itemData.used_in and next(itemData.used_in) then
            local sectionHeaderPrinted = false
            local sortedProfessions = {}
            for profName, recipes in pairs(itemData.used_in) do
                if type(profName) == "string" and not profName:match("^%d+$") then
                    table.insert(sortedProfessions, {name=profName, data=recipes})
                end
            end
            table.sort(sortedProfessions, function(a,b) return a.name < b.name end)
            for _, profEntry in ipairs(sortedProfessions) do
                local profName = profEntry.name -- This is the English name from DB
                local recipes = profEntry.data
                if profName ~= "None" then
                    if (not TipOff.db.profile.filterProfs or PlayerHasProfession(profName)) then -- PlayerHasProfession needs to handle this
                        if not sectionHeaderPrinted then
                            if isFirstAddonBlockBeingRendered then 
                                isFirstAddonBlockBeingRendered = false
                            end
                            tooltip:AddLine(L["TOOLTIP_USED_IN"], 0.31, 0.52, 0.83)
                            sectionHeaderPrinted = true
                        end
                        local profIcon = GetIcon(ItemDB.Icons and ItemDB.Icons["Professions"] and ItemDB.Icons["Professions"][profName] or "")
                        local localizedProfName = L["PROF_" .. string.upper(profName:gsub("%s+", ""))] or profName
                        tooltip:AddLine(profIcon .. " " .. localizedProfName, 0.31, 0.52, 0.83)
                        local sortedRecipes = {}
                        for _, recipe in ipairs(recipes) do table.insert(sortedRecipes, recipe) end
                        table.sort(sortedRecipes, function(a,b) return (a.level or 0) < (b.level or 0) end)
                        for _, recipe in ipairs(sortedRecipes) do
                            if recipe.name and recipe.level and recipe.level > 0 then 
                                local displayRecipeName = SafeL(recipe.name)
                                local coloredDisplayRecipeName = "|cffffffff" .. displayRecipeName .. "|r" -- Окрашиваем в белый
                                local iconKey = recipe.name 
                                local iconFilename = ""
                                if TipOff.recipeIconMap and TipOff.recipeIconMap[iconKey] then
                                    iconFilename = TipOff.recipeIconMap[iconKey]
                                end
                                local iconString = ""
                                if iconFilename ~= "" then
                                    iconString = GetIcon(iconFilename) 
                                end
                                local recipeText = string.format("[%s]%s[%s]", recipe.level, iconString, coloredDisplayRecipeName)
                                tooltip:AddLine(recipeText)
                                itemsAdded = itemsAdded + 1;
                            end
                        end
                    end
                end
            end
        end
        -- СЕКЦИЯ 3: КВЕСТЫ, СВЯЗАННЫЕ С ПРЕДМЕТОМ
        if itemData.quests and #itemData.quests > 0 then
            local playerFaction = UnitFactionGroup("player"):lower();
            local questsToDisplayFinally = {}
            local potentialQuests = {}
            for _, questInfo in ipairs(itemData.quests) do
                local canShowQuest = true;
                if (canShowQuest and TipOff.db.profile.filterUselessQuests and questInfo.id and ArrayContains(steamwheedleRepQuests, questInfo.id)) then
                    canShowQuest = false;
                end
                if canShowQuest then
                    table.insert(potentialQuests, questInfo)
                end
            end
            table.sort(potentialQuests, function(a,b) 
                local aSortLevel = a.reqlevel or a.level or 0
                local bSortLevel = b.reqlevel or b.level or 0
                if aSortLevel == bSortLevel then return (a.name or "") < (b.name or "") end
                return aSortLevel < bSortLevel 
            end)
            local questCache = {};
            local playerLevel = UnitLevel("player")
            local function GetQuestDifficultyColor(questLevel)
                if not questLevel or questLevel == 0 then return "ffffffff" end
                local levelDiff = questLevel - playerLevel
                if levelDiff >= 5 then
                    return "ffff0000"
                elseif levelDiff >= 3 then
                    return "ffff8000"
                elseif levelDiff >= -2 then
                    return "ffffd100"
                elseif questLevel > playerLevel - GetQuestGreenRange() then
                    return "ff00ff00"
                else
                    return "ff808080"
                end
            end
            for _, questInfo in ipairs(potentialQuests) do
                local questTitle = SafeL(questInfo.name) or L["TOOLTIP_UNKNOWN_ITEM"];
                if not questCache[questTitle] then 
                    local displayLevel = questInfo.level;
                    local reqLevelText = "";
                    if (displayLevel == 0 or displayLevel == nil) and questInfo.reqlevel then
                        displayLevel = questInfo.reqlevel;
                    elseif questInfo.reqlevel and questInfo.reqlevel ~= displayLevel and displayLevel ~= nil then
                        reqLevelText = string.format(" (%s: %s)", L["TOOLTIP_QUEST_REQ_LVL_SHORT"], questInfo.reqlevel)
                    end
                    if displayLevel and displayLevel ~= 0 then
                        displayLevel = displayLevel or "?"
                        if displayLevel ~= "?" then
                            local color = GetQuestDifficultyColor(tonumber(displayLevel))
                            local factionPrefix = "[N] "
                            if questInfo.side == "Alliance" then
                                factionPrefix = "|cff3399ff[A]|r "
                            elseif questInfo.side == "Horde" then
                                factionPrefix = "|cffff3333[H]|r "
                            end
                            local levelAndTitlePart = string.format(L["TOOLTIP_PROFESSION_LEVEL"], displayLevel) .. " " .. questTitle
                            local questLine = factionPrefix .. "|c" .. color .. levelAndTitlePart .. "|r"
                            if IsQuestCompleted(questInfo.id) then 
                                questLine = questLine .. " |cff00ff00[V]|r"
                            end
                            questLine = questLine .. reqLevelText
                            table.insert(questsToDisplayFinally, questLine);
                            questsAdded = questsAdded + 1;
                            questCache[questTitle] = true; 
                        end
                    end
                end
            end
            if #questsToDisplayFinally > 0 then
                if isFirstAddonBlockBeingRendered then 
                    isFirstAddonBlockBeingRendered = false
                end
                tooltip:AddLine("|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. L["TOOLTIP_QUEST_OBJECTIVE"], 0.31, 0.52, 0.83)
                for _, questLineText in ipairs(questsToDisplayFinally) do
                    tooltip:AddLine(questLineText);
                end
            end
        end
        if itemsAdded == 0 and questsAdded == 0 and isFirstAddonBlockBeingRendered and itemData then
             -- tooltip:AddLine("\n") 
             -- tooltip:AddLine(L["TOOLTIP_NO_INFORMATION"])
        end
        if (itemsAdded > 0 or questsAdded > 0) then
            tooltip:Show();
        end
    end
end

-- Автопродажа серого хлама и авторемонт
local function SellGrayItems()
    local total = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local _, _, itemRarity, _, _, _, _, _, _, _, itemSellPrice = GetItemInfo(itemLink)
                local _, itemCount = GetContainerItemInfo(bag, slot)
                if itemRarity == 0 and itemSellPrice and itemSellPrice > 0 then
                    UseContainerItem(bag, slot)
                    total = total + (itemSellPrice * (itemCount or 1))
                end
            end
        end
    end
    if total > 0 then
        local gold = math.floor(total / 10000)
        local silver = math.floor((total % 10000) / 100)
        local copper = total % 100
        local msg = string.format("|cff228B22Хлам продан на: %d|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t|r", gold, silver, copper)
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

local function AutoRepair()
    if not TipOff or not TipOff.db or not TipOff.db.profile or not TipOff.db.profile.autoRepair then
        return
    end
    if CanMerchantRepair() then
        local cost, canRepair = GetRepairAllCost()
        if canRepair and cost > 0 then
            local playerMoney = GetMoney()
            local repaired = false
            local repairedByGuild = false
            if IsInGuild() and CanGuildBankRepair() then
                local guildMoney = GetGuildBankWithdrawMoney()
                -- Для ремонта за счёт гильдии нужно, чтобы хватало и в гильдбанке, и у игрока
                if (guildMoney == -1 or guildMoney >= cost) then
                    if playerMoney >= cost then
                        RepairAllItems(true)
                        repaired = true
                        repairedByGuild = true
                    else
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333Для ремонта за счёт гильдии также требуется достаточно личных средств!|r")
                    end
                end
            end
            if not repaired then
                if playerMoney >= cost then
                    RepairAllItems()
                    repaired = true
                    repairedByGuild = false
                end
            end
            if repaired then
                local gold = math.floor(cost / 10000)
                local silver = math.floor((cost % 10000) / 100)
                local copper = cost % 100
                local who = repairedByGuild and "за счёт гильдии" or "за свой счёт"
                local msg = string.format("|cff228B22Экипировка отремонтирована %s на: %d|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t|r", who, gold, silver, copper)
                DEFAULT_CHAT_FRAME:AddMessage(msg)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff3333Денег на авто-ремонт не хватает!|r")
            end
        end
    end
end

local autoSellFrame = CreateFrame("Frame")
autoSellFrame:RegisterEvent("MERCHANT_SHOW")
autoSellFrame:SetScript("OnEvent", function(self, event)
    if TipOff and TipOff.db and TipOff.db.profile then
        if TipOff.db.profile.autoSellGray then
            SellGrayItems()
        end
        AutoRepair()
    end
end)

-- Slash-команды
function TipOff:ChatCommandHandler(input)
    input = input and input:lower() or ""
    if input == "autosellon" then
        self.db.profile.autoSellGray = true
        self:Print("Автопродажа серого хлама: |cff00ff00ВКЛЮЧЕНА|r")
    elseif input == "autoselloff" then
        self.db.profile.autoSellGray = false
        self:Print("Автопродажа серого хлама: |cffff0000ВЫКЛЮЧЕНА|r")
    elseif input == "autorepairon" then
        self.db.profile.autoRepair = true
        self:Print("Авторемонт экипировки: |cff00ff00ВКЛЮЧЕН|r")
    elseif input == "autorepairoff" then
        self.db.profile.autoRepair = false
        self:Print("Авторемонт экипировки: |cffff0000ВЫКЛЮЧЕН|r")
    elseif input == "help" or input == "?" or input == "помощь" then
        self:Print("/TipOff AutoSellOn  - включить автопродажу серого хлама")
        self:Print("/TipOff AutoSellOff - выключить автопродажу серого хлама")
        self:Print("/TipOff AutoRepairOn  - включить авторемонт экипировки")
        self:Print("/TipOff AutoRepairOff - выключить авторемонт экипировки")
    elseif input == "dumpmissing" then
        self:DumpMissingLocaleKeys()
    else
        self:Print("Используйте /TipOff help для списка команд.")
    end
end

function TipOff:DumpMissingLocaleKeys()
    local out = {}
    for k in pairs(_MissingLocaleKeys) do
        table.insert(out, k)
    end
    table.sort(out)
    -- Выводим в чат (по частям, если много)
    for i, key in ipairs(out) do
        print(string.format('L["%s"] = ""', key))
    end
    -- Сохраняем объединённый список в SavedVariables
    TipOffDB_MissingLocaleKeys = out
end

--[[
    Вспомогательные функции для аддона TipOff.
    - Глубокое копирование таблиц
    - Проверка наличия значения в массиве
    - Функция дампа таблицы (для отладки)
]]

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

local function DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[DeepCopy(orig_key)] = DeepCopy(orig_value)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- никаких методов TipOff и хуков здесь быть не должно
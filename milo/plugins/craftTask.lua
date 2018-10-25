local Craft  = require('turtle.craft')
local itemDB = require('itemDB')
local Milo   = require('milo')
local Util   = require('util')

local context = Milo:getContext()

local craftTask = {
  name = 'crafting',
  priority = 70,
}

-- Craft
function craftTask:craftItem(recipe, originalItem, count)
  local missing = { }
  local toCraft = Craft.getCraftableAmount(recipe, count, Milo:listItems(), missing)
  if missing.name then
    originalItem.status = string.format('%s missing', itemDB:getName(missing.name))
    originalItem.statusCode = Milo.STATUS_WARNING
  end

  local crafted = 0

  if toCraft > 0 then
    crafted = Craft.craftRecipe(recipe, toCraft, context.inventoryAdapter, originalItem)
    Milo:clearGrid()
  end

  return crafted
end

-- Craft as much as possible regardless if all ingredients are available
function craftTask:forceCraftItem(inRecipe, originalItem, inCount)
  local summed = { }
  local items = Milo:listItems()
  local throttle = Util.throttle()

  local function sumItems(recipe, count)
    count = math.ceil(count / recipe.count)
    local craftable = count

    for key,iqty in pairs(Craft.sumIngredients(recipe)) do
      throttle()
      local item = itemDB:splitKey(key)
      local summedItem = summed[key]
      if not summedItem then
        summedItem = Util.shallowCopy(item)
        summedItem.recipe = Craft.findRecipe(item)
        summedItem.count = Craft.getItemCount(items, key)
        summedItem.need = 0
        summedItem.used = 0
        summedItem.craftable = 0
        summed[key] = summedItem
      end

      local total = count * iqty                           -- 4 * 2
      local used = math.min(summedItem.count, total)       -- 5
      local need = total - used                            -- 3

      if recipe.craftingTools and recipe.craftingTools[key] then
        if summedItem.count > 0 then
          summedItem.used = 1
          summedItem.need = 0
          need = 0
        elseif not summedItem.recipe then
          summedItem.need = 1
          need = 1
        else
          need = 1
        end
      else
        summedItem.count = summedItem.count - used
        summedItem.used = summedItem.used + used
      end

      if need > 0 then
        if not summedItem.recipe then
          craftable = math.min(craftable, math.floor(used / iqty))
          summedItem.need = summedItem.need + need
        else
          local c = sumItems(summedItem.recipe, need) -- 4
          craftable = math.min(craftable, math.floor((used + c) / iqty))
          summedItem.craftable = summedItem.craftable + c
        end
      end
    end
    if craftable > 0 then
      craftable = Craft.craftRecipe(recipe, craftable * recipe.count,
        context.inventoryAdapter, originalItem) / recipe.count
      Milo:clearGrid()
    end

    return craftable * recipe.count
  end

  return sumItems(inRecipe, inCount)
end

function craftTask:craft(recipe, item)
  item.status = nil
  item.statusCode = nil
  item.crafted = 0

  if Milo:isCraftingPaused() then
    return
  end

  -- todo: is this needed ?
  if not Milo:clearGrid() then
    item.status = 'Grid obstructed'
    item.statusCode = Milo.STATUS_ERROR
    return
  end

  if item.forceCrafting then
    item.crafted = self:forceCraftItem(recipe, item, item.count)
  else
    item.crafted = self:craftItem(recipe, item, item.count)
  end
end

function craftTask:cycle()
  for _,key in pairs(Util.keys(context.craftingQueue)) do
    local item = context.craftingQueue[key]
    if item.count > 0 then
      local recipe = Craft.recipes[key]
      if recipe then
        self:craft(recipe, item)
        if item.eject and item.crafted >= item.requested then
          Milo:eject(item, item.requested)
        end
      elseif not context.controllerAdapter then
        item.status = '(no recipe)'
        item.statusCode = Milo.STATUS_ERROR
        item.crafted = 0
      end
    end
  end
end

Milo:registerTask(craftTask)
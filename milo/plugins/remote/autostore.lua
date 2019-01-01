local itemDB = require('itemDB')
local Event  = require('event')
local UI     = require('ui')
local Util   = require('util')

local args   = { ... }
local colors = _G.colors
local device = _G.device
local ni     = device.neuralInterface

local context = args[1]

local page = UI.Page {
	titleBar = UI.TitleBar {
		backgroundColor = colors.gray,
		title = 'Auto send items to storage',
		previousPage = true,
	},
	tabs = UI.Tabs {
		y = 2,
		inventory = UI.Window {
			tabTitle = 'Inventory',
			grid = UI.Grid {
				y = 2, ey = -2,
				columns = {
					{ heading = 'Name', key = 'displayName' },
				},
				sortColumn = 'displayName',
			},
		},
		autostore = UI.Window {
			tabTitle = 'Sending',
			grid = UI.Grid {
				y = 2, ey = -2,
				columns = {
					{ heading = 'Name', key = 'displayName' },
				},
				sortColumn = 'displayName',
			},
		},
	},
}

function page.tabs.inventory:enable()
	local inv = ni.getInventory().list()
	local list = { }

	for k, item in pairs(inv) do
		local key = itemDB:makeKey(item)
		if not list[key] then
			local cItem = itemDB:get(item)
			if not cItem then
				cItem = itemDB:add(ni.getInventory().getItemMeta(k))
			end
			if cItem then
				cItem = Util.shallowCopy(cItem)
				cItem.key = key
				list[key] = cItem
			end
		end
	end
	self.grid:setValues(list)
	itemDB:flush()

	return UI.Window.enable(self)
end

function page.tabs.inventory.grid:getRowTextColor(row)
	if context.state.autostore[row.key] then
		return colors.yellow
	end
	return UI.Grid.getRowTextColor(self, row)
end

function page.tabs.autostore:enable()
	local list = { }

	for key in pairs(context.state.autostore or { }) do
		local cItem = itemDB:get(key)
		if cItem then
			table.insert(list, cItem)
		end
	end
	self.grid:setValues(list)

	return UI.Window.enable(self)
end

function page.tabs.inventory:eventHandler(event)
	if event.type == 'grid_select' then
		local autostore = context.state.autostore or { }
		if autostore[event.selected.key] then
			autostore[event.selected.key] = nil
		else
			autostore[event.selected.key] = true
		end
		context:setState('autostore', autostore)
		self.grid:draw()
		return true
	end
end

function page.tabs.autostore:eventHandler(event)
	if event.type == 'grid_select' then
		local key = itemDB:makeKey(event.selected)
		context.state.autostore[key] = nil
		context:setState('autostore', context.state.autostore)
		Util.removeByValue(self.grid.values, event.selected)
		self.grid:update()
		self.grid:draw()
		return true
	end
end

Event.onInterval(5, function()
	if context.state.deposit and (context.state.useShield or context.state.slot) then
		local inv = ni.getInventory().list()
		local slot = context.state.slot
		local target = 'inventory'
		local empty = not inv[slot]

		if context.state.useShield then
			slot = 2
			target = 'equipment'
			empty = not ni.getEquipment().list()[slot]
		end

		if empty then
			for k,v in pairs(inv) do
				local key = itemDB:makeKey(v)
				if context.state.autostore[key] then
					ni.getInventory().pushItems(target, k, v.count, slot)
					break
				end
			end
		end
	end
end)

return {
	menuItem = 'Autostore',
	callback = function()
		UI:setPage(page)
	end,
}
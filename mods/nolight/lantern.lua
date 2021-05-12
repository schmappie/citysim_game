-- default/furnace.lua

-- support for MT game translation.
local S = default.get_translator

--
-- Formspecs
--

local function get_lantern_active_formspec(fuel_percent, item_percent)
	return "size[8,8.5]"..
		"list[context;fuel;2.75,2.5;1,1;]"..
		"image[2.75,1.5;1,1;default_furnace_fire_bg.png^[lowpart:"..
		(fuel_percent)..":default_furnace_fire_fg.png]"..
		"list[current_player;main;0,4.25;8,1;]"..
		"list[current_player;main;0,5.5;8,3;8]"..
		"listring[context;fuel]"..
		"listring[current_player;main]"..
		default.get_hotbar_bg(0, 4.25)
end

local function get_lantern_inactive_formspec()
	return "size[8,8.5]"..
		"list[context;fuel;2.75,2.5;1,1;]"..
		"image[2.75,1.5;1,1;default_furnace_fire_bg.png]"..
		"list[current_player;main;0,4.25;8,1;]"..
		"list[current_player;main;0,5.5;8,3;8]"..
		"listring[context;fuel]"..
		"listring[current_player;main]"..
		default.get_hotbar_bg(0, 4.25)
end

--
-- Node callback functions that are the same for active and inactive furnace
--

local function can_dig(pos, player)
	local meta = minetest.get_meta(pos);
	local inv = meta:get_inventory()
	return inv:is_empty("fuel")
end

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	if listname == "fuel" then
		if minetest.get_craft_result({method="fuel", width=1, items={stack}}).time ~= 0 then
			if inv:is_empty("src") then
				meta:set_string("infotext", S("lantern is empty"))
			end
			return stack:get_count()
		else
			return 0
		end
	end
end

local function allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	return allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	return stack:get_count()
end

local function swap_node(pos, name)
	local node = minetest.get_node(pos)
	if node.name == name then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
end

local function lantern_node_timer(pos, elapsed)
	--
	-- Initialize metadata
	--
	local meta = minetest.get_meta(pos)
	local fuel_time = meta:get_float("fuel_time") or 0
	local fuel_totaltime = meta:get_float("fuel_totaltime") or 0

	local inv = meta:get_inventory()
	local fuellist

	local fuel

	local update = true
	while elapsed > 0 and update do
		update = false
		fuellist = inv:get_list("fuel")
		local el = math.min(elapsed, fuel_totaltime - fuel_time)
		if fuel_time < fuel_totaltime then
			-- The furnace is currently active and has enough fuel
			fuel_time = fuel_time + el
		else
			local afterfuel
			fuel, afterfuel = minetest.get_craft_result({method = "fuel", width = 1, items = fuellist})
			fuel.time = fuel.time*10
			if fuel.time == 0 then
				-- No valid fuel in fuel list
				fuel_totaltime = 0
				fuel_time = 0
			else
				-- Take fuel from fuel list
				inv:set_stack("fuel", 1, afterfuel.items[1])
				-- Put replacements in dst list or drop them on the furnace.
				local replacements = fuel.replacements
				if replacements[1] then
					local above = vector.new(pos.x, pos.y + 1, pos.z)
					local drop_pos = minetest.find_node_near(above, 1, {"air"}) or above
					minetest.item_drop(replacements[1], nil, drop_pos)
				end
				update = true
				fuel_totaltime = fuel.time + (fuel_totaltime - fuel_time)
				fuel_time = 0
			end
		end
		elapsed = elapsed - el
	end

	if fuel and fuel_totaltime > fuel.time then
		fuel_totaltime = fuel.time
	end

	--
	-- Update formspec, infotext and node
	--
	local formspec
	local item_state

	local fuel_state = S("Empty")
	local active = false
	local result = false

	if fuel_totaltime ~= 0 then
		active = true
		local fuel_percent = 100 - math.floor(fuel_time / fuel_totaltime * 100)
		fuel_state = S("@1%", fuel_percent)
		formspec = get_lantern_active_formspec(fuel_percent, 0)
		swap_node(pos, "nolight:lantern_active")
		-- make sure timer restarts automatically
		result = true
	else
		if fuellist and not fuellist[1]:is_empty() then
			fuel_state = S("@1%", 0)
		end
		formspec = get_lantern_inactive_formspec()
		swap_node(pos, "nolight:lantern")
		-- stop timer on the inactive furnace
		minetest.get_node_timer(pos):stop()
	end


	local infotext
	if active then
		infotext = S("lantern active")
	else
		infotext = S("lantern inactive")
	end
	infotext = infotext .. "\n" .. S("(Fuel: @1)", fuel_state)

	--
	-- Set meta values
	--
	meta:set_float("fuel_totaltime", fuel_totaltime)
	meta:set_float("fuel_time", fuel_time)
	meta:set_string("formspec", formspec)
	meta:set_string("infotext", infotext)

	return result
end

--
-- Node definitions
--

minetest.register_node("nolight:lantern", {
	description = S("Lantern"),
	drawtype = "plantlike",
	inventory_image = "xdecor_lantern_inv.png",
	wield_image = "xdecor_lantern_inv.png",
	paramtype2 = "wallmounted",
	walkable = true,
	groups = {cracky=2, attached_node=1},
	tiles = {{name = "xdecor_lantern.png", animation = {type="vertical_frames", length=0}}},
	selection_box = xdecor.pixelbox(16, {{4, 0, 4, 8, 16, 8}}),
	legacy_facedir_simple = true,
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),

	can_dig = can_dig,

	on_timer = lantern_node_timer,

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size('fuel', 1)
		lantern_node_timer(pos, 0)
	end,

	on_metadata_inventory_move = function(pos)
		minetest.get_node_timer(pos):start(1.0)
	end,
	on_metadata_inventory_put = function(pos)
		-- start timer function, it will sort out whether furnace can burn or not.
		minetest.get_node_timer(pos):start(1.0)
	end,
	on_blast = function(pos)
		local drops = {}
		default.get_inventory_drops(pos, "fuel", drops)
		drops[#drops+1] = "nolight:lantern"
		minetest.remove_node(pos)
		return drops
	end,
	
	--[[after_place_node = function(pos, placer, itemstack, pointed_thing)
		local meta = itemstack:get_meta()
		local nodemeta = minetest.get_meta(pos)
		nodemeta:set_float("fuel_time", meta:get_float("fuel_time"))
		nodemeta:set_float("fuel_totaltime", meta:get_float("fuel_totaltime"))
		local inv = nodemeta:get_inventory()
		inv:set_stack('fuel', 1, meta:get_string("stack"))
		lantern_node_timer(pos, 0)
		minetest.get_node_timer(pos):start(1.0)
	end,--]]

	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
})

minetest.register_alias_force("xdecor:lantern","nolight:lantern")

minetest.register_node("nolight:lantern_active", {
	description = S("Lantern"),
	light_source = 13,
	drawtype = "plantlike",
	inventory_image = "xdecor_lantern_inv.png",
	wield_image = "xdecor_lantern_inv.png",
	paramtype2 = "wallmounted",
	walkable = true,
	groups = {cracky=2, attached_node=1, not_in_creative_inventory = 1},
	tiles = {{name = "xdecor_lantern.png", animation = {type="vertical_frames", length=1.5}}},
	selection_box = xdecor.pixelbox(16, {{4, 0, 4, 8, 16, 8}}),
	legacy_facedir_simple = true,
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	on_timer = lantern_node_timer,
	--drop = "nolight:lantern",
	stack_max = 1,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size('fuel', 1)
	end,
	--[[on_dig = function(pos, node, digger)
		local nodemeta = minetest.get_meta(pos)
		minetest.chat_send_all(dump(nodemeta:to_table()))
	end,--]]
	--can_dig = can_dig,
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		local meta = itemstack:get_meta()
		local nodemeta = minetest.get_meta(pos)
		nodemeta:set_float("fuel_time", meta:get_float("fuel_time"))
		nodemeta:set_float("fuel_totaltime", meta:get_float("fuel_totaltime"))
		local inv = nodemeta:get_inventory()
		inv:set_stack('fuel', 1, meta:get_string("stack"))
		minetest.get_node_timer(pos):start(0)
	end,

	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
})

local wieldtimer = 0
minetest.register_globalstep(function(dtime)
	wieldtimer = wieldtimer + dtime
	if wieldtimer > 1 then
		wieldtimer = 0
		for i,player in ipairs(minetest.get_connected_players()) do
			local wielded_item = player:get_wielded_item()
			if wielded_item:get_name() == "nolight:lantern_active" then
				beamlight.beams[player:get_player_name()] = {player = player}
				local meta = wielded_item:get_meta()
				local fuel_time = meta:get_float("fuel_time")
				local fuel_totaltime = meta:get_float("fuel_totaltime")
				if fuel_totaltime ~= 0 then
					fuel_time = fuel_time + 1
					--minetest.chat_send_all(fuel_time)
					if fuel_time > fuel_totaltime then
						local nofuel = true
						if meta:get_string("stack") ~= "" then
							local fuelitem = ItemStack(meta:get_string("stack"))
							local afterfuel
							fuel, afterfuel = minetest.get_craft_result({method = "fuel", width = 1, items = {fuelitem}})
							fuel.time = fuel.time*10
							if fuel.time == 0 then
								-- No valid fuel in fuel list
								fuel_totaltime = 0
								fuel_time = 0
							else
								-- Take fuel from fuel list
								fuelitem:take_item(1)
								-- Put replacements in dst list or drop them on the furnace.
								local replacements = fuel.replacements
								if replacements[1] then
									local pos = player:get_pos()
									local above = vector.new(pos.x, pos.y + 1, pos.z)
									local drop_pos = minetest.find_node_near(above, 1, {"air"}) or above
									minetest.item_drop(replacements[1], nil, drop_pos)
								end
								nofuel = false
								meta:set_string("stack", fuelitem:to_string())
								meta:set_float("fuel_time", 0)
								meta:set_float("fuel_totaltime", fuel.time)
							end
						end
						if nofuel then
							meta:set_float("fuel_time", 0)
							meta:set_float("fuel_totaltime", 0)
							local newstack = ItemStack("nolight:lantern")
							--newstack:get_meta():set_string("stack", meta:get_string("stack"))
							wielded_item:replace(newstack)
						end
					else
						meta:set_float("fuel_time", fuel_time)
					end
					player:set_wielded_item(wielded_item)
				end
			else
				beamlight.beams[player:get_player_name()] = nil
			end
		end
	end
end)

local func = minetest.handle_node_drops
minetest.handle_node_drops = function(pos, drops, digger)
	for index, name in pairs(drops) do
		if name == "nolight:lantern_active" or name == "nolight:lantern" then
			drops[index] = ItemStack(name)
			local meta = drops[index]:get_meta()
			local nodemeta = minetest.get_meta(pos)
			meta:set_string("stack", nodemeta:get_inventory():get_stack("fuel", 1):to_string())
			meta:set_float("fuel_time", nodemeta:get_float("fuel_time"))
			meta:set_float("fuel_totaltime", nodemeta:get_float("fuel_totaltime"))
		end
	end
	return func(pos, drops, digger)
end
extends Node

# Announces a completed seed transaction.
signal transaction_completed(
	action: String,
	plant_data: PlantData,
	quantity: int,
	total_price: int
)

# Announces a rejected seed transaction.
signal transaction_failed(
	action: String,
	plant_data: PlantData,
	quantity: int,
	reason: String
)


# Announces a completed permanent plant unlock.
signal plant_unlock_completed(
	plant_data: PlantData,
	token_cost: int
)

# Announces a rejected permanent plant unlock.
signal plant_unlock_failed(
	plant_data: PlantData,
	reason: String
)

# Announces a completed terrain upgrade purchase.
signal terrain_upgrade_completed(
	terrain_id: StringName,
	previous_level: int,
	new_level: int,
	cost: int
)

# Announces a rejected terrain upgrade purchase.
signal terrain_upgrade_failed(
	terrain_id: StringName,
	reason: String
)


# Announces a completed equipment upgrade purchase.
signal equipment_upgrade_completed(
	equipment_id: StringName,
	previous_level: int,
	new_level: int,
	cost: int
)

# Announces a rejected equipment upgrade purchase.
signal equipment_upgrade_failed(
	equipment_id: StringName,
	reason: String
)


const ACTION_BUY: String = "BUY"
const ACTION_SELL: String = "SELL"

const REASON_INVALID_PLANT: String = "INVALID_PLANT"
const REASON_INVALID_QUANTITY: String = "INVALID_QUANTITY"
const REASON_NOT_FOR_SALE: String = "NOT_FOR_SALE"
const REASON_INVALID_PRICE: String = "INVALID_PRICE"
const REASON_INSUFFICIENT_MONEY: String = "INSUFFICIENT_MONEY"
const REASON_INSUFFICIENT_STOCK: String = "INSUFFICIENT_STOCK"
const REASON_TRANSACTION_FAILED: String = "TRANSACTION_FAILED"

const REASON_PLANT_LOCKED: String = "PLANT_LOCKED"
const REASON_ALREADY_UNLOCKED: String = "ALREADY_UNLOCKED"
const REASON_INSUFFICIENT_UNLOCK_TOKENS: String = "INSUFFICIENT_UNLOCK_TOKENS"

const REASON_MAX_TERRAIN_LEVEL: String = "MAX_TERRAIN_LEVEL"
const REASON_PLAYER_LEVEL_TOO_LOW: String = "PLAYER_LEVEL_TOO_LOW"
const REASON_INVALID_TERRAIN: String = "INVALID_TERRAIN"
const REASON_MAX_EQUIPMENT_LEVEL: String = "MAX_EQUIPMENT_LEVEL"
const REASON_INVALID_EQUIPMENT: String = "INVALID_EQUIPMENT"


# Terrain definitions currently exposed by the shop.
const TERRAIN_CATALOG: Array[Dictionary] = [
	{
		"id": &"loamy",
		"display_name": "Loamy Soil",
		"description": "Upgrade the loamy growing area."
	},
	{
		"id": &"sandy",
		"display_name": "Sandy Soil",
		"description": "Upgrade the sandy growing area."
	}
]


# Equipment definitions exposed by the shop.
const EQUIPMENT_CATALOG: Array[Dictionary] = [
	{
		"id": &"watering_can",
		"display_name": "Watering Can",
		"description": "Improves watering strength and interaction range."
	},
	{
		"id": &"fertilizer",
		"display_name": "Fertilizer Spreader",
		"description": "Improves fertilizing strength and interaction range."
	},
	{
		"id": &"lime",
		"display_name": "Lime Applicator",
		"description": "Improves positive pH adjustment and interaction range."
	},
	{
		"id": &"acid",
		"display_name": "Acid Applicator",
		"description": "Improves negative pH adjustment and interaction range."
	},
	{
		"id": &"pesticide",
		"display_name": "Pesticide Sprayer",
		"description": "Improves pesticide strength and interaction range."
	},
	{
		"id": &"fungicide",
		"display_name": "Fungicide Sprayer",
		"description": "Improves fungicide strength and interaction range."
	},
	{
		"id": &"shovel",
		"display_name": "Shovel",
		"description": "Adds seed recovery chance and interaction range."
	},
	{
		"id": &"harvest",
		"display_name": "Harvest Tool",
		"description": "Improves harvest money rewards and interaction range."
	}
]


@export_category("Debug Logging")

# Enables shop operation logging.
@export var debug_log: bool = false


# Returns the plant definitions currently available in the seed shop.
func get_catalog() -> Array[PlantData]:
	var catalog: Array[PlantData] = []

	for plant_data: PlantData in (
		PlantSelectionSystem.available_plants
	):
		if (
			plant_data != null
			and plant_data.available_in_shop
		):
			catalog.append(plant_data)

	return catalog


# Returns every plant definition, including locked plants.
func get_all_plant_catalog() -> Array[PlantData]:
	return PlantSelectionSystem.get_all_plants()


# Returns whether one plant can currently be unlocked.
func get_plant_unlock_status(
	plant_data: PlantData
) -> Dictionary:
	if plant_data == null:
		return {
			"ok": false,
			"reason": REASON_INVALID_PLANT,
			"cost": 1
		}

	var status: Dictionary = (
		ProgressionSystem.get_plant_unlock_status(
			plant_data.seed_item_id
		)
	)
	var reason: String = String(
		status.get("reason", "")
	)

	if reason == ProgressionSystem.PLANT_UNLOCK_ALREADY_UNLOCKED:
		status["reason"] = REASON_ALREADY_UNLOCKED
	elif reason == ProgressionSystem.PLANT_UNLOCK_NO_TOKENS:
		status["reason"] = REASON_INSUFFICIENT_UNLOCK_TOKENS
	elif reason == ProgressionSystem.PLANT_UNLOCK_INVALID:
		status["reason"] = REASON_INVALID_PLANT

	return status


# Permanently unlocks one plant using a milestone token.
func unlock_plant(
	plant_data: PlantData
) -> Dictionary:
	var status: Dictionary = get_plant_unlock_status(
		plant_data
	)

	if not bool(status.get("ok", false)):
		var failed_reason: String = String(
			status.get("reason", REASON_TRANSACTION_FAILED)
		)
		plant_unlock_failed.emit(
			plant_data,
			failed_reason
		)

		if debug_log:
			print(
				"[Shop] plant unlock failed plant=",
				plant_data.display_name if plant_data != null else "NONE",
				" reason=",
				failed_reason
			)

		return status

	var result: Dictionary = ProgressionSystem.unlock_plant(
		plant_data.seed_item_id
	)

	if not bool(result.get("ok", false)):
		var result_reason: String = String(
			result.get("reason", REASON_TRANSACTION_FAILED)
		)

		if result_reason == ProgressionSystem.PLANT_UNLOCK_NO_TOKENS:
			result_reason = REASON_INSUFFICIENT_UNLOCK_TOKENS
		elif result_reason == ProgressionSystem.PLANT_UNLOCK_ALREADY_UNLOCKED:
			result_reason = REASON_ALREADY_UNLOCKED
		elif result_reason == ProgressionSystem.PLANT_UNLOCK_INVALID:
			result_reason = REASON_INVALID_PLANT

		result["reason"] = result_reason
		plant_unlock_failed.emit(
			plant_data,
			result_reason
		)
		return result

	var cost: int = int(result.get("cost", 1))
	plant_unlock_completed.emit(plant_data, cost)

	if debug_log:
		print(
			"[Shop] plant unlock completed plant=",
			plant_data.display_name,
			" cost=",
			cost,
			" tokens_remaining=",
			ProgressionSystem.plant_unlock_tokens
		)

	return result


# Returns terrain shop definitions.
func get_terrain_catalog() -> Array[Dictionary]:
	return TERRAIN_CATALOG.duplicate(true)


# Returns equipment shop definitions.
func get_equipment_catalog() -> Array[Dictionary]:
	return EQUIPMENT_CATALOG.duplicate(true)


# Returns the total purchase price for seeds.
func get_buy_price(
	plant_data: PlantData,
	quantity: int = 1
) -> int:
	if plant_data == null or quantity <= 0:
		return 0

	return maxi(
		plant_data.seed_buy_price,
		0
	) * quantity


# Returns the total selling value for seeds.
func get_sell_price(
	plant_data: PlantData,
	quantity: int = 1
) -> int:
	if plant_data == null or quantity <= 0:
		return 0

	return maxi(
		plant_data.seed_sell_price,
		0
	) * quantity


# Returns the current purchase availability.
func get_buy_status(
	plant_data: PlantData,
	quantity: int = 1
) -> Dictionary:
	var validation: Dictionary = _validate_transaction(
		ACTION_BUY,
		plant_data,
		quantity
	)

	if not bool(validation.get("ok", false)):
		return validation

	var total_price: int = get_buy_price(
		plant_data,
		quantity
	)

	if not EconomySystem.can_afford(total_price):
		return {
			"ok": false,
			"reason": REASON_INSUFFICIENT_MONEY,
			"total_price": total_price,
			"available_money": EconomySystem.get_money()
		}

	return {
		"ok": true,
		"reason": "",
		"total_price": total_price,
		"available_money": EconomySystem.get_money()
	}


# Returns the current selling availability.
func get_sell_status(
	plant_data: PlantData,
	quantity: int = 1
) -> Dictionary:
	var validation: Dictionary = _validate_transaction(
		ACTION_SELL,
		plant_data,
		quantity
	)

	if not bool(validation.get("ok", false)):
		return validation

	var available_stock: int = InventorySystem.get_amount(
		plant_data.seed_item_id
	)
	var total_price: int = get_sell_price(
		plant_data,
		quantity
	)

	if available_stock < quantity:
		return {
			"ok": false,
			"reason": REASON_INSUFFICIENT_STOCK,
			"total_price": total_price,
			"available_stock": available_stock
		}

	return {
		"ok": true,
		"reason": "",
		"total_price": total_price,
		"available_stock": available_stock
	}


# Purchases the requested number of seeds.
func buy_seed(
	plant_data: PlantData,
	quantity: int = 1
) -> Dictionary:
	var status: Dictionary = get_buy_status(
		plant_data,
		quantity
	)

	if not bool(status.get("ok", false)):
		return _fail(
			ACTION_BUY,
			plant_data,
			quantity,
			String(
				status.get(
					"reason",
					REASON_TRANSACTION_FAILED
				)
			)
		)

	var total_price: int = get_buy_price(
		plant_data,
		quantity
	)
	var reason: String = "SHOP_BUY_%s_X%d" % [
		String(plant_data.seed_item_id),
		quantity
	]

	if not EconomySystem.spend_money(
		total_price,
		reason
	):
		return _fail(
			ACTION_BUY,
			plant_data,
			quantity,
			REASON_TRANSACTION_FAILED
		)

	if not InventorySystem.add_item(
		plant_data.seed_item_id,
		quantity
	):
		EconomySystem.add_money(
			total_price,
			reason + "_ROLLBACK"
		)

		return _fail(
			ACTION_BUY,
			plant_data,
			quantity,
			REASON_TRANSACTION_FAILED
		)

	return _complete(
		ACTION_BUY,
		plant_data,
		quantity,
		total_price
	)


# Sells the requested number of seeds.
func sell_seed(
	plant_data: PlantData,
	quantity: int = 1
) -> Dictionary:
	var status: Dictionary = get_sell_status(
		plant_data,
		quantity
	)

	if not bool(status.get("ok", false)):
		return _fail(
			ACTION_SELL,
			plant_data,
			quantity,
			String(
				status.get(
					"reason",
					REASON_TRANSACTION_FAILED
				)
			)
		)

	var total_price: int = get_sell_price(
		plant_data,
		quantity
	)
	var reason: String = "SHOP_SELL_%s_X%d" % [
		String(plant_data.seed_item_id),
		quantity
	]

	if not InventorySystem.remove_item(
		plant_data.seed_item_id,
		quantity
	):
		return _fail(
			ACTION_SELL,
			plant_data,
			quantity,
			REASON_TRANSACTION_FAILED
		)

	if not EconomySystem.add_money(
		total_price,
		reason
	):
		InventorySystem.add_item(
			plant_data.seed_item_id,
			quantity
		)

		return _fail(
			ACTION_SELL,
			plant_data,
			quantity,
			REASON_TRANSACTION_FAILED
		)

	return _complete(
		ACTION_SELL,
		plant_data,
		quantity,
		total_price
	)


# Returns whether a terrain upgrade can currently be purchased.
func get_terrain_upgrade_status(
	terrain_id: StringName
) -> Dictionary:
	if not ProgressionSystem.TRACKED_TERRAINS.has(
		terrain_id
	):
		return {
			"ok": false,
			"reason": REASON_INVALID_TERRAIN
		}

	var current_level: int = (
		ProgressionSystem.get_terrain_level(terrain_id)
	)
	var max_level: int = ProgressionSystem.MAX_TERRAIN_LEVEL

	if current_level >= max_level:
		return {
			"ok": false,
			"reason": REASON_MAX_TERRAIN_LEVEL,
			"current_level": current_level,
			"max_level": max_level,
			"next_level": current_level,
			"cost": 0,
			"required_player_level": 0
		}

	var next_level: int = current_level + 1
	var cost: int = (
		ProgressionSystem.get_terrain_upgrade_cost(
			terrain_id
		)
	)
	var required_player_level: int = (
		ProgressionSystem.get_terrain_required_player_level(
			terrain_id
		)
	)
	var player_level: int = ProgressionSystem.player_level

	if player_level < required_player_level:
		return {
			"ok": false,
			"reason": REASON_PLAYER_LEVEL_TOO_LOW,
			"current_level": current_level,
			"max_level": max_level,
			"next_level": next_level,
			"cost": cost,
			"required_player_level": required_player_level,
			"player_level": player_level
		}

	if not EconomySystem.can_afford(cost):
		return {
			"ok": false,
			"reason": REASON_INSUFFICIENT_MONEY,
			"current_level": current_level,
			"max_level": max_level,
			"next_level": next_level,
			"cost": cost,
			"required_player_level": required_player_level,
			"player_level": player_level
		}

	return {
		"ok": true,
		"reason": "",
		"current_level": current_level,
		"max_level": max_level,
		"next_level": next_level,
		"cost": cost,
		"required_player_level": required_player_level,
		"player_level": player_level
	}


# Purchases one terrain level through ProgressionSystem.
func buy_terrain_upgrade(
	terrain_id: StringName
) -> Dictionary:
	var status: Dictionary = get_terrain_upgrade_status(
		terrain_id
	)

	if not bool(status.get("ok", false)):
		var failed_reason: String = String(
			status.get(
				"reason",
				REASON_TRANSACTION_FAILED
			)
		)

		terrain_upgrade_failed.emit(
			terrain_id,
			failed_reason
		)

		if debug_log:
			print(
				"[Shop] terrain failed id=",
				String(terrain_id),
				" reason=",
				failed_reason
			)

		return status

	var result: Dictionary = (
		ProgressionSystem.upgrade_terrain(terrain_id)
	)

	if not bool(result.get("ok", false)):
		var result_reason: String = String(
			result.get(
				"reason",
				REASON_TRANSACTION_FAILED
			)
		)

		terrain_upgrade_failed.emit(
			terrain_id,
			result_reason
		)

		if debug_log:
			print(
				"[Shop] terrain failed id=",
				String(terrain_id),
				" reason=",
				result_reason
			)

		return result

	var previous_level: int = int(
		result.get("previous_level", 1)
	)
	var new_level: int = int(
		result.get("new_level", previous_level)
	)
	var cost: int = int(result.get("cost", 0))

	terrain_upgrade_completed.emit(
		terrain_id,
		previous_level,
		new_level,
		cost
	)

	if debug_log:
		print(
			"[Shop] terrain completed id=",
			String(terrain_id),
			" level=",
			previous_level,
			"->",
			new_level,
			" cost=",
			cost,
			" money=",
			EconomySystem.get_money()
		)

	return result


# Returns whether an equipment upgrade can currently be purchased.
func get_equipment_upgrade_status(
	equipment_id: StringName
) -> Dictionary:
	if not ProgressionSystem.TRACKED_EQUIPMENT.has(
		equipment_id
	):
		return {
			"ok": false,
			"reason": REASON_INVALID_EQUIPMENT
		}

	var current_level: int = (
		ProgressionSystem.get_equipment_level(
			equipment_id
		)
	)
	var max_level: int = ProgressionSystem.MAX_EQUIPMENT_LEVEL

	if current_level >= max_level:
		return {
			"ok": false,
			"reason": REASON_MAX_EQUIPMENT_LEVEL,
			"current_level": current_level,
			"max_level": max_level,
			"next_level": current_level,
			"cost": 0,
			"required_player_level": 0
		}

	var next_level: int = current_level + 1
	var cost: int = (
		ProgressionSystem.get_equipment_upgrade_cost(
			equipment_id
		)
	)
	var required_player_level: int = (
		ProgressionSystem.get_equipment_required_player_level(
			equipment_id
		)
	)
	var player_level: int = ProgressionSystem.player_level

	if player_level < required_player_level:
		return {
			"ok": false,
			"reason": REASON_PLAYER_LEVEL_TOO_LOW,
			"current_level": current_level,
			"max_level": max_level,
			"next_level": next_level,
			"cost": cost,
			"required_player_level": required_player_level,
			"player_level": player_level
		}

	if not EconomySystem.can_afford(cost):
		return {
			"ok": false,
			"reason": REASON_INSUFFICIENT_MONEY,
			"current_level": current_level,
			"max_level": max_level,
			"next_level": next_level,
			"cost": cost,
			"required_player_level": required_player_level,
			"player_level": player_level
		}

	return {
		"ok": true,
		"reason": "",
		"current_level": current_level,
		"max_level": max_level,
		"next_level": next_level,
		"cost": cost,
		"required_player_level": required_player_level,
		"player_level": player_level
	}


# Purchases one equipment level through ProgressionSystem.
func buy_equipment_upgrade(
	equipment_id: StringName
) -> Dictionary:
	var status: Dictionary = (
		get_equipment_upgrade_status(equipment_id)
	)

	if not bool(status.get("ok", false)):
		var failed_reason: String = String(
			status.get(
				"reason",
				REASON_TRANSACTION_FAILED
			)
		)

		equipment_upgrade_failed.emit(
			equipment_id,
			failed_reason
		)

		if debug_log:
			print(
				"[Shop] equipment failed id=",
				String(equipment_id),
				" reason=",
				failed_reason
			)

		return status

	var result: Dictionary = (
		ProgressionSystem.upgrade_equipment(
			equipment_id
		)
	)

	if not bool(result.get("ok", false)):
		var result_reason: String = String(
			result.get(
				"reason",
				REASON_TRANSACTION_FAILED
			)
		)

		equipment_upgrade_failed.emit(
			equipment_id,
			result_reason
		)

		if debug_log:
			print(
				"[Shop] equipment failed id=",
				String(equipment_id),
				" reason=",
				result_reason
			)

		return result

	var previous_level: int = int(
		result.get("previous_level", 1)
	)
	var new_level: int = int(
		result.get("new_level", previous_level)
	)
	var cost: int = int(result.get("cost", 0))

	equipment_upgrade_completed.emit(
		equipment_id,
		previous_level,
		new_level,
		cost
	)

	if debug_log:
		print(
			"[Shop] equipment completed id=",
			String(equipment_id),
			" level=",
			previous_level,
			"->",
			new_level,
			" cost=",
			cost,
			" money=",
			EconomySystem.get_money()
		)

	return result


# Validates shared seed transaction requirements.
func _validate_transaction(
	action: String,
	plant_data: PlantData,
	quantity: int
) -> Dictionary:
	if plant_data == null:
		return {
			"ok": false,
			"reason": REASON_INVALID_PLANT
		}

	if quantity <= 0:
		return {
			"ok": false,
			"reason": REASON_INVALID_QUANTITY
		}

	if not ProgressionSystem.is_plant_unlocked(
		plant_data.seed_item_id
	):
		return {
			"ok": false,
			"reason": REASON_PLANT_LOCKED
		}

	if not plant_data.available_in_shop:
		return {
			"ok": false,
			"reason": REASON_NOT_FOR_SALE
		}

	var unit_price: int = (
		plant_data.seed_buy_price
		if action == ACTION_BUY
		else plant_data.seed_sell_price
	)

	if unit_price <= 0:
		return {
			"ok": false,
			"reason": REASON_INVALID_PRICE
		}

	return {
		"ok": true,
		"reason": ""
	}


# Completes and reports a successful seed transaction.
func _complete(
	action: String,
	plant_data: PlantData,
	quantity: int,
	total_price: int
) -> Dictionary:
	transaction_completed.emit(
		action,
		plant_data,
		quantity,
		total_price
	)

	if debug_log:
		print(
			"[Shop] completed action=",
			action,
			" plant=",
			plant_data.display_name,
			" quantity=",
			quantity,
			" total=",
			total_price,
			" money=",
			EconomySystem.get_money(),
			" stock=",
			InventorySystem.get_amount(
				plant_data.seed_item_id
			)
		)

	return {
		"ok": true,
		"action": action,
		"plant_data": plant_data,
		"quantity": quantity,
		"total_price": total_price
	}


# Reports a rejected seed transaction.
func _fail(
	action: String,
	plant_data: PlantData,
	quantity: int,
	reason: String
) -> Dictionary:
	transaction_failed.emit(
		action,
		plant_data,
		quantity,
		reason
	)

	if debug_log:
		print(
			"[Shop] failed action=",
			action,
			" plant=",
			plant_data.display_name
			if plant_data != null
			else "NONE",
			" quantity=",
			quantity,
			" reason=",
			reason,
			" money=",
			EconomySystem.get_money()
		)

	return {
		"ok": false,
		"action": action,
		"plant_data": plant_data,
		"quantity": quantity,
		"reason": reason
	}

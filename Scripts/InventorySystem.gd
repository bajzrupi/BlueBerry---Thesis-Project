extends Node

# Emitted when an item's stored amount changes.
signal item_amount_changed(
	item_id: StringName,
	previous_amount: int,
	new_amount: int
)

# Emitted when an item enters the inventory from zero stock.
signal item_discovered(
	item_id: StringName
)

# Emitted when the inventory returns to its default state.
signal inventory_reset(items: Dictionary)


const ITEM_LILY_SEED: StringName = &"lily_seed"
const ITEM_CACTUS_SEED: StringName = &"cactus_seed"


# Alpha starting inventory. Item storage itself is fully generic.
const DEFAULT_ITEMS: Dictionary = {
	ITEM_LILY_SEED: 5
}


var debug_log: bool = false
var _items: Dictionary = {}


# Initializes this system when the node becomes ready.
func _ready() -> void:
	reset_to_defaults()

	if debug_log:
		print("[Inventory] ready")
		_log_inventory()


# Restores this system to its default state.
func reset_to_defaults() -> void:
	_items = DEFAULT_ITEMS.duplicate(true)

	inventory_reset.emit(get_all_items())

	if debug_log:
		print("[Inventory] reset to defaults")


# Returns the amount.
func get_amount(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))


# Checks whether amount exists or is available.
func has_amount(
	item_id: StringName,
	required_amount: int = 1
) -> bool:
	if required_amount <= 0:
		return true

	return get_amount(item_id) >= required_amount


# Adds the item.
func add_item(
	item_id: StringName,
	amount: int
) -> bool:
	if item_id == &"" or amount <= 0:
		push_warning(
			"[Inventory] add_item rejected: invalid id or amount."
		)
		return false

	var previous_amount: int = get_amount(item_id)
	var new_amount: int = previous_amount + amount
	var item_data: ItemData = _get_item_data(item_id)

	if (
		item_data != null
		and new_amount > item_data.stack_limit
	):
		if debug_log:
			print(
				"[Inventory] stack limit item=",
				String(item_id),
				" requested=",
				new_amount,
				" limit=",
				item_data.stack_limit
			)
		return false

	_items[item_id] = new_amount

	if previous_amount <= 0 and new_amount > 0:
		item_discovered.emit(item_id)

	item_amount_changed.emit(
		item_id,
		previous_amount,
		new_amount
	)

	if debug_log:
		print(
			"[Inventory] added item=",
			String(item_id),
			" amount=",
			amount,
			" old=",
			previous_amount,
			" new=",
			new_amount
		)

	return true


# Removes the item.
func remove_item(
	item_id: StringName,
	amount: int
) -> bool:
	if item_id == &"" or amount <= 0:
		push_warning(
			"[Inventory] remove_item rejected: invalid id or amount."
		)
		return false

	var previous_amount: int = get_amount(item_id)

	if previous_amount < amount:
		if debug_log:
			print(
				"[Inventory] insufficient item=",
				String(item_id),
				" required=",
				amount,
				" available=",
				previous_amount
			)
		return false

	var new_amount: int = previous_amount - amount
	_items[item_id] = new_amount

	item_amount_changed.emit(
		item_id,
		previous_amount,
		new_amount
	)

	if debug_log:
		print(
			"[Inventory] removed item=",
			String(item_id),
			" amount=",
			amount,
			" old=",
			previous_amount,
			" new=",
			new_amount
		)

	return true


# Sets the amount.
func set_amount(
	item_id: StringName,
	amount: int
) -> void:
	if item_id == &"":
		return

	var previous_amount: int = get_amount(item_id)
	var new_amount: int = maxi(amount, 0)
	var item_data: ItemData = _get_item_data(item_id)

	if item_data != null:
		new_amount = mini(
			new_amount,
			item_data.stack_limit
		)

	_items[item_id] = new_amount

	if previous_amount <= 0 and new_amount > 0:
		item_discovered.emit(item_id)

	item_amount_changed.emit(
		item_id,
		previous_amount,
		new_amount
	)

	if debug_log:
		print(
			"[Inventory] set item=",
			String(item_id),
			" old=",
			previous_amount,
			" new=",
			new_amount
		)


# Returns the all items.
func get_all_items() -> Dictionary:
	return _items.duplicate(true)


# Returns the item data.
func get_item_data(item_id: StringName) -> ItemData:
	return _get_item_data(item_id)


# Returns the item data.
func _get_item_data(item_id: StringName) -> ItemData:
	if not has_node("/root/ItemCatalogSystem"):
		return null

	return ItemCatalogSystem.get_item(item_id)


# Logs the inventory.
func _log_inventory() -> void:
	for item_id: Variant in _items.keys():
		print(
			"[Inventory] item=",
			String(item_id),
			" amount=",
			get_amount(StringName(String(item_id)))
		)

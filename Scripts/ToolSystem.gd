extends Node
class_name ToolSystem

# Tracks tools, durability, upgrades, and the selected tool.

signal tool_changed(tool_id: int)
signal durability_changed(
	tool_id: int,
	previous_value: int,
	new_value: int,
	delta: int
)
signal tool_broken(tool_id: int)
signal tool_replaced(tool_id: int, cost: int)
signal tool_repaired(
	tool_id: int,
	restored_amount: int,
	cost: int
)

enum Tool {
	PLANT,
	WATER,
	FERTILIZE,
	LIME,
	ACID,
	PESTICIDE,
	FUNGICIDE,
	SHOVEL,
	HARVEST
}


const MAX_DURABILITY: int = 100
const REPAIR_STEP: int = 25

# Planting does not wear a tool. All other values are consumed only after a
# validated gameplay action.
const DURABILITY_COSTS: Dictionary = {
	Tool.WATER: 1,
	Tool.FERTILIZE: 1,
	Tool.LIME: 1,
	Tool.ACID: 1,
	Tool.PESTICIDE: 1,
	Tool.FUNGICIDE: 1,
	Tool.SHOVEL: 3,
	Tool.HARVEST: 2
}

# One Repair Corner / Anvil interaction restores up to 25 durability.
const REPAIR_COST_BY_LEVEL: Dictionary = {
	1: 5,
	2: 10,
	3: 15,
	4: 20,
	5: 25
}

# A fully broken tool cannot be repaired. It must be replaced. The current
# Equipment Level is preserved, but higher-level equipment costs more to buy.
const REPLACEMENT_COST_BY_LEVEL: Dictionary = {
	1: 30,
	2: 60,
	3: 100,
	4: 150,
	5: 220
}


@export_category("Debug Logging")
@export var debug_log: bool = false


# Tool selection state and toolbar ordering.
@export var order: Array[int] = [
	Tool.PLANT,
	Tool.WATER,
	Tool.FERTILIZE,
	Tool.LIME,
	Tool.ACID,
	Tool.PESTICIDE,
	Tool.FUNGICIDE,
	Tool.SHOVEL,
	Tool.HARVEST
]

var current_tool: int = Tool.PLANT

# tool_id -> durability
var _durability: Dictionary = {}

var _replacement_dialog: ConfirmationDialog
var _replacement_tool_id: int = -1
var _dialog_previous_tree_paused: bool = false
var _dialog_previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN
var _dialog_state_captured: bool = false


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_durability()
	_create_replacement_dialog()

	if debug_log:
		print(
			"[Tool] durability ready max=",
			MAX_DURABILITY,
			" repair_step=",
			REPAIR_STEP,
			" state=",
			_durability
		)


# Set active tool and notify listeners.
func set_tool(tool_id: int) -> void:
	if tool_id == current_tool:
		return

	current_tool = tool_id

	if debug_log:
		print(
			"[Tool] switched to:",
			get_tool_name(current_tool),
			" (id=",
			current_tool,
			" durability=",
			get_durability(current_tool),
			")"
		)

	tool_changed.emit(current_tool)


# Select tool by toolbar index.
func set_tool_by_index(idx: int) -> void:
	if idx < 0 or idx >= order.size():
		return
	set_tool(order[idx])


# Cycle to next tool in order.
func next_tool() -> void:
	var i := order.find(current_tool)
	if i == -1:
		set_tool(order[0])
		return
	set_tool(order[(i + 1) % order.size()])


# Cycle to previous tool in order.
func prev_tool() -> void:
	var i := order.find(current_tool)
	if i == -1:
		set_tool(order[0])
		return
	set_tool(order[(i - 1 + order.size()) % order.size()])


# Convert tool enum value to display name.
func get_tool_name(tool_id: int) -> String:
	match tool_id:
		Tool.PLANT:
			return "Plant"
		Tool.WATER:
			return "Water"
		Tool.FERTILIZE:
			return "Fertilize"
		Tool.LIME:
			return "Lime (+pH)"
		Tool.ACID:
			return "Acid (-pH)"
		Tool.PESTICIDE:
			return "Pesticide"
		Tool.FUNGICIDE:
			return "Fungicide"
		Tool.SHOVEL:
			return "Shovel (Remove)"
		Tool.HARVEST:
			return "Harvest"
	return "?"


# Plant is intentionally maintenance-free.
func uses_durability(tool_id: int) -> bool:
	return DURABILITY_COSTS.has(tool_id)


# Returns the durability.
func get_durability(tool_id: int) -> int:
	if not uses_durability(tool_id):
		return MAX_DURABILITY

	return clampi(
		int(_durability.get(tool_id, MAX_DURABILITY)),
		0,
		MAX_DURABILITY
	)


# Returns the durability percent.
func get_durability_percent(tool_id: int) -> int:
	return get_durability(tool_id)


# Checks whether the tool has no durability remaining.
func is_broken(tool_id: int) -> bool:
	return (
		uses_durability(tool_id)
		and get_durability(tool_id) <= 0
	)


# Checks whether use tool is allowed.
func can_use_tool(tool_id: int) -> bool:
	return not is_broken(tool_id)


# Consume durability after one successful tool action.
func consume_use(tool_id: int) -> bool:
	if not uses_durability(tool_id):
		return true

	if is_broken(tool_id):
		return false

	var wear: int = maxi(
		int(DURABILITY_COSTS.get(tool_id, 0)),
		0
	)

	if wear <= 0:
		return true

	var previous: int = get_durability(tool_id)
	var current: int = maxi(previous - wear, 0)
	_durability[tool_id] = current

	durability_changed.emit(
		tool_id,
		previous,
		current,
		current - previous
	)

	if debug_log:
		print(
			"[Tool] wear tool=",
			get_tool_name(tool_id),
			" cost=",
			wear,
			" durability=",
			previous,
			"->",
			current
		)

	if current <= 0:
		tool_broken.emit(tool_id)

	return current > 0


# Resets the durability.
func reset_durability() -> void:
	_durability.clear()

	for tool_id_variant: Variant in DURABILITY_COSTS.keys():
		var tool_id: int = int(tool_id_variant)
		_durability[tool_id] = MAX_DURABILITY


# Repair price for the next +25% step. If less than 25 is missing, the price
# scales down proportionally.
func get_repair_cost(
	tool_id: int,
	restore_amount: int = REPAIR_STEP
) -> int:
	if (
		not uses_durability(tool_id)
		or is_broken(tool_id)
	):
		return 0

	var missing: int = (
		MAX_DURABILITY
		- get_durability(tool_id)
	)

	if missing <= 0:
		return 0

	var actual_restore: int = mini(
		maxi(restore_amount, 1),
		missing
	)
	var level: int = _get_equipment_level(tool_id)
	var full_step_cost: int = int(
		REPAIR_COST_BY_LEVEL.get(level, 5)
	)

	return maxi(
		int(ceil(
			float(full_step_cost)
			* float(actual_restore)
			/ float(REPAIR_STEP)
		)),
		1
	)


# Repair Corner / Anvil entry point. Repairs the currently selected tool.
func repair_current_tool(
	restore_amount: int = REPAIR_STEP
) -> Dictionary:
	return repair_tool(
		current_tool,
		restore_amount
	)


# Repairs the tool.
func repair_tool(
	tool_id: int,
	restore_amount: int = REPAIR_STEP
) -> Dictionary:
	if not uses_durability(tool_id):
		return {
			"ok": false,
			"reason": "NO_DURABILITY",
			"cost": 0,
			"restored": 0
		}

	if is_broken(tool_id):
		return {
			"ok": false,
			"reason": "BROKEN_REPLACE_REQUIRED",
			"cost": get_replacement_cost(tool_id),
			"restored": 0
		}

	var previous: int = get_durability(tool_id)
	var missing: int = MAX_DURABILITY - previous

	if missing <= 0:
		return {
			"ok": false,
			"reason": "ALREADY_FULL",
			"cost": 0,
			"restored": 0
		}

	var restored: int = mini(
		maxi(restore_amount, 1),
		missing
	)
	var cost: int = get_repair_cost(
		tool_id,
		restored
	)

	if (
		cost > 0
		and not EconomySystem.spend_money(
			cost,
			"TOOL_REPAIR_%s"
			% get_tool_name(tool_id)
		)
	):
		return {
			"ok": false,
			"reason": "NOT_ENOUGH_MONEY",
			"cost": cost,
			"restored": 0
		}

	var current: int = mini(
		previous + restored,
		MAX_DURABILITY
	)
	_durability[tool_id] = current

	durability_changed.emit(
		tool_id,
		previous,
		current,
		current - previous
	)
	tool_repaired.emit(
		tool_id,
		current - previous,
		cost
	)

	if debug_log:
		print(
			"[Tool] repaired tool=",
			get_tool_name(tool_id),
			" durability=",
			previous,
			"->",
			current,
			" cost=",
			cost
		)

	return {
		"ok": true,
		"reason": "",
		"cost": cost,
		"restored": current - previous,
		"durability": current
	}


# Returns the replacement cost.
func get_replacement_cost(tool_id: int) -> int:
	if not uses_durability(tool_id):
		return 0

	var level: int = _get_equipment_level(tool_id)
	return int(
		REPLACEMENT_COST_BY_LEVEL.get(
			level,
			30
		)
	)


# Replaces the tool.
func replace_tool(tool_id: int) -> bool:
	if not is_broken(tool_id):
		return false

	var cost: int = get_replacement_cost(tool_id)

	if not EconomySystem.spend_money(
		cost,
		"TOOL_REPLACE_%s"
		% get_tool_name(tool_id)
	):
		return false

	var previous: int = get_durability(tool_id)
	_durability[tool_id] = MAX_DURABILITY

	durability_changed.emit(
		tool_id,
		previous,
		MAX_DURABILITY,
		MAX_DURABILITY - previous
	)
	tool_replaced.emit(tool_id, cost)

	if debug_log:
		print(
			"[Tool] replaced tool=",
			get_tool_name(tool_id),
			" equipment_level=",
			_get_equipment_level(tool_id),
			" cost=",
			cost
		)

	return true


# Replacement popup entry point. RepairSystem calls this only when the player
# presses E at a repair station with a broken tool selected.
func request_replacement(tool_id: int) -> void:
	if not is_broken(tool_id):
		return

	if (
		_replacement_dialog != null
		and _replacement_dialog.visible
	):
		if _replacement_tool_id == tool_id:
			return
		_finish_replacement_dialog()

	_replacement_tool_id = tool_id

	var level: int = _get_equipment_level(tool_id)
	var cost: int = get_replacement_cost(tool_id)
	var available: int = EconomySystem.get_money()

	_replacement_dialog.title = "Tool Broken"
	_replacement_dialog.dialog_text = (
		"%s is broken.\n\n"
		+ "Equipment Level: %d\n"
		+ "Replacement: $%d\n"
		+ "Money: $%d\n\n"
		+ "Buying a replacement keeps the current Equipment Level."
	) % [
		get_tool_name(tool_id),
		level,
		cost,
		available
	]
	_replacement_dialog.get_ok_button().text = (
		"Buy for $%d" % cost
	)
	_replacement_dialog.get_ok_button().disabled = (
		not EconomySystem.can_afford(cost)
	)
	_replacement_dialog.get_cancel_button().text = "Later"

	_capture_dialog_state()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_replacement_dialog.popup_centered(
		Vector2i(420, 250)
	)

	if debug_log:
		print(
			"[Tool] replacement popup tool=",
			get_tool_name(tool_id),
			" level=",
			level,
			" cost=",
			cost,
			" money=",
			available
		)


# Returns the serializable state of this system.
func get_save_state() -> Dictionary:
	var saved: Dictionary = {}

	for tool_id_variant: Variant in DURABILITY_COSTS.keys():
		var tool_id: int = int(tool_id_variant)
		saved[str(tool_id)] = get_durability(tool_id)

	return {
		"current_tool": current_tool,
		"durability": saved
	}


# Restores this system from saved data.
func load_save_state(state: Dictionary) -> void:
	reset_durability()

	var durability_state: Variant = state.get(
		"durability",
		{}
	)

	if typeof(durability_state) == TYPE_DICTIONARY:
		var saved: Dictionary = durability_state

		for tool_id_variant: Variant in DURABILITY_COSTS.keys():
			var tool_id: int = int(tool_id_variant)
			var key: String = str(tool_id)

			if saved.has(key):
				_durability[tool_id] = clampi(
					int(saved.get(key, MAX_DURABILITY)),
					0,
					MAX_DURABILITY
				)

	var loaded_tool: int = int(
		state.get(
			"current_tool",
			current_tool
		)
	)

	if order.has(loaded_tool):
		current_tool = loaded_tool

	tool_changed.emit(current_tool)

	if debug_log:
		print(
			"[Tool] durability loaded current=",
			get_tool_name(current_tool),
			" state=",
			_durability
		)


# Returns the equipment level.
func _get_equipment_level(tool_id: int) -> int:
	var equipment_id: StringName = (
		_equipment_id_for_tool(tool_id)
	)

	if equipment_id == &"":
		return 1

	return clampi(
		ProgressionSystem.get_equipment_level(
			equipment_id
		),
		1,
		5
	)


# Handles equipment ID for tool.
func _equipment_id_for_tool(tool_id: int) -> StringName:
	match tool_id:
		Tool.WATER:
			return ProgressionSystem.EQUIPMENT_WATERING_CAN
		Tool.FERTILIZE:
			return ProgressionSystem.EQUIPMENT_FERTILIZER
		Tool.LIME:
			return ProgressionSystem.EQUIPMENT_LIME
		Tool.ACID:
			return ProgressionSystem.EQUIPMENT_ACID
		Tool.PESTICIDE:
			return ProgressionSystem.EQUIPMENT_PESTICIDE
		Tool.FUNGICIDE:
			return ProgressionSystem.EQUIPMENT_FUNGICIDE
		Tool.SHOVEL:
			return ProgressionSystem.EQUIPMENT_SHOVEL
		Tool.HARVEST:
			return ProgressionSystem.EQUIPMENT_HARVEST

	return &""


# Creates the replacement dialog.
func _create_replacement_dialog() -> void:
	_replacement_dialog = ConfirmationDialog.new()
	_replacement_dialog.name = "ToolReplacementDialog"
	_replacement_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_replacement_dialog.unresizable = true
	_replacement_dialog.exclusive = true
	_replacement_dialog.always_on_top = true
	_replacement_dialog.confirmed.connect(
		_on_replacement_confirmed
	)
	_replacement_dialog.canceled.connect(
		_on_replacement_canceled
	)
	_replacement_dialog.close_requested.connect(
		_on_replacement_canceled
	)
	add_child(_replacement_dialog)


# Captures the dialog state for save, restore, or validation.
func _capture_dialog_state() -> void:
	if _dialog_state_captured:
		return

	_dialog_previous_tree_paused = get_tree().paused
	_dialog_previous_mouse_mode = Input.get_mouse_mode()
	_dialog_state_captured = true


# Finishes the replacement dialog.
func _finish_replacement_dialog() -> void:
	if _replacement_dialog != null:
		_replacement_dialog.hide()

	if _dialog_state_captured:
		get_tree().paused = _dialog_previous_tree_paused
		Input.set_mouse_mode(
			_dialog_previous_mouse_mode
		)

	_dialog_state_captured = false
	_replacement_tool_id = -1


# Handles the replacement confirmed signal or callback.
func _on_replacement_confirmed() -> void:
	var tool_id: int = _replacement_tool_id

	if tool_id >= 0:
		replace_tool(tool_id)

	_finish_replacement_dialog()


# Handles the replacement canceled signal or callback.
func _on_replacement_canceled() -> void:
	_finish_replacement_dialog()

extends Node

# Announces player XP or level changes.
signal player_progress_changed(
	level: int,
	xp: int,
	xp_to_next: int
)

# Announces each player level increase.
signal player_level_changed(
	previous_level: int,
	new_level: int
)

# Announces a ten-level player milestone reward.
signal player_milestone_reached(
	level: int,
	money_reward: int,
	plant_unlock_tokens: int,
	build_cell_credits: int
)

# Announces changes to plant-unlock currency.
signal plant_unlock_tokens_changed(
	previous_amount: int,
	new_amount: int,
	delta: int,
	reason: String
)

# Announces changes to terrain-expansion currency.
signal build_cell_credits_changed(
	previous_amount: int,
	new_amount: int,
	delta: int,
	reason: String
)


# Announces one plant becoming permanently available.
signal plant_unlock_changed(
	plant_id: StringName,
	unlocked: bool
)

# Announces plant mastery XP or level changes.
signal plant_progress_changed(
	plant_id: StringName,
	level: int,
	xp: int,
	xp_to_next: int
)

# Announces each plant mastery level increase.
signal plant_level_changed(
	plant_id: StringName,
	previous_level: int,
	new_level: int
)

# Announces terrain upgrades.
signal terrain_level_changed(
	terrain_id: StringName,
	previous_level: int,
	new_level: int
)

# Announces equipment upgrades.
signal equipment_level_changed(
	equipment_id: StringName,
	previous_level: int,
	new_level: int
)

# Announces a complete progression reset.
signal progression_reset()

# Announces milestone-based automation-machine availability.
signal automation_build_unlocked(
	build_id: StringName,
	required_level: int
)


# Player progression continues indefinitely.
# A negative cap value means that Player Level has no hard maximum.
const MAX_PLAYER_LEVEL: int = -1

# Capped progression branches.
const MAX_PLANT_LEVEL: int = 10
const MAX_TERRAIN_LEVEL: int = 5
const MAX_EQUIPMENT_LEVEL: int = 5


# Plant identifiers used by the alpha version.
const PLANT_LILY: StringName = &"lily_seed"
const PLANT_CACTUS: StringName = &"cactus_seed"

# Terrain identifiers reserved for zone upgrades.
const TERRAIN_LOAMY: StringName = &"loamy"
const TERRAIN_SANDY: StringName = &"sandy"

# Equipment identifiers used by the current tool set.
const EQUIPMENT_WATERING_CAN: StringName = &"watering_can"
const EQUIPMENT_FERTILIZER: StringName = &"fertilizer"
const EQUIPMENT_LIME: StringName = &"lime"
const EQUIPMENT_ACID: StringName = &"acid"
const EQUIPMENT_PESTICIDE: StringName = &"pesticide"
const EQUIPMENT_FUNGICIDE: StringName = &"fungicide"
const EQUIPMENT_SHOVEL: StringName = &"shovel"
const EQUIPMENT_HARVEST: StringName = &"harvest"


# Automation-machine identifiers and milestone unlocks.
# Sprinklers remain on their existing backend; the new machines use the
# shared AutomationMachineBase architecture.
const AUTOMATION_SPRINKLER: StringName = &"sprinkler"
const AUTOMATION_FERTILIZER_INJECTOR: StringName = &"fertilizer_injector"
const AUTOMATION_SOIL_NEUTRALIZER: StringName = &"soil_neutralizer"
const AUTOMATION_PLANT_PROTECTION: StringName = &"plant_protection_station"

const AUTOMATION_UNLOCK_LEVELS: Dictionary = {
	AUTOMATION_SPRINKLER: 10,
	AUTOMATION_FERTILIZER_INJECTOR: 20,
	AUTOMATION_SOIL_NEUTRALIZER: 30,
	AUTOMATION_PLANT_PROTECTION: 40
}


# Tracked progression entries available in the alpha version.
const TRACKED_PLANTS: Array[StringName] = [
	PLANT_LILY,
	PLANT_CACTUS
]


# Plants available at the start of a new game.
const STARTING_UNLOCKED_PLANTS: Array[StringName] = [
	PLANT_LILY
]

# Plant unlock operation results.
const PLANT_UNLOCK_INVALID: String = "INVALID_PLANT"
const PLANT_UNLOCK_ALREADY_UNLOCKED: String = "ALREADY_UNLOCKED"
const PLANT_UNLOCK_NO_TOKENS: String = "INSUFFICIENT_UNLOCK_TOKENS"

const TRACKED_TERRAINS: Array[StringName] = [
	TERRAIN_LOAMY,
	TERRAIN_SANDY
]

const TRACKED_EQUIPMENT: Array[StringName] = [
	EQUIPMENT_WATERING_CAN,
	EQUIPMENT_FERTILIZER,
	EQUIPMENT_LIME,
	EQUIPMENT_ACID,
	EQUIPMENT_PESTICIDE,
	EQUIPMENT_FUNGICIDE,
	EQUIPMENT_SHOVEL,
	EQUIPMENT_HARVEST
]


# Player milestones occur every ten levels.
const PLAYER_MILESTONE_INTERVAL: int = 10

# Explicit early-game milestone rewards.
const PLAYER_MILESTONES: Dictionary = {
	10: {
		"money": 100,
		"plant_unlock_tokens": 1,
		"build_cell_credits": 100
	},
	20: {
		"money": 500,
		"plant_unlock_tokens": 1,
		"build_cell_credits": 250
	},
	30: {
		"money": 500,
		"plant_unlock_tokens": 1,
		"build_cell_credits": 500
	},
	40: {
		"money": 500,
		"plant_unlock_tokens": 1,
		"build_cell_credits": 750
	},
	50: {
		"money": 500,
		"plant_unlock_tokens": 1,
		"build_cell_credits": 1000
	}
}

# Milestones after Level 50 repeat this baseline reward until balancing
# defines additional late-game tiers.
const POST_50_MILESTONE_REWARD: Dictionary = {
	"money": 500,
	"plant_unlock_tokens": 1,
	"build_cell_credits": 1000
}


# Initial balancing values for future shop upgrades.
const TERRAIN_UPGRADE_COSTS: Dictionary = {
	2: 200,
	3: 500,
	4: 1000,
	5: 1800
}

const TERRAIN_REQUIRED_PLAYER_LEVELS: Dictionary = {
	2: 5,
	3: 15,
	4: 25,
	5: 35
}

const EQUIPMENT_UPGRADE_COSTS: Dictionary = {
	2: 100,
	3: 250,
	4: 500,
	5: 900
}

const EQUIPMENT_REQUIRED_PLAYER_LEVELS: Dictionary = {
	2: 3,
	3: 10,
	4: 20,
	5: 30
}


# Equipment gameplay scaling.
const EQUIPMENT_EFFECT_BONUS_PER_LEVEL: float = 0.10
const SHOVEL_SEED_RECOVERY_PER_LEVEL: float = 0.25



@export_category("Debug Logging")

# Enables progression operation logging.
@export var debug_log: bool = false


# Stores the global player progression.
var player_level: int = 0
var player_xp: int = 0

# Stores milestone currencies used by plant unlocks and map expansion.
var plant_unlock_tokens: int = 0
var build_cell_credits: int = 0

# Stores progression independently for each plant type.
var _plant_levels: Dictionary = {}
var _plant_xp: Dictionary = {}

# Stores permanent plant availability.
var _plant_unlocked: Dictionary = {}

# Stores progression independently for each terrain.
var _terrain_levels: Dictionary = {}

# Stores progression independently for each equipment item.
var _equipment_levels: Dictionary = {}


# Initializes every progression branch.
func _ready() -> void:
	reset_to_defaults()

	if debug_log:
		print(
			"[Progression] ready player_level=",
			player_level,
			" player_xp=",
			player_xp
		)


# Restores the default state of all progression branches.
func reset_to_defaults() -> void:
	player_level = 0
	player_xp = 0
	plant_unlock_tokens = 0
	build_cell_credits = 0

	_plant_levels.clear()
	_plant_xp.clear()
	_plant_unlocked.clear()
	_terrain_levels.clear()
	_equipment_levels.clear()

	for plant_id: StringName in TRACKED_PLANTS:
		_plant_levels[plant_id] = 0
		_plant_xp[plant_id] = 0
		_plant_unlocked[plant_id] = (
			STARTING_UNLOCKED_PLANTS.has(plant_id)
		)

	for terrain_id: StringName in TRACKED_TERRAINS:
		_terrain_levels[terrain_id] = 1

	for equipment_id: StringName in TRACKED_EQUIPMENT:
		_equipment_levels[equipment_id] = 1

	progression_reset.emit()
	_emit_player_progress()

	for plant_id: StringName in TRACKED_PLANTS:
		_emit_plant_progress(plant_id)

	if debug_log:
		print(
			"[Progression] reset player=0 plants=",
			_plant_levels,
			" terrains=",
			_terrain_levels,
			" equipment=",
			_equipment_levels,
			" unlocked_plants=",
			get_unlocked_plant_ids()
		)


# Returns the Player Level required for one automation machine.
# Unknown/non-automation build ids return 0 and are treated as unlocked.
func get_automation_unlock_level(
	build_id: StringName
) -> int:
	return maxi(
		int(
			AUTOMATION_UNLOCK_LEVELS.get(
				build_id,
				0
			)
		),
		0
	)


# Returns whether the automation machine is currently available.
func is_automation_build_unlocked(
	build_id: StringName
) -> bool:
	var required_level: int = get_automation_unlock_level(
		build_id
	)

	if required_level <= 0:
		return true

	return player_level >= required_level


# Returns all automation-machine ids currently available to the player.
func get_unlocked_automation_build_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for build_variant: Variant in AUTOMATION_UNLOCK_LEVELS.keys():
		var build_id: StringName = StringName(build_variant)

		if is_automation_build_unlocked(build_id):
			result.append(build_id)

	return result


# Emits the automation unlock for level.
func _emit_automation_unlock_for_level(
	level: int
) -> void:
	for build_variant: Variant in AUTOMATION_UNLOCK_LEVELS.keys():
		var build_id: StringName = StringName(build_variant)
		var required_level: int = get_automation_unlock_level(
			build_id
		)

		if required_level == level:
			automation_build_unlocked.emit(
				build_id,
				required_level
			)

			if debug_log:
				print(
					"[Progression] AUTOMATION UNLOCK ",
					String(build_id),
					" @ L",
					required_level
				)


# Returns the XP required for the next player level.
func get_player_xp_required_for_next(
	level: int = player_level
) -> int:
	var safe_level: int = maxi(level, 0)
	return 100 + safe_level * 20


# Adds global player XP and resolves every crossed level.
func add_player_xp(
	amount: int,
	reason: String = ""
) -> bool:
	if amount <= 0:
		return false

	var previous_level: int = player_level
	var previous_xp: int = player_xp

	player_xp += amount

	while true:
		var required_xp: int = (
			get_player_xp_required_for_next(
				player_level
			)
		)

		if player_xp < required_xp:
			break

		player_xp -= required_xp

		var level_before: int = player_level
		player_level += 1

		player_level_changed.emit(
			level_before,
			player_level
		)

		if debug_log:
			print(
				"[Progression] PLAYER LEVEL UP ",
				level_before,
				"->",
				player_level
			)

		_apply_player_milestone(player_level)
		_emit_automation_unlock_for_level(player_level)

	_emit_player_progress()

	if debug_log:
		print(
			"[Progression] player_xp +",
			amount,
			" level=",
			previous_level,
			"->",
			player_level,
			" xp=",
			previous_xp,
			"->",
			player_xp,
			" next=",
			get_player_xp_required_for_next(),
			" reason=",
			reason
		)

	return true


# Returns whether a player level is a reward milestone.
func is_player_milestone(level: int) -> bool:
	return (
		level > 0
		and level % PLAYER_MILESTONE_INTERVAL == 0
	)


# Returns the configured reward for one milestone level.
func get_player_milestone_reward(
	level: int
) -> Dictionary:
	if not is_player_milestone(level):
		return {}

	if PLAYER_MILESTONES.has(level):
		return (
			PLAYER_MILESTONES[level] as Dictionary
		).duplicate(true)

	if level > 50:
		return POST_50_MILESTONE_REWARD.duplicate(true)

	return {}


# Returns the next milestone level after the current player level.
func get_next_player_milestone_level() -> int:
	var interval: int = PLAYER_MILESTONE_INTERVAL
	return (
		(int(player_level / interval) + 1)
		* interval
	)


# Applies rewards attached to a ten-level player milestone.
func _apply_player_milestone(level: int) -> void:
	var reward: Dictionary = get_player_milestone_reward(
		level
	)

	if reward.is_empty():
		return

	var money_reward: int = int(
		reward.get("money", 0)
	)
	var unlock_tokens: int = int(
		reward.get("plant_unlock_tokens", 0)
	)
	var cell_credits: int = int(
		reward.get("build_cell_credits", 0)
	)

	if money_reward > 0:
		EconomySystem.add_money(
			money_reward,
			"PLAYER_LEVEL_%d_MILESTONE" % level
		)

	if unlock_tokens > 0:
		add_plant_unlock_tokens(
			unlock_tokens,
			"PLAYER_LEVEL_%d_MILESTONE" % level
		)

	if cell_credits > 0:
		add_build_cell_credits(
			cell_credits,
			"PLAYER_LEVEL_%d_MILESTONE" % level
		)

	player_milestone_reached.emit(
		level,
		money_reward,
		unlock_tokens,
		cell_credits
	)

	if debug_log:
		print(
			"[Progression] milestone level=",
			level,
			" money=",
			money_reward,
			" plant_unlock_tokens=",
			unlock_tokens,
			" build_cell_credits=",
			cell_credits,
			" total_unlock_tokens=",
			plant_unlock_tokens,
			" total_build_cell_credits=",
			build_cell_credits
		)


# Adds plant-unlock currency.
func add_plant_unlock_tokens(
	amount: int,
	reason: String = ""
) -> bool:
	if amount <= 0:
		return false

	var previous_amount: int = plant_unlock_tokens
	plant_unlock_tokens += amount

	plant_unlock_tokens_changed.emit(
		previous_amount,
		plant_unlock_tokens,
		amount,
		reason
	)

	if debug_log:
		print(
			"[Progression] plant_unlock_tokens +",
			amount,
			" old=",
			previous_amount,
			" new=",
			plant_unlock_tokens,
			" reason=",
			reason
		)

	return true


# Spends plant-unlock currency.
func spend_plant_unlock_tokens(
	amount: int = 1,
	reason: String = ""
) -> bool:
	if (
		amount <= 0
		or plant_unlock_tokens < amount
	):
		return false

	var previous_amount: int = plant_unlock_tokens
	plant_unlock_tokens -= amount

	plant_unlock_tokens_changed.emit(
		previous_amount,
		plant_unlock_tokens,
		-amount,
		reason
	)

	if debug_log:
		print(
			"[Progression] plant_unlock_tokens -",
			amount,
			" old=",
			previous_amount,
			" new=",
			plant_unlock_tokens,
			" reason=",
			reason
		)

	return true


# Adds terrain-expansion currency.
func add_build_cell_credits(
	amount: int,
	reason: String = ""
) -> bool:
	if amount <= 0:
		return false

	var previous_amount: int = build_cell_credits
	build_cell_credits += amount

	build_cell_credits_changed.emit(
		previous_amount,
		build_cell_credits,
		amount,
		reason
	)

	if debug_log:
		print(
			"[Progression] build_cell_credits +",
			amount,
			" old=",
			previous_amount,
			" new=",
			build_cell_credits,
			" reason=",
			reason
		)

	return true


# Returns whether the requested expansion cost can be paid.
func can_spend_build_cell_credits(amount: int) -> bool:
	return (
		amount > 0
		and build_cell_credits >= amount
	)


# Spends terrain-expansion currency.
func spend_build_cell_credits(
	amount: int,
	reason: String = ""
) -> bool:
	if not can_spend_build_cell_credits(amount):
		return false

	var previous_amount: int = build_cell_credits
	build_cell_credits -= amount

	build_cell_credits_changed.emit(
		previous_amount,
		build_cell_credits,
		-amount,
		reason
	)

	if debug_log:
		print(
			"[Progression] build_cell_credits -",
			amount,
			" old=",
			previous_amount,
			" new=",
			build_cell_credits,
			" reason=",
			reason
		)

	return true


# Returns the current player progression state.
func get_player_progress() -> Dictionary:
	return {
		"level": player_level,
		"xp": player_xp,
		"xp_to_next": get_player_xp_required_for_next(),
		"has_level_cap": false,
		"max_level": MAX_PLAYER_LEVEL,
		"next_milestone": get_next_player_milestone_level(),
		"plant_unlock_tokens": plant_unlock_tokens,
		"build_cell_credits": build_cell_credits
	}


# Returns whether one plant is permanently unlocked.
func is_plant_unlocked(plant_id: StringName) -> bool:
	if not TRACKED_PLANTS.has(plant_id):
		return false

	return bool(_plant_unlocked.get(plant_id, false))


# Returns the currently unlocked plant identifiers.
func get_unlocked_plant_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for plant_id: StringName in TRACKED_PLANTS:
		if is_plant_unlocked(plant_id):
			result.append(plant_id)

	return result


# Returns the currently locked plant identifiers.
func get_locked_plant_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for plant_id: StringName in TRACKED_PLANTS:
		if not is_plant_unlocked(plant_id):
			result.append(plant_id)

	return result


# Returns whether a plant can be unlocked with the current token balance.
func get_plant_unlock_status(
	plant_id: StringName
) -> Dictionary:
	if not TRACKED_PLANTS.has(plant_id):
		return {
			"ok": false,
			"reason": PLANT_UNLOCK_INVALID,
			"cost": 1
		}

	if is_plant_unlocked(plant_id):
		return {
			"ok": false,
			"reason": PLANT_UNLOCK_ALREADY_UNLOCKED,
			"cost": 1
		}

	if plant_unlock_tokens < 1:
		return {
			"ok": false,
			"reason": PLANT_UNLOCK_NO_TOKENS,
			"cost": 1,
			"available_tokens": plant_unlock_tokens
		}

	return {
		"ok": true,
		"reason": "",
		"cost": 1,
		"available_tokens": plant_unlock_tokens
	}


# Permanently unlocks one plant for one Plant Unlock Token.
func unlock_plant(plant_id: StringName) -> Dictionary:
	var status: Dictionary = get_plant_unlock_status(
		plant_id
	)

	if not bool(status.get("ok", false)):
		if debug_log:
			print(
				"[Progression] plant unlock failed id=",
				String(plant_id),
				" reason=",
				String(status.get("reason", ""))
			)

		return status

	if not spend_plant_unlock_tokens(
		1,
		"PLANT_UNLOCK_%s" % String(plant_id)
	):
		return {
			"ok": false,
			"reason": PLANT_UNLOCK_NO_TOKENS,
			"cost": 1
		}

	_plant_unlocked[plant_id] = true
	plant_unlock_changed.emit(plant_id, true)

	if debug_log:
		print(
			"[Progression] PLANT UNLOCKED id=",
			String(plant_id),
			" tokens_remaining=",
			plant_unlock_tokens
		)

	return {
		"ok": true,
		"reason": "",
		"plant_id": plant_id,
		"cost": 1,
		"tokens_remaining": plant_unlock_tokens
	}


# Registers a plant type for future content expansion.
func register_plant(plant_id: StringName) -> void:
	_ensure_plant(plant_id)
	_emit_plant_progress(plant_id)


# Ensures that a plant progression entry exists.
func _ensure_plant(plant_id: StringName) -> void:
	if not _plant_levels.has(plant_id):
		_plant_levels[plant_id] = 0

	if not _plant_xp.has(plant_id):
		_plant_xp[plant_id] = 0

	if not _plant_unlocked.has(plant_id):
		_plant_unlocked[plant_id] = false


# Returns the current mastery level of a plant type.
func get_plant_level(plant_id: StringName) -> int:
	_ensure_plant(plant_id)
	return int(_plant_levels.get(plant_id, 0))


# Returns the current mastery XP of a plant type.
func get_plant_xp(plant_id: StringName) -> int:
	_ensure_plant(plant_id)
	return int(_plant_xp.get(plant_id, 0))


# Returns the XP required for a plant's next mastery level.
func get_plant_xp_required_for_next(
	plant_id: StringName
) -> int:
	var level := get_plant_level(plant_id)

	if level >= MAX_PLANT_LEVEL:
		return 0

	return 5 * (level + 1)


# Adds mastery XP to one plant type.
func add_plant_xp(
	plant_id: StringName,
	amount: int,
	reason: String = ""
) -> bool:
	if amount <= 0:
		return false

	_ensure_plant(plant_id)

	var level := get_plant_level(plant_id)
	if level >= MAX_PLANT_LEVEL:
		return false

	var previous_level := level
	var previous_xp := get_plant_xp(plant_id)
	var applied_amount: int = amount + _get_random_event_plant_xp_bonus()
	var xp := previous_xp + applied_amount

	while level < MAX_PLANT_LEVEL:
		var required_xp := 5 * (level + 1)

		if xp < required_xp:
			break

		xp -= required_xp

		var level_before := level
		level += 1

		_plant_levels[plant_id] = level

		plant_level_changed.emit(
			plant_id,
			level_before,
			level
		)

		if debug_log:
			print(
				"[Progression] PLANT LEVEL UP id=",
				String(plant_id),
				" ",
				level_before,
				"->",
				level
			)

	if level >= MAX_PLANT_LEVEL:
		xp = 0

	_plant_levels[plant_id] = level
	_plant_xp[plant_id] = xp

	_emit_plant_progress(plant_id)

	if debug_log:
		print(
			"[Progression] plant_xp id=",
			String(plant_id),
			" +",
			applied_amount,
			" level=",
			previous_level,
			"->",
			level,
			" xp=",
			previous_xp,
			"->",
			xp,
			" next=",
			get_plant_xp_required_for_next(plant_id),
			" reason=",
			reason
		)

	return true


# Returns the complete progression state of one plant type.
func get_plant_progress(
	plant_id: StringName
) -> Dictionary:
	return {
		"plant_id": plant_id,
		"level": get_plant_level(plant_id),
		"xp": get_plant_xp(plant_id),
		"xp_to_next": get_plant_xp_required_for_next(
			plant_id
		),
		"max_level": MAX_PLANT_LEVEL
	}


# Returns harvest rewards for the current plant mastery band.
func get_harvest_rewards(
	plant_id: StringName
) -> Dictionary:
	var level := get_plant_level(plant_id)
	var seed_gain := 1
	var money_gain := 5
	var player_xp_gain := 20

	if level >= 8:
		seed_gain = 5
		money_gain = 25
		player_xp_gain = 100
	elif level >= 6:
		seed_gain = 4
		money_gain = 20
		player_xp_gain = 80
	elif level >= 4:
		seed_gain = 3
		money_gain = 15
		player_xp_gain = 60
	elif level >= 2:
		seed_gain = 2
		money_gain = 10
		player_xp_gain = 40

	money_gain = maxi(
		int(round(
			float(money_gain)
			* _get_random_event_harvest_multiplier()
		)),
		0
	)

	return {
		"plant_id": plant_id,
		"plant_level": level,
		"seed_gain": seed_gain,
		"money_gain": money_gain,
		"player_xp_gain": player_xp_gain
	}


# Registers a terrain progression entry.
func register_terrain(
	terrain_id: StringName,
	starting_level: int = 1
) -> void:
	if _terrain_levels.has(terrain_id):
		return

	_terrain_levels[terrain_id] = clampi(
		starting_level,
		1,
		MAX_TERRAIN_LEVEL
	)


# Returns one terrain's current level.
func get_terrain_level(terrain_id: StringName) -> int:
	if not _terrain_levels.has(terrain_id):
		register_terrain(terrain_id)

	return int(_terrain_levels.get(terrain_id, 1))


# Returns the next terrain upgrade cost.
func get_terrain_upgrade_cost(
	terrain_id: StringName
) -> int:
	var next_level := get_terrain_level(terrain_id) + 1
	return int(TERRAIN_UPGRADE_COSTS.get(next_level, 0))


# Returns the player level required for the next terrain upgrade.
func get_terrain_required_player_level(
	terrain_id: StringName
) -> int:
	var next_level := get_terrain_level(terrain_id) + 1
	return int(
		TERRAIN_REQUIRED_PLAYER_LEVELS.get(
			next_level,
			0
		)
	)


# Attempts to purchase one terrain level.
func upgrade_terrain(terrain_id: StringName) -> Dictionary:
	var current_level := get_terrain_level(terrain_id)

	if current_level >= MAX_TERRAIN_LEVEL:
		return {
			"ok": false,
			"reason": "MAX_TERRAIN_LEVEL"
		}

	var next_level := current_level + 1
	var required_player_level := get_terrain_required_player_level(
		terrain_id
	)
	var cost := get_terrain_upgrade_cost(terrain_id)

	if player_level < required_player_level:
		return {
			"ok": false,
			"reason": "PLAYER_LEVEL_TOO_LOW",
			"required_player_level": required_player_level
		}

	if not EconomySystem.spend_money(
		cost,
		"TERRAIN_UPGRADE_%s_L%d" % [
			String(terrain_id),
			next_level
		]
	):
		return {
			"ok": false,
			"reason": "INSUFFICIENT_MONEY",
			"cost": cost
		}

	_terrain_levels[terrain_id] = next_level
	terrain_level_changed.emit(
		terrain_id,
		current_level,
		next_level
	)

	if debug_log:
		print(
			"[Progression] terrain upgraded id=",
			String(terrain_id),
			" ",
			current_level,
			"->",
			next_level,
			" cost=",
			cost
		)

	return {
		"ok": true,
		"terrain_id": terrain_id,
		"previous_level": current_level,
		"new_level": next_level,
		"cost": cost
	}


# Registers an equipment progression entry.
func register_equipment(
	equipment_id: StringName,
	starting_level: int = 1
) -> void:
	if _equipment_levels.has(equipment_id):
		return

	_equipment_levels[equipment_id] = clampi(
		starting_level,
		1,
		MAX_EQUIPMENT_LEVEL
	)


# Returns one equipment item's current level.
func get_equipment_level(
	equipment_id: StringName
) -> int:
	if not _equipment_levels.has(equipment_id):
		register_equipment(equipment_id)

	return int(_equipment_levels.get(equipment_id, 1))


# Returns the next equipment upgrade cost.
func get_equipment_upgrade_cost(
	equipment_id: StringName
) -> int:
	var next_level := get_equipment_level(
		equipment_id
	) + 1

	return int(
		EQUIPMENT_UPGRADE_COSTS.get(next_level, 0)
	)


# Returns the player level required for the next equipment upgrade.
func get_equipment_required_player_level(
	equipment_id: StringName
) -> int:
	var next_level := get_equipment_level(
		equipment_id
	) + 1

	return int(
		EQUIPMENT_REQUIRED_PLAYER_LEVELS.get(
			next_level,
			0
		)
	)


# Returns the active level for one equipment item.
func _resolve_equipment_level(
	equipment_id: StringName,
	level_override: int
) -> int:
	if level_override >= 1:
		return clampi(
			level_override,
			1,
			MAX_EQUIPMENT_LEVEL
		)

	return get_equipment_level(equipment_id)


# Returns the common interaction-range bonus for an equipment level.
func get_equipment_range_bonus(
	equipment_id: StringName,
	level_override: int = -1
) -> int:
	var level: int = _resolve_equipment_level(
		equipment_id,
		level_override
	)

	if level >= 5:
		return 2

	if level >= 3:
		return 1

	return 0


# Returns the treatment or reward strength multiplier for supported equipment.
func get_equipment_effectiveness_multiplier(
	equipment_id: StringName,
	level_override: int = -1
) -> float:
	var level: int = _resolve_equipment_level(
		equipment_id,
		level_override
	)

	if equipment_id in [
		EQUIPMENT_WATERING_CAN,
		EQUIPMENT_FERTILIZER,
		EQUIPMENT_LIME,
		EQUIPMENT_ACID,
		EQUIPMENT_PESTICIDE,
		EQUIPMENT_FUNGICIDE,
		EQUIPMENT_HARVEST
	]:
		return 1.0 + (
			float(level - 1)
			* EQUIPMENT_EFFECT_BONUS_PER_LEVEL
		)

	return 1.0


# Returns the chance of recovering a seed when removing a plant.
func get_shovel_seed_recovery_chance(
	level_override: int = -1
) -> float:
	var level: int = _resolve_equipment_level(
		EQUIPMENT_SHOVEL,
		level_override
	)

	return clamp(
		float(level - 1)
		* SHOVEL_SEED_RECOVERY_PER_LEVEL,
		0.0,
		1.0
	)


# Returns gameplay modifiers for one equipment item.
func get_equipment_effects(
	equipment_id: StringName,
	level_override: int = -1
) -> Dictionary:
	var level: int = _resolve_equipment_level(
		equipment_id,
		level_override
	)
	var range_bonus: int = get_equipment_range_bonus(
		equipment_id,
		level
	)
	var effect_bonus: float = 0.0
	var seed_recovery_chance: float = 0.0

	if equipment_id == EQUIPMENT_SHOVEL:
		seed_recovery_chance = (
			get_shovel_seed_recovery_chance(level)
		)
	else:
		effect_bonus = (
			get_equipment_effectiveness_multiplier(
				equipment_id,
				level
			) - 1.0
		)

	return {
		"equipment_id": equipment_id,
		"level": level,
		"max_level": MAX_EQUIPMENT_LEVEL,
		"range_bonus": range_bonus,
		"effect_bonus": effect_bonus,
		"seed_recovery_chance": seed_recovery_chance
	}


# Attempts to purchase one equipment level.
func upgrade_equipment(
	equipment_id: StringName
) -> Dictionary:
	var current_level := get_equipment_level(
		equipment_id
	)

	if current_level >= MAX_EQUIPMENT_LEVEL:
		return {
			"ok": false,
			"reason": "MAX_EQUIPMENT_LEVEL"
		}

	var next_level := current_level + 1
	var required_player_level := (
		get_equipment_required_player_level(
			equipment_id
		)
	)
	var cost := get_equipment_upgrade_cost(
		equipment_id
	)

	if player_level < required_player_level:
		return {
			"ok": false,
			"reason": "PLAYER_LEVEL_TOO_LOW",
			"required_player_level": required_player_level
		}

	if not EconomySystem.spend_money(
		cost,
		"EQUIPMENT_UPGRADE_%s_L%d" % [
			String(equipment_id),
			next_level
		]
	):
		return {
			"ok": false,
			"reason": "INSUFFICIENT_MONEY",
			"cost": cost
		}

	_equipment_levels[equipment_id] = next_level
	equipment_level_changed.emit(
		equipment_id,
		current_level,
		next_level
	)

	if debug_log:
		print(
			"[Progression] equipment upgraded id=",
			String(equipment_id),
			" ",
			current_level,
			"->",
			next_level,
			" cost=",
			cost
		)

	return {
		"ok": true,
		"equipment_id": equipment_id,
		"previous_level": current_level,
		"new_level": next_level,
		"cost": cost
	}


# Emits the current player progression state.
func _get_random_event_system() -> Node:
	return get_node_or_null("/root/RandomEventSystem")


# Returns the random event plant XP bonus.
func _get_random_event_plant_xp_bonus() -> int:
	var event_system: Node = _get_random_event_system()

	if (
		event_system != null
		and event_system.has_method("get_plant_xp_flat_bonus")
	):
		return maxi(
			int(event_system.call("get_plant_xp_flat_bonus")),
			0
		)

	return 0


# Returns the random event harvest multiplier.
func _get_random_event_harvest_multiplier() -> float:
	var event_system: Node = _get_random_event_system()

	if (
		event_system != null
		and event_system.has_method("get_harvest_income_multiplier")
	):
		return clampf(
			float(event_system.call("get_harvest_income_multiplier")),
			0.25,
			3.0
		)

	return 1.0


# Emits the player progress.
func _emit_player_progress() -> void:
	player_progress_changed.emit(
		player_level,
		player_xp,
		get_player_xp_required_for_next()
	)


# Emits one plant type's current progression state.
func _emit_plant_progress(
	plant_id: StringName
) -> void:
	plant_progress_changed.emit(
		plant_id,
		get_plant_level(plant_id),
		get_plant_xp(plant_id),
		get_plant_xp_required_for_next(plant_id)
	)

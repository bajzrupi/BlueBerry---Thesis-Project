extends Node

# Selects, applies, and saves random garden events.

signal event_presented(event_id: StringName, event_type: StringName)
signal event_resolved(event_id: StringName, choice_id: StringName)
signal timed_effects_changed()
signal permanent_effects_changed()


const TYPE_POSITIVE: StringName = &"positive"
const TYPE_NEGATIVE: StringName = &"negative"
const TYPE_DECISION: StringName = &"decision"

const EVENT_PERFECT_WEATHER: StringName = &"perfect_weather"
const EVENT_BOTANICAL_GRANT: StringName = &"botanical_grant"
const EVENT_SEED_DONATION: StringName = &"seed_donation"
const EVENT_RESEARCH_BREAKTHROUGH: StringName = &"research_breakthrough"
const EVENT_MARKET_BOOM: StringName = &"market_boom"
const EVENT_EFFICIENT_IRRIGATION: StringName = &"efficient_irrigation"

const EVENT_SPRINKLER_BREAKDOWN: StringName = &"sprinkler_breakdown"
const EVENT_PEST_OUTBREAK: StringName = &"pest_outbreak"
const EVENT_FUNGAL_SPREAD: StringName = &"fungal_spread"
const EVENT_DROUGHT: StringName = &"drought"
const EVENT_WATER_SHORTAGE: StringName = &"water_shortage"
const EVENT_MARKET_SLUMP: StringName = &"market_slump"

const EVENT_EMERGENCY_MAINTENANCE: StringName = &"emergency_maintenance"
const EVENT_RARE_SEED_OFFER: StringName = &"rare_seed_offer"
const EVENT_SOIL_TREATMENT: StringName = &"soil_treatment"
const EVENT_EXPERIMENTAL_FERTILIZER: StringName = &"experimental_fertilizer"
const EVENT_GARDEN_INSPECTION: StringName = &"garden_inspection"
const EVENT_HEAT_PREPARATION: StringName = &"heat_preparation"

# Automation-machine events.
const EVENT_NUTRIENT_RICH_DELIVERY: StringName = &"nutrient_rich_delivery"
const EVENT_FERTILIZER_SHORTAGE: StringName = &"fertilizer_shortage"

const EVENT_SOIL_ANALYSIS_BREAKTHROUGH: StringName = &"soil_analysis_breakthrough"
const EVENT_REAGENT_CONTAMINATION: StringName = &"reagent_contamination"

const EVENT_BIOCONTROL_BREAKTHROUGH: StringName = &"biocontrol_breakthrough"
const EVENT_TREATMENT_RESISTANCE: StringName = &"treatment_resistance"

const EFFECT_PERFECT_WEATHER: StringName = &"perfect_weather"
const EFFECT_EFFICIENT_IRRIGATION: StringName = &"efficient_irrigation"
const EFFECT_SPRINKLER_BREAKDOWN: StringName = &"sprinkler_breakdown"
const EFFECT_DROUGHT: StringName = &"drought"
const EFFECT_WATER_SHORTAGE: StringName = &"water_shortage"
const EFFECT_EMERGENCY_WAIT: StringName = &"emergency_wait"
const EFFECT_SOIL_TREATMENT: StringName = &"soil_treatment"
const EFFECT_EXPERIMENTAL_FERTILIZER: StringName = &"experimental_fertilizer"
const EFFECT_HEAT_PREPARED: StringName = &"heat_prepared"
const EFFECT_HEAT_UNPREPARED: StringName = &"heat_unprepared"

# Automation-machine timed effects.
const EFFECT_NUTRIENT_RICH_DELIVERY: StringName = &"nutrient_rich_delivery"
const EFFECT_FERTILIZER_SHORTAGE: StringName = &"fertilizer_shortage"

const EFFECT_SOIL_ANALYSIS_BREAKTHROUGH: StringName = &"soil_analysis_breakthrough"
const EFFECT_REAGENT_CONTAMINATION: StringName = &"reagent_contamination"

const EFFECT_BIOCONTROL_BREAKTHROUGH: StringName = &"biocontrol_breakthrough"
const EFFECT_TREATMENT_RESISTANCE: StringName = &"treatment_resistance"


@export_category("Event Roll")

# Standard daily roll chance when no major timed event is already active.
@export_range(0.0, 1.0, 0.01)
var daily_event_chance: float = 0.15

# Give a fresh Garden a short calm opening.
@export_range(1, 30, 1)
var first_event_day: int = 3

# Prevent event spam even when immediate events occur on consecutive rolls.
@export_range(0, 30, 1)
var minimum_days_between_events: int = 2

# The same event cannot naturally repeat inside this window.
@export_range(0, 60, 1)
var same_event_cooldown_days: int = 10


@export_category("Balance")

@export var botanical_grant_money: int = 100
@export var seed_donation_total: int = 5

# Rare permanent research bonus: each future Plant XP award gets +1 XP.
@export var research_plant_xp_flat_bonus: int = 1

# Rare permanent market shifts.
@export_range(1.0, 2.0, 0.01)
var market_boom_multiplier: float = 1.10

@export_range(0.1, 1.0, 0.01)
var market_slump_multiplier: float = 0.90

@export var emergency_repair_cost: int = 80
@export var rare_seed_offer_cost: int = 60
@export var rare_seed_offer_amount: int = 8
@export var soil_treatment_cost: int = 60
@export var heat_preparation_cost: int = 50


@export_category("Automation Event Balance")

@export_range(1, 10, 1)
var automation_event_duration_days: int = 3

@export_range(1.0, 2.0, 0.05)
var automation_positive_strength_multiplier: float = 1.30

@export_range(0.1, 1.0, 0.05)
var automation_negative_strength_multiplier: float = 0.65


@export_category("Popup UI")

@export var popup_canvas_layer: int = 32
@export_range(620.0, 920.0, 10.0)
var popup_width: float = 760.0


@export_category("Debug Logging")

# Event diagnostics are kept, but disabled by default.
@export var debug_log: bool = false


var _catalog: Dictionary = {}
var _catalog_order: Array[StringName] = []

# Timed effect entries:
# {
#   "effect_id": String,
#   "source_event": String,
#   "start_day": int,
#   "end_day": int
# }
var _active_timed_effects: Array[Dictionary] = []

# Event history / anti-repeat state.
var _event_last_day: Dictionary = {}
var _completed_unique: Dictionary = {}
var _last_any_event_day: int = -999999

# Permanent progression modifiers.
var _plant_xp_flat_bonus: int = 0
var _harvest_income_multiplier: float = 1.0

# Current unresolved popup.
var _pending_event_id: StringName = &""
var _pending_event: Dictionary = {}

# Modal state.
var _previous_tree_paused: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

# Runtime UI.
var _canvas: CanvasLayer
var _overlay: ColorRect
var _panel: PanelContainer
var _chronicle_label: Label
var _day_label: Label
var _category_label: Label
var _title_label: Label
var _body_frame: PanelContainer
var _body_label: RichTextLabel
var _hint_label: Label
var _single_button: Button
var _decision_row: HBoxContainer
var _choice_a_button: Button
var _choice_b_button: Button
var _consequence_panel: PanelContainer
var _consequence_header: Label
var _consequence_label: Label
var _bottom_ornament: Label

var _single_consequence: String = ""
var _choice_a_id: StringName = &""
var _choice_b_id: StringName = &""
var _choice_a_consequence: String = ""
var _choice_b_consequence: String = ""


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()

	_build_catalog()
	_build_popup_ui()
	reset_to_defaults()

	if not Clock.day_changed.is_connected(_on_day_changed):
		Clock.day_changed.connect(_on_day_changed)

	if not ProgressionSystem.progression_reset.is_connected(
		_on_progression_reset
	):
		ProgressionSystem.progression_reset.connect(
			_on_progression_reset
		)

	if debug_log:
		print(
			"[RandomEvent] ready events=",
			_catalog.size(),
			" chance=",
			daily_event_chance,
			" first_day=",
			first_event_day,
			" repeat_cooldown=",
			same_event_cooldown_days
		)


# Restores this system to its default state.
func reset_to_defaults() -> void:
	_active_timed_effects.clear()
	_event_last_day.clear()
	_completed_unique.clear()
	_last_any_event_day = -999999
	_plant_xp_flat_bonus = 0
	_harvest_income_multiplier = 1.0
	_pending_event_id = &""
	_pending_event = {}
	if _overlay != null:
		_overlay.visible = false

	_notify_modifier_change()

	if debug_log:
		print("[RandomEvent] reset to defaults")


# Handles the progression reset signal or callback.
func _on_progression_reset() -> void:
	# New Game and SaveSystem load both reset progression first. During load,
	# SaveSystem restores this system's state immediately afterwards.
	reset_to_defaults()


# Handles simulation updates triggered by a new day.
func _on_day_changed(new_day: int) -> void:
	_expire_timed_effects(new_day)

	if not _is_gameplay_world_active():
		return

	if _pending_event_id != &"":
		return

	if new_day < first_event_day:
		return

	# Standard random flow allows only one major/timed situation at once.
	if not _active_timed_effects.is_empty():
		if debug_log:
			print(
				"[RandomEvent] roll skipped active_timed=",
				_active_timed_effects.size(),
				" day=",
				new_day
			)
		return

	if (
		new_day - _last_any_event_day
		< minimum_days_between_events
	):
		return

	if randf() > daily_event_chance:
		if debug_log:
			print(
				"[RandomEvent] no event day=",
				new_day
			)
		return

	var event_id: StringName = _roll_weighted_event(new_day)

	if event_id == &"":
		if debug_log:
			print(
				"[RandomEvent] roll had no eligible event day=",
				new_day
			)
		return

	_present_event(event_id)


# Returns the serializable state of this system.
func get_save_state() -> Dictionary:
	var event_last_day_safe: Dictionary = {}

	for key_variant: Variant in _event_last_day.keys():
		event_last_day_safe[String(key_variant)] = int(
			_event_last_day[key_variant]
		)

	var completed_unique_safe: Array[String] = []

	for key_variant: Variant in _completed_unique.keys():
		if bool(_completed_unique[key_variant]):
			completed_unique_safe.append(String(key_variant))

	var timed_safe: Array[Dictionary] = []

	for effect: Dictionary in _active_timed_effects:
		timed_safe.append({
			"effect_id": String(effect.get("effect_id", "")),
			"source_event": String(effect.get("source_event", "")),
			"start_day": int(effect.get("start_day", Clock.day)),
			"end_day": int(effect.get("end_day", Clock.day))
		})

	return {
		"event_last_day": event_last_day_safe,
		"completed_unique": completed_unique_safe,
		"last_any_event_day": _last_any_event_day,
		"plant_xp_flat_bonus": _plant_xp_flat_bonus,
		"harvest_income_multiplier": _harvest_income_multiplier,
		"active_timed_effects": timed_safe
	}


# Restores this system from saved data.
func load_save_state(state: Dictionary) -> bool:
	# Never restore an unresolved popup. Saves occur outside the event modal,
	# so only applied consequences need persistence.
	_pending_event_id = &""
	_pending_event = {}

	_event_last_day.clear()
	_completed_unique.clear()
	_active_timed_effects.clear()

	var saved_last: Dictionary = _dictionary_value(
		state.get("event_last_day", {})
	)

	for key_variant: Variant in saved_last.keys():
		_event_last_day[StringName(String(key_variant))] = int(
			saved_last[key_variant]
		)

	var saved_unique: Array = _array_value(
		state.get("completed_unique", [])
	)

	for event_variant: Variant in saved_unique:
		_completed_unique[StringName(String(event_variant))] = true

	_last_any_event_day = int(
		state.get("last_any_event_day", -999999)
	)
	_plant_xp_flat_bonus = maxi(
		int(state.get("plant_xp_flat_bonus", 0)),
		0
	)
	_harvest_income_multiplier = clampf(
		float(state.get("harvest_income_multiplier", 1.0)),
		0.25,
		3.0
	)
	var saved_timed: Array = _array_value(
		state.get("active_timed_effects", [])
	)

	for entry_variant: Variant in saved_timed:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_variant
		var effect_id := StringName(
			String(entry.get("effect_id", ""))
		)
		var end_day: int = int(
			entry.get("end_day", Clock.day)
		)

		if effect_id == &"" or end_day <= Clock.day:
			continue

		_active_timed_effects.append({
			"effect_id": String(effect_id),
			"source_event": String(
				entry.get("source_event", "")
			),
			"start_day": int(
				entry.get("start_day", Clock.day)
			),
			"end_day": end_day
		})

	_notify_modifier_change()

	if debug_log:
		print(
			"[RandomEvent] save state loaded timed=",
			_active_timed_effects.size(),
			" permanent_xp_bonus=",
			_plant_xp_flat_bonus,
			" harvest_x=",
			_harvest_income_multiplier,
			" last_day=",
			_last_any_event_day
		)

	return true


# ------------------------------------------------------------------
# Public gameplay modifiers
# ------------------------------------------------------------------

# Returns the plant growth multiplier.
func get_plant_growth_multiplier() -> float:
	var multiplier: float = 1.0

	if has_timed_effect(EFFECT_PERFECT_WEATHER):
		multiplier *= 1.25

	if has_timed_effect(EFFECT_EXPERIMENTAL_FERTILIZER):
		multiplier *= 1.25

	return clampf(multiplier, 0.25, 3.0)


# Returns the soil drying multiplier.
func get_soil_drying_multiplier() -> float:
	var multiplier: float = 1.0

	if has_timed_effect(EFFECT_DROUGHT):
		multiplier *= 1.50

	if has_timed_effect(EFFECT_SOIL_TREATMENT):
		multiplier *= 0.75

	if has_timed_effect(EFFECT_HEAT_PREPARED):
		multiplier *= 0.75

	if has_timed_effect(EFFECT_HEAT_UNPREPARED):
		multiplier *= 1.25

	return clampf(multiplier, 0.35, 3.0)


# Returns the sprinkler strength multiplier.
func get_sprinkler_strength_multiplier() -> float:
	var multiplier: float = 1.0

	if has_timed_effect(EFFECT_EFFICIENT_IRRIGATION):
		multiplier *= 1.30

	return clampf(multiplier, 0.25, 3.0)


# Returns the sprinkler interval multiplier.
func get_sprinkler_interval_multiplier() -> float:
	var multiplier: float = 1.0

	if has_timed_effect(EFFECT_WATER_SHORTAGE):
		multiplier *= 2.0

	return clampf(multiplier, 0.5, 4.0)


# Returns the fertilizer injector strength multiplier.
func get_fertilizer_injector_strength_multiplier() -> float:
	var multiplier: float = 1.0

	if has_timed_effect(EFFECT_NUTRIENT_RICH_DELIVERY):
		multiplier *= automation_positive_strength_multiplier

	if has_timed_effect(EFFECT_FERTILIZER_SHORTAGE):
		multiplier *= automation_negative_strength_multiplier

	return clampf(multiplier, 0.25, 3.0)


# Returns the soil neutralizer strength multiplier.
func get_soil_neutralizer_strength_multiplier() -> float:
	var multiplier: float = 1.0

	if has_timed_effect(EFFECT_SOIL_ANALYSIS_BREAKTHROUGH):
		multiplier *= automation_positive_strength_multiplier

	if has_timed_effect(EFFECT_REAGENT_CONTAMINATION):
		multiplier *= automation_negative_strength_multiplier

	return clampf(multiplier, 0.25, 3.0)


# Returns the plant protection strength multiplier.
func get_plant_protection_strength_multiplier() -> float:
	var multiplier: float = 1.0

	if has_timed_effect(EFFECT_BIOCONTROL_BREAKTHROUGH):
		multiplier *= automation_positive_strength_multiplier

	if has_timed_effect(EFFECT_TREATMENT_RESISTANCE):
		multiplier *= automation_negative_strength_multiplier

	return clampf(multiplier, 0.25, 3.0)


# Handles are sprinklers disabled.
func are_sprinklers_disabled() -> bool:
	return (
		has_timed_effect(EFFECT_SPRINKLER_BREAKDOWN)
		or has_timed_effect(EFFECT_EMERGENCY_WAIT)
	)


# Returns the plant XP flat bonus.
func get_plant_xp_flat_bonus() -> int:
	return _plant_xp_flat_bonus


# Returns the harvest income multiplier.
func get_harvest_income_multiplier() -> float:
	return _harvest_income_multiplier


# Checks whether timed effect exists or is available.
func has_timed_effect(effect_id: StringName) -> bool:
	for entry: Dictionary in _active_timed_effects:
		if StringName(String(entry.get("effect_id", ""))) == effect_id:
			return true

	return false


# Returns the active timed effects.
func get_active_timed_effects() -> Array[Dictionary]:
	return _active_timed_effects.duplicate(true)


# ------------------------------------------------------------------
# Event rolling / eligibility
# ------------------------------------------------------------------

# Randomly selects weighted event using the configured probabilities.
func _roll_weighted_event(day: int) -> StringName:
	var eligible: Array[StringName] = []
	var total_weight: int = 0

	for event_id: StringName in _catalog_order:
		var definition: Dictionary = _catalog.get(event_id, {})

		if not _is_event_eligible(event_id, definition, day):
			continue

		var weight: int = maxi(
			int(definition.get("weight", 1)),
			0
		)

		if weight <= 0:
			continue

		eligible.append(event_id)
		total_weight += weight

	if eligible.is_empty() or total_weight <= 0:
		return &""

	var roll: int = randi() % total_weight
	var accumulator: int = 0

	for event_id: StringName in eligible:
		var definition: Dictionary = _catalog[event_id]
		accumulator += maxi(
			int(definition.get("weight", 1)),
			0
		)

		if roll < accumulator:
			return event_id

	return eligible.back()


# Checks the event eligible condition.
func _is_event_eligible(
	event_id: StringName,
	definition: Dictionary,
	day: int
) -> bool:
	if definition.is_empty():
		return false

	var min_level: int = maxi(
		int(definition.get("min_player_level", 0)),
		0
	)

	if ProgressionSystem.player_level < min_level:
		return false

	if bool(definition.get("unique_once", false)):
		if bool(_completed_unique.get(event_id, false)):
			return false

	if _event_last_day.has(event_id):
		var previous_day: int = int(_event_last_day[event_id])

		if day - previous_day < same_event_cooldown_days:
			return false

	if bool(definition.get("requires_sprinkler", false)):
		if SprinklerSystem.get_sprinkler_cells().is_empty():
			return false

	if bool(
		definition.get(
			"requires_fertilizer_injector",
			false
		)
	):
		if FertilizerInjectorSystem.get_machine_cells().is_empty():
			return false

	if bool(
		definition.get(
			"requires_soil_neutralizer",
			false
		)
	):
		if SoilNeutralizerSystem.get_machine_cells().is_empty():
			return false

	if bool(
		definition.get(
			"requires_plant_protection",
			false
		)
	):
		if PlantProtectionStationSystem.get_machine_cells().is_empty():
			return false

	if bool(definition.get("requires_plants", false)):
		if _get_unique_plants().is_empty():
			return false

	return true


# ------------------------------------------------------------------
# Event resolution
# ------------------------------------------------------------------

# Handles present event.
func _present_event(
	event_id: StringName
) -> bool:
	if _pending_event_id != &"":
		return false

	var definition: Dictionary = _catalog.get(event_id, {})

	if definition.is_empty():
		return false

	_pending_event_id = event_id
	_pending_event = definition.duplicate(true)

	_configure_popup_for_event(event_id, _pending_event)
	_open_modal()

	event_presented.emit(
		event_id,
		StringName(String(definition.get("type", "")))
	)

	if debug_log:
		print(
			"[RandomEvent] PRESENT id=",
			String(event_id),
			" type=",
			String(definition.get("type", "")),
			" day=",
			Clock.day
		)

	return true


# Handles the single ok pressed signal or callback.
func _on_single_ok_pressed() -> void:
	if _pending_event_id == &"":
		return

	var event_id: StringName = _pending_event_id
	_apply_event_effect(event_id, &"")
	_complete_event(event_id, &"ok")
	_close_modal()


# Handles the choice pressed signal or callback.
func _on_choice_pressed(choice_id: StringName) -> void:
	if _pending_event_id == &"":
		return

	var event_id: StringName = _pending_event_id
	var success: bool = _apply_event_effect(
		event_id,
		choice_id
	)

	if not success:
		return

	_complete_event(event_id, choice_id)
	_close_modal()


# Completes the event.
func _complete_event(
	event_id: StringName,
	choice_id: StringName
) -> void:
	var definition: Dictionary = _catalog.get(event_id, {})
	var day: int = Clock.day

	_event_last_day[event_id] = day
	_last_any_event_day = day

	if bool(definition.get("unique_once", false)):
		_completed_unique[event_id] = true

	event_resolved.emit(event_id, choice_id)

	if debug_log:
		print(
			"[RandomEvent] RESOLVED id=",
			String(event_id),
			" choice=",
			String(choice_id),
			" day=",
			day,
			" timed=",
			_active_timed_effects.size(),
			" xp_bonus=",
			_plant_xp_flat_bonus,
			" harvest_x=",
			_harvest_income_multiplier
		)


# Applies the event effect.
func _apply_event_effect(
	event_id: StringName,
	choice_id: StringName
) -> bool:
	match event_id:
		EVENT_PERFECT_WEATHER:
			_start_timed_effect(
				EFFECT_PERFECT_WEATHER,
				3,
				event_id
			)

		EVENT_BOTANICAL_GRANT:
			EconomySystem.add_money(
				botanical_grant_money,
				"RANDOM_EVENT_BOTANICAL_GRANT"
			)

		EVENT_SEED_DONATION:
			_grant_random_unlocked_seeds(
				seed_donation_total
			)

		EVENT_RESEARCH_BREAKTHROUGH:
			_plant_xp_flat_bonus += maxi(
				research_plant_xp_flat_bonus,
				0
			)
			permanent_effects_changed.emit()

		EVENT_MARKET_BOOM:
			_harvest_income_multiplier = clampf(
				_harvest_income_multiplier
				* market_boom_multiplier,
				0.25,
				3.0
			)
			permanent_effects_changed.emit()

		EVENT_EFFICIENT_IRRIGATION:
			_start_timed_effect(
				EFFECT_EFFICIENT_IRRIGATION,
				3,
				event_id
			)

		EVENT_SPRINKLER_BREAKDOWN:
			_start_timed_effect(
				EFFECT_SPRINKLER_BREAKDOWN,
				3,
				event_id
			)

		EVENT_PEST_OUTBREAK:
			_infect_random_plants(
				&"pest",
				1,
				3,
				0.35
			)

		EVENT_FUNGAL_SPREAD:
			_infect_random_plants(
				&"disease",
				1,
				3,
				0.30
			)

		EVENT_DROUGHT:
			_start_timed_effect(
				EFFECT_DROUGHT,
				3,
				event_id
			)

		EVENT_WATER_SHORTAGE:
			_start_timed_effect(
				EFFECT_WATER_SHORTAGE,
				3,
				event_id
			)

		EVENT_MARKET_SLUMP:
			_harvest_income_multiplier = clampf(
				_harvest_income_multiplier
				* market_slump_multiplier,
				0.25,
				3.0
			)
			permanent_effects_changed.emit()

		EVENT_EMERGENCY_MAINTENANCE:
			if choice_id == &"pay_now":
				if not EconomySystem.spend_money(
					emergency_repair_cost,
					"RANDOM_EVENT_EMERGENCY_REPAIR"
				):
					_show_consequence(
						"THE TREASURY OBJECTS\n\n"
						+ "You need $%d for immediate repairs. " % emergency_repair_cost
						+ "The cheaper crew remains available."
					)
					return false
			else:
				_start_timed_effect(
					EFFECT_EMERGENCY_WAIT,
					4,
					event_id
				)

		EVENT_RARE_SEED_OFFER:
			if choice_id == &"buy":
				if not EconomySystem.spend_money(
					rare_seed_offer_cost,
					"RANDOM_EVENT_RARE_SEED_OFFER"
				):
					_show_consequence(
						"A MINOR FINANCIAL OBSTACLE\n\n"
						+ "The merchant requests $%d. " % rare_seed_offer_cost
						+ "Your purse requests mercy."
					)
					return false

				_grant_random_unlocked_seeds(
					rare_seed_offer_amount
				)

		EVENT_SOIL_TREATMENT:
			if choice_id == &"treat":
				if not EconomySystem.spend_money(
					soil_treatment_cost,
					"RANDOM_EVENT_SOIL_TREATMENT"
				):
					_show_consequence(
						"THE SOIL MAY BE RICH. YOU ARE NOT.\n\n"
						+ "The treatment costs $%d." % soil_treatment_cost
					)
					return false

				_start_timed_effect(
					EFFECT_SOIL_TREATMENT,
					5,
					event_id
				)

		EVENT_EXPERIMENTAL_FERTILIZER:
			if choice_id == &"experiment":
				_start_timed_effect(
					EFFECT_EXPERIMENTAL_FERTILIZER,
					3,
					event_id
				)

				if randf() < 0.35:
					_infect_random_plants(
						&"disease",
						1,
						1,
						0.18
					)

		EVENT_GARDEN_INSPECTION:
			if choice_id == &"inspect":
				_resolve_garden_inspection()

		EVENT_HEAT_PREPARATION:
			if choice_id == &"prepare":
				if not EconomySystem.spend_money(
					heat_preparation_cost,
					"RANDOM_EVENT_HEAT_PREPARATION"
				):
					_show_consequence(
						"PREPARATION HAS A PRICE\n\n"
						+ "You need $%d to prepare the garden." % heat_preparation_cost
					)
					return false

				_start_timed_effect(
					EFFECT_HEAT_PREPARED,
					4,
					event_id
				)
			else:
				_start_timed_effect(
					EFFECT_HEAT_UNPREPARED,
					4,
					event_id
				)

		EVENT_NUTRIENT_RICH_DELIVERY:
			_start_timed_effect(
				EFFECT_NUTRIENT_RICH_DELIVERY,
				automation_event_duration_days,
				event_id
			)

		EVENT_FERTILIZER_SHORTAGE:
			_start_timed_effect(
				EFFECT_FERTILIZER_SHORTAGE,
				automation_event_duration_days,
				event_id
			)

		EVENT_SOIL_ANALYSIS_BREAKTHROUGH:
			_start_timed_effect(
				EFFECT_SOIL_ANALYSIS_BREAKTHROUGH,
				automation_event_duration_days,
				event_id
			)

		EVENT_REAGENT_CONTAMINATION:
			_start_timed_effect(
				EFFECT_REAGENT_CONTAMINATION,
				automation_event_duration_days,
				event_id
			)

		EVENT_BIOCONTROL_BREAKTHROUGH:
			_start_timed_effect(
				EFFECT_BIOCONTROL_BREAKTHROUGH,
				automation_event_duration_days,
				event_id
			)

		EVENT_TREATMENT_RESISTANCE:
			_start_timed_effect(
				EFFECT_TREATMENT_RESISTANCE,
				automation_event_duration_days,
				event_id
			)

		_:
			return false

	return true


# Starts the timed effect.
func _start_timed_effect(
	effect_id: StringName,
	duration_days: int,
	source_event: StringName
) -> void:
	var safe_duration: int = maxi(duration_days, 1)
	var end_day: int = Clock.day + safe_duration

	# Refresh an existing effect instead of storing duplicates.
	for index: int in range(_active_timed_effects.size()):
		var existing: Dictionary = _active_timed_effects[index]

		if StringName(String(existing.get("effect_id", ""))) == effect_id:
			existing["start_day"] = Clock.day
			existing["end_day"] = end_day
			existing["source_event"] = String(source_event)
			_active_timed_effects[index] = existing
			_notify_modifier_change(
				_is_sprinkler_modifier_effect(effect_id)
			)
			return

	_active_timed_effects.append({
		"effect_id": String(effect_id),
		"source_event": String(source_event),
		"start_day": Clock.day,
		"end_day": end_day
	})

	_notify_modifier_change(
		_is_sprinkler_modifier_effect(effect_id)
	)

	if debug_log:
		print(
			"[RandomEvent] timed effect start id=",
			String(effect_id),
			" day=",
			Clock.day,
			" end_day=",
			end_day
		)


# Handles expire timed effects.
func _expire_timed_effects(day: int) -> void:
	if _active_timed_effects.is_empty():
		return

	var kept: Array[Dictionary] = []
	var expired: Array[String] = []
	var sprinkler_modifier_expired: bool = false

	for entry: Dictionary in _active_timed_effects:
		var end_day: int = int(
			entry.get("end_day", day)
		)

		if day >= end_day:
			var expired_id := StringName(
				String(
					entry.get("effect_id", "")
				)
			)
			expired.append(String(expired_id))

			if _is_sprinkler_modifier_effect(
				expired_id
			):
				sprinkler_modifier_expired = true

			continue

		# Still active: preserve it exactly as saved/started.
		kept.append(entry)

	if expired.is_empty():
		return

	_active_timed_effects = kept
	_notify_modifier_change(
		sprinkler_modifier_expired
	)

	if debug_log:
		print(
			"[RandomEvent] timed effects expired day=",
			day,
			" ids=",
			expired,
			" remaining=",
			_active_timed_effects.size()
		)


# Notifies listeners about the modifier change.
func _notify_modifier_change(
	reschedule_sprinklers: bool = true
) -> void:
	timed_effects_changed.emit()

	if not reschedule_sprinklers:
		return

	var sprinkler_system: Node = get_node_or_null(
		"/root/SprinklerSystem"
	)

	if (
		sprinkler_system != null
		and sprinkler_system.has_method(
			"reschedule_all_from_now"
		)
	):
		sprinkler_system.call(
			"reschedule_all_from_now"
		)

	if debug_log:
		print(
			"[RandomEvent] sprinkler modifiers refreshed disabled=",
			are_sprinklers_disabled(),
			" interval_x=",
			get_sprinkler_interval_multiplier(),
			" strength_x=",
			get_sprinkler_strength_multiplier()
		)


# Checks the sprinkler modifier effect condition.
func _is_sprinkler_modifier_effect(
	effect_id: StringName
) -> bool:
	return effect_id in [
		EFFECT_EFFICIENT_IRRIGATION,
		EFFECT_SPRINKLER_BREAKDOWN,
		EFFECT_WATER_SHORTAGE,
		EFFECT_EMERGENCY_WAIT
	]


# ------------------------------------------------------------------
# Immediate effect helpers
# ------------------------------------------------------------------

# Handles grant random unlocked seeds.
func _grant_random_unlocked_seeds(total_amount: int) -> void:
	var amount_left: int = maxi(total_amount, 0)

	if amount_left <= 0:
		return

	var unlocked: Array[StringName] = (
		ProgressionSystem.get_unlocked_plant_ids()
	)

	if unlocked.is_empty():
		unlocked.append(&"lily_seed")

	while amount_left > 0:
		var item_id: StringName = unlocked[
			randi() % unlocked.size()
		]

		if InventorySystem.add_item(item_id, 1):
			amount_left -= 1
		else:
			# A full stack should not trap the event in an infinite loop.
			break


# Applies infection to the random plants.
func _infect_random_plants(
	kind: StringName,
	minimum_count: int,
	maximum_count: int,
	amount: float
) -> int:
	var plants: Array[Node] = _get_unique_plants()

	if plants.is_empty():
		return 0

	plants.shuffle()

	var min_count: int = clampi(
		minimum_count,
		1,
		plants.size()
	)
	var max_count: int = clampi(
		maximum_count,
		min_count,
		plants.size()
	)
	var target_count: int = randi_range(
		min_count,
		max_count
	)
	var applied: int = 0

	for index: int in range(target_count):
		var plant: Node = plants[index]

		if kind == &"pest" and plant.has_method("receive_pest_seed"):
			plant.call("receive_pest_seed", amount)
			applied += 1
		elif kind == &"disease" and plant.has_method("receive_disease_seed"):
			plant.call("receive_disease_seed", amount)
			applied += 1

	if debug_log:
		print(
			"[RandomEvent] infection kind=",
			String(kind),
			" targets=",
			applied,
			" amount=",
			amount
		)

	return applied


# Resolves the garden inspection.
func _resolve_garden_inspection() -> void:
	var plants: Array[Node] = _get_unique_plants()

	if plants.is_empty():
		return

	var total_ratio: float = 0.0
	var counted: int = 0

	for plant: Node in plants:
		if not is_instance_valid(plant):
			continue

		var health: float = float(plant.get("health"))
		var data_variant: Variant = plant.get("data")
		var max_health: float = 100.0

		if data_variant is Object:
			var data_object := data_variant as Object
			max_health = maxf(
				float(data_object.get("max_health")),
				1.0
			)

		total_ratio += clampf(
			health / max_health,
			0.0,
			1.0
		)
		counted += 1

	if counted <= 0:
		return

	var average_ratio: float = total_ratio / float(counted)
	var reward: int = 0

	if average_ratio >= 0.80:
		reward = 100
	elif average_ratio >= 0.60:
		reward = 50

	if reward > 0:
		EconomySystem.add_money(
			reward,
			"RANDOM_EVENT_GARDEN_INSPECTION"
		)

	if debug_log:
		print(
			"[RandomEvent] inspection plants=",
			counted,
			" avg_health=",
			snappedf(average_ratio * 100.0, 0.1),
			" reward=",
			reward
		)


# Returns the unique plants.
func _get_unique_plants() -> Array[Node]:
	var result: Array[Node] = []
	var seen: Dictionary = {}
	var registry_variant: Variant = PlantRegistry.get("plants_by_cell")

	if typeof(registry_variant) != TYPE_DICTIONARY:
		return result

	var registry: Dictionary = registry_variant

	for plant_variant: Variant in registry.values():
		if not (plant_variant is Node):
			continue

		var plant := plant_variant as Node

		if not is_instance_valid(plant):
			continue

		if bool(plant.get("is_dead")):
			continue

		var instance_id: int = plant.get_instance_id()

		if seen.has(instance_id):
			continue

		seen[instance_id] = true
		result.append(plant)

	return result


# ------------------------------------------------------------------
# Popup UI
# ------------------------------------------------------------------

# Builds the popup UI.
func _build_popup_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "RandomEventCanvas"
	_canvas.layer = popup_canvas_layer
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	_overlay = ColorRect.new()
	_overlay.name = "EventOverlay"
	_overlay.visible = false
	_overlay.color = Color(0.008, 0.007, 0.006, 0.72)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_canvas.add_child(_overlay)

	# Main event card. The deliberately narrow, tall composition is meant to
	# feel more like a grand-strategy event parchment than a generic menu.
	_panel = PanelContainer.new()
	_panel.name = "EventCard"
	_panel.custom_minimum_size = Vector2(
		popup_width,
		0.0
	)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(
		"panel",
		_make_event_card_style(
			Color(0.70, 0.54, 0.24, 0.95)
		)
	)
	_panel.set_anchors_preset(
		Control.PRESET_CENTER
	)
	_panel.position = Vector2(
		-popup_width * 0.5,
		-305.0
	)
	_overlay.add_child(_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override(
		"margin_left",
		30
	)
	outer_margin.add_theme_constant_override(
		"margin_right",
		30
	)
	outer_margin.add_theme_constant_override(
		"margin_top",
		20
	)
	outer_margin.add_theme_constant_override(
		"margin_bottom",
		22
	)
	_panel.add_child(outer_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(
		"separation",
		9
	)
	outer_margin.add_child(column)

	# Chronicle masthead.
	var masthead := HBoxContainer.new()
	masthead.add_theme_constant_override(
		"separation",
		10
	)
	column.add_child(masthead)

	var left_ornament := _make_label(
		"◆ ─────",
		10,
		Color(0.52, 0.43, 0.27, 0.88)
	)
	left_ornament.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	left_ornament.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	masthead.add_child(left_ornament)

	_chronicle_label = _make_label(
		"THE GARDEN CHRONICLE",
		11,
		Color(0.76, 0.66, 0.43, 1.0)
	)
	_chronicle_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	masthead.add_child(_chronicle_label)

	var right_ornament := _make_label(
		"───── ◆",
		10,
		Color(0.52, 0.43, 0.27, 0.88)
	)
	right_ornament.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	right_ornament.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	right_ornament.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	masthead.add_child(right_ornament)

	_day_label = _make_label(
		"DAY 1",
		10,
		Color(0.58, 0.53, 0.42, 0.92)
	)
	_day_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_day_label)

	_category_label = _make_label(
		"AN EVENT",
		12,
		Color(0.90, 0.80, 0.52, 1.0)
	)
	_category_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_category_label)

	_title_label = _make_label(
		"EVENT TITLE",
		27,
		Color(0.99, 0.94, 0.78, 1.0)
	)
	_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_title_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	column.add_child(_title_label)

	var title_ornament := _make_label(
		"— ◆ —",
		13,
		Color(0.64, 0.50, 0.26, 0.88)
	)
	title_ornament.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(title_ornament)

	# The story text sits inside its own inset parchment-like frame.
	_body_frame = PanelContainer.new()
	_body_frame.name = "EventStoryFrame"
	_body_frame.custom_minimum_size = Vector2(
		0.0,
		206.0
	)
	_body_frame.add_theme_stylebox_override(
		"panel",
		_make_story_style()
	)
	column.add_child(_body_frame)

	var story_margin := MarginContainer.new()
	story_margin.add_theme_constant_override(
		"margin_left",
		22
	)
	story_margin.add_theme_constant_override(
		"margin_right",
		22
	)
	story_margin.add_theme_constant_override(
		"margin_top",
		17
	)
	story_margin.add_theme_constant_override(
		"margin_bottom",
		17
	)
	_body_frame.add_child(story_margin)

	_body_label = RichTextLabel.new()
	_body_label.name = "EventBody"
	_body_label.bbcode_enabled = false
	_body_label.fit_content = false
	_body_label.scroll_active = true
	_body_label.custom_minimum_size = Vector2(
		0.0,
		166.0
	)
	_body_label.mouse_filter = (
		Control.MOUSE_FILTER_PASS
	)
	_body_label.add_theme_font_size_override(
		"normal_font_size",
		16
	)
	_body_label.add_theme_color_override(
		"default_color",
		Color(0.94, 0.91, 0.80, 1.0)
	)
	story_margin.add_child(_body_label)

	_hint_label = _make_label(
		"Hover over your response to reveal what fate has in store.",
		11,
		Color(0.61, 0.57, 0.47, 0.95)
	)
	_hint_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_hint_label)

	# Consequences remain hidden until hover, but the frame keeps its size so
	# the event card does not jump around when the mouse enters a response.
	_consequence_panel = PanelContainer.new()
	_consequence_panel.name = "ConsequencePreview"
	_consequence_panel.custom_minimum_size = Vector2(
		0.0,
		96.0
	)
	_consequence_panel.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_consequence_panel.add_theme_stylebox_override(
		"panel",
		_make_consequence_style(
			Color(0.63, 0.51, 0.28, 0.72)
		)
	)
	column.add_child(_consequence_panel)

	var consequence_margin := MarginContainer.new()
	consequence_margin.add_theme_constant_override(
		"margin_left",
		14
	)
	consequence_margin.add_theme_constant_override(
		"margin_right",
		14
	)
	consequence_margin.add_theme_constant_override(
		"margin_top",
		8
	)
	consequence_margin.add_theme_constant_override(
		"margin_bottom",
		8
	)
	_consequence_panel.add_child(consequence_margin)

	var consequence_column := VBoxContainer.new()
	consequence_column.add_theme_constant_override(
		"separation",
		3
	)
	consequence_margin.add_child(
		consequence_column
	)

	_consequence_header = _make_label(
		"THE CONSEQUENCES",
		10,
		Color(0.81, 0.69, 0.43, 1.0)
	)
	_consequence_header.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	consequence_column.add_child(
		_consequence_header
	)

	_consequence_label = _make_label(
		"",
		12,
		Color(0.93, 0.89, 0.76, 1.0)
	)
	_consequence_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	_consequence_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_consequence_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_consequence_label.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	consequence_column.add_child(
		_consequence_label
	)

	# Positive and negative events use one restrained response.
	_single_button = _make_event_button(
		"OK"
	)
	_single_button.custom_minimum_size.y = 52.0
	_single_button.pressed.connect(
		_on_single_ok_pressed
	)
	_single_button.mouse_entered.connect(
		_on_single_hover
	)
	_single_button.mouse_exited.connect(
		_hide_consequence
	)
	column.add_child(_single_button)

	# Decision events use two equal, two-line response cards.
	_decision_row = HBoxContainer.new()
	_decision_row.add_theme_constant_override(
		"separation",
		14
	)
	column.add_child(_decision_row)

	_choice_a_button = _make_event_button(
		"CHOICE A"
	)
	_choice_a_button.custom_minimum_size = Vector2(
		0.0,
		82.0
	)
	_choice_a_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	_choice_a_button.pressed.connect(
		_on_choice_a_pressed
	)
	_choice_a_button.mouse_entered.connect(
		_on_choice_a_hover
	)
	_choice_a_button.mouse_exited.connect(
		_hide_consequence
	)
	_decision_row.add_child(_choice_a_button)

	_choice_b_button = _make_event_button(
		"CHOICE B"
	)
	_choice_b_button.custom_minimum_size = Vector2(
		0.0,
		82.0
	)
	_choice_b_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	_choice_b_button.pressed.connect(
		_on_choice_b_pressed
	)
	_choice_b_button.mouse_entered.connect(
		_on_choice_b_hover
	)
	_choice_b_button.mouse_exited.connect(
		_hide_consequence
	)
	_decision_row.add_child(_choice_b_button)

	_bottom_ornament = _make_label(
		"◆  THE GARDEN REMEMBERS  ◆",
		9,
		Color(0.48, 0.43, 0.34, 0.84)
	)
	_bottom_ornament.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_bottom_ornament)

	_hide_consequence()


# Handles configure popup for event.
func _configure_popup_for_event(
	event_id: StringName,
	definition: Dictionary
) -> void:
	var event_type := StringName(
		String(definition.get("type", ""))
	)
	var accent: Color = _accent_for_event_type(
		event_type
	)

	_day_label.text = "DAY %d • A NEW ENTRY IS RECORDED" % Clock.day
	_title_label.text = String(
		definition.get("title", "An Event")
	)
	_body_label.text = String(
		definition.get("body", "")
	)
	_body_label.scroll_to_line(0)

	# The whole card takes on a subtle type-specific accent while preserving
	# one unified visual language.
	_panel.add_theme_stylebox_override(
		"panel",
		_make_event_card_style(accent)
	)
	_consequence_panel.add_theme_stylebox_override(
		"panel",
		_make_consequence_style(
			Color(
				accent.r,
				accent.g,
				accent.b,
				0.70
			)
		)
	)
	_category_label.add_theme_color_override(
		"font_color",
		accent.lightened(0.18)
	)
	_title_label.add_theme_color_override(
		"font_color",
		Color(
			0.99,
			0.94,
			0.80,
			1.0
		)
	)

	match event_type:
		TYPE_POSITIVE:
			_category_label.text = (
				"A FORTUNATE TURN OF EVENTS"
			)
			_bottom_ornament.text = (
				"◆  FORTUNE FAVOURS THE GARDEN  ◆"
			)
		TYPE_NEGATIVE:
			_category_label.text = (
				"AN UNWELCOME DEVELOPMENT"
			)
			_bottom_ornament.text = (
				"◆  EVEN FLOWERS HAVE ENEMIES  ◆"
			)
		TYPE_DECISION:
			_category_label.text = (
				"A MATTER REQUIRING JUDGMENT"
			)
			_bottom_ornament.text = (
				"◆  CHOOSE, AND LIVE WITH IT  ◆"
			)
		_:
			_category_label.text = "AN EVENT"
			_bottom_ornament.text = (
				"◆  THE GARDEN REMEMBERS  ◆"
			)

	_hide_consequence()

	if event_type == TYPE_DECISION:
		_single_button.visible = false
		_decision_row.visible = true

		var choices: Array = _array_value(
			definition.get("choices", [])
		)

		if choices.size() >= 2:
			_configure_choice_button(
				_choice_a_button,
				_dictionary_value(
					choices[0]
				),
				0,
				accent
			)
			_configure_choice_button(
				_choice_b_button,
				_dictionary_value(
					choices[1]
				),
				1,
				accent
			)
	else:
		_single_button.visible = true
		_decision_row.visible = false
		_single_button.text = "OK"
		_single_button.add_theme_stylebox_override(
			"normal",
			_make_response_style(
				false,
				accent
			)
		)
		_single_button.add_theme_stylebox_override(
			"hover",
			_make_response_style(
				true,
				accent.lightened(0.15)
			)
		)
		_single_button.add_theme_stylebox_override(
			"pressed",
			_make_response_style(
				true,
				accent.lightened(0.28)
			)
		)

		_single_consequence = String(
			definition.get(
				"consequence",
				""
			)
		)

	if debug_log:
		print(
			"[RandomEvent] popup configured id=",
			String(event_id)
		)


# Handles configure choice button.
func _configure_choice_button(
	button: Button,
	choice: Dictionary,
	index: int,
	accent: Color
) -> void:
	var choice_id := StringName(
		String(choice.get("id", ""))
	)
	var label: String = String(
		choice.get("label", "Choose")
	)
	var consequence: String = String(
		choice.get("consequence", "")
	)

	button.text = label

	# Both decisions deliberately use the same structure and weight.
	# Small accent differences only help the mouse read them as two distinct
	# responses rather than "good button / bad button".
	var choice_accent: Color = accent

	if index == 1:
		choice_accent = accent.darkened(0.08)

	button.add_theme_stylebox_override(
		"normal",
		_make_response_style(
			false,
			choice_accent
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_response_style(
			true,
			choice_accent.lightened(0.16)
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_response_style(
			true,
			choice_accent.lightened(0.26)
		)
	)

	if index == 0:
		_choice_a_id = choice_id
		_choice_a_consequence = consequence
	else:
		_choice_b_id = choice_id
		_choice_b_consequence = consequence


# Handles the single hover signal or callback.
func _on_single_hover() -> void:
	_show_consequence(
		_single_consequence
	)


# Handles the choice a pressed signal or callback.
func _on_choice_a_pressed() -> void:
	_on_choice_pressed(
		_choice_a_id
	)


# Handles the choice b pressed signal or callback.
func _on_choice_b_pressed() -> void:
	_on_choice_pressed(
		_choice_b_id
	)


# Handles the choice a hover signal or callback.
func _on_choice_a_hover() -> void:
	_show_consequence(
		_choice_a_consequence
	)


# Handles the choice b hover signal or callback.
func _on_choice_b_hover() -> void:
	_show_consequence(
		_choice_b_consequence
	)


# Shows the consequence.
func _show_consequence(
	text_value: String
) -> void:
	if _consequence_panel == null:
		return

	_consequence_header.text = (
		"THE CONSEQUENCES"
	)
	_consequence_label.text = text_value
	_consequence_panel.modulate = (
		Color.WHITE
	)


# Hides the consequence.
func _hide_consequence() -> void:
	if _consequence_panel == null:
		return

	_consequence_header.text = ""
	_consequence_label.text = ""
	_consequence_panel.modulate = Color(
		1.0,
		1.0,
		1.0,
		0.0
	)


# Opens the modal.
func _open_modal() -> void:
	_previous_tree_paused = (
		get_tree().paused
	)
	_previous_mouse_mode = (
		Input.mouse_mode
	)

	get_tree().paused = true
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
	)
	_overlay.visible = true

	call_deferred(
		"_enforce_modal_mouse"
	)


# Closes the modal.
func _close_modal() -> void:
	_overlay.visible = false
	_pending_event_id = &""
	_pending_event = {}

	get_tree().paused = (
		_previous_tree_paused
	)
	Input.mouse_mode = (
		_previous_mouse_mode
	)


# Enforces the modal mouse.
func _enforce_modal_mouse() -> void:
	if _pending_event_id != &"":
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
		)


# Handles accent for event type.
func _accent_for_event_type(
	event_type: StringName
) -> Color:
	match event_type:
		TYPE_POSITIVE:
			return Color(
				0.55,
				0.74,
				0.38,
				1.0
			)
		TYPE_NEGATIVE:
			return Color(
				0.72,
				0.34,
				0.26,
				1.0
			)
		TYPE_DECISION:
			return Color(
				0.47,
				0.57,
				0.74,
				1.0
			)
		_:
			return Color(
				0.70,
				0.54,
				0.24,
				1.0
			)


# Creates the label.
func _make_label(
	text_value: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override(
		"font_size",
		font_size
	)
	label.add_theme_color_override(
		"font_color",
		color
	)
	label.add_theme_color_override(
		"font_outline_color",
		Color(
			0.01,
			0.01,
			0.01,
			0.95
		)
	)
	label.add_theme_constant_override(
		"outline_size",
		2
	)
	return label


# Creates the event button.
func _make_event_button(
	text_value: String
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.add_theme_font_size_override(
		"font_size",
		13
	)
	button.add_theme_color_override(
		"font_color",
		Color(0.93, 0.89, 0.75, 1.0)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(1.0, 0.96, 0.81, 1.0)
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color(1.0, 0.97, 0.84, 1.0)
	)
	button.add_theme_color_override(
		"font_outline_color",
		Color(0.015, 0.012, 0.008, 1.0)
	)
	button.add_theme_constant_override(
		"outline_size",
		2
	)
	button.add_theme_stylebox_override(
		"normal",
		_make_response_style(
			false,
			Color(0.63, 0.50, 0.25, 0.88)
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_response_style(
			true,
			Color(0.86, 0.69, 0.34, 1.0)
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_response_style(
			true,
			Color(0.95, 0.79, 0.42, 1.0)
		)
	)
	return button


# Creates the event card style.
func _make_event_card_style(
	accent: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.045,
		0.037,
		0.025,
		0.995
	)
	style.border_color = accent
	style.border_width_left = 2
	style.border_width_top = 3
	style.border_width_right = 2
	style.border_width_bottom = 3
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.72
	)
	style.shadow_size = 18
	style.shadow_offset = Vector2(
		0.0,
		7.0
	)
	return style


# Creates the story style.
func _make_story_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.115,
		0.092,
		0.057,
		0.96
	)
	style.border_color = Color(
		0.42,
		0.33,
		0.19,
		0.92
	)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.28
	)
	style.shadow_size = 4
	return style


# Creates the consequence style.
func _make_consequence_style(
	accent: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.025,
		0.025,
		0.021,
		0.97
	)
	style.border_color = accent
	style.border_width_left = 2
	style.border_width_top = 1
	style.border_width_right = 2
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.32
	)
	style.shadow_size = 4
	return style


# Creates the response style.
func _make_response_style(
	highlighted: bool,
	accent: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if highlighted:
		style.bg_color = Color(
			0.17,
			0.135,
			0.075,
			0.99
		)
	else:
		style.bg_color = Color(
			0.075,
			0.063,
			0.043,
			0.98
		)

	style.border_color = accent
	var width: int = 2 if highlighted else 1
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.34
	)
	style.shadow_size = 4 if highlighted else 2
	return style


# ------------------------------------------------------------------
# Catalog
# ------------------------------------------------------------------

# Builds the catalog.
func _build_catalog() -> void:
	_catalog.clear()
	_catalog_order.clear()

	# Catalog order alternates the three event families so
	# reaches every popup structure quickly.
	_add_event(EVENT_PERFECT_WEATHER, {
		"type": TYPE_POSITIVE,
		"title": "Perfect Weather",
		"weight": 10,
		"body": "At long last, the skies have remembered their manners. The sun is gentle, the air is kind, and even the breeze seems determined to assist in my noble horticultural ambitions. For a few glorious days, the garden shall behave as if it actually wants to live.",
		"consequence": "For 3 days, plant growth speed is increased by 25%."
	})

	_add_event(EVENT_SPRINKLER_BREAKDOWN, {
		"type": TYPE_NEGATIVE,
		"title": "Sprinkler Breakdown",
		"weight": 9,
		"requires_sprinkler": true,
		"body": "Disaster has struck the irrigation works. A leak, a rattle, and one very suspicious metallic clunk later, the sprinkler system has declared a temporary strike. It appears the machinery has decided to explore the concept of rest.",
		"consequence": "For 3 days, all automatic sprinklers are out of service. Manual watering still works."
	})

	_add_event(EVENT_EMERGENCY_MAINTENANCE, {
		"type": TYPE_DECISION,
		"title": "Emergency Maintenance",
		"weight": 8,
		"requires_sprinkler": true,
		"body": "The sprinkler network groans like an old castle gate and rattles with all the confidence of a spoon in a storm. A technician offers two solutions: a swift repair for a price, or a slower fix that requires patience and a certain tolerance for inconvenience.",
		"choices": [
			{
				"id": "pay_now",
				"label": "A stitch in time...\nPAY FOR IMMEDIATE REPAIRS",
				"consequence": "Pay $80 now. The sprinkler network remains operational with no downtime."
			},
			{
				"id": "wait",
				"label": "Patience is a virtue. Allegedly.\nWAIT FOR THE CHEAP CREW",
				"consequence": "Pay nothing, but automatic sprinklers stop working for 4 days."
			}
		]
	})

	_add_event(EVENT_BOTANICAL_GRANT, {
		"type": TYPE_POSITIVE,
		"title": "Botanical Grant",
		"weight": 10,
		"body": "A curious benefactor, whose handwriting suggests either great wealth or terrible penmanship, has decided that my gardening efforts deserve support. I shall not question their motives. I shall merely accept the coins with the dignity of a true agricultural visionary.",
		"consequence": "Immediately gain $100. No paperwork has survived to object."
	})

	_add_event(EVENT_PEST_OUTBREAK, {
		"type": TYPE_NEGATIVE,
		"title": "Pest Outbreak",
		"weight": 10,
		"requires_plants": true,
		"body": "Something small, greedy, and deeply offensive has arrived in the garden. The leaves are being sampled without permission, and certain residents seem far too comfortable committing botanical crimes. This, I regret to report, means war.",
		"consequence": "Immediately infect 1-3 living plants with a significant pest level."
	})

	_add_event(EVENT_RARE_SEED_OFFER, {
		"type": TYPE_DECISION,
		"title": "Rare Seed Offer",
		"weight": 8,
		"body": "A travelling merchant arrives with a grin too confident to be entirely honest. From a carefully guarded pouch, they reveal a set of uncommon seeds and an even rarer opportunity. The price is audacious. The temptation is worse.",
		"choices": [
			{
				"id": "buy",
				"label": "Fortune favours the gardener.\nBUY THE SEEDS",
				"consequence": "Pay $60 and receive 8 seeds drawn from your currently unlocked plants."
			},
			{
				"id": "refuse",
				"label": "My purse has spoken.\nPOLITELY REFUSE",
				"consequence": "Keep your money. The merchant departs with theatrical disappointment."
			}
		]
	})

	_add_event(EVENT_SEED_DONATION, {
		"type": TYPE_POSITIVE,
		"title": "Seed Donation",
		"weight": 10,
		"body": "A parcel has arrived, full of seeds and absolutely no useful explanation. Either I have inspired the local community, or someone has mistaken me for a much more responsible gardener. No matter. Seeds are seeds, and I am not one to waste a miracle.",
		"consequence": "Immediately receive 5 seeds from currently unlocked plant types."
	})

	_add_event(EVENT_FUNGAL_SPREAD, {
		"type": TYPE_NEGATIVE,
		"title": "Fungal Spread",
		"weight": 10,
		"requires_plants": true,
		"body": "A grim and fuzzy menace has appeared. What began as a suspicious little patch now spreads with the confidence of a scandal in a small village. The garden has entered a most undignified chapter, and several plants are about to look thoroughly unwell.",
		"consequence": "Immediately infect 1-3 living plants with fungal disease."
	})

	_add_event(EVENT_SOIL_TREATMENT, {
		"type": TYPE_DECISION,
		"title": "Soil Treatment",
		"weight": 8,
		"body": "A local specialist claims they can improve the condition of my fields with a proprietary mixture of minerals, methods, and vague confidence. It may genuinely help the soil. It may also simply be very expensive dirt. This is the gamble of progress.",
		"choices": [
			{
				"id": "treat",
				"label": "Science! Probably.\nCOMMISSION THE TREATMENT",
				"consequence": "Pay $60. For 5 days, soil loses moisture 25% more slowly."
			},
			{
				"id": "leave",
				"label": "The dirt knows what it is doing.\nLEAVE IT ALONE",
				"consequence": "No cost and no additional effect. The soil remains proudly ordinary."
			}
		]
	})

	_add_event(EVENT_RESEARCH_BREAKTHROUGH, {
		"type": TYPE_POSITIVE,
		"title": "Research Breakthrough",
		"weight": 2,
		"unique_once": true,
		"min_player_level": 5,
		"body": "After much observation, note-taking, and what some critics might call staring at plants for suspiciously long periods, I have arrived at a revelation. My cultivation methods are improving. Posterity may remember this as a scientific triumph. My plants will remember it as competent supervision.",
		"consequence": "Permanent and rare: every future Plant XP award gains +1 bonus XP. This event can occur only once per Garden."
	})

	_add_event(EVENT_DROUGHT, {
		"type": TYPE_NEGATIVE,
		"title": "Drought",
		"weight": 9,
		"body": "The air has gone dry, the soil has gone thirsty, and the heavens have apparently misplaced their sense of generosity. Every patch of earth now drinks like it has been personally insulted. I shall need to keep a closer eye on moisture, lest the garden begin auditioning for the desert.",
		"consequence": "For 3 days, natural soil moisture loss is increased by 50%."
	})

	_add_event(EVENT_EXPERIMENTAL_FERTILIZER, {
		"type": TYPE_DECISION,
		"title": "Experimental Fertilizer",
		"weight": 8,
		"requires_plants": true,
		"body": "A suspiciously enthusiastic supplier offers me a new fertilizer that promises vigorous growth and exciting results. The tone suggests science. The smell suggests caution. Still, fortune has often favoured the bold, and occasionally the reckless.",
		"choices": [
			{
				"id": "experiment",
				"label": "What could possibly go wrong?\nUSE THE EXPERIMENTAL MIX",
				"consequence": "For 3 days, plant growth is 25% faster. There is also a 35% chance that one living plant receives a fungal infection."
			},
			{
				"id": "decline",
				"label": "Boring is sometimes alive.\nSTICK TO THE USUAL STUFF",
				"consequence": "No bonus and no added risk. Your plants remain blissfully unaware of experimental agriculture."
			}
		]
	})

	_add_event(EVENT_MARKET_BOOM, {
		"type": TYPE_POSITIVE,
		"title": "Market Boom",
		"weight": 2,
		"unique_once": true,
		"min_player_level": 5,
		"body": "For reasons known only to the whims of commerce, my produce has suddenly become fashionable. Perhaps the public has developed refined taste. Perhaps everyone else's vegetables are dreadful. Either way, the market smiles upon me today.",
		"consequence": "Permanent and rare: harvest money is multiplied by 1.10. This event can occur only once per Garden."
	})

	_add_event(EVENT_WATER_SHORTAGE, {
		"type": TYPE_NEGATIVE,
		"title": "Water Shortage",
		"weight": 8,
		"requires_sprinkler": true,
		"body": "The water supply has become uncooperative. Pressure is weak, timing is poor, and the irrigation network now behaves like a bureaucrat nearing lunch. This is no total catastrophe, but it does mean the sprinklers will be far less dependable for a while.",
		"consequence": "For 3 days, every sprinkler's effective watering interval is doubled."
	})

	_add_event(EVENT_GARDEN_INSPECTION, {
		"type": TYPE_DECISION,
		"title": "Garden Inspection",
		"weight": 8,
		"requires_plants": true,
		"body": "An inspector has arrived, carrying a clipboard and the terrifying calm of someone empowered to judge my life choices. A well-kept garden may earn praise and a reward. A chaotic one may earn stern commentary, which is somehow even worse.",
		"choices": [
			{
				"id": "inspect",
				"label": "Behold my magnificent domain.\nWELCOME THE INSPECTION",
				"consequence": "Average living-plant health 80%+: gain $100. 60%+: gain $50. Below 60%: no reward."
			},
			{
				"id": "avoid",
				"label": "The gate appears to be stuck.\nAVOID THE WHOLE AFFAIR",
				"consequence": "No inspection, no risk, and no reward. The clipboard retreats unsatisfied."
			}
		]
	})

	_add_event(EVENT_EFFICIENT_IRRIGATION, {
		"type": TYPE_POSITIVE,
		"title": "Efficient Irrigation",
		"weight": 9,
		"requires_sprinkler": true,
		"body": "A brief inspection of the sprinkler system has revealed a shocking truth: it works better when properly maintained. Who could have foreseen this? The water now flies with renewed enthusiasm, and the fields are about to enjoy a most refreshing improvement.",
		"consequence": "For 3 days, sprinkler moisture output is increased by 30%."
	})

	_add_event(EVENT_MARKET_SLUMP, {
		"type": TYPE_NEGATIVE,
		"title": "Market Slump",
		"weight": 2,
		"unique_once": true,
		"min_player_level": 5,
		"body": "The market has become moody. Buyers hesitate, prices wobble, and the merchants now wear the expression of people who have recently read very disappointing numbers. My harvest remains respectable. Its financial prospects, however, have grown considerably less glamorous.",
		"consequence": "Permanent and rare: harvest money is multiplied by 0.90. This event can occur only once per Garden."
	})

	_add_event(EVENT_HEAT_PREPARATION, {
		"type": TYPE_DECISION,
		"title": "Heat Preparation",
		"weight": 8,
		"body": "Word arrives of severe heat on the horizon. I can prepare now, investing in protection and prevention, or I can do what lesser gardeners call hoping for the best. History suggests this is rarely a sound agricultural policy.",
		"choices": [
			{
				"id": "prepare",
				"label": "A sensible expense. How dreadful.\nPREPARE FOR THE HEAT",
				"consequence": "Pay $50. For 4 days, natural soil moisture loss is reduced by 25%."
			},
			{
				"id": "chance",
				"label": "The sun surely respects confidence.\nTAKE MY CHANCES",
				"consequence": "Pay nothing. For 4 days, natural soil moisture loss is increased by 25%."
			}
		]
	})


	# --------------------------------------------------------------
	# Late-game automation-machine events
	# --------------------------------------------------------------

	_add_event(EVENT_NUTRIENT_RICH_DELIVERY, {
		"type": TYPE_POSITIVE,
		"title": "Nutrient-Rich Delivery",
		"weight": 6,
		"min_player_level": 20,
		"requires_fertilizer_injector": true,
		"body": "A supply cart has arrived carrying a fertilizer concentrate so potent that the driver insists on calling it 'premium agricultural enthusiasm.' The injector system accepts the mixture without complaint, which is more confidence than I personally feel. Still, the nutrient readings are excellent.",
		"consequence": "For 3 days, Fertilizer Injectors apply 30% more nutrients per cycle."
	})

	_add_event(EVENT_FERTILIZER_SHORTAGE, {
		"type": TYPE_NEGATIVE,
		"title": "Fertilizer Shortage",
		"weight": 6,
		"min_player_level": 20,
		"requires_fertilizer_injector": true,
		"body": "The fertilizer stores have become distressingly light. The supplier blames transport delays, the transport company blames weather, and the weather has declined to comment. The injectors can keep running, but they will have to stretch what remains.",
		"consequence": "For 3 days, Fertilizer Injector nutrient output is reduced by 35%."
	})

	_add_event(EVENT_SOIL_ANALYSIS_BREAKTHROUGH, {
		"type": TYPE_POSITIVE,
		"title": "Soil Analysis Breakthrough",
		"weight": 6,
		"min_player_level": 30,
		"requires_soil_neutralizer": true,
		"body": "A fresh set of soil readings reveals a wonderfully precise calibration profile. Apparently the Neutralizer has been capable of greater accuracy all along; it merely required several pages of calculations and one very smug laboratory assistant to prove it.",
		"consequence": "For 3 days, Soil Neutralizer pH correction strength is increased by 30%."
	})

	_add_event(EVENT_REAGENT_CONTAMINATION, {
		"type": TYPE_NEGATIVE,
		"title": "Reagent Contamination",
		"weight": 6,
		"min_player_level": 30,
		"requires_soil_neutralizer": true,
		"body": "Several Neutralizer reagent containers have developed an alarming collection of labels, crossed-out labels, and labels correcting the crossed-out labels. The mixture still functions, but until a clean batch arrives the machine will be noticeably less decisive about soil chemistry.",
		"consequence": "For 3 days, Soil Neutralizer pH correction strength is reduced by 35%."
	})

	_add_event(EVENT_BIOCONTROL_BREAKTHROUGH, {
		"type": TYPE_POSITIVE,
		"title": "Biocontrol Breakthrough",
		"weight": 6,
		"min_player_level": 40,
		"requires_plant_protection": true,
		"requires_plants": true,
		"body": "The Plant Protection Station has received a new treatment protocol combining better timing, better coverage, and considerably less shouting at insects. Early trials are excellent. Even the fungus appears offended by the professionalism.",
		"consequence": "For 3 days, Plant Protection Stations treat pests and fungal disease 30% more effectively."
	})

	_add_event(EVENT_TREATMENT_RESISTANCE, {
		"type": TYPE_NEGATIVE,
		"title": "Treatment Resistance",
		"weight": 6,
		"min_player_level": 40,
		"requires_plant_protection": true,
		"requires_plants": true,
		"body": "The garden's least welcome residents have adapted with infuriating enthusiasm. Pests shrug off treatments that once sent them fleeing, while fungal patches display a resilience bordering on arrogance. The protection stations still work, but the enemy has clearly been studying.",
		"consequence": "For 3 days, Plant Protection Station pest and fungus treatment strength is reduced by 35%."
	})


# Adds the event.
func _add_event(
	event_id: StringName,
	definition: Dictionary
) -> void:
	_catalog[event_id] = definition
	_catalog_order.append(event_id)


# ------------------------------------------------------------------
# Small Variant helpers
# ------------------------------------------------------------------

# Reads a Dictionary value used by the regression checks.
func _dictionary_value(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value

	return {}


# Reads an Array value used by the regression checks.
func _array_value(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value

	return []


# Checks whether the gameplay world is active.
func _is_gameplay_world_active() -> bool:
	var scene: Node = get_tree().current_scene

	if scene == null:
		return false

	var player: Node = scene.get_node_or_null("Player")

	if player == null:
		player = scene.find_child("Player", true, false)

	return player != null

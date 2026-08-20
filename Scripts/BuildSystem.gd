extends Node

# In-game farm editor with free camera navigation and an icon-based build catalog.

signal build_mode_changed(active: bool)
signal build_selection_changed(build_id: StringName)
signal build_cell_placed(
	cell: Vector2i,
	build_id: StringName,
	cost: int
)
signal build_cell_removed(
	cell: Vector2i,
	build_id: StringName,
	refund: int
)
signal build_action_failed(
	cell: Vector2i,
	build_id: StringName,
	reason: String
)
signal build_world_rebuilt()

const CATEGORY_TERRAIN: StringName = &"terrain"
const CATEGORY_LOAMY: StringName = &"loamy"
const CATEGORY_SANDY: StringName = &"sandy"
const CATEGORY_WATER: StringName = &"water"
const CATEGORY_PATH: StringName = &"path"
const CATEGORY_FENCE: StringName = &"fence"
const CATEGORY_GROUND_DECOR: StringName = &"ground_decor"
const CATEGORY_WATER_DECOR: StringName = &"water_decor"
const CATEGORY_FARM_OBJECTS: StringName = &"farm_objects"

const CATEGORY_ORDER: Array[StringName] = [
	CATEGORY_TERRAIN,
	CATEGORY_GROUND_DECOR,
	CATEGORY_LOAMY,
	CATEGORY_SANDY,
	CATEGORY_WATER,
	CATEGORY_WATER_DECOR,
	CATEGORY_PATH,
	CATEGORY_FENCE,
	CATEGORY_FARM_OBJECTS
]

const CATEGORY_NAMES: Dictionary = {
	CATEGORY_TERRAIN: "Terrain",
	CATEGORY_GROUND_DECOR: "Ground Decor",
	CATEGORY_LOAMY: "Loamy",
	CATEGORY_SANDY: "Sandy",
	CATEGORY_WATER: "Water",
	CATEGORY_WATER_DECOR: "Water Decor",
	CATEGORY_PATH: "Path",
	CATEGORY_FENCE: "Fence",
	CATEGORY_FARM_OBJECTS: "Farm Objects"
}

# Exact atlas source IDs from biome.tscn.
const TERRAIN_SOURCE_ID: int = 11
const FENCE_SOURCE_ID: int = 2
const FENCE_ALT_SOURCE_ID: int = 3

const NO_TILE: Vector2i = Vector2i(-1, -1)

const SOIL_LOAMY: StringName = &"loamy"
const SOIL_SANDY: StringName = &"sandy"

const FARMING_SOURCE_ID: int = 1
const BUILD_ID_SEED_STORAGE: StringName = &"seed_storage"
const BUILD_ID_REPAIR_ANVIL: StringName = &"repair_anvil"
const REPAIR_ANVIL_TILE: Vector2i = Vector2i(6, 1)
const SEED_STORAGE_TILE_A: Vector2i = Vector2i(1, 3)
const SEED_STORAGE_TILE_B: Vector2i = Vector2i(1, 5)
# Single 32x32 sack tile used for buildable Seed Storage.
const SEED_STORAGE_SINGLE_TILE: Vector2i = SEED_STORAGE_TILE_A

const BUILD_ID_SPRINKLER: StringName = &"sprinkler"
const RUNTIME_KIND_SPRINKLER: StringName = &"sprinkler"

const BUILD_ID_FERTILIZER_INJECTOR: StringName = &"fertilizer_injector"
const RUNTIME_KIND_FERTILIZER_INJECTOR: StringName = &"fertilizer_injector"

const BUILD_ID_SOIL_NEUTRALIZER: StringName = &"soil_neutralizer"
const RUNTIME_KIND_SOIL_NEUTRALIZER: StringName = &"soil_neutralizer"

const BUILD_ID_PLANT_PROTECTION: StringName = &"plant_protection_station"
const RUNTIME_KIND_PLANT_PROTECTION: StringName = &"plant_protection_station"

# Existing terrain families that are safe to expose to the player.
const LOAMY_VISUALS: Array[Vector2i] = [
	Vector2i(18, 8),
	Vector2i(19, 8),
	Vector2i(20, 8),
	Vector2i(18, 9),
	Vector2i(19, 9),
	Vector2i(20, 9),
	Vector2i(18, 10),
	Vector2i(19, 10),
	Vector2i(20, 10)
]

# This 3x3 family is the light-brown field family used as the sandy field border set.
const SANDY_EDGE_VISUALS: Array[Vector2i] = [
	Vector2i(0, 2),
	Vector2i(1, 2),
	Vector2i(2, 2),
	Vector2i(0, 3),
	Vector2i(1, 3),
	Vector2i(2, 3),
	Vector2i(0, 4),
	Vector2i(1, 4),
	Vector2i(2, 4)
]

# The current map builds sandy fields as a layered composition:
# filler=(2,5) underlay, Ground2 edge family=(0..2,2..4),
# and Plantable=(1,5) only for the center crop cell.
const SANDY_FILLER_BASE: Vector2i = Vector2i(2, 5)
const SANDY_PLANTABLE_CENTER: Vector2i = Vector2i(1, 5)

# Ground decoration tiles are full 32x32 grass variants already used
# on Ground2 in the original biome map. They are surface variants, not overlays.
const GROUND_DECOR_VISUALS: Array[Vector2i] = [
	Vector2i(0, 11),
	Vector2i(2, 11),
	Vector2i(3, 11),
	Vector2i(4, 11),
	Vector2i(5, 11),
	Vector2i(10, 11),
	Vector2i(13, 11),
	Vector2i(14, 11)
]

const GROUND_DECOR_NAMES: Array[String] = [
	"Grass Tufts A",
	"Grass Tufts B",
	"Red Flowers A",
	"Red Flowers B",
	"Red Flowers C",
	"White Water-Lily Grass",
	"Yellow Grass A",
	"Yellow Grass B"
]

# These three full atlas tiles are the decorative water plants actually
# placed on water cells in the original biome.tscn objects layer.
# Original map evidence:
# (9,22), (10,22), (12,22) sit over Ground2 water tile (8,17).
const WATER_DECOR_VISUALS: Array[Vector2i] = [
	Vector2i(9, 22),
	Vector2i(10, 22),
	Vector2i(12, 22)
]

const WATER_DECOR_NAMES: Array[String] = [
	"Water Flower White",
	"Water Flowers Pink",
	"Water Flower Red"
]

const WATER_VISUALS: Array[Vector2i] = [
	Vector2i(6, 14),
	Vector2i(7, 14),
	Vector2i(8, 14),
	Vector2i(6, 15),
	Vector2i(7, 15),
	Vector2i(8, 15),
	Vector2i(6, 16),
	Vector2i(7, 16),
	Vector2i(8, 16),
	Vector2i(3, 17),
	Vector2i(5, 17),
	Vector2i(8, 17),
	Vector2i(19, 3)
]

const PATH_VISUALS: Array[Vector2i] = [
	Vector2i(1, 19),
	Vector2i(2, 19),
	Vector2i(3, 19),
	Vector2i(1, 20),
	Vector2i(2, 20),
	Vector2i(3, 20),
	Vector2i(2, 21),
	Vector2i(3, 21)
]

const GRASS_VISUALS: Array[Vector2i] = [
	Vector2i(0, 11),
	Vector2i(1, 11),
	Vector2i(2, 11),
	Vector2i(4, 11),
	Vector2i(5, 11),
	Vector2i(13, 11),
	Vector2i(14, 11)
]

const FENCE_VISUALS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(2, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(2, 1),
	Vector2i(0, 2),
	Vector2i(1, 2),
	Vector2i(2, 2),
	Vector2i(0, 3),
	Vector2i(1, 3),
	Vector2i(2, 3),
	Vector2i(0, 4),
	Vector2i(1, 4),
	Vector2i(2, 4),
	Vector2i(0, 5),
	Vector2i(1, 5),
	Vector2i(2, 5)
]

const EDGE_NAMES: Array[String] = [
	"Top Left",
	"Top",
	"Top Right",
	"Left",
	"Center",
	"Right",
	"Bottom Left",
	"Bottom",
	"Bottom Right"
]

const REASON_NOT_CONFIGURED: String = "NOT_CONFIGURED"
const REASON_NO_CREDITS: String = "INSUFFICIENT_BUILD_CREDITS"
const REASON_OCCUPIED_BY_PLANT: String = "OCCUPIED_BY_PLANT"
const REASON_PLAYER_CELL: String = "PLAYER_CELL"
const REASON_BLOCKED_LAYER: String = "BLOCKED_LAYER"
const REASON_BLOCKED_BY_BUILD_OBJECT: String = "BLOCKED_BY_BUILD_OBJECT"
const REASON_NOT_ADJACENT: String = "NOT_ADJACENT_TO_MAP"
const REASON_ALREADY_BUILT: String = "PLAYER_BUILD_ALREADY_PRESENT"
const REASON_SAME_SURFACE: String = "SAME_SURFACE"
const REASON_NOT_PLAYER_BUILT: String = "NOT_PLAYER_BUILT"
const REASON_NO_SURFACE: String = "NO_SURFACE"
const REASON_PLANTABLE_SURFACE: String = "PLANTABLE_SURFACE"
const REASON_WATER_SURFACE: String = "WATER_SURFACE"
const REASON_MISSING_TILE: String = "MISSING_TILE_IN_TILESET"
const REASON_SAME_BUILD: String = "SAME_BUILD_ITEM"
const REASON_DECOR_NEEDS_SURFACE: String = "DECOR_NEEDS_SURFACE"
const REASON_DECOR_ON_PLANTABLE: String = "DECOR_ON_PLANTABLE"
const REASON_DECOR_ON_WATER: String = "DECOR_ON_WATER"
const REASON_GROUND_DECOR_NEEDS_GRASS: String = "GROUND_DECOR_NEEDS_GRASS"
const REASON_WATER_DECOR_NEEDS_WATER: String = "WATER_DECOR_NEEDS_WATER"
const REASON_OBJECT_NEEDS_GRASS: String = "OBJECT_NEEDS_GRASS"
const REASON_OBJECT_NEEDS_DRY_GROUND: String = "OBJECT_NEEDS_DRY_GROUND"
const REASON_SPRINKLER_NEEDS_VALID_SURFACE: String = "SPRINKLER_NEEDS_VALID_SURFACE"
const REASON_AUTOMATION_NEEDS_VALID_SURFACE: String = "AUTOMATION_NEEDS_VALID_SURFACE"
const REASON_BUILD_LOCKED: String = "BUILD_LOCKED"
const REASON_STORAGE_NOT_EMPTY: String = "STORAGE_NOT_EMPTY"

@export var debug_log: bool = false
@export var refund_ratio: float = 1.0
@export var build_camera_pan_speed: float = 560.0

# Build Mode camera workspace around the current real map.
# WorldBoundsSystem applies the same 20-cell exploration margin.
@export var build_camera_margin_cells: int = 20

@export var build_camera_default_zoom: float = 1.0
@export var build_camera_min_zoom: float = 0.60
@export var build_camera_max_zoom: float = 1.60
@export var build_camera_zoom_step: float = 0.10

# Smooth editor-style edge panning. Moving the cursor near a screen edge pans
# the build camera without requiring a click or middle-drag.
@export var build_edge_pan_enabled: bool = true
@export var build_edge_pan_margin_pixels: float = 54.0
@export var build_edge_pan_speed_multiplier: float = 0.80

var _active: bool = false
var _selected_category: StringName = CATEGORY_TERRAIN
var _selected_build_id: StringName = &"grass_plain"
var _selected_rotation: int = 0

var _tilemap: TileMap
var _player: Node2D
var _camera: Camera2D
var _gameplay_overlays: CanvasItem

var _filler_layer: int = -1
var _ground_layer: int = -1
var _plantable_layer: int = -1
var _intersections_layer: int = -1
var _house_layer: int = -1
var _objects_layer: int = -1
var _decorations_layer: int = -1

# Build catalog state.
var _catalog_items: Array[Dictionary] = []
var _items_by_id: Dictionary = {}
var _catalog_valid: bool = false
var _item_texture_cache: Dictionary = {}

# Player-made tile/object state for later save/minimap integration.
var _placed_cells: Dictionary = {}
# Surface cells present when the world is first configured. These are the
# permanent roots used to determine whether player-built expansion remains
# connected to the original map.
var _base_surface_cells: Dictionary = {}
var _built_soil_overrides: Dictionary = {}

# Runtime collision is currently required by player-built water.
var _collision_root: Node2D
var _blocking_bodies: Dictionary = {}

# Cell validity overlay and selected-tile ghost.
var _preview: Polygon2D
var _ghost_preview: Sprite2D

# Build editor camera/gameplay state.
var _saved_tree_paused: bool = false
var _saved_player_visible: bool = true
var _saved_overlays_visible: bool = true
var _saved_camera_position: Vector2 = Vector2.ZERO
var _saved_camera_zoom: Vector2 = Vector2.ONE
var _saved_camera_smoothing: bool = false
var _middle_dragging: bool = false

# Build editor UI.
var _hud_layer: CanvasLayer
var _top_bar: PanelContainer
var _palette_panel: PanelContainer
var _credits_label: Label
var _status_label: Label
var _selected_name_label: Label
var _selected_icon: TextureRect
var _category_grid: GridContainer
var _item_grid: GridContainer
var _category_buttons: Dictionary = {}
var _item_buttons: Dictionary = {}


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_catalog()
	_create_hud()

	if not ProgressionSystem.build_cell_credits_changed.is_connected(
		_on_build_cell_credits_changed
	):
		ProgressionSystem.build_cell_credits_changed.connect(
			_on_build_cell_credits_changed
		)

	if not ProgressionSystem.progression_reset.is_connected(
		_on_progression_reset
	):
		ProgressionSystem.progression_reset.connect(
			_on_progression_reset
		)

	if not ProgressionSystem.player_level_changed.is_connected(
		_on_player_level_changed
	):
		ProgressionSystem.player_level_changed.connect(
			_on_player_level_changed
		)

	_refresh_hud()

	if debug_log:
		print(
			"[BuildSystem] ready selected=",
			String(_selected_build_id),
			" catalog_items=",
			_catalog_items.size()
		)


# Connects the global build editor to the active world.
func configure(
	tilemap: TileMap,
	player: Node2D,
	camera: Camera2D
) -> void:
	if tilemap == null or player == null or camera == null:
		push_error("[BuildSystem] configure received missing world references.")
		return

	if _tilemap != null and _tilemap != tilemap:
		_clear_runtime_state(false)

	_tilemap = tilemap
	_player = player
	_camera = camera
	_gameplay_overlays = _find_gameplay_overlays()

	_filler_layer = _find_layer_by_name("filler")
	_ground_layer = _find_layer_by_name("Ground2")
	_plantable_layer = _find_layer_by_name("Plantable")
	_intersections_layer = _find_layer_by_name("Intersections")
	_house_layer = _find_layer_by_name("house")
	_objects_layer = _find_layer_by_name("objects")
	_decorations_layer = _find_or_create_decorations_layer()

	if (
		_filler_layer == -1
		or _ground_layer == -1
		or _plantable_layer == -1
		or _objects_layer == -1
		or _decorations_layer == -1
	):
		push_error(
			"[BuildSystem] Required TileMap layers were not available."
		)
		return

	_item_texture_cache.clear()
	_catalog_valid = _validate_catalog_tiles()

	# Capture the original map BEFORE SaveSystem restores player-built terrain.
	# These cells remain the permanent roots for connected-expansion checks.
	_capture_base_surface_cells()

	_create_preview()
	_create_collision_root()
	_refresh_camera_limits()
	_rebuild_category_buttons()
	_rebuild_item_grid()
	_refresh_hud()

	if debug_log:
		print(
			"[BuildSystem] configured filler_layer=",
			_filler_layer,
			" ground_layer=",
			_ground_layer,
			" plantable_layer=",
			_plantable_layer,
			" objects_layer=",
			_objects_layer,
			" decorations_layer=",
			_decorations_layer,
			" catalog_valid=",
			_catalog_valid,
			" credits=",
			ProgressionSystem.build_cell_credits
		)


# Disconnects this system from the current world references.
func unconfigure(tilemap: TileMap) -> void:
	if _tilemap != tilemap:
		return

	if _active:
		_set_active(false)

	_clear_runtime_state(false)

	if _preview != null:
		_preview.queue_free()
		_preview = null

	if _ghost_preview != null:
		_ghost_preview.queue_free()
		_ghost_preview = null

	if _collision_root != null:
		_collision_root.queue_free()
		_collision_root = null

	_tilemap = null
	_player = null
	_camera = null
	_base_surface_cells.clear()
	_gameplay_overlays = null
	_catalog_valid = false
	_item_texture_cache.clear()

	_filler_layer = -1
	_ground_layer = -1
	_plantable_layer = -1
	_intersections_layer = -1
	_house_layer = -1
	_objects_layer = -1
	_decorations_layer = -1


# Checks whether this system is currently active.
func is_active() -> bool:
	return _active


# Returns the selected build ID.
func get_selected_build_id() -> StringName:
	return _selected_build_id


# WorldBoundsSystem uses this to decide whether the one-cell map-expansion
# apron should be available. Objects/decorations never need outside-map access.
func get_selected_build_slot() -> String:
	var item: Dictionary = _get_item(_selected_build_id)
	return String(item.get("slot", "surface"))


# Used by BiomeSystem and player planting validation for visual soil edge tiles.
func get_built_soil_type(cell: Vector2i) -> String:
	return String(_built_soil_overrides.get(cell, ""))


# Public occupancy helper used by gameplay systems such as Player planting.
# This checks the authoritative internal build record, so it also catches
# non-anchor cells of multi-cell objects.
func has_build_object_at(cell: Vector2i) -> bool:
	return _has_build_record(cell, "object")


# Returns true when a sprinkler may sit directly on the outermost cell of a
# Loamy/Sandy biome. The current cell must be plantable soil, and at least one
# of its four cardinal neighbours must no longer be the same soil type.
func is_sprinkler_biome_edge_cell(cell: Vector2i) -> bool:
	return _is_sprinkler_biome_edge_cell(cell)


# Exposes the whitelist catalog for future save/help/menu systems.
func get_build_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for item: Dictionary in _catalog_items:
		result.append(item.duplicate(true))

	return result


# Exposes compact player-build state for the future save/minimap systems.
# Returns the visual used by the Build catalog/ghost for runtime systems.
func get_build_icon(build_id: StringName) -> Texture2D:
	if not _is_configured():
		return null

	var item: Dictionary = _get_item(build_id)

	if item.is_empty():
		return null

	return _make_item_texture(item)


# Returns the player built cells.
func get_player_built_cells() -> Dictionary:
	var result: Dictionary = {}

	for cell_variant: Variant in _placed_cells.keys():
		var cell: Vector2i = cell_variant
		var cell_record: Dictionary = _placed_cells[cell]
		var output: Dictionary = {}

		if cell_record.has("surface"):
			var surface: Dictionary = cell_record["surface"]
			output["surface_build_id"] = surface.get("build_id", &"")
			output["surface_cost"] = int(surface.get("cost", 0))

		if cell_record.has("object"):
			var object_record: Dictionary = cell_record["object"]
			var include_object: bool = not bool(
				object_record.get("multi_object", false)
			) or bool(object_record.get("is_anchor", false))

			if include_object:
				output["object_build_id"] = object_record.get(
					"build_id",
					&""
				)
				output["object_cost"] = int(
					object_record.get("cost", 0)
				)
				if object_record.has("rotation"):
					output["object_rotation"] = int(
						object_record.get("rotation", 0)
					)
				if object_record.has("object_cells"):
					output["object_cells"] = object_record.get(
						"object_cells",
						[]
					)

		if cell_record.has("decoration"):
			var decoration_record: Dictionary = cell_record["decoration"]
			output["decoration_build_id"] = decoration_record.get(
				"build_id",
				&""
			)
			output["decoration_cost"] = int(
				decoration_record.get("cost", 0)
			)

		if not output.is_empty():
			result[cell] = output

	return result


# Sets the active.
func set_active(active: bool) -> void:
	if active and not _is_configured():
		return

	if active and get_tree().paused:
		return

	_set_active(active)


# Selects the build.
func select_build(build_id: StringName) -> bool:
	if not _items_by_id.has(build_id):
		return false

	if not _is_build_unlocked(build_id):
		var required_level: int = _get_required_player_level(
			build_id
		)
		_set_status(
			"Unlocks at Player Level %d." % required_level,
			true
		)
		return false

	_selected_build_id = build_id
	_selected_rotation = 0
	var item: Dictionary = _get_item(build_id)
	_selected_category = StringName(
		item.get("category", CATEGORY_TERRAIN)
	)

	build_selection_changed.emit(build_id)
	_refresh_hud()
	_update_ghost_texture()

	if debug_log:
		print(
			"[BuildSystem] selected=",
			String(build_id),
			" cost=",
			_get_build_cost(build_id),
			" category=",
			String(_selected_category),
			" rotation=",
			_get_rotation_name(_selected_rotation)
		)

	return true


# Selects the category.
func select_category(category: StringName) -> bool:
	if not CATEGORY_ORDER.has(category):
		return false

	_selected_category = category
	_rebuild_item_grid()
	_refresh_hud()

	if debug_log:
		print(
			"[BuildSystem] category=",
			String(category)
		)

	return true


# Validates one placement without changing the map.
func get_place_status(
	cell: Vector2i,
	build_id: StringName = &""
) -> Dictionary:
	var resolved_id: StringName = (
		_selected_build_id
		if build_id == &""
		else build_id
	)

	if not _is_configured():
		return _failed_status(REASON_NOT_CONFIGURED, resolved_id)

	if not _catalog_valid:
		return _failed_status(REASON_MISSING_TILE, resolved_id)

	if not _items_by_id.has(resolved_id):
		return _failed_status("INVALID_BUILD_ID", resolved_id)

	if not _is_build_unlocked(resolved_id):
		return _failed_status(
			REASON_BUILD_LOCKED,
			resolved_id
		)

	if _is_player_cell(cell):
		return _failed_status(REASON_PLAYER_CELL, resolved_id)

	var item: Dictionary = _get_item(resolved_id)
	var slot: String = String(item.get("slot", "surface"))
	var new_cost: int = int(item.get("cost", 0))
	var multi_object: bool = (
		slot == "object"
		and bool(item.get("multi_object", false))
	)

	var old_record: Dictionary = {}
	var old_cost: int = 0
	var old_build_id: StringName = &""
	var replacing: bool = false

	# Multi-cell objects are intentionally not direct-replaceable. This keeps
	# footprint validation and refunds deterministic; remove them first.
	if not multi_object:
		old_record = _get_build_record(cell, slot)
		old_cost = int(old_record.get("cost", 0))
		old_build_id = StringName(
			old_record.get("build_id", &"")
		)
		replacing = not old_record.is_empty()

		if replacing and old_build_id == resolved_id:
			return _failed_status(REASON_SAME_BUILD, resolved_id)

		if (
			slot == "object"
			and replacing
			and old_build_id == BUILD_ID_SEED_STORAGE
			and not ChestSystem.is_chest_empty(cell)
		):
			return _failed_status(
				REASON_STORAGE_NOT_EMPTY,
				resolved_id
			)

	var credit_delta: int = (
		new_cost
		if multi_object
		else new_cost - old_cost
	)

	if (
		credit_delta > 0
		and not ProgressionSystem.can_spend_build_cell_credits(
			credit_delta
		)
	):
		return _failed_status(REASON_NO_CREDITS, resolved_id)

	var status: Dictionary

	match slot:
		"object":
			status = _get_object_place_status(
				cell,
				resolved_id,
				new_cost,
				replacing
			)
		"decoration":
			status = _get_decoration_place_status(
				cell,
				resolved_id,
				new_cost,
				replacing
			)
		_:
			status = _get_surface_place_status(
				cell,
				resolved_id,
				new_cost,
				replacing
			)

	if not bool(status.get("ok", false)):
		return status

	status["replace"] = replacing
	status["old_build_id"] = old_build_id
	status["old_cost"] = old_cost
	status["credit_delta"] = credit_delta
	return status


# Returns the current get surface place status result.
func _get_surface_place_status(
	cell: Vector2i,
	build_id: StringName,
	cost: int,
	replacing: bool
) -> Dictionary:
	if PlantRegistry.get_plant(cell) != null:
		return _failed_status(REASON_OCCUPIED_BY_PLANT, build_id)

	if _has_build_record(cell, "object"):
		return _failed_status(REASON_BLOCKED_BY_BUILD_OBJECT, build_id)

	if _has_build_record(cell, "decoration"):
		return _failed_status(
			"REMOVE_DECORATION_FIRST",
			build_id
		)

	if _has_protected_map_content(cell, false):
		return _failed_status(REASON_BLOCKED_LAYER, build_id)

	var item: Dictionary = _get_item(build_id)
	var placement_surface: StringName = StringName(
		item.get("placement_surface", &"")
	)

	if placement_surface == &"grass":
		if not _is_grass_cell(cell):
			return _failed_status(
				REASON_GROUND_DECOR_NEEDS_GRASS,
				build_id
			)

	if not replacing and _matches_selected_surface(cell, build_id):
		return _failed_status(REASON_SAME_SURFACE, build_id)

	# Expanding the map is always connection-based.
	# A surface may be placed into an empty cell only when at least one of its
	# four direct neighbours belongs to the surface component connected to the
	# original map. This prevents remote/floating islands in the 20-cell camera
	# workspace.
	if (
		not replacing
		and not _has_surface_at(cell)
		and not _has_adjacent_main_map_surface(cell)
	):
		return _failed_status(REASON_NOT_ADJACENT, build_id)

	return {
		"ok": true,
		"reason": "",
		"cost": cost
	}


# Returns the current get object place status result.
func _get_object_place_status(
	cell: Vector2i,
	build_id: StringName,
	cost: int,
	replacing: bool
) -> Dictionary:
	var item: Dictionary = _get_item(build_id)
	var placement_surface: StringName = StringName(
		item.get("placement_surface", &"")
	)
	var target_cells: Array[Vector2i] = _get_object_target_cells(
		cell,
		build_id
	)
	var dry_surface_kind: StringName = &""

	for target_cell: Vector2i in target_cells:
		if _is_player_cell(target_cell):
			return _failed_status(REASON_PLAYER_CELL, build_id)

		if PlantRegistry.get_plant(target_cell) != null:
			return _failed_status(REASON_OCCUPIED_BY_PLANT, build_id)

		if _has_build_record(target_cell, "decoration"):
			return _failed_status(
				"REMOVE_DECORATION_FIRST",
				build_id
			)

		if _has_build_record(target_cell, "object"):
			return _failed_status(
				REASON_BLOCKED_BY_BUILD_OBJECT,
				build_id
			)

		if _has_protected_map_content(target_cell, false):
			return _failed_status(REASON_BLOCKED_LAYER, build_id)

		if not _has_surface_at(target_cell):
			return _failed_status(REASON_NO_SURFACE, build_id)

		var is_plantable: bool = (
			_tilemap.get_cell_source_id(
				_plantable_layer,
				target_cell
			) != -1
		)

		# Field automation machines share the Sprinkler placement rule:
		# - grass is valid;
		# - Loamy/Sandy soil is valid only on the visual/topological outer edge,
		#   so machines do not consume arbitrary central crop cells.
		if (
			build_id == BUILD_ID_SPRINKLER
			or build_id == BUILD_ID_FERTILIZER_INJECTOR
			or build_id == BUILD_ID_SOIL_NEUTRALIZER
			or build_id == BUILD_ID_PLANT_PROTECTION
		):
			var automation_surface_ok: bool = (
				_is_grass_cell(target_cell)
				or _is_sprinkler_biome_edge_cell(target_cell)
			)

			if not automation_surface_ok:
				return _failed_status(
					REASON_AUTOMATION_NEEDS_VALID_SURFACE,
					build_id
				)
		else:
			if is_plantable:
				return _failed_status(
					REASON_PLANTABLE_SURFACE,
					build_id
				)

			if _is_water_cell(target_cell):
				return _failed_status(
					REASON_WATER_SURFACE,
					build_id
				)

			if placement_surface == &"grass":
				if not _is_grass_cell(target_cell):
					return _failed_status(
						REASON_OBJECT_NEEDS_GRASS,
						build_id
					)

		if placement_surface == &"dry_ground":
			var current_kind: StringName = &""

			if _is_grass_cell(target_cell):
				current_kind = &"grass"
			elif _is_path_cell(target_cell):
				current_kind = &"path"

			if current_kind == &"":
				return _failed_status(
					REASON_OBJECT_NEEDS_DRY_GROUND,
					build_id
				)

			if dry_surface_kind == &"":
				dry_surface_kind = current_kind
			elif dry_surface_kind != current_kind:
				return _failed_status(
					REASON_OBJECT_NEEDS_DRY_GROUND,
					build_id
				)

	return {
		"ok": true,
		"reason": "",
		"cost": cost,
		"replace": replacing
	}


# Checks whether the cell is a valid biome edge for automation placement.
func _is_sprinkler_biome_edge_cell(
	cell: Vector2i
) -> bool:
	if not _is_configured():
		return false

	# ------------------------------------------------------------
	# LOAMY
	# ------------------------------------------------------------
	# A Loamy 3x3 atlascsaládban a 4-es index a középső tile.
	# A másik 8 elem a vizuális külső szél/sarok.
	#
	# Az eredeti map és a runtime-buildelt map miatt is ellenőrizzük
	# a Ground és a Plantable layert is.
	var ground_source: int = _tilemap.get_cell_source_id(
		_ground_layer,
		cell
	)
	var ground_atlas: Vector2i = _tilemap.get_cell_atlas_coords(
		_ground_layer,
		cell
	)

	var plantable_source: int = _tilemap.get_cell_source_id(
		_plantable_layer,
		cell
	)
	var plantable_atlas: Vector2i = _tilemap.get_cell_atlas_coords(
		_plantable_layer,
		cell
	)

	if plantable_source == TERRAIN_SOURCE_ID:
		var loamy_plantable_index: int = LOAMY_VISUALS.find(
			plantable_atlas
		)

		if loamy_plantable_index >= 0:
			return loamy_plantable_index != 4

	if ground_source == TERRAIN_SOURCE_ID:
		var loamy_ground_index: int = LOAMY_VISUALS.find(
			ground_atlas
		)

		if loamy_ground_index >= 0:
			return loamy_ground_index != 4

	# ------------------------------------------------------------
	# SANDY
	# ------------------------------------------------------------
	# A Sandy perem eltér a Loamytól:
	#
	# - filler layer: tömör alátét
	# - Ground2: transzparens 3x3 sandy edge/corner tile
	# - Plantable: csak a valódi termesztőcellák
	#
	# Emiatt a sandy külső pereme NEM feltétlenül Plantable cella.
	# A sprinkler placementnél ezért kifejezetten a Ground2
	# SANDY_EDGE_VISUALS családját kell felismerni.
	#
	# A dupla/layerelt sandy edge-et szándékosan egy cellaként kezeljük:
	# az alatta lévő filler megmarad, a sprinkler pedig objektumként kerül
	# ugyanarra a cellára. A 4-es index a sandy közép, arra itt nem engedünk
	# sprinklert; a másik 8 index a külső szél és sarok.
	if ground_source == TERRAIN_SOURCE_ID:
		var sandy_edge_index: int = SANDY_EDGE_VISUALS.find(
			ground_atlas
		)

		if sandy_edge_index >= 0:
			return sandy_edge_index != 4

	# ------------------------------------------------------------
	# FALLBACK – runtime épített Loamy/Sandy mezők
	# ------------------------------------------------------------
	# Ha valamilyen runtime/custom mező nem a vizuális 3x3 edge atlasokat
	# használja, akkor csak tényleges Plantable Loamy/Sandy cellán végzünk
	# topológiai peremvizsgálatot.
	if plantable_source == -1:
		return false

	var soil_type: String = (
		BiomeSystem.get_soil_type_at_cell(cell)
	).strip_edges().to_lower()

	if soil_type != "loamy" and soil_type != "sandy":
		return false

	var cardinal_directions: Array[Vector2i] = [
		Vector2i.UP,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.RIGHT
	]

	for direction: Vector2i in cardinal_directions:
		var neighbour: Vector2i = cell + direction

		if _tilemap.get_cell_source_id(
			_plantable_layer,
			neighbour
		) == -1:
			return true

		var neighbour_soil: String = (
			BiomeSystem.get_soil_type_at_cell(neighbour)
		).strip_edges().to_lower()

		if neighbour_soil != soil_type:
			return true

	return false


# Returns the current get decoration place status result.
func _get_decoration_place_status(
	cell: Vector2i,
	build_id: StringName,
	cost: int,
	replacing: bool
) -> Dictionary:
	if PlantRegistry.get_plant(cell) != null:
		return _failed_status(REASON_OCCUPIED_BY_PLANT, build_id)

	if _has_build_record(cell, "object"):
		return _failed_status(REASON_BLOCKED_BY_BUILD_OBJECT, build_id)

	if _has_protected_map_content(cell, false):
		return _failed_status(REASON_BLOCKED_LAYER, build_id)

	if not _has_surface_at(cell):
		return _failed_status(REASON_DECOR_NEEDS_SURFACE, build_id)

	var item: Dictionary = _get_item(build_id)
	var placement_surface: StringName = StringName(
		item.get("placement_surface", &"")
	)

	if placement_surface == &"water":
		if not _is_water_cell(cell):
			return _failed_status(
				REASON_WATER_DECOR_NEEDS_WATER,
				build_id
			)
		return {
			"ok": true,
			"reason": "",
			"cost": cost,
			"replace": replacing
		}

	if _tilemap.get_cell_source_id(
		_plantable_layer,
		cell
	) != -1:
		return _failed_status(REASON_DECOR_ON_PLANTABLE, build_id)

	if _is_water_cell(cell):
		return _failed_status(REASON_DECOR_ON_WATER, build_id)

	return {
		"ok": true,
		"reason": "",
		"cost": cost,
		"replace": replacing
	}


# Places the selected at.
func place_selected_at(cell: Vector2i) -> bool:
	var build_id: StringName = _selected_build_id
	var status: Dictionary = get_place_status(cell, build_id)

	if not bool(status.get("ok", false)):
		_emit_failed(
			cell,
			build_id,
			String(status.get("reason", ""))
		)
		return false

	var item: Dictionary = _get_item(build_id)
	var cost: int = int(status.get("cost", 0))
	var slot: String = String(item.get("slot", "surface"))
	var replacing: bool = bool(status.get("replace", false))
	var old_build_id: StringName = StringName(
		status.get("old_build_id", &"")
	)
	var credit_delta: int = int(
		status.get("credit_delta", cost)
	)

	if credit_delta > 0:
		if not ProgressionSystem.spend_build_cell_credits(
			credit_delta,
			"BUILD_%s" % String(build_id).to_upper()
		):
			_emit_failed(cell, build_id, REASON_NO_CREDITS)
			return false
	elif credit_delta < 0:
		ProgressionSystem.add_build_cell_credits(
			-credit_delta,
			"BUILD_REPLACE_REFUND_%s" % String(
				old_build_id
			).to_upper()
		)

	match slot:
		"object":
			_place_object(
				cell,
				build_id,
				item,
				cost,
				replacing
			)
		"decoration":
			_place_decoration(
				cell,
				build_id,
				item,
				cost,
				replacing
			)
		_:
			_place_surface(
				cell,
				build_id,
				item,
				cost,
				replacing
			)

	_refresh_world_after_edit()
	build_cell_placed.emit(cell, build_id, cost)

	if replacing:
		_set_status(
			"%s replaced with %s. Credit change: %d" % [
				_get_display_name(old_build_id),
				String(item.get("display_name", build_id)),
				credit_delta
			],
			false
		)
	else:
		_set_status(
			"%s placed. -%d credits" % [
				String(item.get("display_name", build_id)),
				cost
			],
			false
		)

	if debug_log:
		print(
			"[Build] ",
			"REPLACE" if replacing else "PLACE",
			" old=",
			String(old_build_id),
			" new=",
			String(build_id),
			" cell=",
			cell,
			" slot=",
			slot,
			" credit_delta=",
			credit_delta,
			" credits=",
			ProgressionSystem.build_cell_credits
		)
		_log_cell_tiles(cell)

	return true


# Places or replaces a buildable surface tile.
func _place_surface(
	cell: Vector2i,
	build_id: StringName,
	item: Dictionary,
	cost: int,
	replacing: bool
) -> void:
	var record: Dictionary = _get_build_record(cell, "surface")

	if not replacing or record.is_empty():
		record = {
			"filler_before": _capture_tile(_filler_layer, cell),
			"ground_before": _capture_tile(_ground_layer, cell),
			"plantable_before": _capture_tile(_plantable_layer, cell),
			"soil_override_before": get_built_soil_type(cell)
		}
	else:
		_restore_tile(
			_filler_layer,
			cell,
			record.get("filler_before", {})
		)
		_restore_tile(
			_ground_layer,
			cell,
			record.get("ground_before", {})
		)
		_restore_tile(
			_plantable_layer,
			cell,
			record.get("plantable_before", {})
		)

	record["build_id"] = build_id
	record["cost"] = cost
	_set_build_record(cell, "surface", record)

	_remove_blocking_collision(cell)
	_built_soil_overrides.erase(cell)

	var filler_source_id: int = int(
		item.get("filler_source_id", -1)
	)
	var filler_atlas: Vector2i = item.get(
		"filler_atlas",
		NO_TILE
	)

	if filler_source_id >= 0 and filler_atlas != NO_TILE:
		_tilemap.set_cell(
			_filler_layer,
			cell,
			filler_source_id,
			filler_atlas,
			0
		)

	var source_id: int = int(item.get("source_id", -1))
	var atlas: Vector2i = item.get("atlas", NO_TILE)

	_tilemap.set_cell(
		_ground_layer,
		cell,
		source_id,
		atlas,
		0
	)

	var plantable_source_id: int = int(
		item.get("plantable_source_id", -1)
	)
	var plantable_atlas: Vector2i = item.get(
		"plantable_atlas",
		NO_TILE
	)
	var soil_type: String = String(item.get("soil_type", ""))

	if (
		plantable_source_id >= 0
		and plantable_atlas != NO_TILE
	):
		_tilemap.set_cell(
			_plantable_layer,
			cell,
			plantable_source_id,
			plantable_atlas,
			0
		)

		if soil_type != "":
			_built_soil_overrides[cell] = soil_type
	elif soil_type != "":
		_tilemap.set_cell(
			_plantable_layer,
			cell,
			source_id,
			atlas,
			0
		)
		_built_soil_overrides[cell] = soil_type
	else:
		_tilemap.erase_cell(_plantable_layer, cell)

	if bool(item.get("blocks_movement", false)):
		_create_blocking_collision(cell, "BuildSurface")


# Places a buildable world object.
func _place_object(
	cell: Vector2i,
	build_id: StringName,
	item: Dictionary,
	cost: int,
	replacing: bool,
	rotation_override: int = -1
) -> void:
	if build_id == BUILD_ID_SEED_STORAGE:
		var rotation: int = (
			rotation_override
			if rotation_override >= 0
			else _get_build_rotation(build_id)
		)
		var object_cells: Array[Vector2i] = _get_object_target_cells(
			cell,
			build_id,
			rotation
		)
		var visuals: Array[Dictionary] = _get_object_visual_entries(
			build_id,
			rotation
		)

		for index: int in range(object_cells.size()):
			var target_cell: Vector2i = object_cells[index]
			var record: Dictionary = {
				"build_id": build_id,
				"cost": cost,
				"multi_object": bool(item.get("multi_object", false)),
				"is_anchor": index == 0,
				"anchor_cell": cell,
				"rotation": rotation,
				"object_cells": object_cells.duplicate(),
				"objects_before": _capture_tile(
					_objects_layer,
					target_cell
				)
			}
			_set_build_record(target_cell, "object", record)
			_remove_blocking_collision(target_cell)

			var visual: Dictionary = visuals[index]
			var atlas: Vector2i = visual.get("atlas", NO_TILE)

			_tilemap.set_cell(
				_objects_layer,
				target_cell,
				int(item.get("source_id", -1)),
				atlas,
				0
			)

			if bool(item.get("blocks_movement", false)):
				_create_blocking_collision(
					target_cell,
					"BuildObject"
				)
		return

	var record: Dictionary = _get_build_record(cell, "object")

	if not replacing or record.is_empty():
		record = {
			"objects_before": _capture_tile(_objects_layer, cell)
		}
	else:
		_restore_tile(
			_objects_layer,
			cell,
			record.get("objects_before", {})
		)

	record["build_id"] = build_id
	record["cost"] = cost
	_set_build_record(cell, "object", record)

	_remove_blocking_collision(cell)

	if bool(item.get("runtime_visual", false)):
		_tilemap.erase_cell(
			_objects_layer,
			cell
		)
	else:
		var atlas: Vector2i = item.get(
			"atlas",
			NO_TILE
		)

		_tilemap.set_cell(
			_objects_layer,
			cell,
			int(item.get("source_id", -1)),
			atlas,
			0
		)

	if bool(item.get("blocks_movement", false)):
		_create_blocking_collision(
			cell,
			"BuildObject"
		)


# Places a decorative build item.
func _place_decoration(
	cell: Vector2i,
	build_id: StringName,
	item: Dictionary,
	cost: int,
	replacing: bool
) -> void:
	var record: Dictionary = _get_build_record(
		cell,
		"decoration"
	)

	if not replacing or record.is_empty():
		record = {
			"decoration_before": _capture_tile(
				_decorations_layer,
				cell
			)
		}
	else:
		_restore_tile(
			_decorations_layer,
			cell,
			record.get("decoration_before", {})
		)

	record["build_id"] = build_id
	record["cost"] = cost
	_set_build_record(cell, "decoration", record)

	var atlas: Vector2i = item.get(
		"atlas",
		NO_TILE
	)

	_tilemap.set_cell(
		_decorations_layer,
		cell,
		int(item.get("source_id", -1)),
		atlas,
		0
	)


# Removes the player build at.
func remove_player_build_at(cell: Vector2i) -> bool:
	if not _is_configured():
		_emit_failed(cell, _selected_build_id, REASON_NOT_CONFIGURED)
		return false

	if _is_player_cell(cell):
		_emit_failed(cell, _selected_build_id, REASON_PLAYER_CELL)
		return false

	if _has_build_record(cell, "object"):
		var object_record: Dictionary = _get_build_record(
			cell,
			"object"
		)
		var object_build_id := StringName(
			object_record.get("build_id", &"")
		)

		if (
			object_build_id == BUILD_ID_SEED_STORAGE
			and not ChestSystem.is_chest_empty(cell)
		):
			_emit_failed(
				cell,
				object_build_id,
				REASON_STORAGE_NOT_EMPTY
			)
			return false

		return _remove_build_slot(cell, "object")

	if _has_build_record(cell, "decoration"):
		return _remove_build_slot(cell, "decoration")

	if _has_build_record(cell, "surface"):
		if PlantRegistry.get_plant(cell) != null:
			var surface: Dictionary = _get_build_record(cell, "surface")
			_emit_failed(
				cell,
				StringName(surface.get("build_id", &"")),
				REASON_OCCUPIED_BY_PLANT
			)
			return false

		return _remove_build_slot(cell, "surface")

	_emit_failed(cell, _selected_build_id, REASON_NOT_PLAYER_BUILT)
	return false


# Removes the build slot.
func _remove_build_slot(cell: Vector2i, slot: String) -> bool:
	var record: Dictionary = _get_build_record(cell, slot)

	if record.is_empty():
		return false

	if slot == "object" and bool(record.get("multi_object", false)):
		var anchor_cell: Vector2i = record.get("anchor_cell", cell)
		var anchor_record: Dictionary = _get_build_record(
			anchor_cell,
			"object"
		)

		if anchor_record.is_empty():
			anchor_record = record

		var build_id_multi := StringName(
			anchor_record.get("build_id", &"")
		)
		var original_cost_multi: int = int(
			anchor_record.get("cost", 0)
		)
		var refund_multi: int = maxi(
			int(
				round(
					float(original_cost_multi)
					* refund_ratio
				)
			),
			0
		)
		var object_cells_variant: Variant = anchor_record.get(
			"object_cells",
			[anchor_cell]
		)
		var object_cells: Array = [anchor_cell]

		if typeof(object_cells_variant) == TYPE_ARRAY:
			object_cells = object_cells_variant

		for object_cell_variant: Variant in object_cells:
			if not (object_cell_variant is Vector2i):
				continue

			var object_cell: Vector2i = object_cell_variant
			var cell_record: Dictionary = _get_build_record(
				object_cell,
				"object"
			)
			_remove_blocking_collision(object_cell)
			_restore_tile(
				_objects_layer,
				object_cell,
				cell_record.get("objects_before", {})
			)
			_erase_build_record(object_cell, "object")

		if refund_multi > 0:
			ProgressionSystem.add_build_cell_credits(
				refund_multi,
				"BUILD_REFUND_%s" % String(
					build_id_multi
				).to_upper()
			)

		_refresh_world_after_edit()
		build_cell_removed.emit(
			anchor_cell,
			build_id_multi,
			refund_multi
		)
		_set_status(
			"Removed %s. +%d credits" % [
				_get_display_name(build_id_multi),
				refund_multi
			],
			false
		)

		if debug_log:
			print(
				"[Build] REMOVE multi id=",
				String(build_id_multi),
				" anchor=",
				anchor_cell,
				" cells=",
				object_cells,
				" refund=",
				refund_multi
			)

		return true

	var build_id: StringName = StringName(record.get("build_id", &""))
	var original_cost: int = int(record.get("cost", 0))
	var refund: int = maxi(
		int(round(float(original_cost) * refund_ratio)),
		0
	)

	match slot:
		"object":
			_remove_blocking_collision(cell)
			_restore_tile(
				_objects_layer,
				cell,
				record.get("objects_before", {})
			)
			_erase_build_record(cell, "object")
		"decoration":
			_restore_tile(
				_decorations_layer,
				cell,
				record.get("decoration_before", {})
			)
			_erase_build_record(cell, "decoration")
		_:
			_remove_blocking_collision(cell)
			_restore_tile(
				_filler_layer,
				cell,
				record.get("filler_before", {})
			)
			_restore_tile(
				_ground_layer,
				cell,
				record.get("ground_before", {})
			)
			_restore_tile(
				_plantable_layer,
				cell,
				record.get("plantable_before", {})
			)

			var previous_soil: String = String(
				record.get("soil_override_before", "")
			)

			if previous_soil == "":
				_built_soil_overrides.erase(cell)
			else:
				_built_soil_overrides[cell] = previous_soil

			_erase_build_record(cell, "surface")

	if refund > 0:
		ProgressionSystem.add_build_cell_credits(
			refund,
			"BUILD_REFUND_%s" % String(build_id).to_upper()
		)

	_refresh_world_after_edit()
	build_cell_removed.emit(cell, build_id, refund)

	_set_status(
		"Removed %s. +%d credits" % [
			_get_display_name(build_id),
			refund
		],
		false
	)

	if debug_log:
		print(
			"[Build] REMOVE id=",
			String(build_id),
			" cell=",
			cell,
			" slot=",
			slot,
			" refund=",
			refund,
			" credits=",
			ProgressionSystem.build_cell_credits
		)
		_log_cell_tiles(cell)

	return true


# Updates this system every frame.
func _process(delta: float) -> void:
	if not _active:
		return

	_update_build_camera(delta)
	_update_preview()


# Build mode uses _input so the editor camera remains responsive while the world is paused.
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey

		if (
			key_event.pressed
			and not key_event.echo
			and key_event.keycode == KEY_B
		):
			if _active:
				_set_active(false)
			elif not get_tree().paused:
				_set_active(true)

			get_viewport().set_input_as_handled()
			return

		if (
			_active
			and key_event.pressed
			and not key_event.echo
			and key_event.keycode == KEY_ESCAPE
		):
			_set_active(false)
			get_viewport().set_input_as_handled()
			return

		if (
			_active
			and key_event.pressed
			and not key_event.echo
			and key_event.keycode == KEY_R
		):
			if _rotate_selected_build():
				get_viewport().set_input_as_handled()
			return

	if not _active:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_dragging = mouse_event.pressed

			if mouse_event.pressed:
				get_viewport().set_input_as_handled()
			return

		if (
			mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP
		):
			_change_build_zoom(build_camera_zoom_step)
			get_viewport().set_input_as_handled()
			return

		if (
			mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			_change_build_zoom(-build_camera_zoom_step)
			get_viewport().set_input_as_handled()
			return

		if not mouse_event.pressed:
			return

		if _is_pointer_over_hud():
			return

		var target_cell: Vector2i = _get_mouse_cell()

		if debug_log:
			print(
				"[Build] INPUT button=",
				mouse_event.button_index,
				" cell=",
				target_cell,
				" selected=",
				String(_selected_build_id),
				" rotation=",
				_get_rotation_name(_selected_rotation)
			)

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			place_selected_at(target_cell)
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			remove_player_build_at(target_cell)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _middle_dragging:
		var motion := event as InputEventMouseMotion

		if _camera != null:
			var zoom_factor: float = maxf(_camera.zoom.x, 0.01)
			_camera.global_position -= motion.relative / zoom_factor
			get_viewport().set_input_as_handled()


# Sets the active.
func _set_active(active: bool) -> void:
	if _active == active:
		return

	if active:
		_enter_build_view()
	else:
		_exit_build_view()

	_active = active

	if _top_bar != null:
		_top_bar.visible = _active

	if _palette_panel != null:
		_palette_panel.visible = _active

	if _preview != null:
		_preview.visible = _active

	if _ghost_preview != null:
		_ghost_preview.visible = _active

	if _active:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_set_status(
			"WASD / screen edge / middle-drag: move map  •  Wheel: zoom  •  R: rotate  •  Left: build  •  Right: remove",
			false
		)

	build_mode_changed.emit(_active)
	_refresh_hud()
	_update_ghost_texture()

	if debug_log:
		print(
			"[BuildSystem] mode=",
			"ON" if _active else "OFF"
		)


# Enters the build view.
func _enter_build_view() -> void:
	if not _is_configured():
		return

	_saved_tree_paused = get_tree().paused

	if _gameplay_overlays != null:
		_saved_overlays_visible = _gameplay_overlays.visible
		_gameplay_overlays.visible = false

	if _player != null:
		_saved_player_visible = _player.visible
		_player.visible = false

	if _camera != null:
		_saved_camera_position = _camera.position
		_saved_camera_zoom = _camera.zoom
		_saved_camera_smoothing = _camera.position_smoothing_enabled

		_camera.position_smoothing_enabled = false
		_camera.zoom = Vector2(
			build_camera_default_zoom,
			build_camera_default_zoom
		)
		_set_build_camera_limits()

	_middle_dragging = false
	get_tree().paused = true


# Exits the build view.
func _exit_build_view() -> void:
	_middle_dragging = false

	if _camera != null:
		_camera.position_smoothing_enabled = _saved_camera_smoothing
		_camera.zoom = _saved_camera_zoom
		_camera.position = _saved_camera_position
		_refresh_camera_limits()

	if _player != null:
		_player.visible = _saved_player_visible

	if _gameplay_overlays != null:
		_gameplay_overlays.visible = _saved_overlays_visible

	get_tree().paused = _saved_tree_paused


# Updates the build camera.
func _update_build_camera(delta: float) -> void:
	if _camera == null:
		return

	var keyboard_direction: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	var edge_direction: Vector2 = (
		_get_build_edge_pan_direction()
	)

	var direction: Vector2 = (
		keyboard_direction + edge_direction
	)

	if direction.length_squared() <= 0.0:
		return

	if direction.length() > 1.0:
		direction = direction.normalized()

	var zoom_factor: float = maxf(
		_camera.zoom.x,
		0.01
	)

	_camera.global_position += (
		direction
		* build_camera_pan_speed
		* delta
		/ zoom_factor
	)


# Returns the build edge pan direction.
func _get_build_edge_pan_direction() -> Vector2:
	if (
		not build_edge_pan_enabled
		or _camera == null
		or _is_pointer_over_hud()
	):
		return Vector2.ZERO

	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)
	var mouse_position: Vector2 = (
		get_viewport().get_mouse_position()
	)
	var margin: float = maxf(
		build_edge_pan_margin_pixels,
		1.0
	)

	var direction := Vector2.ZERO

	if mouse_position.x < margin:
		direction.x = -(
			1.0 - clampf(
				mouse_position.x / margin,
				0.0,
				1.0
			)
		)
	elif mouse_position.x > viewport_size.x - margin:
		direction.x = (
			1.0 - clampf(
				(viewport_size.x - mouse_position.x)
				/ margin,
				0.0,
				1.0
			)
		)

	if mouse_position.y < margin:
		direction.y = -(
			1.0 - clampf(
				mouse_position.y / margin,
				0.0,
				1.0
			)
		)
	elif mouse_position.y > viewport_size.y - margin:
		direction.y = (
			1.0 - clampf(
				(viewport_size.y - mouse_position.y)
				/ margin,
				0.0,
				1.0
			)
		)

	return direction * build_edge_pan_speed_multiplier


# Changes the build zoom.
func _change_build_zoom(delta_zoom: float) -> void:
	if _camera == null:
		return

	var minimum_zoom: float = build_camera_min_zoom

	if (
		WorldBoundsSystem != null
		and WorldBoundsSystem.has_method(
			"get_minimum_camera_zoom_for_current_bounds"
		)
	):
		minimum_zoom = maxf(
			minimum_zoom,
			WorldBoundsSystem.get_minimum_camera_zoom_for_current_bounds()
		)

	var next_zoom: float = clampf(
		_camera.zoom.x + delta_zoom,
		minimum_zoom,
		build_camera_max_zoom
	)

	_camera.zoom = Vector2(next_zoom, next_zoom)

	if debug_log:
		print(
			"[BuildSystem] camera zoom=",
			next_zoom,
			" min_fit=",
			minimum_zoom
		)


# Checks whether this system is configured for the current world.
func _is_configured() -> bool:
	return (
		_tilemap != null
		and _player != null
		and _camera != null
		and _filler_layer >= 0
		and _ground_layer >= 0
		and _plantable_layer >= 0
		and _objects_layer >= 0
		and _decorations_layer >= 0
	)


# Returns the mouse cell.
func _get_mouse_cell() -> Vector2i:
	var mouse_global: Vector2 = _tilemap.get_global_mouse_position()
	return _tilemap.local_to_map(
		_tilemap.to_local(mouse_global)
	)


# Checks whether the target cell is occupied by the player.
func _is_player_cell(cell: Vector2i) -> bool:
	if _player == null:
		return false

	var player_cell: Vector2i = _tilemap.local_to_map(
		_tilemap.to_local(_player.global_position)
	)

	return player_cell == cell


# Checks whether protected map content exists or is available.
func _has_protected_map_content(
	cell: Vector2i,
	ignore_player_built_object: bool
) -> bool:
	for layer: int in [
		_intersections_layer,
		_house_layer
	]:
		if (
			layer >= 0
			and _tilemap.get_cell_source_id(layer, cell) != -1
		):
			return true

	if (
		_objects_layer >= 0
		and _tilemap.get_cell_source_id(
			_objects_layer,
			cell
		) != -1
	):
		if not (
			ignore_player_built_object
			and _has_build_record(cell, "object")
		):
			return true

	return false


# Checks whether surface at exists or is available.
func _has_surface_at(cell: Vector2i) -> bool:
	return (
		_tilemap.get_cell_source_id(_ground_layer, cell) != -1
		or _tilemap.get_cell_source_id(_plantable_layer, cell) != -1
	)


# Checks whether adjacent surface exists or is available.
func _has_adjacent_surface(cell: Vector2i) -> bool:
	for offset: Vector2i in [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN
	]:
		if _has_surface_at(cell + offset):
			return true

	return false


# Returns true only when the candidate touches the surface component that can
# be traced back to the original map. This is stronger than plain adjacency:
# even if a disconnected legacy island exists, it cannot become an expansion
# anchor.
func _has_adjacent_main_map_surface(
	cell: Vector2i
) -> bool:
	for offset: Vector2i in [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN
	]:
		var neighbour: Vector2i = cell + offset

		if (
			_has_surface_at(neighbour)
			and _surface_cell_reaches_base_map(neighbour)
		):
			return true

	return false


# Checks whether a surface cell remains connected to the base map.
func _surface_cell_reaches_base_map(
	start_cell: Vector2i
) -> bool:
	if not _has_surface_at(start_cell):
		return false

	if _base_surface_cells.has(start_cell):
		return true

	var open: Array[Vector2i] = [start_cell]
	var visited: Dictionary = {
		start_cell: true
	}

	var index: int = 0

	while index < open.size():
		var current: Vector2i = open[index]
		index += 1

		for offset: Vector2i in [
			Vector2i.LEFT,
			Vector2i.RIGHT,
			Vector2i.UP,
			Vector2i.DOWN
		]:
			var next_cell: Vector2i = current + offset

			if visited.has(next_cell):
				continue

			if not _has_surface_at(next_cell):
				continue

			if _base_surface_cells.has(next_cell):
				return true

			visited[next_cell] = true
			open.append(next_cell)

	return false


# Captures the base surface cells for save, restore, or validation.
func _capture_base_surface_cells() -> void:
	_base_surface_cells.clear()

	if _tilemap == null:
		return

	for layer: int in [
		_ground_layer,
		_plantable_layer
	]:
		if layer < 0:
			continue

		for cell: Vector2i in _tilemap.get_used_cells(layer):
			_base_surface_cells[cell] = true

	if debug_log:
		print(
			"[BuildSystem] base surface captured cells=",
			_base_surface_cells.size()
		)


# Checks whether the cell already matches the selected surface.
func _matches_selected_surface(
	cell: Vector2i,
	build_id: StringName
) -> bool:
	var item: Dictionary = _get_item(build_id)

	if String(item.get("slot", "surface")) != "surface":
		return false

	var atlas: Vector2i = item.get(
		"atlas",
		NO_TILE
	)

	return (
		_tilemap.get_cell_source_id(_ground_layer, cell)
		== int(item.get("source_id", -1))
		and _tilemap.get_cell_atlas_coords(_ground_layer, cell)
		== atlas
	)


# Checks whether the target cell uses a water surface.
func _is_water_cell(cell: Vector2i) -> bool:
	if _has_build_record(cell, "surface"):
		var record: Dictionary = _get_build_record(cell, "surface")
		var build_id: StringName = StringName(
			record.get("build_id", &"")
		)
		var item: Dictionary = _get_item(build_id)

		if StringName(item.get("category", &"")) == CATEGORY_WATER:
			return true

	if _tilemap.get_cell_source_id(_ground_layer, cell) != TERRAIN_SOURCE_ID:
		return false

	return WATER_VISUALS.has(
		_tilemap.get_cell_atlas_coords(_ground_layer, cell)
	)


# Checks whether the target cell uses a grass surface.
func _is_grass_cell(cell: Vector2i) -> bool:
	if _tilemap.get_cell_source_id(
		_plantable_layer,
		cell
	) != -1:
		return false

	if _is_water_cell(cell):
		return false

	if _tilemap.get_cell_source_id(
		_ground_layer,
		cell
	) != TERRAIN_SOURCE_ID:
		return false

	var atlas: Vector2i = _tilemap.get_cell_atlas_coords(
		_ground_layer,
		cell
	)

	if atlas == Vector2i(1, 11):
		return true

	if GROUND_DECOR_VISUALS.has(atlas):
		return true

	return false


# Checks whether the target cell uses a path surface.
func _is_path_cell(cell: Vector2i) -> bool:
	if _tilemap.get_cell_source_id(
		_plantable_layer,
		cell
	) != -1:
		return false

	if _is_water_cell(cell):
		return false

	if _has_build_record(cell, "surface"):
		var record: Dictionary = _get_build_record(
			cell,
			"surface"
		)
		var build_id := StringName(
			record.get("build_id", &"")
		)
		var item: Dictionary = _get_item(build_id)

		if StringName(
			item.get("category", &"")
		) == CATEGORY_PATH:
			return true

	if _tilemap.get_cell_source_id(
		_ground_layer,
		cell
	) != TERRAIN_SOURCE_ID:
		return false

	return PATH_VISUALS.has(
		_tilemap.get_cell_atlas_coords(
			_ground_layer,
			cell
		)
	)


# Captures the tile for save, restore, or validation.
func _capture_tile(
	layer: int,
	cell: Vector2i
) -> Dictionary:
	var source_id: int = _tilemap.get_cell_source_id(layer, cell)

	if source_id == -1:
		return {"empty": true}

	return {
		"empty": false,
		"source_id": source_id,
		"atlas_coords": _tilemap.get_cell_atlas_coords(layer, cell),
		"alternative_tile": _tilemap.get_cell_alternative_tile(layer, cell)
	}


# Restores the tile from saved or temporary state.
func _restore_tile(
	layer: int,
	cell: Vector2i,
	snapshot_variant: Variant
) -> void:
	var snapshot: Dictionary = {}

	if typeof(snapshot_variant) == TYPE_DICTIONARY:
		snapshot = snapshot_variant

	if bool(snapshot.get("empty", true)):
		_tilemap.erase_cell(layer, cell)
		return

	var atlas_coords: Vector2i = snapshot.get("atlas_coords", NO_TILE)

	_tilemap.set_cell(
		layer,
		cell,
		int(snapshot.get("source_id", -1)),
		atlas_coords,
		int(snapshot.get("alternative_tile", 0))
	)


# Sets the build record.
func _set_build_record(
	cell: Vector2i,
	slot: String,
	record: Dictionary
) -> void:
	var cell_record: Dictionary = _placed_cells.get(cell, {})
	cell_record[slot] = record
	_placed_cells[cell] = cell_record


# Returns the build record.
func _get_build_record(
	cell: Vector2i,
	slot: String
) -> Dictionary:
	var cell_record: Dictionary = _placed_cells.get(cell, {})
	var value: Variant = cell_record.get(slot, {})

	if typeof(value) == TYPE_DICTIONARY:
		return value

	return {}


# Checks whether build record exists or is available.
func _has_build_record(cell: Vector2i, slot: String) -> bool:
	return not _get_build_record(cell, slot).is_empty()


# Erases the build record.
func _erase_build_record(cell: Vector2i, slot: String) -> void:
	if not _placed_cells.has(cell):
		return

	var cell_record: Dictionary = _placed_cells[cell]
	cell_record.erase(slot)

	if cell_record.is_empty():
		_placed_cells.erase(cell)
	else:
		_placed_cells[cell] = cell_record


# Refreshes the world after edit.
func _refresh_world_after_edit() -> void:
	if BiomeSystem.has_method("refresh_from_tilemap_preserving_stats"):
		BiomeSystem.refresh_from_tilemap_preserving_stats()

	if _active:
		_set_build_camera_limits()
	else:
		_refresh_camera_limits()

	_refresh_hud()


# Refreshes the camera limits.
func _refresh_camera_limits() -> void:
	_apply_camera_limits_for_rect(
		_tilemap.get_used_rect()
	)


# Sets the build camera limits.
func _set_build_camera_limits() -> void:
	var used: Rect2i = _tilemap.get_used_rect()

	if used.size == Vector2i.ZERO:
		return

	var expanded := Rect2i(
		used.position - Vector2i(
			build_camera_margin_cells,
			build_camera_margin_cells
		),
		used.size + Vector2i(
			build_camera_margin_cells * 2,
			build_camera_margin_cells * 2
		)
	)

	_apply_camera_limits_for_rect(expanded)


# Applies the camera limits for rectangle.
func _apply_camera_limits_for_rect(rect: Rect2i) -> void:
	if (
		_tilemap == null
		or _camera == null
		or rect.size == Vector2i.ZERO
	):
		return

	var tile_size: Vector2i = _tilemap.tile_set.tile_size
	var top_left_local := Vector2(
		rect.position.x * tile_size.x,
		rect.position.y * tile_size.y
	)
	var bottom_right_local := Vector2(
		(rect.position.x + rect.size.x) * tile_size.x,
		(rect.position.y + rect.size.y) * tile_size.y
	)

	var top_left_global: Vector2 = _tilemap.to_global(
		top_left_local
	)
	var bottom_right_global: Vector2 = _tilemap.to_global(
		bottom_right_local
	)

	_camera.limit_left = int(top_left_global.x)
	_camera.limit_top = int(top_left_global.y)
	_camera.limit_right = int(bottom_right_global.x)
	_camera.limit_bottom = int(bottom_right_global.y)


# Checks whether the selected build item supports rotation.
func _is_rotatable_build(build_id: StringName) -> bool:
	var item: Dictionary = _get_item(build_id)
	return bool(item.get("rotatable", false))


# Rotates the currently selected build item.
func _rotate_selected_build() -> bool:
	if not _is_rotatable_build(_selected_build_id):
		return false

	_selected_rotation = posmod(_selected_rotation + 1, 4)
	_update_ghost_texture()
	_refresh_hud()

	if debug_log:
		print(
			"[BuildSystem] rotate selected=",
			String(_selected_build_id),
			" rotation=",
			_get_rotation_name(_selected_rotation)
		)

	return true


# Returns the rotation name.
func _get_rotation_name(rotation: int) -> String:
	match posmod(rotation, 4):
		0:
			return "Right"
		1:
			return "Down"
		2:
			return "Left"
		_:
			return "Up"


# Returns the build rotation.
func _get_build_rotation(build_id: StringName) -> int:
	if build_id == BUILD_ID_SEED_STORAGE:
		return posmod(_selected_rotation, 4)

	return 0


# Returns the object target cells.
func _get_object_target_cells(
	anchor_cell: Vector2i,
	build_id: StringName,
	rotation_override: int = -1
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor_cell]

	# Seed Storage now uses a single 32x32 sack tile.
	# No secondary footprint cell is added anymore.
	if build_id == BUILD_ID_SEED_STORAGE:
		return cells

	return cells


# Returns the object visual entries.
func _get_object_visual_entries(
	build_id: StringName,
	rotation_override: int = -1
) -> Array[Dictionary]:
	if build_id == BUILD_ID_SEED_STORAGE:
		return [
			{
				"offset": Vector2i.ZERO,
				"atlas": SEED_STORAGE_SINGLE_TILE
			}
		]

	return [
		{
			"offset": Vector2i.ZERO,
			"atlas": _get_item(build_id).get("atlas", NO_TILE)
		}
	]


# Returns the preview metrics.
func _get_preview_metrics(
	build_id: StringName,
	rotation: int
) -> Dictionary:
	var target_cells: Array[Vector2i] = _get_object_target_cells(
		Vector2i.ZERO,
		build_id,
		rotation
	)
	var min_x: int = 0
	var max_x: int = 0
	var min_y: int = 0
	var max_y: int = 0

	for offset_cell: Vector2i in target_cells:
		min_x = mini(min_x, offset_cell.x)
		max_x = maxi(max_x, offset_cell.x)
		min_y = mini(min_y, offset_cell.y)
		max_y = maxi(max_y, offset_cell.y)

	var tile_size := Vector2(_tilemap.tile_set.tile_size)

	return {
		"pixel_width": float(max_x - min_x + 1) * tile_size.x,
		"pixel_height": float(max_y - min_y + 1) * tile_size.y,
		"center_offset_x": float(min_x + max_x) * tile_size.x * 0.5,
		"center_offset_y": float(min_y + max_y) * tile_size.y * 0.5
	}


# Creates the seed storage texture.
func _make_seed_storage_texture(rotation: int = 0) -> Texture2D:
	var visuals: Array[Dictionary] = _get_object_visual_entries(
		BUILD_ID_SEED_STORAGE,
		rotation
	)
	var tile_size: Vector2i = _tilemap.tile_set.tile_size
	var min_x: int = 0
	var max_x: int = 0
	var min_y: int = 0
	var max_y: int = 0

	for entry: Dictionary in visuals:
		var offset: Vector2i = entry.get(
			"offset",
			Vector2i.ZERO
		)
		min_x = mini(min_x, offset.x)
		max_x = maxi(max_x, offset.x)
		min_y = mini(min_y, offset.y)
		max_y = maxi(max_y, offset.y)

	var image := Image.create(
		(max_x - min_x + 1) * tile_size.x,
		(max_y - min_y + 1) * tile_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for entry: Dictionary in visuals:
		var offset: Vector2i = entry.get(
			"offset",
			Vector2i.ZERO
		)
		var atlas: Vector2i = entry.get("atlas", NO_TILE)
		var tile_image: Image = _get_tile_image(
			FARMING_SOURCE_ID,
			atlas
		)

		if tile_image == null:
			continue

		var destination := Vector2i(
			(offset.x - min_x) * tile_size.x,
			(offset.y - min_y) * tile_size.y
		)
		image.blend_rect(
			tile_image,
			Rect2i(
				Vector2i.ZERO,
				tile_image.get_size()
			),
			destination
		)

	return ImageTexture.create_from_image(image)


# Creates the preview.
func _create_preview() -> void:
	if _preview != null:
		_preview.queue_free()

	if _ghost_preview != null:
		_ghost_preview.queue_free()

	_preview = Polygon2D.new()
	_preview.name = "BuildCellValidity"
	_preview.z_index = 999
	_preview.visible = false

	_ghost_preview = Sprite2D.new()
	_ghost_preview.name = "BuildTileGhost"
	_ghost_preview.z_index = 1000
	_ghost_preview.visible = false

	_tilemap.get_parent().add_child(_preview)
	_tilemap.get_parent().add_child(_ghost_preview)

	_update_ghost_texture()


# Updates the preview.
func _update_preview() -> void:
	if (
		_preview == null
		or _ghost_preview == null
		or not _is_configured()
	):
		return

	if _is_pointer_over_hud():
		_preview.visible = false
		_ghost_preview.visible = false
		return

	_preview.visible = true
	_ghost_preview.visible = true

	var cell: Vector2i = _get_mouse_cell()
	var rotation: int = _get_build_rotation(
		_selected_build_id
	)
	var metrics: Dictionary = _get_preview_metrics(
		_selected_build_id,
		rotation
	)
	var tile_size := Vector2(_tilemap.tile_set.tile_size)
	var anchor_position: Vector2 = _tilemap.to_global(
		_tilemap.map_to_local(cell)
	)
	var world_position: Vector2 = anchor_position + Vector2(
		float(metrics.get("center_offset_x", 0.0)),
		float(metrics.get("center_offset_y", 0.0))
	)
	var width: float = float(
		metrics.get("pixel_width", tile_size.x)
	)
	var height: float = float(
		metrics.get("pixel_height", tile_size.y)
	)
	var half := Vector2(width, height) * 0.5 - Vector2(2.0, 2.0)

	_preview.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
	_preview.global_position = world_position
	_ghost_preview.global_position = world_position

	var status: Dictionary = get_place_status(
		cell,
		_selected_build_id
	)
	var valid: bool = bool(status.get("ok", false))

	_preview.color = (
		Color(0.20, 1.0, 0.40, 0.32)
		if valid
		else Color(1.0, 0.18, 0.18, 0.34)
	)

	_ghost_preview.modulate = (
		Color(1.0, 1.0, 1.0, 0.78)
		if valid
		else Color(1.0, 0.38, 0.38, 0.70)
	)

	if _selected_build_id == BUILD_ID_SEED_STORAGE:
		_ghost_preview.texture = _make_seed_storage_texture(
			rotation
		)


# Updates the ghost texture.
func _update_ghost_texture() -> void:
	if _ghost_preview == null or not _is_configured():
		return

	if _selected_build_id == BUILD_ID_SEED_STORAGE:
		_ghost_preview.texture = _make_seed_storage_texture(
			_get_build_rotation(_selected_build_id)
		)
		return

	var item: Dictionary = _get_item(_selected_build_id)
	_ghost_preview.texture = _make_item_texture(item)


# Creates the collision root.
func _create_collision_root() -> void:
	if _collision_root != null:
		_collision_root.queue_free()

	_collision_root = Node2D.new()
	_collision_root.name = "BuildRuntimeCollisions"
	_tilemap.get_parent().add_child(_collision_root)
	_blocking_bodies.clear()


# Creates the blocking collision.
func _create_blocking_collision(
	cell: Vector2i,
	label: String
) -> void:
	if _collision_root == null:
		return

	_remove_blocking_collision(cell)

	var body := StaticBody2D.new()
	body.name = "%s_%d_%d" % [
		label,
		cell.x,
		cell.y
	]
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := RectangleShape2D.new()
	shape.size = Vector2(_tilemap.tile_set.tile_size)

	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	_collision_root.add_child(body)
	body.global_position = _tilemap.to_global(
		_tilemap.map_to_local(cell)
	)

	_blocking_bodies[cell] = body


# Removes the blocking collision.
func _remove_blocking_collision(cell: Vector2i) -> void:
	if not _blocking_bodies.has(cell):
		return

	var body: Node = _blocking_bodies[cell]

	if is_instance_valid(body):
		body.queue_free()

	_blocking_bodies.erase(cell)


# Clears the runtime state.
func _clear_runtime_state(restore_original_tiles: bool) -> void:
	if restore_original_tiles and _tilemap != null:
		for cell_variant: Variant in _placed_cells.keys():
			var cell: Vector2i = cell_variant
			var cell_record: Dictionary = _placed_cells[cell]

			if cell_record.has("object"):
				var object_record: Dictionary = cell_record["object"]
				_restore_tile(
					_objects_layer,
					cell,
					object_record.get("objects_before", {})
				)

			if cell_record.has("decoration"):
				var decoration_record: Dictionary = cell_record["decoration"]
				_restore_tile(
					_decorations_layer,
					cell,
					decoration_record.get(
						"decoration_before",
						{}
					)
				)

			if cell_record.has("surface"):
				var surface_record: Dictionary = cell_record["surface"]
				_restore_tile(
					_filler_layer,
					cell,
					surface_record.get("filler_before", {})
				)
				_restore_tile(
					_ground_layer,
					cell,
					surface_record.get("ground_before", {})
				)
				_restore_tile(
					_plantable_layer,
					cell,
					surface_record.get("plantable_before", {})
				)

	for cell_variant: Variant in _blocking_bodies.keys():
		var collision_cell: Vector2i = cell_variant
		_remove_blocking_collision(collision_cell)

	_placed_cells.clear()
	_built_soil_overrides.clear()

	if restore_original_tiles and _tilemap != null:
		_refresh_world_after_edit()


# Builds the catalog.
func _build_catalog() -> void:
	_catalog_items.clear()
	_items_by_id.clear()

	# Keep Terrain focused on simple map-building surfaces.
	_add_surface_item(
		&"grass_plain",
		CATEGORY_TERRAIN,
		"Grass",
		1,
		TERRAIN_SOURCE_ID,
		Vector2i(1, 11)
	)

	for index: int in range(GROUND_DECOR_VISUALS.size()):
		_add_ground_decor_item(
			StringName("ground_decor_%d" % index),
			GROUND_DECOR_NAMES[index],
			1,
			TERRAIN_SOURCE_ID,
			GROUND_DECOR_VISUALS[index]
		)

	for index: int in range(LOAMY_VISUALS.size()):
		_add_surface_item(
			StringName("loamy_%d" % index),
			CATEGORY_LOAMY,
			"Loamy %s" % EDGE_NAMES[index],
			2,
			TERRAIN_SOURCE_ID,
			LOAMY_VISUALS[index],
			SOIL_LOAMY
		)

	for index: int in range(SANDY_EDGE_VISUALS.size()):
		var is_center: bool = index == 4
		var item: Dictionary = {
			"id": StringName("sandy_%d" % index),
			"category": CATEGORY_SANDY,
			"display_name": "Sandy %s" % EDGE_NAMES[index],
			"cost": 2,
			"slot": "surface",
			"source_id": TERRAIN_SOURCE_ID,
			"atlas": SANDY_EDGE_VISUALS[index],
			"filler_source_id": TERRAIN_SOURCE_ID,
			"filler_atlas": SANDY_FILLER_BASE,
			"soil_type": String(SOIL_SANDY) if is_center else "",
			"blocks_movement": false
		}

		if is_center:
			item["plantable_source_id"] = TERRAIN_SOURCE_ID
			item["plantable_atlas"] = SANDY_PLANTABLE_CENTER

		_add_catalog_item(item)

	var water_names: Array[String] = [
		"Water Top Left",
		"Water Top",
		"Water Top Right",
		"Water Left",
		"Water Center",
		"Water Right",
		"Water Bottom Left",
		"Water Bottom",
		"Water Bottom Right",
		"Water Detail 1",
		"Water Detail 2",
		"Water Detail 3",
		"Water Pool"
	]

	for index: int in range(WATER_VISUALS.size()):
		_add_surface_item(
			StringName("water_%d" % index),
			CATEGORY_WATER,
			water_names[index],
			2,
			TERRAIN_SOURCE_ID,
			WATER_VISUALS[index],
			&"",
			true
		)

	for index: int in range(WATER_DECOR_VISUALS.size()):
		_add_water_decoration_item(
			StringName("water_decor_%d" % index),
			WATER_DECOR_NAMES[index],
			1,
			TERRAIN_SOURCE_ID,
			WATER_DECOR_VISUALS[index]
		)

	for index: int in range(PATH_VISUALS.size()):
		_add_surface_item(
			StringName("path_%d" % index),
			CATEGORY_PATH,
			"Stone Path %d" % (index + 1),
			1,
			TERRAIN_SOURCE_ID,
			PATH_VISUALS[index]
		)

	for index: int in range(FENCE_VISUALS.size()):
		_add_object_item(
			StringName("fence_wood_%d" % index),
			CATEGORY_FENCE,
			"Wood Fence %d" % (index + 1),
			2,
			FENCE_SOURCE_ID,
			FENCE_VISUALS[index]
		)

	for index: int in range(FENCE_VISUALS.size()):
		_add_object_item(
			StringName("fence_alt_%d" % index),
			CATEGORY_FENCE,
			"Alt Fence %d" % (index + 1),
			2,
			FENCE_ALT_SOURCE_ID,
			FENCE_VISUALS[index]
		)

	_add_catalog_item({
		"id": BUILD_ID_SPRINKLER,
		"category": CATEGORY_FARM_OBJECTS,
		"display_name": "Field Sprinkler",
		"cost": 20,
		"slot": "object",
		"source_id": -1,
		"atlas": NO_TILE,
		"soil_type": "",
		"blocks_movement": true,
		"runtime_visual": true,
		"runtime_kind": RUNTIME_KIND_SPRINKLER,
		"required_player_level": 10,
		# Special validation allows grass OR an outer Loamy/Sandy biome cell.
		"placement_surface": &"automation_surface"
	})

	_add_catalog_item({
		"id": BUILD_ID_FERTILIZER_INJECTOR,
		"category": CATEGORY_FARM_OBJECTS,
		"display_name": "Fertilizer Injector",
		"cost": 30,
		"slot": "object",
		"source_id": -1,
		"atlas": NO_TILE,
		"soil_type": "",
		"blocks_movement": true,
		"runtime_visual": true,
		"runtime_kind": RUNTIME_KIND_FERTILIZER_INJECTOR,
		"required_player_level": 20,
		"placement_surface": &"automation_surface"
	})

	_add_catalog_item({
		"id": BUILD_ID_SOIL_NEUTRALIZER,
		"category": CATEGORY_FARM_OBJECTS,
		"display_name": "Soil Neutralizer",
		"cost": 40,
		"slot": "object",
		"source_id": -1,
		"atlas": NO_TILE,
		"soil_type": "",
		"blocks_movement": true,
		"runtime_visual": true,
		"runtime_kind": RUNTIME_KIND_SOIL_NEUTRALIZER,
		"required_player_level": 30,
		"placement_surface": &"automation_surface"
	})

	_add_catalog_item({
		"id": BUILD_ID_PLANT_PROTECTION,
		"category": CATEGORY_FARM_OBJECTS,
		"display_name": "Plant Protection Station",
		"cost": 50,
		"slot": "object",
		"source_id": -1,
		"atlas": NO_TILE,
		"soil_type": "",
		"blocks_movement": true,
		"runtime_visual": true,
		"runtime_kind": RUNTIME_KIND_PLANT_PROTECTION,
		"required_player_level": 40,
		"placement_surface": &"automation_surface"
	})

	_add_catalog_item({
		"id": BUILD_ID_SEED_STORAGE,
		"category": CATEGORY_FARM_OBJECTS,
		"display_name": "Seed Storage",
		"cost": 15,
		"slot": "object",
		"source_id": FARMING_SOURCE_ID,
		"atlas": SEED_STORAGE_SINGLE_TILE,
		"soil_type": "",
		"blocks_movement": true,
		"runtime_visual": false,
		"placement_surface": &"dry_ground",
		"rotatable": false,
		"multi_object": false
	})

	_add_catalog_item({
		"id": BUILD_ID_REPAIR_ANVIL,
		"category": CATEGORY_FARM_OBJECTS,
		"display_name": "Repair Anvil",
		"cost": 30,
		"slot": "object",
		"source_id": FARMING_SOURCE_ID,
		"atlas": REPAIR_ANVIL_TILE,
		"soil_type": "",
		"blocks_movement": true,
		"runtime_visual": false,
		"placement_surface": &"dry_ground",
		"rotatable": false,
		"multi_object": false
	})


# Adds the surface item.
func _add_surface_item(
	build_id: StringName,
	category: StringName,
	display_name: String,
	cost: int,
	source_id: int,
	atlas: Vector2i,
	soil_type: StringName = &"",
	blocks_movement: bool = false
) -> void:
	_add_catalog_item({
		"id": build_id,
		"category": category,
		"display_name": display_name,
		"cost": cost,
		"slot": "surface",
		"source_id": source_id,
		"atlas": atlas,
		"soil_type": String(soil_type),
		"blocks_movement": blocks_movement
	})


# Adds the object item.
func _add_object_item(
	build_id: StringName,
	category: StringName,
	display_name: String,
	cost: int,
	source_id: int,
	atlas: Vector2i
) -> void:
	_add_catalog_item({
		"id": build_id,
		"category": category,
		"display_name": display_name,
		"cost": cost,
		"slot": "object",
		"source_id": source_id,
		"atlas": atlas,
		"soil_type": "",
		"blocks_movement": false
	})


# Adds the decoration item.
func _add_decoration_item(
	build_id: StringName,
	category: StringName,
	display_name: String,
	cost: int,
	source_id: int,
	atlas: Vector2i,
	placement_surface: StringName
) -> void:
	_add_catalog_item({
		"id": build_id,
		"category": category,
		"display_name": display_name,
		"cost": cost,
		"slot": "decoration",
		"source_id": source_id,
		"atlas": atlas,
		"soil_type": "",
		"blocks_movement": false,
		"placement_surface": placement_surface
	})


# Adds the ground decor item.
func _add_ground_decor_item(
	build_id: StringName,
	display_name: String,
	cost: int,
	source_id: int,
	atlas: Vector2i
) -> void:
	_add_catalog_item({
		"id": build_id,
		"category": CATEGORY_GROUND_DECOR,
		"display_name": display_name,
		"cost": cost,
		"slot": "surface",
		"source_id": source_id,
		"atlas": atlas,
		"soil_type": "",
		"blocks_movement": false,
		"placement_surface": &"grass"
	})


# Adds the water decoration item.
func _add_water_decoration_item(
	build_id: StringName,
	display_name: String,
	cost: int,
	source_id: int,
	atlas: Vector2i
) -> void:
	_add_decoration_item(
		build_id,
		CATEGORY_WATER_DECOR,
		display_name,
		cost,
		source_id,
		atlas,
		&"water"
	)


# Adds the catalog item.
func _add_catalog_item(item: Dictionary) -> void:
	var build_id: StringName = StringName(item.get("id", &""))

	_catalog_items.append(item)
	_items_by_id[build_id] = item


# Returns the item.
func _get_item(build_id: StringName) -> Dictionary:
	var value: Variant = _items_by_id.get(build_id, {})

	if typeof(value) == TYPE_DICTIONARY:
		return value

	return {}


# Returns the items for category.
func _get_items_for_category(
	category: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for item: Dictionary in _catalog_items:
		if StringName(item.get("category", &"")) == category:
			result.append(item)

	return result


# Creates the dedicated build editor UI. It remains outside TestLevel/Overlays.
func _create_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "BuildHUD"
	_hud_layer.layer = 30
	add_child(_hud_layer)

	_top_bar = PanelContainer.new()
	_top_bar.name = "BuildTopBar"
	_top_bar.anchor_left = 0.0
	_top_bar.anchor_right = 1.0
	_top_bar.anchor_top = 0.0
	_top_bar.anchor_bottom = 0.0
	_top_bar.offset_left = 12.0
	_top_bar.offset_right = -392.0
	_top_bar.offset_top = 12.0
	_top_bar.offset_bottom = 64.0
	_top_bar.visible = false
	_hud_layer.add_child(_top_bar)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 12)
	top_margin.add_theme_constant_override("margin_right", 12)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_bottom", 8)
	_top_bar.add_child(top_margin)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	top_margin.add_child(top_row)

	var title := Label.new()
	title.text = "BUILD MODE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	top_row.add_child(title)

	var controls := Label.new()
	controls.text = "WASD / MMB drag • Wheel zoom • B / Esc close"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(controls)

	_credits_label = Label.new()
	_credits_label.text = "Build Credits: 0"
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits_label.add_theme_font_size_override("font_size", 16)
	top_row.add_child(_credits_label)

	_palette_panel = PanelContainer.new()
	_palette_panel.name = "BuildPalette"
	_palette_panel.anchor_left = 1.0
	_palette_panel.anchor_right = 1.0
	_palette_panel.anchor_top = 0.0
	_palette_panel.anchor_bottom = 1.0
	_palette_panel.offset_left = -372.0
	_palette_panel.offset_right = -12.0
	_palette_panel.offset_top = 12.0
	_palette_panel.offset_bottom = -12.0
	_palette_panel.visible = false
	_hud_layer.add_child(_palette_panel)

	var palette_margin := MarginContainer.new()
	palette_margin.add_theme_constant_override("margin_left", 12)
	palette_margin.add_theme_constant_override("margin_right", 12)
	palette_margin.add_theme_constant_override("margin_top", 12)
	palette_margin.add_theme_constant_override("margin_bottom", 12)
	_palette_panel.add_child(palette_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	palette_margin.add_child(column)

	var selected_title := Label.new()
	selected_title.text = "SELECTED BLOCK"
	selected_title.add_theme_font_size_override("font_size", 13)
	column.add_child(selected_title)

	var selected_row := HBoxContainer.new()
	selected_row.custom_minimum_size = Vector2(0.0, 68.0)
	selected_row.add_theme_constant_override("separation", 10)
	column.add_child(selected_row)

	_selected_icon = TextureRect.new()
	_selected_icon.custom_minimum_size = Vector2(64.0, 64.0)
	_selected_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_selected_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_selected_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	selected_row.add_child(_selected_icon)

	_selected_name_label = Label.new()
	_selected_name_label.text = ""
	_selected_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selected_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_name_label.add_theme_font_size_override("font_size", 15)
	selected_row.add_child(_selected_name_label)

	var separator_a := HSeparator.new()
	column.add_child(separator_a)

	var category_title := Label.new()
	category_title.text = "CATEGORY"
	category_title.add_theme_font_size_override("font_size", 13)
	column.add_child(category_title)

	_category_grid = GridContainer.new()
	_category_grid.columns = 3
	_category_grid.add_theme_constant_override("h_separation", 5)
	_category_grid.add_theme_constant_override("v_separation", 5)
	column.add_child(_category_grid)

	var separator_b := HSeparator.new()
	column.add_child(separator_b)

	var blocks_title := Label.new()
	blocks_title.text = "BLOCKS"
	blocks_title.add_theme_font_size_override("font_size", 13)
	column.add_child(blocks_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = 4
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_grid.add_theme_constant_override("h_separation", 6)
	_item_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_item_grid)

	var separator_c := HSeparator.new()
	column.add_child(separator_c)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.custom_minimum_size = Vector2(0.0, 46.0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_status_label)


# Rebuilds the category buttons.
func _rebuild_category_buttons() -> void:
	if _category_grid == null:
		return

	for child: Node in _category_grid.get_children():
		child.queue_free()

	_category_buttons.clear()

	for category: StringName in CATEGORY_ORDER:
		var button := Button.new()
		button.text = String(
			CATEGORY_NAMES.get(
				category,
				String(category)
			)
		)
		button.custom_minimum_size = Vector2(104.0, 34.0)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(
			_on_category_pressed.bind(category)
		)
		_category_grid.add_child(button)
		_category_buttons[category] = button


# Rebuilds the item grid.
func _rebuild_item_grid() -> void:
	if _item_grid == null:
		return

	for child: Node in _item_grid.get_children():
		child.queue_free()

	_item_buttons.clear()

	for item: Dictionary in _get_items_for_category(
		_selected_category
	):
		var build_id: StringName = StringName(
			item.get("id", &"")
		)
		var button := Button.new()
		button.custom_minimum_size = Vector2(76.0, 76.0)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.expand_icon = true
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var required_level: int = _get_required_player_level(
			build_id
		)
		var unlocked: bool = _is_build_unlocked(build_id)

		if unlocked:
			button.tooltip_text = "%s\nCost: %d Build Credits" % [
				String(item.get("display_name", build_id)),
				int(item.get("cost", 0))
			]
		else:
			button.tooltip_text = "%s\nLOCKED • Player Level %d" % [
				String(item.get("display_name", build_id)),
				required_level
			]
			button.disabled = true

		button.icon = _make_item_texture(item)
		button.pressed.connect(
			_on_item_pressed.bind(build_id)
		)
		_item_grid.add_child(button)
		_item_buttons[build_id] = button

	_refresh_hud()


# Refreshes the HUD.
func _refresh_hud() -> void:
	if _credits_label != null:
		_credits_label.text = "Build Credits: %d" % (
			ProgressionSystem.build_cell_credits
		)

	for category_variant: Variant in _category_buttons.keys():
		var category: StringName = category_variant
		var category_button: Button = _category_buttons.get(
			category
		) as Button

		if category_button != null:
			category_button.button_pressed = (
				category == _selected_category
			)

	for item_variant: Variant in _item_buttons.keys():
		var build_id: StringName = item_variant
		var item_button: Button = _item_buttons.get(
			build_id
		) as Button

		if item_button != null:
			item_button.button_pressed = (
				build_id == _selected_build_id
			)

	var selected: Dictionary = _get_item(
		_selected_build_id
	)

	if _selected_name_label != null:
		var selected_text: String = "%s\nCost: %d" % [
			String(
				selected.get(
					"display_name",
					_selected_build_id
				)
			),
			int(selected.get("cost", 0))
		]

		if not _is_build_unlocked(_selected_build_id):
			selected_text += "\nLOCKED • Player Level %d" % (
				_get_required_player_level(
					_selected_build_id
				)
			)

		if bool(selected.get("rotatable", false)):
			selected_text += "\nR: Rotate  •  %s" % (
				_get_rotation_name(_selected_rotation)
			)

		_selected_name_label.text = selected_text

	if _selected_icon != null and _is_configured():
		if _selected_build_id == BUILD_ID_SEED_STORAGE:
			_selected_icon.texture = _make_seed_storage_texture(
				_get_build_rotation(_selected_build_id)
			)
		else:
			_selected_icon.texture = _make_item_texture(selected)


# Creates the item texture.
func _make_item_texture(item: Dictionary) -> Texture2D:
	if not _is_configured():
		return null

	var build_id: StringName = StringName(item.get("id", &""))

	if build_id == BUILD_ID_SEED_STORAGE:
		if _item_texture_cache.has(build_id):
			return _item_texture_cache[build_id] as Texture2D

		var storage_texture: Texture2D = _make_seed_storage_texture(0)
		_item_texture_cache[build_id] = storage_texture
		return storage_texture

	if _item_texture_cache.has(build_id):
		return _item_texture_cache[build_id] as Texture2D

	if bool(item.get("runtime_visual", false)):
		var runtime_texture: Texture2D = (
			_make_runtime_object_texture(item)
		)
		_item_texture_cache[build_id] = runtime_texture
		return runtime_texture

	var layers: Array[Dictionary] = []

	var filler_source_id: int = int(
		item.get("filler_source_id", -1)
	)
	var filler_atlas: Vector2i = item.get(
		"filler_atlas",
		NO_TILE
	)

	if filler_source_id >= 0 and filler_atlas != NO_TILE:
		layers.append({
			"source_id": filler_source_id,
			"atlas": filler_atlas
		})

	layers.append({
		"source_id": int(item.get("source_id", -1)),
		"atlas": item.get("atlas", NO_TILE)
	})

	var plantable_source_id: int = int(
		item.get("plantable_source_id", -1)
	)
	var plantable_atlas: Vector2i = item.get(
		"plantable_atlas",
		NO_TILE
	)

	if (
		plantable_source_id >= 0
		and plantable_atlas != NO_TILE
	):
		layers.append({
			"source_id": plantable_source_id,
			"atlas": plantable_atlas
		})

	if layers.size() == 1:
		var single_atlas: Vector2i = layers[0].get(
			"atlas",
			NO_TILE
		)
		var single_texture: Texture2D = _make_tile_texture(
			int(layers[0].get("source_id", -1)),
			single_atlas
		)
		_item_texture_cache[build_id] = single_texture
		return single_texture

	var composite: Image = Image.create(
		32,
		32,
		false,
		Image.FORMAT_RGBA8
	)
	composite.fill(Color(0.0, 0.0, 0.0, 0.0))

	for layer_data: Dictionary in layers:
		var atlas: Vector2i = layer_data.get(
			"atlas",
			NO_TILE
		)
		var tile_image: Image = _get_tile_image(
			int(layer_data.get("source_id", -1)),
			atlas
		)

		if tile_image == null:
			continue

		composite.blend_rect(
			tile_image,
			Rect2i(
				Vector2i.ZERO,
				tile_image.get_size()
			),
			Vector2i.ZERO
		)

	var texture: ImageTexture = ImageTexture.create_from_image(
		composite
	)
	_item_texture_cache[build_id] = texture
	return texture


# Creates the runtime object texture.
func _make_runtime_object_texture(
	item: Dictionary
) -> Texture2D:
	var runtime_kind: StringName = StringName(
		item.get("runtime_kind", &"")
	)

	var image := Image.create(
		32,
		32,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	match runtime_kind:
		RUNTIME_KIND_SPRINKLER:
			_draw_sprinkler_icon(image)
		RUNTIME_KIND_FERTILIZER_INJECTOR:
			_draw_fertilizer_injector_icon(image)
		RUNTIME_KIND_SOIL_NEUTRALIZER:
			_draw_soil_neutralizer_icon(image)
		RUNTIME_KIND_PLANT_PROTECTION:
			_draw_plant_protection_icon(image)
		_:
			_draw_generic_runtime_icon(image)

	return ImageTexture.create_from_image(image)


# Draws the sprinkler icon.
func _draw_sprinkler_icon(image: Image) -> void:
	var outline := Color(0.10, 0.14, 0.15, 1.0)
	var metal_dark := Color(0.28, 0.38, 0.40, 1.0)
	var metal_light := Color(0.58, 0.72, 0.72, 1.0)
	var water := Color(0.28, 0.68, 1.0, 1.0)

	_fill_image_rect(
		image,
		Rect2i(12, 20, 8, 6),
		outline
	)
	_fill_image_rect(
		image,
		Rect2i(13, 21, 6, 4),
		metal_dark
	)
	_fill_image_rect(
		image,
		Rect2i(15, 11, 2, 10),
		outline
	)
	_fill_image_rect(
		image,
		Rect2i(16, 12, 1, 8),
		metal_light
	)
	_fill_image_rect(
		image,
		Rect2i(8, 10, 16, 3),
		outline
	)
	_fill_image_rect(
		image,
		Rect2i(9, 11, 14, 1),
		metal_light
	)

	for point: Vector2i in [
		Vector2i(5, 8),
		Vector2i(3, 6),
		Vector2i(26, 8),
		Vector2i(28, 6),
		Vector2i(8, 5),
		Vector2i(23, 5)
	]:
		if (
			point.x >= 0
			and point.y >= 0
			and point.x < image.get_width()
			and point.y < image.get_height()
		):
			image.set_pixel(
				point.x,
				point.y,
				water
			)


# Draws the fertilizer injector icon.
func _draw_fertilizer_injector_icon(image: Image) -> void:
	var outline := Color(0.06, 0.10, 0.06, 1.0)
	var tank_dark := Color(0.16, 0.34, 0.18, 1.0)
	var tank_light := Color(0.36, 0.70, 0.30, 1.0)
	var nutrient := Color(0.76, 0.91, 0.24, 1.0)
	var metal := Color(0.55, 0.62, 0.53, 1.0)

	_fill_image_rect(image, Rect2i(8, 7, 16, 19), outline)
	_fill_image_rect(image, Rect2i(9, 8, 14, 17), tank_dark)
	_fill_image_rect(image, Rect2i(11, 9, 10, 15), tank_light)
	_fill_image_rect(image, Rect2i(9, 15, 14, 3), nutrient)

	_fill_image_rect(image, Rect2i(13, 3, 6, 5), outline)
	_fill_image_rect(image, Rect2i(14, 4, 4, 4), metal)

	# Ground-fit injector pipe, matching the approved runtime sprite.
	_fill_image_rect(image, Rect2i(23, 17, 5, 4), outline)
	_fill_image_rect(image, Rect2i(24, 18, 3, 2), metal)
	_fill_image_rect(image, Rect2i(25, 20, 3, 7), outline)
	_fill_image_rect(image, Rect2i(26, 20, 1, 6), metal)

	_fill_image_rect(image, Rect2i(6, 25, 20, 3), outline)
	_fill_image_rect(image, Rect2i(8, 26, 16, 1), metal)


# Draws the soil neutralizer icon.
func _draw_soil_neutralizer_icon(image: Image) -> void:
	var outline := Color(0.07, 0.08, 0.12, 1.0)
	var body_dark := Color(0.22, 0.22, 0.38, 1.0)
	var body_light := Color(0.43, 0.42, 0.67, 1.0)
	var lime_color := Color(0.72, 0.90, 0.42, 1.0)
	var acid_color := Color(0.46, 0.76, 0.94, 1.0)
	var metal := Color(0.58, 0.61, 0.67, 1.0)

	_fill_image_rect(image, Rect2i(7, 8, 18, 17), outline)
	_fill_image_rect(image, Rect2i(8, 9, 16, 15), body_dark)
	_fill_image_rect(image, Rect2i(10, 10, 12, 12), body_light)

	_fill_image_rect(image, Rect2i(10, 13, 5, 6), outline)
	_fill_image_rect(image, Rect2i(11, 14, 3, 4), lime_color)
	_fill_image_rect(image, Rect2i(17, 13, 5, 6), outline)
	_fill_image_rect(image, Rect2i(18, 14, 3, 4), acid_color)

	_fill_image_rect(image, Rect2i(12, 4, 8, 5), outline)
	_fill_image_rect(image, Rect2i(13, 5, 6, 3), metal)

	_fill_image_rect(image, Rect2i(24, 18, 5, 3), outline)
	_fill_image_rect(image, Rect2i(26, 20, 3, 8), outline)
	_fill_image_rect(image, Rect2i(27, 20, 1, 7), metal)

	_fill_image_rect(image, Rect2i(6, 24, 20, 4), outline)
	_fill_image_rect(image, Rect2i(8, 25, 16, 2), metal)


# Draws the plant protection icon.
func _draw_plant_protection_icon(image: Image) -> void:
	var outline := Color(0.08, 0.08, 0.07, 1.0)
	var body_dark := Color(0.29, 0.25, 0.18, 1.0)
	var body_light := Color(0.58, 0.48, 0.26, 1.0)
	var pesticide := Color(0.72, 0.86, 0.25, 1.0)
	var fungicide := Color(0.33, 0.78, 0.72, 1.0)
	var shield := Color(0.82, 0.85, 0.72, 1.0)
	var metal := Color(0.54, 0.57, 0.51, 1.0)

	_fill_image_rect(image, Rect2i(7, 8, 18, 17), outline)
	_fill_image_rect(image, Rect2i(8, 9, 16, 15), body_dark)
	_fill_image_rect(image, Rect2i(10, 10, 12, 12), body_light)

	_fill_image_rect(image, Rect2i(9, 16, 6, 5), outline)
	_fill_image_rect(image, Rect2i(10, 17, 4, 3), pesticide)
	_fill_image_rect(image, Rect2i(17, 16, 6, 5), outline)
	_fill_image_rect(image, Rect2i(18, 17, 4, 3), fungicide)

	_fill_image_rect(image, Rect2i(13, 11, 6, 2), shield)
	_fill_image_rect(image, Rect2i(12, 12, 8, 3), shield)
	_fill_image_rect(image, Rect2i(14, 15, 4, 2), shield)
	_fill_image_rect(image, Rect2i(15, 17, 2, 1), shield)

	_fill_image_rect(image, Rect2i(13, 4, 6, 5), outline)
	_fill_image_rect(image, Rect2i(14, 5, 4, 3), metal)

	_fill_image_rect(image, Rect2i(24, 17, 5, 4), outline)
	_fill_image_rect(image, Rect2i(25, 18, 3, 2), metal)
	_fill_image_rect(image, Rect2i(26, 20, 3, 8), outline)
	_fill_image_rect(image, Rect2i(27, 20, 1, 7), metal)

	_fill_image_rect(image, Rect2i(6, 24, 20, 4), outline)
	_fill_image_rect(image, Rect2i(8, 25, 16, 2), metal)


# Draws the generic runtime icon.
func _draw_generic_runtime_icon(image: Image) -> void:
	_fill_image_rect(
		image,
		Rect2i(8, 8, 16, 16),
		Color(0.65, 0.65, 0.65, 1.0)
	)


# Fills the image rectangle.
func _fill_image_rect(
	image: Image,
	rect: Rect2i,
	color: Color
) -> void:
	for y: int in range(
		rect.position.y,
		rect.position.y + rect.size.y
	):
		for x: int in range(
			rect.position.x,
			rect.position.x + rect.size.x
		):
			if (
				x >= 0
				and y >= 0
				and x < image.get_width()
				and y < image.get_height()
			):
				image.set_pixel(
					x,
					y,
					color
				)


# Returns the tile image.
func _get_tile_image(
	source_id: int,
	atlas: Vector2i
) -> Image:
	if (
		source_id < 0
		or atlas == NO_TILE
		or not _tilemap.tile_set.has_source(source_id)
	):
		return null

	var source: TileSetSource = _tilemap.tile_set.get_source(
		source_id
	)

	if not (source is TileSetAtlasSource):
		return null

	var atlas_source := source as TileSetAtlasSource

	if not atlas_source.has_tile(atlas):
		return null

	var runtime_texture: Texture2D = atlas_source.get_runtime_texture()
	var source_image: Image = runtime_texture.get_image()
	var region: Rect2i = atlas_source.get_runtime_tile_texture_region(
		atlas,
		0
	)

	return source_image.get_region(region)


# Creates the tile texture.
func _make_tile_texture(
	source_id: int,
	atlas: Vector2i
) -> Texture2D:
	if (
		not _is_configured()
		or source_id < 0
		or atlas == NO_TILE
		or not _tilemap.tile_set.has_source(source_id)
	):
		return null

	var source: TileSetSource = _tilemap.tile_set.get_source(
		source_id
	)

	if not (source is TileSetAtlasSource):
		return null

	var atlas_source := source as TileSetAtlasSource

	if not atlas_source.has_tile(atlas):
		return null

	var texture := AtlasTexture.new()
	texture.atlas = atlas_source.get_runtime_texture()
	texture.region = Rect2(
		atlas_source.get_runtime_tile_texture_region(
			atlas,
			0
		)
	)
	return texture


# Checks whether the pointer is currently over the HUD.
func _is_pointer_over_hud() -> bool:
	var mouse_position: Vector2 = get_viewport().get_mouse_position()

	if (
		_top_bar != null
		and _top_bar.visible
		and _top_bar.get_global_rect().has_point(
			mouse_position
		)
	):
		return true

	if (
		_palette_panel != null
		and _palette_panel.visible
		and _palette_panel.get_global_rect().has_point(
			mouse_position
		)
	):
		return true

	return false


# Returns the current set status result.
func _set_status(
	message: String,
	is_error: bool
) -> void:
	if _status_label == null:
		return

	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.48, 0.42, 1.0)
		if is_error
		else Color(0.82, 0.90, 0.86, 1.0)
	)


# Emits the failed.
func _emit_failed(
	cell: Vector2i,
	build_id: StringName,
	reason: String
) -> void:
	build_action_failed.emit(cell, build_id, reason)
	_set_status(_get_reason_text(reason), true)

	if debug_log:
		print(
			"[Build] INVALID id=",
			String(build_id),
			" cell=",
			cell,
			" reason=",
			reason
		)


# Creates a standard failed placement-status result.
func _failed_status(
	reason: String,
	build_id: StringName
) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"cost": _get_build_cost(build_id)
	}


# Returns the required player level.
func _get_required_player_level(
	build_id: StringName
) -> int:
	var item: Dictionary = _get_item(build_id)
	var metadata_level: int = maxi(
		int(item.get("required_player_level", 0)),
		0
	)

	if ProgressionSystem.has_method(
		"get_automation_unlock_level"
	):
		var progression_level: int = int(
			ProgressionSystem.get_automation_unlock_level(
				build_id
			)
		)

		if progression_level > 0:
			return progression_level

	return metadata_level


# Checks whether the selected build item is currently unlocked.
func _is_build_unlocked(
	build_id: StringName
) -> bool:
	var required_level: int = _get_required_player_level(
		build_id
	)

	if required_level <= 0:
		return true

	return ProgressionSystem.player_level >= required_level


# Returns the build cost.
func _get_build_cost(build_id: StringName) -> int:
	var item: Dictionary = _get_item(build_id)
	return int(item.get("cost", 0))


# Returns the display name.
func _get_display_name(build_id: StringName) -> String:
	var item: Dictionary = _get_item(build_id)
	return String(
		item.get(
			"display_name",
			build_id
		)
	)


# Formats get reason for UI display.
func _get_reason_text(reason: String) -> String:
	match reason:
		REASON_NO_CREDITS:
			return "Not enough Build Credits."
		REASON_OCCUPIED_BY_PLANT:
			return "Remove the plant before rebuilding this cell."
		REASON_PLAYER_CELL:
			return "You cannot build under the player."
		REASON_BLOCKED_LAYER:
			return "This cell contains a protected map object."
		REASON_BLOCKED_BY_BUILD_OBJECT:
			return "Remove the player-built object first."
		REASON_NOT_ADJACENT:
			return "New map cells must connect to the main map through adjacent surface tiles."
		REASON_ALREADY_BUILT:
			return "That build slot already contains a player-built block."
		REASON_SAME_SURFACE:
			return "This exact surface tile is already present."
		REASON_SAME_BUILD:
			return "This exact build item is already present."
		REASON_NOT_PLAYER_BUILT:
			return "Only player-built blocks can be removed."
		REASON_NO_SURFACE:
			return "Fence needs an existing ground surface."
		REASON_PLANTABLE_SURFACE:
			return "Fence cannot be placed on plantable soil yet."
		REASON_WATER_SURFACE:
			return "Fence cannot be placed on water."
		REASON_DECOR_NEEDS_SURFACE:
			return "Decoration needs an existing ground surface."
		REASON_DECOR_ON_PLANTABLE:
			return "Decoration cannot be placed on plantable soil."
		REASON_DECOR_ON_WATER:
			return "Ground decoration cannot be placed on water."
		REASON_GROUND_DECOR_NEEDS_GRASS:
			return "Ground Decor can only replace grass cells."
		REASON_WATER_DECOR_NEEDS_WATER:
			return "Water Decor can only be placed on water."
		REASON_OBJECT_NEEDS_GRASS:
			return "This object can only be placed on grass."
		REASON_OBJECT_NEEDS_DRY_GROUND:
			return "This farm object can only be placed on grass or stone path."
		REASON_SPRINKLER_NEEDS_VALID_SURFACE:
			return "Field Sprinkler needs grass or the outer edge of Loamy/Sandy soil."
		REASON_AUTOMATION_NEEDS_VALID_SURFACE:
			return "Automation machines need grass or the outer edge of Loamy/Sandy soil."
		REASON_BUILD_LOCKED:
			return "This automation machine has not been unlocked yet."
		REASON_STORAGE_NOT_EMPTY:
			return "Empty the Seed Storage before moving or demolishing it."
		"REMOVE_DECORATION_FIRST":
			return "Remove the player-built decoration first."
		REASON_NOT_CONFIGURED:
			return "Build System is not connected to the world."
		REASON_MISSING_TILE:
			return "A whitelisted build tile is missing from the TileSet."

	return "Build action unavailable: %s" % reason


# Finds the layer by name.
func _find_layer_by_name(layer_name: String) -> int:
	if _tilemap == null:
		return -1

	for index: int in range(_tilemap.get_layers_count()):
		if _tilemap.get_layer_name(index) == layer_name:
			return index

	return -1


# Finds the or create decorations layer.
func _find_or_create_decorations_layer() -> int:
	var existing: int = _find_layer_by_name("decorations")

	if existing >= 0:
		return existing

	_tilemap.add_layer(-1)
	var new_layer: int = _tilemap.get_layers_count() - 1
	_tilemap.set_layer_name(new_layer, "decorations")

	if debug_log:
		print(
			"[BuildSystem] runtime TileMap layer created name=decorations index=",
			new_layer
		)

	return new_layer


# Finds the gameplay overlays.
func _find_gameplay_overlays() -> CanvasItem:
	if _tilemap == null:
		return null

	var current_scene: Node = _tilemap.get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.get_node_or_null(
		"Overlays"
	) as CanvasItem


# Checks every whitelisted atlas coordinate before Build Credits can be spent.
func _validate_catalog_tiles() -> bool:
	if _tilemap == null or _tilemap.tile_set == null:
		return false

	var ok: bool = true

	for item: Dictionary in _catalog_items:
		var build_id: StringName = StringName(
			item.get("id", &"")
		)

		if bool(item.get("runtime_visual", false)):
			continue

		var required_tiles: Array[Dictionary] = [{
			"source_id": int(item.get("source_id", -1)),
			"atlas": item.get("atlas", NO_TILE)
		}]

		if build_id == BUILD_ID_SEED_STORAGE:
			required_tiles.append({
				"source_id": FARMING_SOURCE_ID,
				"atlas": SEED_STORAGE_TILE_B
			})

		var filler_source_id: int = int(
			item.get("filler_source_id", -1)
		)
		var filler_atlas: Vector2i = item.get(
			"filler_atlas",
			NO_TILE
		)

		if filler_source_id >= 0 and filler_atlas != NO_TILE:
			required_tiles.append({
				"source_id": filler_source_id,
				"atlas": filler_atlas
			})

		var plantable_source_id: int = int(
			item.get("plantable_source_id", -1)
		)
		var plantable_atlas: Vector2i = item.get(
			"plantable_atlas",
			NO_TILE
		)

		if (
			plantable_source_id >= 0
			and plantable_atlas != NO_TILE
		):
			required_tiles.append({
				"source_id": plantable_source_id,
				"atlas": plantable_atlas
			})

		for tile: Dictionary in required_tiles:
			var source_id: int = int(
				tile.get("source_id", -1)
			)
			var atlas: Vector2i = tile.get(
				"atlas",
				NO_TILE
			)

			if not _tile_exists(source_id, atlas):
				ok = false
				push_error(
					"[BuildSystem] Missing whitelist tile source=%d atlas=%s id=%s"
					% [
						source_id,
						atlas,
						String(build_id)
					]
				)

	if debug_log:
		print(
			"[BuildSystem] tile catalog validation=",
			"OK" if ok else "FAILED",
			" items=",
			_catalog_items.size()
		)

	return ok


# Checks whether the requested atlas tile exists.
func _tile_exists(
	source_id: int,
	atlas: Vector2i
) -> bool:
	var tile_set: TileSet = _tilemap.tile_set

	if not tile_set.has_source(source_id):
		return false

	var source: TileSetSource = tile_set.get_source(
		source_id
	)

	if source == null:
		return false

	return source.has_tile(atlas)


# Writes the target cell tile data to the debug log.
func _log_cell_tiles(cell: Vector2i) -> void:
	print(
		"[Build] TILE cell=",
		cell,
		" filler=(source=",
		_tilemap.get_cell_source_id(_filler_layer, cell),
		" atlas=",
		_tilemap.get_cell_atlas_coords(_filler_layer, cell),
		") ground=(source=",
		_tilemap.get_cell_source_id(_ground_layer, cell),
		" atlas=",
		_tilemap.get_cell_atlas_coords(_ground_layer, cell),
		") plantable=(source=",
		_tilemap.get_cell_source_id(_plantable_layer, cell),
		" atlas=",
		_tilemap.get_cell_atlas_coords(_plantable_layer, cell),
		") objects=(source=",
		_tilemap.get_cell_source_id(_objects_layer, cell),
		" atlas=",
		_tilemap.get_cell_atlas_coords(_objects_layer, cell),
		") decorations=(source=",
		_tilemap.get_cell_source_id(_decorations_layer, cell),
		" atlas=",
		_tilemap.get_cell_atlas_coords(_decorations_layer, cell),
		") soil_override=",
		get_built_soil_type(cell)
	)



# Returns JSON-safe player-built map state.
func get_save_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for cell_variant: Variant in _placed_cells.keys():
		var cell: Vector2i = cell_variant
		var cell_record: Dictionary = _placed_cells[cell]
		var entry: Dictionary = {
			"x": cell.x,
			"y": cell.y
		}

		if cell_record.has("surface"):
			var surface: Dictionary = cell_record["surface"]
			entry["surface_build_id"] = String(
				surface.get("build_id", &"")
			)

		if cell_record.has("object"):
			var object_record: Dictionary = cell_record["object"]
			var include_object: bool = not bool(
				object_record.get("multi_object", false)
			) or bool(object_record.get("is_anchor", false))

			if include_object:
				entry["object_build_id"] = String(
					object_record.get("build_id", &"")
				)
				if object_record.has("rotation"):
					entry["object_rotation"] = int(
						object_record.get("rotation", 0)
					)

		if cell_record.has("decoration"):
			var decoration_record: Dictionary = cell_record["decoration"]
			entry["decoration_build_id"] = String(
				decoration_record.get("build_id", &"")
			)

		if entry.size() > 2:
			result.append(entry)

	return result


# Restores this system from saved data.
func load_save_state(entries: Array) -> bool:
	if not _is_configured():
		push_warning(
			"[BuildSystem] load_save_state rejected: world is not configured."
		)
		return false

	_clear_runtime_state(true)

	var decoded_entries: Array[Dictionary] = []

	for entry_variant: Variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_variant
		decoded_entries.append(entry)

	# Surfaces must be restored before objects and water decorations.
	for entry: Dictionary in decoded_entries:
		_load_saved_build_slot(entry, "surface")

	for entry: Dictionary in decoded_entries:
		_load_saved_build_slot(entry, "object")

	for entry: Dictionary in decoded_entries:
		_load_saved_build_slot(entry, "decoration")

	_refresh_world_after_edit()
	build_world_rebuilt.emit()

	if debug_log:
		print(
			"[BuildSystem] save state loaded cells=",
			_placed_cells.size()
		)

	return true


# Loads the saved build slot.
func _load_saved_build_slot(
	entry: Dictionary,
	slot: String
) -> void:
	var key: String = "%s_build_id" % slot
	var build_id_text: String = String(entry.get(key, ""))

	if build_id_text == "":
		return

	var build_id := StringName(build_id_text)
	var item: Dictionary = _get_item(build_id)

	if item.is_empty():
		push_warning(
			"[BuildSystem] saved build item no longer exists id=%s"
			% build_id_text
		)
		return

	var item_slot: String = String(item.get("slot", "surface"))

	if item_slot != slot:
		push_warning(
			"[BuildSystem] saved build slot mismatch id=%s expected=%s actual=%s"
			% [build_id_text, slot, item_slot]
		)
		return

	var cell := Vector2i(
		int(entry.get("x", 0)),
		int(entry.get("y", 0))
	)
	var cost: int = int(item.get("cost", 0))

	match slot:
		"object":
			_place_object(
				cell,
				build_id,
				item,
				cost,
				false,
				int(entry.get("object_rotation", 0))
			)
		"decoration":
			_place_decoration(
				cell,
				build_id,
				item,
				cost,
				false
			)
		_:
			_place_surface(
				cell,
				build_id,
				item,
				cost,
				false
			)


# Handles the category pressed signal or callback.
func _on_category_pressed(category: StringName) -> void:
	select_category(category)


# Handles the item pressed signal or callback.
func _on_item_pressed(build_id: StringName) -> void:
	select_build(build_id)


# Handles the build cell credits changed signal or callback.
func _on_build_cell_credits_changed(
	_previous_amount: int,
	_new_amount: int,
	_delta: int,
	_reason: String
) -> void:
	_refresh_hud()


# Handles the progression reset signal or callback.
func _on_progression_reset() -> void:
	_clear_runtime_state(true)
	build_world_rebuilt.emit()
	_rebuild_item_grid()
	_refresh_hud()


# Handles the player level changed signal or callback.
func _on_player_level_changed(
	_previous_level: int,
	_new_level: int
) -> void:
	_rebuild_item_grid()
	_refresh_hud()

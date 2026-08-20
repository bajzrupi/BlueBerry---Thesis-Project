extends Node

# Dynamic boundary system for the current playable map.
#
# Gameplay:
# - Player cannot leave cells backed by Ground2/Plantable tiles.
# - The full camera viewport is kept inside the real map rectangle.
#
# Build Mode:
# - The camera still cannot reveal the uncontrolled empty world.
# - When a SURFACE tile is selected, a one-cell construction apron appears
#   around the current map. This is the only outside area the camera may show.
# - Placing a connected surface tile in that apron immediately expands the
#   real Player/Camera boundary.

@export_category("Map Surface")
@export var ground_layer_name: String = "Ground2"
@export var plantable_layer_name: String = "Plantable"

# The original map contains a few narrow decorative/protruding surface rows.
# For the gameplay camera we detect the dense rectangular "main map" first,
# then expand that rectangle only with player-built surface cells.
@export_range(0.50, 1.0, 0.05)
var camera_core_row_density: float = 0.75

@export_category("Build Expansion")

# The Build camera may explore this many empty cells beyond the real map.
# This is only a CAMERA workspace; it does not make those cells placeable.
@export_range(1, 40, 1)
var build_camera_exploration_margin_cells: int = 20

# Only this one-cell frontier is visually marked as the next placeable strip.
# Placing a connected surface tile moves this frontier outward automatically.
@export_range(1, 3, 1)
var build_frontier_margin_cells: int = 1

@export var build_apron_color: Color = Color(
	0.055,
	0.12,
	0.095,
	0.92
)

@export var build_apron_grid_color: Color = Color(
	0.28,
	0.48,
	0.38,
	0.72
)

@export var build_apron_grid_width: float = 1.0

@export_category("Player Boundary")
@export var player_probe_inset_pixels: float = 1.5

@export_category("Refresh")
@export var bounds_poll_seconds: float = 0.25

@export_category("Debug Logging")
@export var debug_log: bool = false


var _tilemap: TileMap
var _player: CharacterBody2D
var _camera: Camera2D

var _ground_layer: int = -1
var _plantable_layer: int = -1

var _surface_cell_rect: Rect2i = Rect2i()
var _surface_world_rect: Rect2 = Rect2()

# Original surface cells are captured before SaveSystem restores player-built
# terrain. They let the camera ignore narrow base-map protrusions while still
# expanding one tile at a time for real player construction.
var _base_surface_cells: Dictionary = {}
var _base_camera_cell_rect: Rect2i = Rect2i()
var _gameplay_camera_cell_rect: Rect2i = Rect2i()

var _camera_home_local_position: Vector2 = Vector2.ZERO

var _last_surface_signature: String = ""
var _last_expansion_mode: bool = false
var _last_camera_zoom: Vector2 = Vector2.ZERO
var _last_viewport_size: Vector2 = Vector2.ZERO

var _poll_elapsed: float = 0.0
var _configured: bool = false

var _apron_root: Node2D
var _apron_fill_nodes: Array[Polygon2D] = []
var _apron_grid_nodes: Array[Line2D] = []


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_build_signals()

	if debug_log:
		print("[WorldBounds] ready")


# Connects this system to the current world references.
func configure(
	tilemap: TileMap,
	player: CharacterBody2D,
	camera: Camera2D
) -> void:
	if tilemap == null or player == null or camera == null:
		push_error(
			"[WorldBounds] configure received missing world references."
		)
		return

	_tilemap = tilemap
	_player = player
	_camera = camera

	_ground_layer = _find_layer_by_name(
		_tilemap,
		ground_layer_name
	)
	_plantable_layer = _find_layer_by_name(
		_tilemap,
		plantable_layer_name
	)

	if _ground_layer == -1 and _plantable_layer == -1:
		push_error(
			"[WorldBounds] No playable surface layers were found."
		)
		_clear_world_references()
		return

	_camera_home_local_position = _camera.position

	_capture_base_camera_geometry()

	_configured = true
	_poll_elapsed = 0.0
	_last_surface_signature = ""
	_last_expansion_mode = false
	_last_camera_zoom = Vector2.ZERO
	_last_viewport_size = Vector2.ZERO

	_create_apron_root()
	refresh_bounds(true)
	_update_build_apron()
	_update_camera_constraints(true)

	if debug_log:
		print(
			"[WorldBounds] configured cell_rect=",
			_surface_cell_rect,
			" world_rect=",
			_surface_world_rect
		)


# Disconnects this system from the current world references.
func unconfigure(tilemap: TileMap) -> void:
	if not _configured or _tilemap != tilemap:
		return

	_configured = false

	_surface_cell_rect = Rect2i()
	_surface_world_rect = Rect2()

	_base_surface_cells.clear()
	_base_camera_cell_rect = Rect2i()
	_gameplay_camera_cell_rect = Rect2i()

	_last_surface_signature = ""
	_last_expansion_mode = false
	_last_camera_zoom = Vector2.ZERO
	_last_viewport_size = Vector2.ZERO
	_poll_elapsed = 0.0

	_destroy_apron()
	_clear_world_references()

	if debug_log:
		print("[WorldBounds] unconfigured")


# Checks whether this system is configured for the current world.
func is_configured() -> bool:
	return _configured


# Returns the surface cell rectangle.
func get_surface_cell_rect() -> Rect2i:
	return _surface_cell_rect


# Returns the surface world rectangle.
func get_surface_world_rect() -> Rect2:
	return _surface_world_rect


# Checks whether the build expansion is available.
func is_build_expansion_available() -> bool:
	return (
		_configured
		and BuildSystem.is_active()
		and _selected_build_is_surface()
	)


# BuildSystem can use this when clamping its zoom input.
func get_minimum_camera_zoom_for_current_bounds() -> float:
	if (
		not _configured
		or _camera == null
		or _surface_world_rect.size.x <= 0.0
		or _surface_world_rect.size.y <= 0.0
	):
		return 0.01

	var allowed_rect: Rect2 = _get_camera_world_rect()
	var viewport_size: Vector2 = (
		_camera.get_viewport_rect().size
	)

	if (
		allowed_rect.size.x <= 0.0
		or allowed_rect.size.y <= 0.0
	):
		return 0.01

	return maxf(
		viewport_size.x / allowed_rect.size.x,
		viewport_size.y / allowed_rect.size.y
	)


# Player calls this immediately after move_and_slide().
# Axis-preserving fallback lets the character slide naturally along the edge.
func constrain_player_after_move(
	player: CharacterBody2D,
	previous_position: Vector2
) -> void:
	if (
		not _configured
		or _tilemap == null
		or player == null
		or player != _player
	):
		return

	_refresh_for_player_position_if_needed(
		player.global_position
	)

	var current_position: Vector2 = player.global_position

	if _is_player_position_valid(
		player,
		current_position
	):
		return

	var x_only := Vector2(
		current_position.x,
		previous_position.y
	)

	if _is_player_position_valid(player, x_only):
		player.global_position = x_only
		player.velocity.y = 0.0
		return

	var y_only := Vector2(
		previous_position.x,
		current_position.y
	)

	if _is_player_position_valid(player, y_only):
		player.global_position = y_only
		player.velocity.x = 0.0
		return

	if _is_player_position_valid(
		player,
		previous_position
	):
		player.global_position = previous_position
		player.velocity = Vector2.ZERO
		return

	# Recovery path for a legacy/debug save that already contains an invalid
	# Player position.
	var recovery: Dictionary = (
		_find_nearest_valid_player_position(
			player,
			current_position
		)
	)

	if bool(recovery.get("found", false)):
		var recovery_position: Vector2 = recovery.get(
			"position",
			current_position
		)

		player.global_position = recovery_position
		player.velocity = Vector2.ZERO

		if debug_log:
			print(
				"[WorldBounds] player recovered position=",
				recovery_position
			)


# Refreshes the bounds.
func refresh_bounds(force: bool = false) -> void:
	if (
		not _configured
		or _tilemap == null
		or _tilemap.tile_set == null
	):
		return

	var signature: String = _get_surface_signature()

	if not force and signature == _last_surface_signature:
		return

	var next_cell_rect: Rect2i = (
		_calculate_surface_cell_rect()
	)

	if next_cell_rect.size == Vector2i.ZERO:
		return

	_surface_cell_rect = next_cell_rect
	_surface_world_rect = _cell_rect_to_world_rect(
		_surface_cell_rect
	)

	_refresh_gameplay_camera_cell_rect()
	_last_surface_signature = signature

	_rebuild_build_apron()
	_update_camera_constraints(true)

	if debug_log:
		print(
			"[WorldBounds] refreshed cell_rect=",
			_surface_cell_rect,
			" world_rect=",
			_surface_world_rect,
			" expansion=",
			is_build_expansion_available(),
			" camera_margin_cells=",
			build_camera_exploration_margin_cells,
			" frontier_cells=",
			build_frontier_margin_cells,
			" gameplay_camera_cells=",
			_gameplay_camera_cell_rect
		)


# Updates this system every frame.
func _process(delta: float) -> void:
	if not _configured:
		return

	_poll_elapsed += delta

	if _poll_elapsed >= maxf(
		bounds_poll_seconds,
		0.05
	):
		_poll_elapsed = 0.0
		refresh_bounds(false)

	var expansion_now: bool = (
		is_build_expansion_available()
	)

	if expansion_now != _last_expansion_mode:
		_last_expansion_mode = expansion_now
		_update_build_apron()
		_update_camera_constraints(true)

	var viewport_size: Vector2 = (
		_camera.get_viewport_rect().size
		if _camera != null
		else Vector2.ZERO
	)

	if (
		_camera != null
		and (
			_camera.zoom != _last_camera_zoom
			or viewport_size != _last_viewport_size
		)
	):
		_update_camera_constraints(true)
	else:
		_update_camera_constraints(false)


# Connects the build signals signals and callbacks.
func _connect_build_signals() -> void:
	if not BuildSystem.build_mode_changed.is_connected(
		_on_build_mode_changed
	):
		BuildSystem.build_mode_changed.connect(
			_on_build_mode_changed
		)

	if not BuildSystem.build_cell_placed.is_connected(
		_on_build_cell_placed
	):
		BuildSystem.build_cell_placed.connect(
			_on_build_cell_placed
		)

	if not BuildSystem.build_cell_removed.is_connected(
		_on_build_cell_removed
	):
		BuildSystem.build_cell_removed.connect(
			_on_build_cell_removed
		)


# Handles the build mode changed signal or callback.
func _on_build_mode_changed(_active: bool) -> void:
	if not _configured:
		return

	# BuildSystem also changes camera state while entering/leaving build mode.
	# Run one frame later so this system remains the final boundary authority.
	call_deferred("_refresh_after_build_mode_change")


# Refreshes the after build mode change.
func _refresh_after_build_mode_change() -> void:
	if not _configured:
		return

	_last_expansion_mode = is_build_expansion_available()
	_update_build_apron()
	_update_camera_constraints(true)


# Handles the build cell placed signal or callback.
func _on_build_cell_placed(
	_cell: Vector2i,
	_build_id: StringName,
	_cost: int
) -> void:
	if _configured:
		call_deferred("refresh_bounds", true)


# Handles the build cell removed signal or callback.
func _on_build_cell_removed(
	_cell: Vector2i,
	_build_id: StringName,
	_refund: int
) -> void:
	if _configured:
		call_deferred("refresh_bounds", true)


# Updates the camera constraints.
func _update_camera_constraints(
	force_limits: bool
) -> void:
	if (
		_camera == null
		or _gameplay_camera_cell_rect.size == Vector2i.ZERO
	):
		return

	_enforce_camera_zoom_fit()

	var allowed_rect: Rect2 = _get_camera_world_rect()

	if force_limits:
		_apply_camera_limits(allowed_rect)

	if BuildSystem.is_active():
		# Build Mode moves Camera2D.global_position manually, so its target
		# position must also be clamped to the current build workspace.
		var center_rect: Rect2 = _get_camera_center_rect(
			allowed_rect
		)

		_camera.global_position = _clamp_point_to_rect(
			_camera.global_position,
			center_rect
		)
	else:
		# IMPORTANT:
		# Camera2D is a child of Player. Do NOT write global_position here.
		# Doing that changes its local offset every frame and cancels the
		# Player's movement, which makes the camera appear frozen.
		#
		# In gameplay the Camera2D follows its parent normally. Godot's own
		# limit_* properties stop the rendered view at the map rectangle.
		if (
			force_limits
			and _camera.position_smoothing_enabled
		):
			_camera.reset_smoothing()

	_last_camera_zoom = _camera.zoom
	_last_viewport_size = (
		_camera.get_viewport_rect().size
	)


# Applies the camera limits.
func _apply_camera_limits(
	allowed_rect: Rect2
) -> void:
	# Camera2D limit_* values are scroll limits in world pixels.
	# They should match the real map edges directly. Camera2D itself accounts
	# for the viewport size when stopping the visible screen at those edges.
	_camera.limit_enabled = true
	_camera.limit_smoothed = false
	_camera.offset = Vector2.ZERO

	_camera.limit_left = floori(
		allowed_rect.position.x
	)
	_camera.limit_top = floori(
		allowed_rect.position.y
	)
	_camera.limit_right = ceili(
		allowed_rect.end.x
	)
	_camera.limit_bottom = ceili(
		allowed_rect.end.y
	)

	_camera.force_update_scroll()


# Enforces the camera zoom fit.
func _enforce_camera_zoom_fit() -> void:
	if _camera == null:
		return

	var minimum_zoom: float = (
		get_minimum_camera_zoom_for_current_bounds()
	)
	var current_zoom: float = maxf(
		_camera.zoom.x,
		0.01
	)

	if current_zoom + 0.0001 < minimum_zoom:
		_camera.zoom = Vector2(
			minimum_zoom,
			minimum_zoom
		)

		if debug_log:
			print(
				"[WorldBounds] camera zoom clamped to fit=",
				snappedf(minimum_zoom, 0.001)
			)


# Returns the camera world rectangle.
func _get_camera_world_rect() -> Rect2:
	var gameplay_rect: Rect2 = _cell_rect_to_world_rect(
		_gameplay_camera_cell_rect
	)

	if not is_build_expansion_available():
		return gameplay_rect

	var tile_size: Vector2i = (
		_tilemap.tile_set.tile_size
	)
	var margin := Vector2(
		tile_size.x * build_camera_exploration_margin_cells,
		tile_size.y * build_camera_exploration_margin_cells
	)

	return Rect2(
		gameplay_rect.position - margin,
		gameplay_rect.size + margin * 2.0
	)


# Returns the camera center rectangle.
func _get_camera_center_rect(
	allowed_rect: Rect2
) -> Rect2:
	var half_visible: Vector2 = (
		_get_visible_world_size() * 0.5
	)

	var min_center: Vector2 = (
		allowed_rect.position + half_visible
	)
	var max_center: Vector2 = (
		allowed_rect.end - half_visible
	)

	if min_center.x > max_center.x:
		var center_x: float = allowed_rect.get_center().x
		min_center.x = center_x
		max_center.x = center_x

	if min_center.y > max_center.y:
		var center_y: float = allowed_rect.get_center().y
		min_center.y = center_y
		max_center.y = center_y

	return Rect2(
		min_center,
		max_center - min_center
	)


# Returns the visible world size.
func _get_visible_world_size() -> Vector2:
	if _camera == null:
		return Vector2.ZERO

	var viewport_size: Vector2 = (
		_camera.get_viewport_rect().size
	)
	var zoom_x: float = maxf(
		absf(_camera.zoom.x),
		0.001
	)
	var zoom_y: float = maxf(
		absf(_camera.zoom.y),
		0.001
	)

	return Vector2(
		viewport_size.x / zoom_x,
		viewport_size.y / zoom_y
	)


# Handles clamp point to rectangle.
func _clamp_point_to_rect(
	point: Vector2,
	rect: Rect2
) -> Vector2:
	if rect.size == Vector2.ZERO:
		return rect.position

	return Vector2(
		clampf(
			point.x,
			rect.position.x,
			rect.end.x
		),
		clampf(
			point.y,
			rect.position.y,
			rect.end.y
		)
	)


# Handles selected build is surface.
func _selected_build_is_surface() -> bool:
	if not BuildSystem.has_method(
		"get_selected_build_slot"
	):
		return false

	return (
		String(BuildSystem.get_selected_build_slot())
		== "surface"
	)


# Captures the base camera geometry for save, restore, or validation.
func _capture_base_camera_geometry() -> void:
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

	_base_camera_cell_rect = _calculate_dense_ground_camera_core()

	if _base_camera_cell_rect.size == Vector2i.ZERO:
		_base_camera_cell_rect = _calculate_surface_cell_rect()

	_gameplay_camera_cell_rect = _base_camera_cell_rect

	if debug_log:
		print(
			"[WorldBounds] base camera core=",
			_base_camera_cell_rect,
			" base_surface_cells=",
			_base_surface_cells.size()
		)


# Calculates the dense ground camera core.
func _calculate_dense_ground_camera_core() -> Rect2i:
	if _tilemap == null or _ground_layer < 0:
		return Rect2i()

	var ground_cells: Array[Vector2i] = (
		_tilemap.get_used_cells(_ground_layer)
	)

	if ground_cells.is_empty():
		return Rect2i()

	var row_counts: Dictionary = {}
	var maximum_row_count: int = 0

	for cell: Vector2i in ground_cells:
		var count: int = int(
			row_counts.get(cell.y, 0)
		) + 1
		row_counts[cell.y] = count
		maximum_row_count = maxi(
			maximum_row_count,
			count
		)

	var minimum_dense_count: int = maxi(
		1,
		ceili(
			float(maximum_row_count)
			* camera_core_row_density
		)
	)

	var found_dense_row: bool = false
	var min_y: int = 0
	var max_y: int = 0

	for row_key: Variant in row_counts.keys():
		var row_y: int = int(row_key)
		var count: int = int(row_counts[row_key])

		if count < minimum_dense_count:
			continue

		if not found_dense_row:
			min_y = row_y
			max_y = row_y
			found_dense_row = true
		else:
			min_y = mini(min_y, row_y)
			max_y = maxi(max_y, row_y)

	if not found_dense_row:
		return Rect2i()

	var found_cell: bool = false
	var min_x: int = 0
	var max_x: int = 0

	for cell: Vector2i in ground_cells:
		if cell.y < min_y or cell.y > max_y:
			continue

		if int(row_counts.get(cell.y, 0)) < minimum_dense_count:
			continue

		if not found_cell:
			min_x = cell.x
			max_x = cell.x
			found_cell = true
		else:
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)

	if not found_cell:
		return Rect2i()

	return Rect2i(
		Vector2i(min_x, min_y),
		Vector2i(
			max_x - min_x + 1,
			max_y - min_y + 1
		)
	)


# Refreshes the gameplay camera cell rectangle.
func _refresh_gameplay_camera_cell_rect() -> void:
	if _base_camera_cell_rect.size == Vector2i.ZERO:
		_gameplay_camera_cell_rect = _surface_cell_rect
		return

	var min_x: int = _base_camera_cell_rect.position.x
	var min_y: int = _base_camera_cell_rect.position.y
	var max_x: int = _base_camera_cell_rect.end.x - 1
	var max_y: int = _base_camera_cell_rect.end.y - 1

	# Only PLAYER-BUILT surface cells are allowed to expand the gameplay
	# camera beyond the original dense main-map rectangle. Narrow decorative
	# protrusions that already existed in the base map therefore do not expose
	# large grey strips.
	for layer: int in [
		_ground_layer,
		_plantable_layer
	]:
		if layer < 0:
			continue

		for cell: Vector2i in _tilemap.get_used_cells(layer):
			if _base_surface_cells.has(cell):
				continue

			min_x = mini(min_x, cell.x)
			min_y = mini(min_y, cell.y)
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)

	_gameplay_camera_cell_rect = Rect2i(
		Vector2i(min_x, min_y),
		Vector2i(
			max_x - min_x + 1,
			max_y - min_y + 1
		)
	)


# Calculates the surface cell rectangle.
func _calculate_surface_cell_rect() -> Rect2i:
	var found: bool = false

	var min_x: int = 0
	var min_y: int = 0
	var max_x: int = 0
	var max_y: int = 0

	for layer: int in [
		_ground_layer,
		_plantable_layer
	]:
		if layer < 0:
			continue

		for cell: Vector2i in _tilemap.get_used_cells(
			layer
		):
			if not found:
				min_x = cell.x
				max_x = cell.x
				min_y = cell.y
				max_y = cell.y
				found = true
			else:
				min_x = mini(min_x, cell.x)
				max_x = maxi(max_x, cell.x)
				min_y = mini(min_y, cell.y)
				max_y = maxi(max_y, cell.y)

	if not found:
		return Rect2i()

	return Rect2i(
		Vector2i(min_x, min_y),
		Vector2i(
			max_x - min_x + 1,
			max_y - min_y + 1
		)
	)


# Handles cell rectangle to world rectangle.
func _cell_rect_to_world_rect(
	cell_rect: Rect2i
) -> Rect2:
	var tile_size: Vector2i = (
		_tilemap.tile_set.tile_size
	)

	var top_left_local := Vector2(
		cell_rect.position.x * tile_size.x,
		cell_rect.position.y * tile_size.y
	)
	var bottom_right_local := Vector2(
		(cell_rect.position.x + cell_rect.size.x)
		* tile_size.x,
		(cell_rect.position.y + cell_rect.size.y)
		* tile_size.y
	)

	var point_a: Vector2 = _tilemap.to_global(
		top_left_local
	)
	var point_b: Vector2 = _tilemap.to_global(
		bottom_right_local
	)

	var minimum := Vector2(
		minf(point_a.x, point_b.x),
		minf(point_a.y, point_b.y)
	)
	var maximum := Vector2(
		maxf(point_a.x, point_b.x),
		maxf(point_a.y, point_b.y)
	)

	return Rect2(
		minimum,
		maximum - minimum
	)


# Checks whether the player position is valid.
func _is_player_position_valid(
	player: CharacterBody2D,
	candidate_position: Vector2
) -> bool:
	var probe_points: Array[Vector2] = (
		_get_player_probe_points(
			player,
			candidate_position
		)
	)

	for world_point: Vector2 in probe_points:
		var cell: Vector2i = _tilemap.local_to_map(
			_tilemap.to_local(world_point)
		)

		if not _is_surface_cell_live(cell):
			return false

	return true


# Returns the player probe points.
func _get_player_probe_points(
	player: CharacterBody2D,
	candidate_position: Vector2
) -> Array[Vector2]:
	var points: Array[Vector2] = []

	var collision := player.get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D

	if collision == null or collision.shape == null:
		points.append(candidate_position)
		return points

	var local_center: Vector2 = collision.position
	var half_extents := Vector2(5.0, 5.0)

	if collision.shape is RectangleShape2D:
		var rectangle := (
			collision.shape as RectangleShape2D
		)
		half_extents = rectangle.size * 0.5
	elif collision.shape is CircleShape2D:
		var circle := (
			collision.shape as CircleShape2D
		)
		half_extents = Vector2.ONE * circle.radius
	elif collision.shape is CapsuleShape2D:
		var capsule := (
			collision.shape as CapsuleShape2D
		)
		half_extents = Vector2(
			capsule.radius,
			capsule.height * 0.5
		)

	half_extents.x = maxf(
		half_extents.x - player_probe_inset_pixels,
		0.5
	)
	half_extents.y = maxf(
		half_extents.y - player_probe_inset_pixels,
		0.5
	)

	var center: Vector2 = (
		candidate_position + local_center
	)

	points.append(center)
	points.append(
		center + Vector2(
			-half_extents.x,
			-half_extents.y
		)
	)
	points.append(
		center + Vector2(
			half_extents.x,
			-half_extents.y
		)
	)
	points.append(
		center + Vector2(
			-half_extents.x,
			half_extents.y
		)
	)
	points.append(
		center + Vector2(
			half_extents.x,
			half_extents.y
		)
	)

	return points


# Checks the surface cell live condition.
func _is_surface_cell_live(cell: Vector2i) -> bool:
	if _tilemap == null:
		return false

	if (
		_ground_layer >= 0
		and _tilemap.get_cell_source_id(
			_ground_layer,
			cell
		) != -1
	):
		return true

	if (
		_plantable_layer >= 0
		and _tilemap.get_cell_source_id(
			_plantable_layer,
			cell
		) != -1
	):
		return true

	return false


# Finds the nearest valid player position.
func _find_nearest_valid_player_position(
	player: CharacterBody2D,
	from_position: Vector2
) -> Dictionary:
	if (
		_tilemap == null
		or _surface_cell_rect.size == Vector2i.ZERO
	):
		return {
			"found": false
		}

	var origin_cell: Vector2i = _tilemap.local_to_map(
		_tilemap.to_local(from_position)
	)

	var max_radius: int = maxi(
		_surface_cell_rect.size.x,
		_surface_cell_rect.size.y
	) + 2

	var collision := player.get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D
	var collision_offset := Vector2.ZERO

	if collision != null:
		collision_offset = collision.position

	for radius: int in range(max_radius + 1):
		for y: int in range(
			origin_cell.y - radius,
			origin_cell.y + radius + 1
		):
			for x: int in range(
				origin_cell.x - radius,
				origin_cell.x + radius + 1
			):
				if (
					abs(x - origin_cell.x) != radius
					and abs(y - origin_cell.y) != radius
				):
					continue

				var cell := Vector2i(x, y)

				if not _is_surface_cell_live(cell):
					continue

				var cell_center: Vector2 = (
					_tilemap.to_global(
						_tilemap.map_to_local(cell)
					)
				)
				var candidate: Vector2 = (
					cell_center - collision_offset
				)

				if _is_player_position_valid(
					player,
					candidate
				):
					return {
						"found": true,
						"position": candidate
					}

	return {
		"found": false
	}


# Refreshes the for player position if needed.
func _refresh_for_player_position_if_needed(
	player_position: Vector2
) -> void:
	if _surface_cell_rect.size == Vector2i.ZERO:
		refresh_bounds(true)
		return

	var cell: Vector2i = _tilemap.local_to_map(
		_tilemap.to_local(player_position)
	)

	if (
		not _surface_cell_rect.has_point(cell)
		and _is_surface_cell_live(cell)
	):
		refresh_bounds(true)


# Returns the surface signature.
func _get_surface_signature() -> String:
	var ground_count: int = 0
	var plantable_count: int = 0

	if _ground_layer >= 0:
		ground_count = _tilemap.get_used_cells(
			_ground_layer
		).size()

	if _plantable_layer >= 0:
		plantable_count = _tilemap.get_used_cells(
			_plantable_layer
		).size()

	return "%d|%d|%d,%d|%d,%d" % [
		ground_count,
		plantable_count,
		_surface_cell_rect.position.x,
		_surface_cell_rect.position.y,
		_surface_cell_rect.size.x,
		_surface_cell_rect.size.y
	]


# Finds the layer by name.
func _find_layer_by_name(
	tilemap: TileMap,
	layer_name: String
) -> int:
	for layer: int in range(
		tilemap.get_layers_count()
	):
		if tilemap.get_layer_name(layer) == layer_name:
			return layer

	return -1


# Creates the apron root.
func _create_apron_root() -> void:
	_destroy_apron()

	if _tilemap == null:
		return

	_apron_root = Node2D.new()
	_apron_root.name = "BuildExpansionApron"
	_apron_root.z_index = 900
	_apron_root.visible = false
	_tilemap.add_child(_apron_root)


# Destroys the apron.
func _destroy_apron() -> void:
	_apron_fill_nodes.clear()
	_apron_grid_nodes.clear()

	if is_instance_valid(_apron_root):
		_apron_root.queue_free()

	_apron_root = null


# Rebuilds the build apron.
func _rebuild_build_apron() -> void:
	if _apron_root == null:
		return

	for node: Polygon2D in _apron_fill_nodes:
		if is_instance_valid(node):
			node.queue_free()

	for line: Line2D in _apron_grid_nodes:
		if is_instance_valid(line):
			line.queue_free()

	_apron_fill_nodes.clear()
	_apron_grid_nodes.clear()

	if (
		_tilemap == null
		or _tilemap.tile_set == null
		or _surface_cell_rect.size == Vector2i.ZERO
	):
		return

	var margin: int = build_frontier_margin_cells
	var min_x: int = _surface_cell_rect.position.x - margin
	var min_y: int = _surface_cell_rect.position.y - margin
	var max_x: int = (
		_surface_cell_rect.end.x + margin
	)
	var max_y: int = (
		_surface_cell_rect.end.y + margin
	)

	var tile_size: Vector2i = (
		_tilemap.tile_set.tile_size
	)

	var outer_rect := Rect2(
		Vector2(
			min_x * tile_size.x,
			min_y * tile_size.y
		),
		Vector2(
			(max_x - min_x) * tile_size.x,
			(max_y - min_y) * tile_size.y
		)
	)

	var inner_rect := Rect2(
		Vector2(
			_surface_cell_rect.position.x
			* tile_size.x,
			_surface_cell_rect.position.y
			* tile_size.y
		),
		Vector2(
			_surface_cell_rect.size.x
			* tile_size.x,
			_surface_cell_rect.size.y
			* tile_size.y
		)
	)

	_add_apron_fill(Rect2(
		Vector2(
			outer_rect.position.x,
			outer_rect.position.y
		),
		Vector2(
			outer_rect.size.x,
			inner_rect.position.y
			- outer_rect.position.y
		)
	))

	_add_apron_fill(Rect2(
		Vector2(
			outer_rect.position.x,
			inner_rect.end.y
		),
		Vector2(
			outer_rect.size.x,
			outer_rect.end.y - inner_rect.end.y
		)
	))

	_add_apron_fill(Rect2(
		Vector2(
			outer_rect.position.x,
			inner_rect.position.y
		),
		Vector2(
			inner_rect.position.x
			- outer_rect.position.x,
			inner_rect.size.y
		)
	))

	_add_apron_fill(Rect2(
		Vector2(
			inner_rect.end.x,
			inner_rect.position.y
		),
		Vector2(
			outer_rect.end.x - inner_rect.end.x,
			inner_rect.size.y
		)
	))

	_add_apron_grid(
		outer_rect,
		inner_rect,
		tile_size
	)

	_update_build_apron()


# Adds the apron fill.
func _add_apron_fill(rect: Rect2) -> void:
	if (
		_apron_root == null
		or rect.size.x <= 0.0
		or rect.size.y <= 0.0
	):
		return

	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	])
	polygon.color = build_apron_color
	polygon.z_index = 0
	_apron_root.add_child(polygon)
	_apron_fill_nodes.append(polygon)


# Adds the apron grid.
func _add_apron_grid(
	outer_rect: Rect2,
	inner_rect: Rect2,
	tile_size: Vector2i
) -> void:
	if _apron_root == null:
		return

	var start_x: int = floori(
		outer_rect.position.x / tile_size.x
	)
	var end_x: int = ceili(
		outer_rect.end.x / tile_size.x
	)
	var start_y: int = floori(
		outer_rect.position.y / tile_size.y
	)
	var end_y: int = ceili(
		outer_rect.end.y / tile_size.y
	)

	for x: int in range(start_x, end_x + 1):
		var px: float = x * tile_size.x

		_add_grid_line(
			Vector2(px, outer_rect.position.y),
			Vector2(px, inner_rect.position.y)
		)
		_add_grid_line(
			Vector2(px, inner_rect.end.y),
			Vector2(px, outer_rect.end.y)
		)

	for y: int in range(start_y, end_y + 1):
		var py: float = y * tile_size.y

		_add_grid_line(
			Vector2(outer_rect.position.x, py),
			Vector2(inner_rect.position.x, py)
		)
		_add_grid_line(
			Vector2(inner_rect.end.x, py),
			Vector2(outer_rect.end.x, py)
		)

	# Inner and outer borders make the construction strip read as a deliberate
	# editor region rather than as empty world.
	_add_rect_outline(outer_rect)
	_add_rect_outline(inner_rect)


# Adds the grid line.
func _add_grid_line(
	from_point: Vector2,
	to_point: Vector2
) -> void:
	if (
		_apron_root == null
		or from_point.is_equal_approx(to_point)
	):
		return

	var line := Line2D.new()
	line.points = PackedVector2Array([
		from_point,
		to_point
	])
	line.width = build_apron_grid_width
	line.default_color = build_apron_grid_color
	line.antialiased = false
	line.z_index = 1
	_apron_root.add_child(line)
	_apron_grid_nodes.append(line)


# Adds the rectangle outline.
func _add_rect_outline(rect: Rect2) -> void:
	_add_grid_line(
		rect.position,
		Vector2(rect.end.x, rect.position.y)
	)
	_add_grid_line(
		Vector2(rect.end.x, rect.position.y),
		rect.end
	)
	_add_grid_line(
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	)
	_add_grid_line(
		Vector2(rect.position.x, rect.end.y),
		rect.position
	)


# Updates the build apron.
func _update_build_apron() -> void:
	if _apron_root == null:
		return

	_apron_root.visible = (
		is_build_expansion_available()
	)


# Clears the world references.
func _clear_world_references() -> void:
	_tilemap = null
	_player = null
	_camera = null

	_ground_layer = -1
	_plantable_layer = -1

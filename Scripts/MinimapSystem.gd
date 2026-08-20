extends Node

# Dynamic in-game minimap rendered from the live World2D.

const MAP_VIEWPORT_SIZE: Vector2i = Vector2i(190, 112)
const PANEL_SIZE: Vector2 = Vector2(210.0, 132.0)
const PANEL_TOP_MARGIN: float = 108.0
const SCREEN_EDGE_MARGIN: float = 16.0
const MINIMAP_HIDDEN_VISIBILITY_LAYER: int = 1 << 19
const MAP_TEXTURE_POSITION: Vector2 = Vector2(10.0, 10.0)
const MARKER_SIZE: Vector2 = Vector2(8.0, 8.0)

@export_category("Minimap")
@export var map_padding_cells: int = 2
@export var bounds_poll_seconds: float = 0.75
@export var min_camera_zoom: float = 0.02
@export var max_camera_zoom: float = 4.0
@export var player_follow_zoom_multiplier: float = 6.0

@export_category("Debug Logging")
@export var debug_log: bool = false

var _tilemap: TileMap
var _player: Node2D
var _player_original_visibility_layer: int = 1
var _configured: bool = false
var _build_mode_active: bool = false

var _world_rect: Rect2 = Rect2()
var _fit_scale: float = 1.0
var _display_scale: float = 1.0
var _camera_center: Vector2 = Vector2.ZERO
var _last_used_rect: Rect2i = Rect2i()
var _last_viewport_size: Vector2 = Vector2.ZERO

var _hud_layer: CanvasLayer
var _panel: Panel
var _title_label: Label
var _map_background: ColorRect
var _map_texture: TextureRect
var _player_marker: Panel

var _subviewport: SubViewport
var _minimap_camera: Camera2D
var _bounds_timer: Timer


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_create_render_target()
	_create_ui()
	_create_bounds_timer()
	_connect_global_signals()
	_update_panel_layout(true)

	_set_visible_state()

	if debug_log:
		print(
			"[Minimap] ready viewport=",
			MAP_VIEWPORT_SIZE,
			" panel_position=",
			_panel.position
		)


# Connects the minimap to the active gameplay world.
func configure(
	tilemap: TileMap,
	player: Node2D
) -> void:
	if tilemap == null or player == null:
		push_error(
			"[Minimap] configure received missing world references."
		)
		return

	_tilemap = tilemap
	_player = player
	_player_original_visibility_layer = _player.visibility_layer

	# The main game viewport renders all normal visibility layers, while the
	# minimap excludes this reserved layer. Since the player is a CanvasItem
	# parent, excluding its layer also removes its visual children from the
	# minimap without hiding them from the main game camera.
	_player.visibility_layer = MINIMAP_HIDDEN_VISIBILITY_LAYER
	_subviewport.canvas_cull_mask = (
		_subviewport.canvas_cull_mask
		& ~MINIMAP_HIDDEN_VISIBILITY_LAYER
	)

	_configured = true

	# Reuse the exact live 2D world. Built tiles, plants and runtime objects
	# therefore appear automatically without maintaining a second map copy.
	_subviewport.world_2d = _tilemap.get_viewport().world_2d

	_minimap_camera.enabled = true
	_minimap_camera.make_current()

	_last_used_rect = Rect2i()
	refresh_bounds(true)
	_update_player_marker()
	_set_visible_state()

	if debug_log:
		print(
			"[Minimap] configured used_rect=",
			_tilemap.get_used_rect(),
			" world_rect=",
			_world_rect,
			" fit_zoom=",
			_fit_scale,
			" display_zoom=",
			_display_scale
		)


# Disconnects this system from the current world references.
func unconfigure(tilemap: TileMap) -> void:
	if _tilemap != tilemap:
		return

	_configured = false

	if _player != null:
		_player.visibility_layer = (
			_player_original_visibility_layer
		)

	_tilemap = null
	_player = null
	_player_original_visibility_layer = 1
	_world_rect = Rect2()
	_fit_scale = 1.0
	_display_scale = 1.0
	_camera_center = Vector2.ZERO
	_last_used_rect = Rect2i()

	_subviewport.world_2d = World2D.new()
	_set_visible_state()

	if debug_log:
		print("[Minimap] unconfigured")


# Updates this system every frame.
func _process(_delta: float) -> void:
	_update_panel_layout(false)

	if not _configured or _build_mode_active:
		return

	_update_follow_camera()
	_update_player_marker()


# Recalculates the world rectangle and minimap camera fit.
func refresh_bounds(force: bool = false) -> void:
	if not _configured or _tilemap == null:
		return

	var used: Rect2i = _tilemap.get_used_rect()

	if used.size == Vector2i.ZERO:
		return

	if not force and used == _last_used_rect:
		return

	_last_used_rect = used

	var padding := Vector2i(
		maxi(map_padding_cells, 0),
		maxi(map_padding_cells, 0)
	)
	var expanded := Rect2i(
		used.position - padding,
		used.size + padding * 2
	)

	var cell_size: Vector2i = _tilemap.tile_set.tile_size

	var top_left_local := Vector2(
		expanded.position.x * cell_size.x,
		expanded.position.y * cell_size.y
	)
	var bottom_right_local := Vector2(
		(expanded.position.x + expanded.size.x)
		* cell_size.x,
		(expanded.position.y + expanded.size.y)
		* cell_size.y
	)

	var top_left_global: Vector2 = _tilemap.to_global(
		top_left_local
	)
	var bottom_right_global: Vector2 = _tilemap.to_global(
		bottom_right_local
	)

	var min_point := Vector2(
		minf(top_left_global.x, bottom_right_global.x),
		minf(top_left_global.y, bottom_right_global.y)
	)
	var max_point := Vector2(
		maxf(top_left_global.x, bottom_right_global.x),
		maxf(top_left_global.y, bottom_right_global.y)
	)

	_world_rect = Rect2(
		min_point,
		Vector2(
			maxf(max_point.x - min_point.x, 1.0),
			maxf(max_point.y - min_point.y, 1.0)
		)
	)

	var viewport_size := Vector2(MAP_VIEWPORT_SIZE)
	var scale_x: float = (
		viewport_size.x / _world_rect.size.x
	)
	var scale_y: float = (
		viewport_size.y / _world_rect.size.y
	)

	_fit_scale = clampf(
		minf(scale_x, scale_y),
		min_camera_zoom,
		max_camera_zoom
	)

	_display_scale = clampf(
		_fit_scale * maxf(
			player_follow_zoom_multiplier,
			1.0
		),
		min_camera_zoom,
		max_camera_zoom
	)

	_minimap_camera.zoom = Vector2(
		_display_scale,
		_display_scale
	)
	_update_follow_camera()
	_minimap_camera.force_update_scroll()

	_update_player_marker()

	if debug_log:
		print(
			"[Minimap] bounds refreshed used_rect=",
			used,
			" expanded=",
			expanded,
			" world_rect=",
			_world_rect,
			" zoom=",
			_fit_scale,
			" player_visibility_layer=",
			_player.visibility_layer,
			" minimap_cull_mask=",
			_subviewport.canvas_cull_mask
		)


# Updates the player marker.
func _update_player_marker() -> void:
	if (
		not _configured
		or _player == null
		or _display_scale <= 0.0
	):
		return

	var viewport_size := Vector2(MAP_VIEWPORT_SIZE)
	var map_position: Vector2 = (
		(_player.global_position - _camera_center)
		* _display_scale
		+ viewport_size * 0.5
	)

	map_position.x = clampf(
		map_position.x,
		0.0,
		viewport_size.x
	)
	map_position.y = clampf(
		map_position.y,
		0.0,
		viewport_size.y
	)

	_player_marker.position = (
		MAP_TEXTURE_POSITION
		+ map_position
		- MARKER_SIZE * 0.5
	)


# Updates the follow camera.
func _update_follow_camera() -> void:
	if (
		not _configured
		or _player == null
		or _display_scale <= 0.0
		or _world_rect.size.x <= 0.0
		or _world_rect.size.y <= 0.0
	):
		return

	var half_visible: Vector2 = (
		Vector2(MAP_VIEWPORT_SIZE)
		/ (2.0 * _display_scale)
	)

	var min_center: Vector2 = (
		_world_rect.position + half_visible
	)
	var max_center: Vector2 = (
		_world_rect.end - half_visible
	)

	var target: Vector2 = _player.global_position

	# If one map dimension is smaller than the minimap view, keep that axis
	# centered instead of producing inverted clamp bounds.
	if min_center.x > max_center.x:
		target.x = _world_rect.get_center().x
	else:
		target.x = clampf(
			target.x,
			min_center.x,
			max_center.x
		)

	if min_center.y > max_center.y:
		target.y = _world_rect.get_center().y
	else:
		target.y = clampf(
			target.y,
			min_center.y,
			max_center.y
		)

	_camera_center = target
	_minimap_camera.global_position = _camera_center


# Creates the render target.
func _create_render_target() -> void:
	_subviewport = SubViewport.new()
	_subviewport.name = "MinimapViewport"
	_subviewport.size = MAP_VIEWPORT_SIZE
	_subviewport.disable_3d = true
	_subviewport.transparent_bg = true
	_subviewport.gui_disable_input = true
	_subviewport.canvas_cull_mask = (
		(1 << 20) - 1
	) & ~MINIMAP_HIDDEN_VISIBILITY_LAYER
	_subviewport.render_target_clear_mode = (
		SubViewport.CLEAR_MODE_ALWAYS
	)
	_subviewport.render_target_update_mode = (
		SubViewport.UPDATE_DISABLED
	)
	add_child(_subviewport)

	_minimap_camera = Camera2D.new()
	_minimap_camera.name = "MinimapCamera"
	_minimap_camera.enabled = true
	_minimap_camera.ignore_rotation = true
	_minimap_camera.position_smoothing_enabled = false
	_minimap_camera.rotation_smoothing_enabled = false
	_subviewport.add_child(_minimap_camera)


# Creates the UI.
func _create_ui() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "MinimapHUD"
	_hud_layer.layer = 6
	add_child(_hud_layer)

	_panel = Panel.new()
	_panel.name = "MinimapPanel"
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_hud_layer.add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(
		0.035,
		0.050,
		0.055,
		0.92
	)
	panel_style.border_color = Color(
		0.28,
		0.52,
		0.39,
		1.0
	)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.position = Vector2(10.0, 3.0)
	_title_label.size = Vector2(190.0, 21.0)
	_title_label.text = ""
	_title_label.visible = false
	_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_title_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_title_label.add_theme_font_size_override(
		"font_size",
		12
	)
	_title_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_panel.add_child(_title_label)

	_map_background = ColorRect.new()
	_map_background.name = "MapBackground"
	_map_background.position = (
		MAP_TEXTURE_POSITION - Vector2.ONE
	)
	_map_background.size = (
		Vector2(MAP_VIEWPORT_SIZE)
		+ Vector2(2.0, 2.0)
	)
	_map_background.color = Color(
		0.015,
		0.020,
		0.025,
		0.96
	)
	_map_background.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_panel.add_child(_map_background)

	_map_texture = TextureRect.new()
	_map_texture.name = "MapTexture"
	_map_texture.position = MAP_TEXTURE_POSITION
	_map_texture.size = Vector2(MAP_VIEWPORT_SIZE)
	_map_texture.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)
	_map_texture.stretch_mode = (
		TextureRect.STRETCH_SCALE
	)
	_map_texture.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	_map_texture.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_map_texture.texture = _subviewport.get_texture()
	_panel.add_child(_map_texture)

	_player_marker = Panel.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.size = MARKER_SIZE
	_player_marker.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_player_marker.z_index = 10
	_panel.add_child(_player_marker)

	var marker_style := StyleBoxFlat.new()
	marker_style.bg_color = Color(
		1.0,
		0.82,
		0.18,
		1.0
	)
	marker_style.border_color = Color(
		0.10,
		0.08,
		0.02,
		1.0
	)
	marker_style.border_width_left = 1
	marker_style.border_width_top = 1
	marker_style.border_width_right = 1
	marker_style.border_width_bottom = 1
	marker_style.corner_radius_top_left = 4
	marker_style.corner_radius_top_right = 4
	marker_style.corner_radius_bottom_left = 4
	marker_style.corner_radius_bottom_right = 4
	_player_marker.add_theme_stylebox_override(
		"panel",
		marker_style
	)


# Updates the panel layout.
func _update_panel_layout(force: bool = false) -> void:
	if _panel == null:
		return

	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	if (
		not force
		and viewport_size == _last_viewport_size
	):
		return

	_last_viewport_size = viewport_size

	# Keep the minimap aligned with the ProgressionHUD on the right side.
	# The Player Level panel occupies the top-right area, so the minimap sits
	# directly below it with the same outer screen margin.
	var resolved_x: float = maxf(
		viewport_size.x
		- PANEL_SIZE.x
		- SCREEN_EDGE_MARGIN,
		SCREEN_EDGE_MARGIN
	)

	var resolved_y: float = PANEL_TOP_MARGIN

	# On very short windows, clamp vertically so the minimap remains visible.
	var max_y: float = maxf(
		viewport_size.y
		- PANEL_SIZE.y
		- SCREEN_EDGE_MARGIN,
		SCREEN_EDGE_MARGIN
	)
	resolved_y = minf(
		resolved_y,
		max_y
	)

	_panel.position = Vector2(
		resolved_x,
		resolved_y
	)

	if debug_log:
		print(
			"[Minimap] layout viewport=",
			viewport_size,
			" panel_position=",
			_panel.position,
			" placement=below_progression_hud"
		)


# Creates the bounds timer.
func _create_bounds_timer() -> void:
	_bounds_timer = Timer.new()
	_bounds_timer.name = "BoundsPollTimer"
	_bounds_timer.wait_time = maxf(
		bounds_poll_seconds,
		0.20
	)
	_bounds_timer.one_shot = false
	_bounds_timer.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)
	_bounds_timer.timeout.connect(
		_on_bounds_timer_timeout
	)
	add_child(_bounds_timer)
	_bounds_timer.start()


# Connects the global signals signals and callbacks.
func _connect_global_signals() -> void:
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

	if not SaveSystem.load_completed.is_connected(
		_on_load_completed
	):
		SaveSystem.load_completed.connect(
			_on_load_completed
		)


# Sets the visible state.
func _set_visible_state() -> void:
	var should_show: bool = (
		_configured
		and not _build_mode_active
	)

	if _panel != null:
		_panel.visible = should_show

	if _subviewport != null:
		_subviewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS
			if should_show
			else SubViewport.UPDATE_DISABLED
		)


# Handles the bounds timer timeout signal or callback.
func _on_bounds_timer_timeout() -> void:
	if not _configured or _build_mode_active:
		return

	refresh_bounds(false)


# Handles the build mode changed signal or callback.
func _on_build_mode_changed(active: bool) -> void:
	_build_mode_active = active

	if not active:
		call_deferred("refresh_bounds", true)

	_set_visible_state()


# Handles the build cell placed signal or callback.
func _on_build_cell_placed(
	_cell: Vector2i,
	_build_id: StringName,
	_cost: int
) -> void:
	call_deferred("refresh_bounds", true)


# Handles the build cell removed signal or callback.
func _on_build_cell_removed(
	_cell: Vector2i,
	_build_id: StringName,
	_refund: int
) -> void:
	call_deferred("refresh_bounds", true)


# Handles the load completed signal or callback.
func _on_load_completed(_path: String) -> void:
	call_deferred("refresh_bounds", true)

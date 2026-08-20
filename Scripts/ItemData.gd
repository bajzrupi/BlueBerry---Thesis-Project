extends Resource
class_name ItemData

# Generic inventory item definition shared by inventory, layout and hotbar.

enum ItemKind {
	GENERIC,
	SEED,
	HARVEST,
	CONSUMABLE,
	PLACEABLE
}

@export_category("Identity")

@export var item_id: StringName = &""
@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var item_kind: ItemKind = ItemKind.GENERIC


@export_category("Inventory")

@export_range(1, 999999, 1) var stack_limit: int = 9999
@export var hotbar_allowed: bool = true


@export_category("Visuals")

@export var icon: Texture2D


# Runtime compatibility link used by seed items.
var linked_plant_data: PlantData = null


# Checks whether the current data is valid.
func is_valid() -> bool:
	return item_id != &""


# Checks whether this item represents a seed.
func is_seed() -> bool:
	return item_kind == ItemKind.SEED and linked_plant_data != null


# Returns an explicit icon or derives one from a linked plant.
func get_inventory_icon() -> Texture2D:
	if icon != null:
		return icon

	if linked_plant_data == null:
		return null

	if linked_plant_data.stage_textures.is_empty():
		return null

	var stage_index: int = clampi(
		linked_plant_data.max_stage,
		0,
		linked_plant_data.stage_textures.size() - 1
	)
	var source_texture: Texture2D = (
		linked_plant_data.stage_textures[stage_index]
	)

	if source_texture == null:
		return null

	if stage_index >= linked_plant_data.stage_regions.size():
		return source_texture

	var region: Rect2 = (
		linked_plant_data.stage_regions[stage_index]
	)

	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return source_texture

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = source_texture
	atlas_texture.region = region
	return atlas_texture

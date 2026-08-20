extends Resource
class_name PlantData

# Plant definition data used by Plant instances
@export var display_name: String = "Plant"

# Inventory item consumed when this plant is placed.
@export var seed_item_id: StringName = &""

# Number of seeds required for one planting action.
@export var planting_cost: int = 1

# Inventory item awarded when this plant is harvested.
@export var harvest_item_id: StringName = &""

# Minimum item amount awarded by one harvest.
@export var harvest_yield_min: int = 1

# Maximum item amount awarded by one harvest.
@export var harvest_yield_max: int = 1

# Controls whether the plant can regrow after harvesting.
@export var regrows_after_harvest: bool = false


@export_category("Progression")

# Plant mastery XP awarded by one successful harvest.
@export_range(1, 100, 1) var plant_mastery_xp_per_harvest: int = 1



@export_category("Shop")

# Controls whether this seed appears in the seed shop.
@export var available_in_shop: bool = true

# Money required to buy one seed.
@export_range(0, 100000, 1) var seed_buy_price: int = 10

# Money received when selling one seed.
@export_range(0, 100000, 1) var seed_sell_price: int = 4


@export_category("Visuals")

@export var stage_textures: Array[Texture2D] = []
@export var stage_regions: Array[Rect2] = []
@export var max_stage: int = 2

# Uniform scale applied to this plant's sprite.
@export_range(0.1, 3.0, 0.01) var visual_scale: float = 1.0

# Vertical alignment reference for the plant sprite.
@export var base_sprite_offset_y: float = -10.0

@export var footprint_size: Vector2i = Vector2i(1, 1)
@export var footprint_origin: Vector2i = Vector2i(0, 0)

@export var allowed_soils: Array[String] = ["loamy"]


@export var optimal_moisture_min: float = 0.55
@export var optimal_moisture_max: float = 0.85


@export var optimal_nutrients_min: float = 0.45
@export var optimal_nutrients_max: float = 0.85


@export var optimal_ph_min: float = 6.0
@export var optimal_ph_max: float = 7.5


@export var max_health: float = 100.0
@export var health_recover_per_hour: float = 0.4
@export var health_decay_per_hour: float = 1.0


@export var growth_factor_outside_range: float = 0.35


@export var days_to_next_stage: Array[float] = [3.0, 7.0]


@export var pest_resistance: float = 0.25
@export var disease_resistance: float = 0.20


@export var optimal_temp_min: float = 18.0
@export var optimal_temp_max: float = 26.0

@export var optimal_humidity_min: float = 0.40
@export var optimal_humidity_max: float = 0.80

@export var optimal_light_min: float = 0.50
@export var optimal_light_max: float = 1.00

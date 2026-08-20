extends Node

# Announces every money balance change.
signal money_changed(
	previous_amount: int,
	new_amount: int,
	delta: int,
	reason: String
)

# Announces a complete economy reset.
signal economy_reset(current_amount: int)


# Starting balance used by a new test session.
const DEFAULT_MONEY: int = 50


@export_category("Debug Logging")

# Enables economy operation logging.
@export var debug_log: bool = false


# Stores the current money balance.
var _money: int = DEFAULT_MONEY


# Initializes the economy state.
func _ready() -> void:
	reset_to_defaults()

	if debug_log:
		print("[Economy] ready money=", _money)


# Restores the default money balance.
func reset_to_defaults() -> void:
	_money = DEFAULT_MONEY
	economy_reset.emit(_money)

	if debug_log:
		print("[Economy] reset money=", _money)


# Returns the current money balance.
func get_money() -> int:
	return _money


# Returns whether the requested amount can be paid.
func can_afford(amount: int) -> bool:
	if amount <= 0:
		return true

	return _money >= amount


# Adds money to the current balance.
func add_money(
	amount: int,
	reason: String = ""
) -> bool:
	if amount <= 0:
		push_warning(
			"[Economy] add_money rejected: amount must be positive."
		)

		if debug_log:
			print(
				"[Economy] add failed amount=",
				amount,
				" reason=",
				reason
			)

		return false

	var previous_amount := _money
	_money += amount

	money_changed.emit(
		previous_amount,
		_money,
		amount,
		reason
	)

	if debug_log:
		print(
			"[Economy] added amount=",
			amount,
			" old=",
			previous_amount,
			" new=",
			_money,
			" reason=",
			reason
		)

	return true


# Removes money when the current balance is sufficient.
func spend_money(
	amount: int,
	reason: String = ""
) -> bool:
	if amount <= 0:
		push_warning(
			"[Economy] spend_money rejected: amount must be positive."
		)

		if debug_log:
			print(
				"[Economy] spend failed amount=",
				amount,
				" reason=",
				reason
			)

		return false

	if not can_afford(amount):
		if debug_log:
			print(
				"[Economy] insufficient money required=",
				amount,
				" available=",
				_money,
				" reason=",
				reason
			)

		return false

	var previous_amount := _money
	_money -= amount

	money_changed.emit(
		previous_amount,
		_money,
		-amount,
		reason
	)

	if debug_log:
		print(
			"[Economy] spent amount=",
			amount,
			" old=",
			previous_amount,
			" new=",
			_money,
			" reason=",
			reason
		)

	return true


# Sets the balance for loading or administrative changes.
func set_money(
	amount: int,
	reason: String = "SET"
) -> void:
	var previous_amount := _money
	_money = maxi(amount, 0)

	money_changed.emit(
		previous_amount,
		_money,
		_money - previous_amount,
		reason
	)

	if debug_log:
		print(
			"[Economy] set old=",
			previous_amount,
			" new=",
			_money,
			" reason=",
			reason
		)

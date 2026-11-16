extends CharacterBody2D

const SPEED = 200.0
signal health_changed(current_health: float, max_health: float)
signal died
signal dashed
signal perfect_dodged(source_position: Vector2)
signal slipped(source: Node)
signal got_stuck(source: Node)

@export var max_health: int = 5
@export var invincibility_duration: float = 1.0
@export var hitstun_duration: float = 0.3
@export var player_hit_stagger_duration: float = 0.3
@export var received_knockback_decay: float = 700.0
@export var received_knockback_force: float = 60.0
@export var dodge_distance: float = 55.0
@export var dodge_invulnerability_duration: float = 0.15
@export var dodge_cooldown: float = 15.0
@export var dodge_duration: float = 0.15

@export_category("Dash")
## Pure movement (no invulnerability). Tuned in CombatV3Tuning.
@export var dash_distance: float = 90.0
@export var dash_duration: float = 0.12
@export var dash_max_charges: int = 2
@export var dash_recharge_time: float = 1.2
@export var perfect_dodge_counter_window: float = 1.0
@export var pounce_window_after_dash: float = 0.3

@export_category("Defense")
@export var shield_max_durability: float = 100.0
@export var slime_attack_shield_cost: float = 25.0
@export var shield_regen_delay: float = 3.0
@export var shield_regen_per_second: float = 15.0
@export var defense_movement_multiplier: float = 0.0
@export var guard_break_stun_duration: float = 1.5
@export var guard_break_restore_ratio: float = 0.3
@export var perfect_guard_window: float = 0.25
@export var perfect_guard_pause_duration: float = 1.0

var current_health: float
var nearby_objects: Array[Node] = []
var last_facing: Vector2 = Vector2.DOWN
var invincibility_left: float = 0.0
var dodge_cooldown_left: float = 0.0
var dodge_time_left: float = 0.0
var dodge_direction: Vector2 = Vector2.ZERO
var dodge_iframes_left: float = 0.0
var perfect_dodge_triggered: bool = false
var counter_window_left: float = 0.0
var dash_time_left: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var dash_charges: int = 2
var dash_recharge_left: float = 0.0
var pounce_window_left: float = 0.0
var pounce_time_left: float = 0.0
var pounce_direction: Vector2 = Vector2.ZERO
var pounce_speed: float = 0.0
# Touching a slime: a chance to slip (lose control for a moment) or get stuck (slowed, no
# dash / dodge). Tuned in CombatV3Tuning ("史莱姆接触").
var slime_contact_chance: float = 0.35
var contact_roll_interval: float = 0.5
var slip_share: float = 0.5
var slip_duration: float = 0.6
var slip_speed: float = 220.0
var stick_duration: float = 1.2
var stick_speed_multiplier: float = 0.25
var contact_immunity_duration: float = 2.0
var slip_time_left: float = 0.0
var slip_velocity: Vector2 = Vector2.ZERO
var stick_time_left: float = 0.0
var contact_immunity_left: float = 0.0
var contact_roll_left: float = 0.0
var contact_rng := RandomNumberGenerator.new()
var hitstun_left: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var dead: bool = false
var position_discontinuity_version: int = 0
var shield_durability: float = 100.0
var shield_regen_delay_left: float = 0.0
var guard_break_left: float = 0.0
var is_defending: bool = false
var perfect_guard_flash_left: float = 0.0
var defend_must_release: bool = false
var perfect_guard_hold_consumed: bool = false
var received_attack_ids: Dictionary = {}
var received_attack_id_order: Array[int] = []
var attack_block_handler: Callable

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var combat = get_node_or_null("PlayerCombat")


func _ready() -> void:
	_apply_combat_tuning()
	_apply_progression_stats(true)
	current_health = max_health
	shield_durability = shield_max_durability
	dash_charges = dash_max_charges
	contact_rng.randomize()
	add_to_group("player")
	animated_sprite.play("idle")
	var time_controller := get_node_or_null("/root/CombatTimeController")
	if is_instance_valid(time_controller) and time_controller.is_enemy_side_paused():
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.has_method("set_combat_paused"):
				enemy.set_combat_paused(true)
	health_changed.emit(current_health, max_health)
	ProgressionManager.progression_changed.connect(_on_progression_changed)
	if ExpeditionManager.run_active:
		ExpeditionManager.restore_player_if_resuming(self)
		died.connect(func(): ExpeditionManager.on_player_died(self))


func _physics_process(delta: float) -> void:
	invincibility_left = maxf(invincibility_left - delta, 0.0)
	dodge_cooldown_left = maxf(dodge_cooldown_left - delta, 0.0)
	dodge_iframes_left = maxf(dodge_iframes_left - delta, 0.0)
	counter_window_left = maxf(counter_window_left - delta, 0.0)
	pounce_window_left = maxf(pounce_window_left - delta, 0.0)
	hitstun_left = maxf(hitstun_left - delta, 0.0)
	slip_time_left = maxf(slip_time_left - delta, 0.0)
	contact_immunity_left = maxf(contact_immunity_left - delta, 0.0)
	contact_roll_left = maxf(contact_roll_left - delta, 0.0)
	if stick_time_left > 0.0:
		stick_time_left = maxf(stick_time_left - delta, 0.0)
		if stick_time_left <= 0.0:
			animated_sprite.modulate = Color.WHITE
	_update_dash_recharge(delta)

	if dead:
		velocity = Vector2.ZERO
		return
	if InventoryManager.ui_open:
		velocity = Vector2.ZERO
		update_animation(Vector2.ZERO)
		move_and_slide()
		return
	_update_defense(delta)
	if guard_break_left > 0.0:
		velocity = Vector2.ZERO
		update_animation(Vector2.ZERO)
		move_and_slide()
		return

	if hitstun_left > 0.0:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(
			Vector2.ZERO,
			received_knockback_decay * delta
		)
		move_and_slide()
		return

	if slip_time_left > 0.0:
		# Slipping: no steering, the slide fades out.
		velocity = slip_velocity * (slip_time_left / maxf(slip_duration, 0.001))
		move_and_slide()
		return

	var direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	if direction != Vector2.ZERO:
		last_facing = direction.normalized()
	if is_defending:
		velocity = Vector2.ZERO
		update_animation(Vector2.ZERO)
		move_and_slide()
		return
	if dodge_time_left > 0.0:
		_move_during_dodge(delta)
		return
	if pounce_time_left > 0.0:
		_move_during_pounce(delta)
		return
	if dash_time_left > 0.0:
		_move_during_dash(delta)
		return
	if Input.is_action_just_pressed("dodge") and _try_start_dodge(direction):
		_move_during_dodge(delta)
		return
	if Input.is_action_just_pressed("dash") and _try_start_dash(direction):
		_move_during_dash(delta)
		return

	var movement_multiplier := defense_movement_multiplier if is_defending else 1.0
	if combat != null and combat.has_method("get_movement_multiplier"):
		movement_multiplier *= combat.get_movement_multiplier()
	if stick_time_left > 0.0:
		movement_multiplier *= stick_speed_multiplier
	velocity = direction * get_effective_move_speed() * movement_multiplier

	if combat == null or not combat.has_method("is_action_active") or not combat.is_action_active():
		update_animation(direction)

	move_and_slide()
	_check_slime_contact()


func update_animation(direction: Vector2) -> void:
	if dead:
		return
	if direction == Vector2.ZERO:
		animated_sprite.play("idle")
		return

	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			animated_sprite.play("walk_right")
		else:
			animated_sprite.play("walk_left")
	else:
		if direction.y > 0:
			animated_sprite.play("walk_down")
		else:
			animated_sprite.play("walk_up")


func restore_movement_animation() -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	update_animation(direction)


func get_last_facing() -> Vector2:
	return last_facing


func get_facing_name() -> String:
	if absf(last_facing.x) > absf(last_facing.y):
		return "right" if last_facing.x > 0.0 else "left"
	return "down" if last_facing.y > 0.0 else "up"


func is_alive() -> bool:
	return not dead


func is_in_hitstun() -> bool:
	return hitstun_left > 0.0


func can_perform_combat_action() -> bool:
	return (
		not dead
		and slip_time_left <= 0.0
		and hitstun_left <= 0.0
		and guard_break_left <= 0.0
		and not is_defending
	)


func _try_start_dodge(input_direction: Vector2) -> bool:
	if dodge_cooldown_left > 0.0 or guard_break_left > 0.0 or hitstun_left > 0.0 or dead or is_defending or stick_time_left > 0.0:
		return false
	dodge_direction = input_direction.normalized() if input_direction != Vector2.ZERO else last_facing.normalized()
	if dodge_direction == Vector2.ZERO:
		dodge_direction = Vector2.DOWN
	dodge_time_left = dodge_duration
	dodge_cooldown_left = dodge_cooldown
	invincibility_left = maxf(invincibility_left, dodge_invulnerability_duration)
	dodge_iframes_left = dodge_invulnerability_duration
	perfect_dodge_triggered = false
	return true


func _move_during_dodge(delta: float) -> void:
	dodge_time_left = maxf(dodge_time_left - delta, 0.0)
	velocity = dodge_direction * (dodge_distance / maxf(dodge_duration, 0.001))
	move_and_slide()


## Cat-step dash: a short burst of movement with NO invulnerability. It can cancel a
## melee swing, so dash-cancelling is a skill expression, not a safety button.
func _try_start_dash(input_direction: Vector2) -> bool:
	if dash_charges <= 0 or dead or guard_break_left > 0.0 or hitstun_left > 0.0 or is_defending or stick_time_left > 0.0:
		return false
	dash_direction = input_direction.normalized() if input_direction != Vector2.ZERO else last_facing.normalized()
	if dash_direction == Vector2.ZERO:
		dash_direction = Vector2.DOWN
	if dash_charges >= dash_max_charges:
		dash_recharge_left = dash_recharge_time
	dash_charges -= 1
	dash_time_left = dash_duration
	pounce_window_left = dash_duration + pounce_window_after_dash
	if combat != null and combat.has_method("cancel_action"):
		combat.cancel_action()
	last_facing = dash_direction
	HitFeel.afterimage(animated_sprite, Color(1.0, 0.8, 0.9, 0.55))
	dashed.emit()
	return true


func _move_during_dash(delta: float) -> void:
	# The last frame only moves for the time that is left, so the dash covers exactly
	# dash_distance whatever the frame rate (0.12 s is not a whole number of frames).
	var step_time := minf(delta, dash_time_left)
	dash_time_left = maxf(dash_time_left - delta, 0.0)
	var speed := dash_distance / maxf(dash_duration, 0.001)
	velocity = dash_direction * speed * (step_time / maxf(delta, 0.0001))
	update_animation(dash_direction)
	move_and_slide()
	_check_slime_contact()
	HitFeel.afterimage(animated_sprite, Color(1.0, 0.8, 0.9, 0.4))


## Pounce (move learned by exploring): a forward leap that follows a dash. The combat
## script decides when it starts; the controller only moves the body, with the same
## frame-rate independent distance as the dash. No invulnerability.
func can_pounce() -> bool:
	return pounce_window_left > 0.0 and not dead and guard_break_left <= 0.0 and hitstun_left <= 0.0 and not is_defending


func start_pounce(direction: Vector2, distance: float, move_duration: float) -> void:
	pounce_direction = direction.normalized() if direction != Vector2.ZERO else last_facing
	pounce_speed = distance / maxf(move_duration, 0.001)
	pounce_time_left = move_duration
	pounce_window_left = 0.0
	dash_time_left = 0.0
	last_facing = pounce_direction


func stop_pounce() -> void:
	pounce_time_left = 0.0


func is_pouncing() -> bool:
	return pounce_time_left > 0.0


func _move_during_pounce(delta: float) -> void:
	var step_time := minf(delta, pounce_time_left)
	pounce_time_left = maxf(pounce_time_left - delta, 0.0)
	velocity = pounce_direction * pounce_speed * (step_time / maxf(delta, 0.0001))
	update_animation(pounce_direction)
	move_and_slide()
	_check_slime_contact()
	HitFeel.afterimage(animated_sprite, Color(1.0, 0.75, 0.6, 0.4))


## Touching a living, active slime: every contact_roll_interval there is a slime_contact_chance
## to slip or get stuck, and after an effect the cat is immune for a while.
func _check_slime_contact() -> void:
	if dead or contact_immunity_left > 0.0 or contact_roll_left > 0.0:
		return
	if dodge_iframes_left > 0.0 or hitstun_left > 0.0 or guard_break_left > 0.0:
		return
	for index in range(get_slide_collision_count()):
		var other := get_slide_collision(index).get_collider()
		if other is Node and other.is_in_group("enemies") and other.has_method("is_contact_harmful") and other.is_contact_harmful():
			contact_roll_left = contact_roll_interval
			if contact_rng.randf() < slime_contact_chance:
				_apply_slime_contact_effect(other)
			return


func _apply_slime_contact_effect(source: Node) -> void:
	contact_immunity_left = contact_immunity_duration
	dash_time_left = 0.0
	pounce_time_left = 0.0
	if combat != null and combat.has_method("cancel_action"):
		combat.cancel_action()
	if contact_rng.randf() < slip_share:
		_start_slip(source)
	else:
		_start_stick(source)


func _start_slip(source: Node) -> void:
	var direction := velocity.normalized() if velocity.length() > 10.0 else (global_position - (source as Node2D).global_position).normalized()
	if direction == Vector2.ZERO:
		direction = -last_facing
	slip_velocity = direction * slip_speed
	slip_time_left = slip_duration
	slipped.emit(source)
	HitFeel.damage_number(global_position + Vector2(0.0, -22.0), "滑倒！", HitFeel.CYAN, 15)


func _start_stick(source: Node) -> void:
	stick_time_left = stick_duration
	animated_sprite.modulate = Color(0.7, 1.0, 0.7, 1.0)
	got_stuck.emit(source)
	HitFeel.damage_number(global_position + Vector2(0.0, -22.0), "被黏住了！", HitFeel.GREEN, 15)


## Spend the counter window (the counter claw uses it up).
func consume_counter_window() -> void:
	counter_window_left = 0.0


func _update_dash_recharge(delta: float) -> void:
	if dash_charges >= dash_max_charges:
		dash_recharge_left = 0.0
		return
	dash_recharge_left -= delta
	if dash_recharge_left <= 0.0:
		dash_charges += 1
		dash_recharge_left = dash_recharge_time if dash_charges < dash_max_charges else 0.0


func is_dashing() -> bool:
	return dash_time_left > 0.0


## A hit that lands inside the dodge's invulnerability frames is a "perfect dodge":
## the dodge cooldown is refunded and a short counter window opens.
func _trigger_perfect_dodge(source_position: Vector2) -> void:
	if perfect_dodge_triggered:
		return
	perfect_dodge_triggered = true
	dodge_cooldown_left = 0.0
	counter_window_left = perfect_dodge_counter_window
	perfect_dodged.emit(source_position)
	HitFeel.perfect_dodge(global_position)


func is_counter_window_open() -> bool:
	return counter_window_left > 0.0


func is_guard_broken() -> bool:
	return guard_break_left > 0.0


func _update_defense(delta: float) -> void:
	perfect_guard_flash_left = maxf(perfect_guard_flash_left - delta, 0.0)
	var defend_held := Input.is_action_pressed("defend")
	var defend_just_pressed := Input.is_action_just_pressed("defend")
	if not defend_held:
		if is_defending:
			is_defending = false
		defend_must_release = false
		perfect_guard_hold_consumed = false
	if guard_break_left > 0.0:
		guard_break_left = maxf(guard_break_left - delta, 0.0)
		is_defending = false
		if guard_break_left <= 0.0:
			shield_durability = shield_max_durability * guard_break_restore_ratio
		else:
			_update_shield_regeneration_delay(delta)
		return
	if hitstun_left > 0.0:
		is_defending = false
		_update_shield_regeneration(delta)
		return
	if defend_just_pressed and not defend_must_release and shield_durability > 0.0:
		_handle_defend_press(defend_held)
	elif (
		defend_held
		and not perfect_guard_hold_consumed
		and not defend_must_release
		and shield_durability > 0.0
		and not is_defending
	):
		is_defending = true
		if combat != null and combat.has_method("cancel_action"):
			combat.cancel_action()
	_update_shield_regeneration(delta)


func _update_shield_regeneration(delta: float) -> void:
	if _update_shield_regeneration_delay(delta):
		return
	if shield_durability > 0.0 and shield_durability < shield_max_durability:
		shield_durability = minf(
			shield_durability + shield_regen_per_second * delta,
			shield_max_durability
		)


func _update_shield_regeneration_delay(delta: float) -> bool:
	if shield_regen_delay_left <= 0.0:
		return false
	shield_regen_delay_left = maxf(shield_regen_delay_left - delta, 0.0)
	return true


func _handle_defend_press(defend_held: bool) -> void:
	if defend_must_release or shield_durability <= 0.0 or guard_break_left > 0.0 or hitstun_left > 0.0:
		return
	if _try_perfect_guard():
		perfect_guard_hold_consumed = defend_held
		is_defending = false
	else:
		is_defending = true
		if combat != null and combat.has_method("cancel_action"):
			combat.cancel_action()


func _try_perfect_guard() -> bool:
	var time_controller := get_node_or_null("/root/CombatTimeController")
	if not is_instance_valid(time_controller) or time_controller.is_enemy_side_paused():
		return false
	var best_enemy: Node = null
	var best_attack_id: int = 0
	var best_eta := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("get_attack_eta_for"):
			continue
		var eta: float = enemy.get_attack_eta_for(self, perfect_guard_window)
		if eta >= 0.0 and eta < best_eta:
			best_enemy = enemy
			best_attack_id = int(enemy.current_attack_id)
			best_eta = eta
	if not is_instance_valid(best_enemy) or not best_enemy.has_method("parry_attack"):
		return false
	if not best_enemy.parry_attack(best_attack_id):
		return false
	time_controller.pause_enemy_side(perfect_guard_pause_duration)
	perfect_guard_flash_left = perfect_guard_pause_duration
	HitFeel.perfect_guard(global_position)
	return true


func _break_shield() -> void:
	shield_durability = 0.0
	guard_break_left = guard_break_stun_duration
	is_defending = false
	defend_must_release = Input.is_action_pressed("defend")
	if combat != null and combat.has_method("cancel_action"):
		combat.cancel_action()


func receive_damage(amount: float, source_position: Vector2, knockback_force: float = 120.0) -> bool:
	if not dead and amount > 0 and dodge_iframes_left > 0.0 and guard_break_left <= 0.0:
		_trigger_perfect_dodge(source_position)
		return false
	if dead or guard_break_left > 0.0 or invincibility_left > 0.0 or amount <= 0:
		return false

	current_health = maxf(current_health - amount, 0.0)
	invincibility_left = invincibility_duration
	hitstun_left = hitstun_duration
	var knockback_direction := (global_position - source_position).normalized()
	if knockback_direction == Vector2.ZERO:
		knockback_direction = -last_facing
	knockback_velocity = knockback_direction.normalized() * minf(knockback_force, received_knockback_force)
	if combat != null and combat.has_method("cancel_action"):
		combat.cancel_action()
	dash_time_left = 0.0
	pounce_time_left = 0.0
	health_changed.emit(current_health, max_health)
	play_hit_feedback()
	HitFeel.player_hurt(global_position)

	if current_health <= 0:
		die()
	return true


func receive_attack_damage(
	attack_id: int,
	amount: float,
	source_position: Vector2,
	knockback_force: float = 120.0,
	shield_damage: float = 25.0
) -> bool:
	if attack_id <= 0 or received_attack_ids.has(attack_id):
		return false
	received_attack_ids[attack_id] = true
	received_attack_id_order.append(attack_id)
	if received_attack_id_order.size() > 128:
		var expired_id: int = received_attack_id_order.pop_front()
		received_attack_ids.erase(expired_id)
	if try_block_attack(attack_id, shield_damage):
		return true
	var accepted := receive_damage(amount, source_position, knockback_force)
	if accepted and not dead:
		hitstun_left = player_hit_stagger_duration
	return accepted


func try_block_attack(attack_id: int, shield_damage: float = 25.0) -> bool:
	if attack_block_handler.is_valid():
		return bool(attack_block_handler.call(attack_id))
	if dead or guard_break_left > 0.0 or not is_defending or shield_durability <= 0.0:
		return false
	shield_durability = maxf(shield_durability - maxf(shield_damage, 0.0), 0.0)
	shield_regen_delay_left = shield_regen_delay
	if shield_durability <= 0.0:
		_break_shield()
	return true


func play_hit_feedback() -> void:
	animated_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	var tween := create_tween()
	tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.16)


func die() -> void:
	if dead:
		return
	dead = true
	is_defending = false
	velocity = Vector2.ZERO
	var time_controller := get_node_or_null("/root/CombatTimeController")
	if is_instance_valid(time_controller):
		time_controller.clear_enemy_pause()
	if combat != null and combat.has_method("set_combat_enabled"):
		combat.set_combat_enabled(false)
	animated_sprite.stop()
	animated_sprite.modulate = Color(0.45, 0.45, 0.55, 1.0)
	died.emit()


func revive_from_expedition(respawn_position: Vector2) -> void:
	mark_position_discontinuity()
	dead = false
	global_position = respawn_position
	velocity = Vector2.ZERO
	current_health = max_health
	shield_durability = shield_max_durability * 0.5
	shield_regen_delay_left = shield_regen_delay
	invincibility_left = invincibility_duration
	hitstun_left = 0.0
	guard_break_left = 0.0
	is_defending = false
	dash_charges = dash_max_charges
	dash_time_left = 0.0
	pounce_time_left = 0.0
	pounce_window_left = 0.0
	slip_time_left = 0.0
	stick_time_left = 0.0
	contact_immunity_left = 0.0
	animated_sprite.modulate = Color.WHITE
	if combat != null and combat.has_method("set_combat_enabled"):
		combat.set_combat_enabled(true)
	animated_sprite.modulate = Color.WHITE
	animated_sprite.play("idle")
	health_changed.emit(current_health, max_health)


func mark_position_discontinuity() -> void:
	position_discontinuity_version += 1


func restore_expedition_state(health: float, shield: float) -> void:
	if health >= 0.0:
		current_health = clampf(health, 1.0, float(max_health))
	if shield >= 0.0:
		shield_durability = clampf(shield, 0.0, shield_max_durability)
	health_changed.emit(current_health, max_health)


func get_effective_move_speed() -> float:
	return SPEED * ProgressionManager.get_movement_multiplier() * DayManager.get_night_movement_multiplier()


func _apply_progression_stats(initial: bool = false) -> void:
	var old_max_health := max_health
	var old_max_shield := shield_max_durability
	max_health = (
		ProgressionManager.get_effective_max_health(CombatBalance.tuning.player_base_health)
		+ DayManager.get_night_max_health_bonus()
	)
	shield_max_durability = CombatBalance.tuning.shield_max_durability * ProgressionManager.get_shield_multiplier()
	if not initial:
		current_health = minf(current_health + float(max_health - old_max_health), float(max_health))
		shield_durability = minf(shield_durability, shield_max_durability)
	health_changed.emit(current_health, max_health)


func _on_progression_changed() -> void:
	_apply_progression_stats()


func _apply_combat_tuning() -> void:
	var tuning: CombatV3Tuning = CombatBalance.tuning
	max_health = tuning.player_base_health
	invincibility_duration = tuning.player_invulnerability_duration
	hitstun_duration = tuning.player_hitstun_duration
	player_hit_stagger_duration = tuning.player_hitstun_duration
	received_knockback_force = tuning.player_knockback_force
	dodge_distance = tuning.dodge_distance
	dodge_invulnerability_duration = tuning.dodge_invulnerability_duration
	dodge_cooldown = tuning.dodge_cooldown
	dodge_duration = tuning.dodge_invulnerability_duration
	dash_distance = tuning.dash_distance
	dash_duration = tuning.dash_duration
	dash_max_charges = tuning.dash_max_charges
	dash_recharge_time = tuning.dash_recharge_time
	perfect_dodge_counter_window = tuning.perfect_dodge_counter_window
	pounce_window_after_dash = tuning.pounce_window_after_dash
	slime_contact_chance = tuning.slime_contact_chance
	contact_roll_interval = tuning.contact_roll_interval
	slip_share = tuning.slip_share
	slip_duration = tuning.slip_duration
	slip_speed = tuning.slip_speed
	stick_duration = tuning.stick_duration
	stick_speed_multiplier = tuning.stick_speed_multiplier
	contact_immunity_duration = tuning.contact_immunity_duration
	# Automated tests must not be disturbed by random slips; tests that cover the effect
	# switch the chance on explicitly.
	if OS.get_environment("PIXELCAT_TEST_MODE") == "1":
		slime_contact_chance = 0.0
	shield_max_durability = tuning.shield_max_durability
	slime_attack_shield_cost = tuning.slime_lunge_shield_cost
	defense_movement_multiplier = tuning.shield_movement_multiplier
	shield_regen_delay = tuning.shield_regen_delay
	shield_regen_per_second = tuning.shield_regen_per_second
	guard_break_stun_duration = tuning.guard_break_stun_duration
	guard_break_restore_ratio = tuning.guard_break_restore_ratio
	perfect_guard_window = tuning.perfect_guard_window
	perfect_guard_pause_duration = tuning.perfect_guard_pause_duration


func register_interactable(object: Node) -> void:
	if not nearby_objects.has(object):
		nearby_objects.append(object)


func unregister_interactable(object: Node) -> void:
	nearby_objects.erase(object)


func _process(_delta: float) -> void:
	if dead or InventoryManager.ui_open:
		return
	if Input.is_action_just_pressed("interact"):
		nearby_objects = nearby_objects.filter(func(object: Node) -> bool: return is_instance_valid(object))
		if nearby_objects.size() > 0:
			var min_distance = INF
			var nearest_object: Node = null
			for object in nearby_objects:
				var interactable := object as Node2D
				if interactable == null:
					continue
				var collision_shape := interactable.get_node_or_null("CollisionShape2D") as Node2D
				var target_position := interactable.global_position
				if collision_shape != null:
					target_position = collision_shape.global_position
				var distance = global_position.distance_to(target_position)
				print(object.name, " 距离：", distance)
				if distance < min_distance:
					min_distance = distance
					nearest_object = object
			print("最近的家具：", nearest_object.name)
			if nearest_object.has_method("interact"):
				nearest_object.interact()
		else:
			print("附近没有家具")

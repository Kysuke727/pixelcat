extends CharacterBody2D

## Shared parts of the "new generation" enemies (charger, flyer): health and damage, stun,
## the perfect-guard / perfect-dodge interface the cat uses, drops, objective reporting and the
## battle UI. A subclass only decides how the enemy behaves (override _behave and friends).
##
## (The older slime keeps its own implementation; both answer the same interface.)

signal health_changed(current_health: float, max_health: float)
signal died(enemy: Node)

enum S { IDLE, CHASE, WINDUP, ACT, RECOVER, HURT, STUNNED, DEAD, GROUNDED, RISE }

const FISH_PICKUP_SCENE := preload("res://scenes/pickups/dried_fish_pickup.tscn")
const MATERIAL_PICKUP_SCENE := preload("res://scenes/pickups/material_drop_pickup.tscn")
const MaterialLoot := preload("res://scripts/material_loot.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
## Attack ids must not clash with the slimes' (the cat remembers ids to ignore repeats).
static var _next_attack_id: int = 100000
const HIT_FLASH_DURATION := 0.14

@export var display_name: String = "敌人"
@export var max_health: int = 5
@export var experience_reward: int = 15
@export var counts_toward_objective: bool = true
@export var fish_drop_min: int = 1
@export var fish_drop_max: int = 3
@export var chase_range: float = 280.0
@export var disengage_range: float = 360.0

var state: int = S.IDLE
var current_health: float
var state_time: float = 0.0          # time spent in the current state
var spawn_position: Vector2
var target: Node2D
var facing: Vector2 = Vector2.RIGHT
var combat_paused: bool = false
var current_attack_id: int = 0
var current_attack_parried: bool = false
var stun_time_left: float = 0.0
var hurt_velocity: Vector2 = Vector2.ZERO
var hit_flash_left: float = 0.0
var base_color: Color = Color.WHITE   # sprite tint (a subclass changes it for telegraphs)
var vulnerable_multiplier: float = 1.0   # >1 while the enemy is exposed (stunned after a crash...)
var chase_path: PackedVector2Array = PackedVector2Array()
var chase_path_index: int = 0
var path_replan_left: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var body_collision: CollisionShape2D = $CollisionShape2D
var stars: Label


func _ready() -> void:
	current_health = max_health
	spawn_position = global_position
	add_to_group("enemies")
	add_to_group("damageable")
	_find_player()
	if is_instance_valid(CombatTimeController) and CombatTimeController.is_enemy_side_paused():
		combat_paused = true
	stars = Label.new()
	stars.text = "✦  ✦  ✦"
	stars.add_theme_font_size_override("font_size", 11)
	stars.add_theme_color_override("font_color", Color("#ffd84d"))
	stars.add_theme_color_override("font_outline_color", Color("#5c3a4b"))
	stars.add_theme_constant_override("outline_size", 4)
	stars.light_mask = 0
	stars.z_index = 100
	stars.position = Vector2(-22.0, -48.0)
	stars.visible = false
	add_child(stars)
	_setup()
	health_changed.emit(current_health, max_health)


# --- to override -------------------------------------------------------------------------
func _setup() -> void:
	pass


## Called every physics frame while alive, not paused, not stunned and not hurt.
func _behave(_delta: float) -> void:
	pass


## Visual update every frame (animation, telegraphs).
func _animate(_delta: float) -> void:
	pass


## (seconds until the attack reaches `candidate`, or -1 when it would not hit / is not attacking)
func _attack_eta(_candidate: Node2D, _max_window: float) -> float:
	return -1.0


# --- common loop -------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if state == S.DEAD or combat_paused:
		return
	state_time += delta
	if not is_instance_valid(target):
		_find_player()
	if state == S.STUNNED:
		stun_time_left = maxf(stun_time_left - delta, 0.0)
		velocity = Vector2.ZERO
		if stun_time_left <= 0.0:
			vulnerable_multiplier = 1.0
			stars.visible = false
			_enter(S.RECOVER if current_attack_id > 0 else S.IDLE)
	elif state == S.HURT:
		velocity = hurt_velocity
		hurt_velocity = hurt_velocity.move_toward(Vector2.ZERO, 650.0 * delta)
		move_and_slide()
		if state_time >= 0.2:
			_enter(S.CHASE if _target_distance() <= disengage_range else S.IDLE)
	else:
		_behave(delta)
	hit_flash_left = maxf(hit_flash_left - delta, 0.0)
	_animate(delta)
	var flash := clampf(hit_flash_left / HIT_FLASH_DURATION, 0.0, 1.0)
	sprite.modulate = base_color.lerp(Color(3, 3, 3, 1), flash)


func _enter(new_state: int) -> void:
	state = new_state
	state_time = 0.0


func _find_player() -> void:
	target = get_tree().get_first_node_in_group("player") as Node2D


func _target_distance() -> float:
	return global_position.distance_to(target.global_position) if is_instance_valid(target) else INF


func new_attack_id() -> int:
	_next_attack_id += 1
	current_attack_id = _next_attack_id
	current_attack_parried = false
	return current_attack_id


func is_alive() -> bool:
	return state != S.DEAD


func is_contact_harmful() -> bool:
	return false   # these enemies hurt through their attacks, not by being touched


# --- the interface the cat and the weapons use ---------------------------------------------
func receive_damage(amount: float, source_position: Vector2, knockback_force: float = 130.0) -> bool:
	if state == S.DEAD or amount <= 0:
		return false
	if ProgressionManager.debug_session:
		hit_flash_left = HIT_FLASH_DURATION
		return true
	current_health = maxf(current_health - amount * vulnerable_multiplier, 0.0)
	health_changed.emit(current_health, max_health)
	_show_in_battle_ui()
	hit_flash_left = HIT_FLASH_DURATION
	if current_health <= 0:
		_die()
		return true
	if state == S.STUNNED:
		return true
	if _can_be_knocked_back():
		var away := (global_position - source_position).normalized()
		if away == Vector2.ZERO:
			away = -facing
		hurt_velocity = away * knockback_force
		_enter(S.HURT)
	return true


## Subclasses return false for moments when a hit should not interrupt them (mid-charge...).
func _can_be_knocked_back() -> bool:
	return state != S.ACT


func apply_stun(duration: float, _immunity_duration: float = 1.0) -> bool:
	if state == S.DEAD or duration <= 0.0:
		return false
	stun_time_left = maxf(stun_time_left, duration)
	velocity = Vector2.ZERO
	stars.visible = true
	_enter(S.STUNNED)
	hit_flash_left = HIT_FLASH_DURATION
	return true


func register_combo_finisher(_attack_id: int, stun_roll_succeeded: bool, stun_duration: float, immunity: float) -> void:
	if stun_roll_succeeded:
		apply_stun(stun_duration, immunity)


func apply_yarn_bind(duration: float) -> bool:
	# a yarn ball briefly pins these enemies in place
	return apply_stun(minf(duration, 1.2), 1.0)


func get_attack_eta_for(candidate: Node2D, max_window: float = 0.7) -> float:
	if state == S.DEAD or combat_paused or current_attack_parried or current_attack_id <= 0 or not is_instance_valid(candidate):
		return -1.0
	if state != S.WINDUP and state != S.ACT:
		return -1.0
	return _attack_eta(candidate, max_window)


func parry_attack(attack_id: int) -> bool:
	if attack_id != current_attack_id or current_attack_parried or (state != S.WINDUP and state != S.ACT):
		return false
	current_attack_parried = true
	velocity = Vector2.ZERO
	apply_stun(1.0, 1.0)
	return true


func set_combat_paused(paused: bool) -> void:
	combat_paused = paused


func can_perform_attack() -> bool:
	return state != S.DEAD and not combat_paused


func get_control_status() -> Dictionary:
	return {"stunned": state == S.STUNNED, "bound": false, "slowed": false, "knocked_back": state == S.HURT}


# --- death and drops ---------------------------------------------------------------------------
func _die() -> void:
	if state == S.DEAD:
		return
	_enter(S.DEAD)
	velocity = Vector2.ZERO
	stars.visible = false
	body_collision.set_deferred("disabled", true)
	var drops := _prepare_fish_drops()
	var materials := _prepare_material_drops()
	if ExpeditionManager.run_active:
		ExpeditionManager.complete_enemy_with_drops(String(name), experience_reward, drops, materials)
	call_deferred("_drop_fish", drops)
	if not materials.is_empty():
		call_deferred("_drop_materials", materials)
	HitFeel.enemy_died(global_position)
	died.emit(self)
	for ui in get_tree().get_nodes_in_group("battle_ui"):
		if ui.has_method("hide_enemy"):
			ui.hide_enemy(self)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(sprite.scale.x * 1.3, 0.0), 0.3)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	await tween.finished
	queue_free()


func _drop_position(wanted: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(global_position, wanted, 1)
	if is_instance_valid(target) and target is CollisionObject2D:
		query.exclude = [target.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return wanted
	return hit["position"] + (global_position - hit["position"]).normalized() * 12.0


func _prepare_fish_drops() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var count := randi_range(fish_drop_min, fish_drop_max)
	for index in range(count):
		var angle := TAU * float(index) / float(maxi(count, 1)) + randf_range(-0.25, 0.25)
		var p := _drop_position(global_position + Vector2.from_angle(angle) * randf_range(8.0, 16.0))
		records.append({"id": "%s:fish:%d" % [String(name), index], "position": [p.x, p.y], "amount": 1})
	return records


func _prepare_material_drops() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if not ExpeditionManager.run_active:
		return records
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ids: Array[String] = MaterialLoot.roll_material_ids(rng)
	for index in range(ids.size()):
		var angle: float = TAU * float(index) / float(maxi(ids.size(), 1)) + rng.randf_range(-0.18, 0.18)
		var p := _drop_position(global_position + Vector2.from_angle(angle) * rng.randf_range(22.0, 34.0))
		records.append({"id": "%s:material:%d" % [String(name), index], "item_id": ids[index], "position": [p.x, p.y], "amount": 1})
	return records


func _drop_materials(records: Array[Dictionary]) -> void:
	if ProgressionManager.debug_session or not ExpeditionManager.run_active:
		return
	for record in records:
		if not ExpeditionManager.material_drops.has(str(record.get("id", ""))):
			continue
		var pickup: Area2D = MATERIAL_PICKUP_SCENE.instantiate()
		pickup.setup_saved_drop(str(record["id"]), str(record["item_id"]), 1)
		get_parent().add_child(pickup)
		var pos: Array = record.get("position", [global_position.x, global_position.y])
		pickup.global_position = Vector2(float(pos[0]), float(pos[1]))


func _drop_fish(records: Array[Dictionary]) -> void:
	if ProgressionManager.debug_session:
		return
	for record in records:
		var pickup: Area2D = FISH_PICKUP_SCENE.instantiate()
		if pickup.has_method("setup_saved_drop"):
			pickup.setup_saved_drop(str(record.get("id", "")), int(record.get("amount", 1)))
		get_parent().add_child(pickup)
		var pos: Array = record.get("position", [global_position.x, global_position.y])
		pickup.global_position = Vector2(float(pos[0]), float(pos[1]))


func _show_in_battle_ui() -> void:
	for ui in get_tree().get_nodes_in_group("battle_ui"):
		if ui.has_method("show_enemy"):
			ui.show_enemy(self, display_name, current_health, max_health)


# --- helpers for subclasses ---------------------------------------------------------------------
func clear_line_to(point: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var side := global_position.direction_to(point).orthogonal() * 8.0
	for offset in [side, -side]:
		var query := PhysicsRayQueryParameters2D.create(global_position + offset, point + offset, 1)
		if is_instance_valid(target) and target is CollisionObject2D:
			query.exclude = [target.get_rid()]
		if not space.intersect_ray(query).is_empty():
			return false
	return true


## Next point to walk to when going around trees to `goal` (grid path); the goal itself when the
## way is clear. Vector2.INF = no short way round.
func path_aim_point(goal: Vector2, delta: float) -> Vector2:
	if clear_line_to(goal):
		chase_path = PackedVector2Array()
		return goal
	path_replan_left -= delta
	if chase_path.is_empty() or path_replan_left <= 0.0:
		path_replan_left = 0.4
		var grid: AStarGrid2D = NavGrid.for_scene(get_tree().current_scene)
		if grid == null:
			return goal
		var from := NavGrid.cell_of(grid, global_position)
		var to := NavGrid.cell_of(grid, goal)
		if not grid.is_in_boundsv(from) or not grid.is_in_boundsv(to) or grid.is_point_solid(to):
			return goal
		chase_path = grid.get_point_path(from, to, true)
		chase_path_index = 1
		var length := 0.0
		for i in range(1, chase_path.size()):
			length += chase_path[i].distance_to(chase_path[i - 1])
		if chase_path.size() < 2 or length > disengage_range * 1.6:
			chase_path = PackedVector2Array()
			return Vector2.INF
	while chase_path_index < chase_path.size() - 1 and global_position.distance_to(chase_path[chase_path_index]) < 10.0:
		chase_path_index += 1
	return chase_path[mini(chase_path_index, chase_path.size() - 1)]

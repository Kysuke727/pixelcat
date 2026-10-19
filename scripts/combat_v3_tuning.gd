extends Resource
class_name CombatV3Tuning

@export_category("玩家基础战斗")
@export var player_base_health: int = 5
@export var first_claw_damage: float = 1.0
@export var second_claw_damage: float = 2.0
@export var combo_window: float = 0.35
@export var melee_recovery: float = 0.45
@export_range(0.0, 1.0) var second_claw_stun_chance: float = 0.5
@export var stun_duration: float = 1.0
@export var control_immunity_duration: float = 1.0
@export var player_hitstun_duration: float = 0.3
@export var player_invulnerability_duration: float = 1.0
@export var player_knockback_force: float = 60.0

@export_category("毛线技能")
@export var yarn_cooldown: float = 4.0
@export_range(180.0, 360.0) var yarn_required_wrap_angle_degrees: float = 270.0
@export var yarn_minimum_wrap_radius: float = 22.0
@export var yarn_minimum_pivot_contact_radius: float = 18.0
@export var yarn_minimum_player_step: float = 6.0
@export var yarn_maximum_sample_angle_degrees: float = 100.0
@export var yarn_required_tension_extension: float = 24.0
@export var yarn_required_pull_distance: float = 20.0

@export_category("闪避")
@export var dodge_distance: float = 55.0
@export var dodge_invulnerability_duration: float = 0.15
@export var dodge_cooldown: float = 15.0

@export_category("护盾与完美格挡")
@export var shield_max_durability: float = 100.0
@export var slime_lunge_shield_cost: float = 25.0
@export var shield_movement_multiplier: float = 0.0
@export var shield_regen_delay: float = 3.0
@export var shield_regen_per_second: float = 15.0
@export var perfect_guard_window: float = 0.5
@export var perfect_guard_pause_duration: float = 1.0
@export var guard_break_stun_duration: float = 1.5
@export_range(0.0, 1.0) var guard_break_restore_ratio: float = 0.3

@export_category("普通史莱姆")
@export var slime_base_health: int = 5
@export var slime_attack_damage: int = 1
@export var slime_windup_duration: float = 0.4
@export var slime_recover_duration: float = 0.5
@export var slime_collision_stun_duration: float = 1.0
@export var slime_collision_stun_cooldown: float = 0.8

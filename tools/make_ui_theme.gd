extends SceneTree

## Generates res://resources/ui/pixelcat_theme.tres - the shared "cute + pixel"
## look for the inventory, crafting and other menus.
##
##   godot --headless --path . --script res://tools/make_ui_theme.gd
##
## Pixel feel without art assets: hard 2 px outlines, no anti-aliasing, tiny
## chamfered corners (radius 3, detail 1) and a thick bottom edge that makes
## buttons look like chunky keys. To restyle everything, edit the palette below
## and re-run - or replace the StyleBoxes with hand-drawn StyleBoxTexture
## nine-patches later.

const OUT_PATH := "res://resources/ui/pixelcat_theme.tres"
const FONT_TITLE := "res://assets/fonts/SmileySans-Oblique.otf"

# Palette
const INK := Color("#5c3a4b")            # body text
const INK_SOFT := Color("#8f6b7b")       # secondary text
const INK_DISABLED := Color("#b5a2aa")
const OUTLINE := Color("#8a566b")        # dark pixel outline
const PANEL_BG := Color("#fff4ee")
const PANEL_EDGE := Color("#efb7c9")
const INSET_BG := Color("#fbe3ea")       # slot / list backgrounds
const INSET_EDGE := Color("#e9bccb")
const BTN := Color("#f7b9cd")
const BTN_EDGE := Color("#d4809f")
const BTN_HOVER := Color("#ffcbdb")
const BTN_PRESSED := Color("#ec9db9")
const BTN_DISABLED := Color("#ece2e6")
const BTN_DISABLED_EDGE := Color("#cdbfc5")
const GOLD := Color("#f2b84b")
const GOOD := Color("#2f8a5a")
const BAD := Color("#c8434f")


func _initialize() -> void:
	var theme := Theme.new()
	theme.default_font_size = 15

	# Panels ---------------------------------------------------------------
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, OUTLINE, 3, 0, 4, 0, 6, 6))
	theme.set_stylebox("panel", "Panel", _box(PANEL_BG, OUTLINE, 3, 0, 4, 0, 6, 6))

	theme.add_type("InsetPanel")
	theme.set_type_variation("InsetPanel", "PanelContainer")
	theme.set_stylebox("panel", "InsetPanel", _box(INSET_BG, INSET_EDGE, 2, 0, 3, 0, 6, 6))

	theme.add_type("SlotPanel")
	theme.set_type_variation("SlotPanel", "PanelContainer")
	theme.set_stylebox("panel", "SlotPanel", _box(Color("#fff0f4"), INSET_EDGE, 2, 2, 3, 0, 2, 2))

	theme.add_type("SlotPanelSelected")
	theme.set_type_variation("SlotPanelSelected", "PanelContainer")
	theme.set_stylebox("panel", "SlotPanelSelected", _box(Color("#fff3c9"), GOLD, 3, 2, 3, 0, 1, 1))

	# Workbench crafting uses a warm wood tone so it is obviously a different mode.
	theme.add_type("WorkbenchPanel")
	theme.set_type_variation("WorkbenchPanel", "PanelContainer")
	theme.set_stylebox("panel", "WorkbenchPanel", _box(Color("#fff1dc"), Color("#8a5a3b"), 3, 0, 4, 0, 6, 6))
	theme.add_type("BadgePortable")
	theme.set_type_variation("BadgePortable", "PanelContainer")
	theme.set_stylebox("panel", "BadgePortable", _box(BTN, BTN_EDGE, 2, 0, 3, 0, 4, 0))
	theme.add_type("BadgeWorkbench")
	theme.set_type_variation("BadgeWorkbench", "PanelContainer")
	theme.set_stylebox("panel", "BadgeWorkbench", _box(Color("#e8c08a"), Color("#8a5a3b"), 2, 0, 3, 0, 4, 0))

	# Buttons --------------------------------------------------------------
	theme.set_stylebox("normal", "Button", _box(BTN, BTN_EDGE, 2, 4, 3))
	theme.set_stylebox("hover", "Button", _box(BTN_HOVER, BTN_EDGE, 2, 4, 3))
	theme.set_stylebox("pressed", "Button", _box(BTN_PRESSED, BTN_EDGE, 2, 1, 3, 3))
	theme.set_stylebox("hover_pressed", "Button", _box(BTN_PRESSED, BTN_EDGE, 2, 1, 3, 3))
	theme.set_stylebox("disabled", "Button", _box(BTN_DISABLED, BTN_DISABLED_EDGE, 2, 4, 3))
	var focus := _box(Color(0, 0, 0, 0), GOLD, 2, 0, 3)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_hover_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", INK_DISABLED)
	theme.set_color("icon_normal_color", "Button", Color.WHITE)
	theme.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.5))
	theme.set_constant("h_separation", "Button", 8)

	# Recipe list entries: the selected (toggled) one gets the same gold edge as
	# a selected inventory slot.
	theme.add_type("RecipeButton")
	theme.set_type_variation("RecipeButton", "Button")
	theme.set_stylebox("pressed", "RecipeButton", _box(Color("#fff3c9"), GOLD, 3, 2, 3))
	theme.set_stylebox("hover_pressed", "RecipeButton", _box(Color("#fff3c9"), GOLD, 3, 2, 3))

	# Labels ---------------------------------------------------------------
	theme.set_color("font_color", "Label", INK)
	theme.add_type("TitleLabel")
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_color("font_color", "TitleLabel", Color("#a65d77"))
	theme.set_font_size("font_size", "TitleLabel", 26)
	if ResourceLoader.exists(FONT_TITLE):
		theme.set_font("font", "TitleLabel", load(FONT_TITLE))

	theme.add_type("HeadingLabel")
	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_color("font_color", "HeadingLabel", Color("#a65d77"))
	theme.set_font_size("font_size", "HeadingLabel", 19)
	if ResourceLoader.exists(FONT_TITLE):
		theme.set_font("font", "HeadingLabel", load(FONT_TITLE))

	theme.add_type("SoftLabel")
	theme.set_type_variation("SoftLabel", "Label")
	theme.set_color("font_color", "SoftLabel", INK_SOFT)
	theme.set_font_size("font_size", "SoftLabel", 13)

	theme.add_type("GoodLabel")
	theme.set_type_variation("GoodLabel", "Label")
	theme.set_color("font_color", "GoodLabel", GOOD)

	theme.add_type("BadLabel")
	theme.set_type_variation("BadLabel", "Label")
	theme.set_color("font_color", "BadLabel", BAD)

	# HUD ------------------------------------------------------------------
	# Translucent so the strip never hides the scene behind it.
	theme.add_type("HudPanel")
	theme.set_type_variation("HudPanel", "PanelContainer")
	theme.set_stylebox("panel", "HudPanel", _box(Color(1.0, 0.957, 0.933, 0.86), OUTLINE, 2, 0, 3, 0, 5, 2))

	theme.set_stylebox("background", "ProgressBar", _box(Color("#ead7df"), OUTLINE, 2, 0, 1, 0, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(BTN, OUTLINE, 2, 0, 1, 0, 0, 0))
	theme.set_color("font_color", "ProgressBar", INK)
	for pair in [["HungerBar", Color("#f2a65a")], ["MoodBar", Color("#f07aa0")], ["EnergyBar", Color("#6fc3e8")], ["LowBar", BAD]]:
		theme.add_type(pair[0])
		theme.set_type_variation(pair[0], "ProgressBar")
		theme.set_stylebox("fill", pair[0], _box(pair[1], OUTLINE, 2, 0, 1, 0, 0, 0))

	# Misc -----------------------------------------------------------------
	var line := StyleBoxLine.new()
	line.color = INSET_EDGE
	line.thickness = 2
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 8)

	theme.set_stylebox("panel", "PopupMenu", _box(PANEL_BG, OUTLINE, 2, 0, 3))
	theme.set_stylebox("hover", "PopupMenu", _box(BTN_HOVER, Color(0, 0, 0, 0), 0, 0, 2))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", INK)

	theme.set_stylebox("panel", "TooltipPanel", _box(Color("#5c3a4b"), OUTLINE, 2, 0, 3))
	theme.set_color("font_color", "TooltipLabel", Color("#fff4ee"))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/ui"))
	var err := ResourceSaver.save(theme, OUT_PATH)
	if err != OK:
		push_error("Could not save theme: %d" % err)
		quit(1)
		return
	print("UI_THEME_WRITTEN ", OUT_PATH)
	quit(0)


## A pixel-style box: hard outline, no anti-aliasing, chamfered corners.
## `bottom` is the extra thickness of the lower edge (chunky "key" look).
func _box(fill: Color, edge: Color, width: int, bottom: int, radius: int, top_extra: int = 0, pad_x: int = 8, pad_y: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.border_width_bottom = width + bottom
	box.border_width_top = width + top_extra
	box.set_corner_radius_all(radius)
	box.corner_detail = 1
	box.anti_aliasing = false
	box.content_margin_left = pad_x + width
	box.content_margin_right = pad_x + width
	box.content_margin_top = pad_y + width + top_extra
	box.content_margin_bottom = pad_y + width + bottom
	return box

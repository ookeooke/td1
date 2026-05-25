extends CanvasLayer

# Tactical-pause Help / Controls reference. Pure static text — opens via
# EventBus.help_overlay_requested (emitted by the Help button on the
# pause card). Auto-closes on resume. Doesn't navigate.

@onready var root: Control = %Root
@onready var dim: ColorRect = %Dim
@onready var body: RichTextLabel = %Body
@onready var close_button: Button = %CloseButton

const HELP_BBCODE: String = "[b]Hero[/b]\nTap the portrait to select your hero. While selected, tap empty ground to walk there. Tap an enemy you can reach to attack it.\n\n[b]Build towers[/b]\nTap an empty spot to open the build ring. Tap a tower to preview cost and stats. Tap the same tower again to commit.\n\n[b]Manage towers[/b]\nTap a built tower for the action ring: upgrade, sell, change target priority, place rally flag (barracks only).\n\n[b]Skills[/b]\nTap a skill slot to arm it. Single-target skills cast on the next valid tap; area skills need a second tap to aim.\n\n[b]Waves[/b]\nThe Send Wave badge appears in the last seconds of each wave's spawn. Press it for bonus gold — the next wave starts immediately, overlapping the current one.\n\n[b]Tactical pause[/b]\nPause anytime. Tap the dim background to hide the menu while staying paused — you can inspect towers, heroes and enemies, build, upgrade, and cast. Tap the [b]≡[/b] badge to reopen the menu, or the pause button to resume.\n\n[b]Speed[/b]\nCycle 1× / 2× / 3× via the speed button. Pause preserves your fast-forward."


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	body.text = HELP_BBCODE
	close_button.pressed.connect(_hide)
	dim.gui_input.connect(_on_dim_input)
	EventBus.help_overlay_requested.connect(_on_requested)
	EventBus.pause_state_changed.connect(_on_pause_state_changed)


func _on_requested() -> void:
	root.visible = true


func _on_pause_state_changed(paused: bool) -> void:
	if not paused:
		_hide()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_hide()


func _hide() -> void:
	root.visible = false

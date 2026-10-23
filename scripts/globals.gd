extends Node

signal changed
signal player_dead
signal beast_dead
signal new_phase

var player: Node3D
var boss: Node3D
var camera: Node3D
var arena: Node3D
var fx: Node3D
var audio: Node
var ui: CanvasLayer
var main: Node3D
var playing := false
var mobile := OS.has_feature("web") or OS.has_feature("mobile_web") or "--mobile" in OS.get_cmdline_user_args()
var training := false
var freeze := 0.0
var attempt := 1
var elapsed := 0.0
var settings := {"sensitivity": 1.0, "volume": 0.75, "music": 0.5, "shake": true, "load": 1, "fullscreen": false, "quality": 1}
var stats := {"rolls":0, "evades":0, "hits":0, "damage":0.0, "taken":0.0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_inputs()
	var adapter:=RenderingServer.get_video_adapter_name().to_lower()
	if adapter.contains("llvmpipe") or adapter.contains("lavapipe"):settings.quality=0
	if "--low" in OS.get_cmdline_user_args():settings.quality=0
	var cfg := ConfigFile.new()
	if cfg.load(_settings_path()) == OK:
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])
	if "--beauty" in OS.get_cmdline_user_args():settings.quality=1
	# Mobile uses the same materials. Only resolution, shadows and light count
	# vary by quality; a phone must not silently select the old flat renderer.
	if mobile:settings.quality=1

func save() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(_settings_path())
	changed.emit()

func _process(dt: float) -> void:
	freeze = maxf(0, freeze-dt)
	if playing and not get_tree().paused:
		elapsed += dt

func impact(t := 0.045) -> void:
	freeze = maxf(freeze, t)

func reset_stats() -> void:
	elapsed = 0
	stats = {"rolls":0, "evades":0, "hits":0, "damage":0.0, "taken":0.0}

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mouse(code: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = code
	return e

func _pad(code: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = code
	return e

func _axis(code: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = code
	e.axis_value = value
	return e

func _bind(action: String, events: Array, deadzone := 0.2) -> void:
	if InputMap.has_action(action): InputMap.erase_action(action)
	InputMap.add_action(action, deadzone)
	for e in events: InputMap.action_add_event(action, e)

func _inputs() -> void:
	_bind("forward", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y,-1)])
	_bind("back", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y,1)])
	_bind("left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X,-1)])
	_bind("right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X,1)])
	_bind("dodge", [_key(KEY_SPACE), _pad(JOY_BUTTON_B)])
	_bind("sprint", [_key(KEY_SHIFT)])
	_bind("jump", [_key(KEY_F), _pad(JOY_BUTTON_A)])
	_bind("light", [_mouse(MOUSE_BUTTON_LEFT), _pad(JOY_BUTTON_RIGHT_SHOULDER)])
	_bind("heavy", [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_RIGHT,1)],0.35)
	_bind("guard", [_key(KEY_CTRL), _pad(JOY_BUTTON_LEFT_SHOULDER)])
	_bind("parry", [_key(KEY_C), _axis(JOY_AXIS_TRIGGER_LEFT,1)],0.35)
	_bind("heal", [_key(KEY_R), _pad(JOY_BUTTON_X)])
	_bind("lock", [_key(KEY_Q), _mouse(MOUSE_BUTTON_MIDDLE), _pad(JOY_BUTTON_RIGHT_STICK)])
	_bind("interact", [_key(KEY_E), _pad(JOY_BUTTON_Y)])
	_bind("pause", [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)])
	_bind("help", [_key(KEY_F1), _pad(JOY_BUTTON_BACK)])
	_bind("fullscreen", [_key(KEY_F11)])
	_bind("cam_left", [_axis(JOY_AXIS_RIGHT_X,-1)])
	_bind("cam_right", [_axis(JOY_AXIS_RIGHT_X,1)])
	_bind("cam_up", [_axis(JOY_AXIS_RIGHT_Y,-1)])
	_bind("cam_down", [_axis(JOY_AXIS_RIGHT_Y,1)])

func flat(v: Vector3) -> Vector3:
	return Vector3(v.x,0,v.z)

func _settings_path() -> String:
	if OS.has_feature("web"):return "user://settings.cfg"
	var base:=ProjectSettings.globalize_path("res://")
	if OS.has_feature("template"):base=OS.get_executable_path().get_base_dir()
	var dir:=base.path_join(".runtime")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join("settings.cfg")

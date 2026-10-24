extends "res://tools/encounter_reel.gd"
## Own rig rehearsal, with real root travel. No third-party reference footage.
func _ready() -> void:
	G.mobile=true;G.settings.quality=1;_world()
	for kind in ["knight","boss"]:
		var actor:=FighterRig.new();actor.position.y=.05
		if kind=="boss":actor.scale=Vector3.ONE*1.20
		add_child(actor);actor.setup(kind);actor.visible=false;rigs[kind]=actor
	clips=[{"kind":"knight","id":"light_series","length":3.35},
		{"kind":"knight","id":"heavy_series","length":2.55},
		{"kind":"knight","id":"gait_run","length":1.90,"speed":4.0},
		{"kind":"boss","id":"gait_approach","length":1.90,"speed":3.3},
		{"kind":"boss","id":"gait_charge","length":1.90,"speed":5.2},
		{"kind":"boss","id":"bound_left","length":.80},
		{"kind":"boss","id":"bound_right","length":.80},
		{"kind":"boss","id":"bound_forward","length":.85},
		{"kind":"boss","id":"combo","length":2.85}]
	for i in clips.size():clips[i].output_index=i;clips[i].view="reference"
	manifest_path="res://artifacts/reference_reel_manifest.json"
	for group in ["knight","boss"]:
		if "--"+group+"-only" in OS.get_cmdline_user_args():
			clips=clips.filter(func(item:Dictionary) -> bool:return item.kind==group)
			manifest_path="res://artifacts/reference_reel_"+group+".json"
	if "--resume" in OS.get_cmdline_user_args() and FileAccess.file_exists(manifest_path):
		manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		clips=clips.filter(func(item:Dictionary) -> bool:
			for previous:Dictionary in manifest.clips:
				if previous.kind==item.kind and previous.id==item.id:return false
			return true)
	if clips.is_empty():get_tree().quit();return
	if "--one" in OS.get_cmdline_user_args():clips=clips.slice(0,1)
	_begin_clip()

func _tick() -> void:
	if not String(clip.id).begins_with("gait_") and not String(clip.id).begins_with("bound_"):
		super._tick()
		if clip.kind=="knight":
			camera.position=rig.position+Vector3(-3.9,2.0,5.2);camera.fov=43
			camera.look_at(rig.position+Vector3(0,1.28,.55))
		return
	var time:=tick*DT-PRE_ROLL;tick+=1
	var action:="idle";var local_time:=maxf(0,time);var speed:=0.0
	if String(clip.id).begins_with("gait_"):
		speed=float(clip.speed)*smoothstep(0,.24,time)*(1-smoothstep(1.45,1.85,time))
		rig.position+=Vector3.BACK*speed*DT
		action="move" if speed>.01 else "idle"
		var offset:=Vector3(-3.1,1.55,2.1) if clip.kind=="knight" else Vector3(-5.7,2.5,4.6)
		camera.position=rig.position+offset;camera.fov=43;camera.look_at(rig.position+Vector3(0,1.1 if clip.kind=="knight" else 1.3,0))
	else:
		var duration:=.62 if clip.id=="bound_forward" else .58
		var delta:=Vector3(-1.90,0,.35) if clip.id=="bound_left" else Vector3(1.90,0,.35)
		if clip.id=="bound_forward":delta=Vector3(.50,0,2.45)
		var u:=clampf((time/duration-.14)/.70,0,1)
		var height:float=(.33 if clip.id=="bound_forward" else .27)*4*u*(1-u)
		rig.position=Vector3(0,.05,0)+delta*BeastMoves.smooth_motion(u)+Vector3.UP*height
		action=String(clip.id) if time>=0 and time<=duration else "idle"
		camera.position=Vector3(-5.7,2.7,7.5);camera.fov=44;camera.look_at(Vector3(0,1.3,.7))
	rig.pose(action,local_time,DT,speed,Vector3.BACK)
	label.text="%s / %s"%[String(clip.kind).to_upper(),String(clip.id).to_upper().replace("_"," ")]

extends "res://tools/motion_reel.gd"
## Following camera and actual world translation expose foot sliding and reach.
var baseline:=false
func _ready() -> void:
	G.mobile=true;G.settings.quality=1;_world()
	baseline="--baseline" in OS.get_cmdline_user_args()
	for kind in ["knight","boss"]:
		var actor:=FighterRig.new();actor.position.y=.05
		if kind=="boss":actor.scale=Vector3.ONE*1.20
		add_child(actor);actor.setup(kind);actor.visible=false;rigs[kind]=actor
	clips=[{"kind":"knight","id":"run","view":"side","speed":4.0,"direction":Vector3(0,0,1)}, {"kind":"boss","id":"approach","view":"three_quarter","speed":2.75,"direction":Vector3(0,0,1)}]
	if "--all" in OS.get_cmdline_user_args():
		clips.append({"kind":"knight","id":"strafe","view":"front","speed":3.52,"direction":Vector3(1,0,0)})
		clips.append({"kind":"boss","id":"orbit","view":"front","speed":.95,"direction":Vector3(1,0,0)})
		clips.append({"kind":"knight","id":"sprint","view":"three_quarter","speed":6.0,"direction":Vector3(0,0,1)})
		clips.append({"kind":"boss","id":"retreat","view":"side","speed":1.5,"direction":Vector3(0,0,-1)})
	for i in clips.size():clips[i]["output_index"]=i
	manifest_path="res://artifacts/locomotion_reel_%s.json"%("baseline" if baseline else "after")
	if "--boss-only" in OS.get_cmdline_user_args():
		clips=clips.filter(func(item:Dictionary) -> bool:return item.kind=="boss")
		manifest_path="res://artifacts/locomotion_reel_boss_final.json"
	_begin_clip()
func _begin_clip() -> void:
	clip=clips[clip_index];rig=rigs[clip.kind]
	for kind in rigs:rigs[kind].visible=kind==clip.kind
	rig.position=Vector3(0,.05,0);rig.rotation=Vector3.ZERO;rig.initialized=false;rig.gait=0
	for i in 12:rig.pose("idle",0,DT,0,Vector3.ZERO)
	tick=0;clip_frame=0;frame_count=75
	clip_dir="res://artifacts/locomotion_reel_%s/%02d_%s_%s"%["baseline" if baseline else "after",clip.output_index,clip.kind,clip.id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(clip_dir))
	print("LOCOMOTION REEL BEGIN ",clip.kind," ",clip.id)
func _tick() -> void:
	var t:=tick*DT;tick+=1
	var speed:float=clip.speed*smoothstep(0,.24,t)*(1-smoothstep(1.95,2.4,t))
	rig.position+=Vector3(clip.direction)*speed*DT
	rig.pose("move" if speed>.01 else "idle",t,DT,speed,clip.direction)
	var offset:=Vector3(-3.1,1.35,.5) if clip.view=="side" else Vector3(-2.7,1.5,3.8)
	if clip.view=="front":offset=Vector3(-.4,1.45,4.4)
	var aim:=Vector3(0,1.0,0)
	if clip.kind=="boss":offset*=1.65;aim.y=1.25
	camera.position=rig.position+offset;camera.fov=42;camera.look_at(rig.position+aim)
	label.text="%s / %s / %.2fm/s"%[String(clip.kind).to_upper(),String(clip.id).to_upper(),speed]

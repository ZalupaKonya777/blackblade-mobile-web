extends "res://tools/motion_reel.gd"
## Silent study of the shipped rig curves, not a prerecorded simulation of AI.
func _ready() -> void:
	G.mobile=true;G.settings.quality=1;_world()
	for kind in ["knight","boss"]:
		var actor:=FighterRig.new();actor.position.y=.05
		if kind=="boss":actor.scale=Vector3.ONE*1.20
		add_child(actor);actor.setup(kind);actor.visible=false;rigs[kind]=actor
	clips=[{"kind":"knight","id":"light_series","length":3.35},
		{"kind":"knight","id":"heavy_series","length":2.55},
		{"kind":"knight","id":"running_attack","length":1.01},
		{"kind":"boss","id":"backhand","length":1.13},
		{"kind":"boss","id":"paw_strike","length":1.26},
		{"kind":"boss","id":"evade_cut","length":1.37},
		{"kind":"knight","id":"locked_left","length":1.05},
		{"kind":"knight","id":"locked_right","length":1.05}]
	for i in clips.size():clips[i].output_index=i;clips[i].view="encounter"
	manifest_path="res://artifacts/encounter_reel_manifest.json"
	_begin_clip()

func _begin_clip() -> void:
	clip=clips[clip_index];rig=rigs[clip.kind]
	for kind in rigs:rigs[kind].visible=kind==clip.kind
	rig.position=Vector3(0,.05,0);rig.rotation=Vector3.ZERO;rig.initialized=false
	tick=0;clip_frame=0;frame_count=int(ceil((PRE_ROLL+float(clip.length)+TAIL)*FPS))
	clip_dir="res://artifacts/encounter_reel/%02d_%s"%[clip.output_index,clip.id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(clip_dir))
	if clip.kind=="boss":
		camera.position=Vector3(-5.7,2.7,7.5);camera.fov=44;camera.look_at(Vector3(0,1.3,.4))
	else:
		camera.position=Vector3(-3.6,1.8,4.8);camera.fov=43;camera.look_at(Vector3(0,1.1,.9))
	if String(clip.id).begins_with("locked_"):
		rig.rotation.y=PI;rig.roll_locked=true
		rig.roll_direction=Vector3.RIGHT if clip.id=="locked_left" else Vector3.LEFT
		rigs.boss.visible=true;rigs.boss.position=Vector3(0,.05,-4.8);rigs.boss.rotation=Vector3.ZERO;rigs.boss.initialized=false
	print("ENCOUNTER REEL BEGIN ",clip.id," ",frame_count," frames")

func _tick() -> void:
	var time:=tick*DT-PRE_ROLL;tick+=1
	var action:String=clip.id;var local_time:=maxf(0,time);var variant:=0;var travel:=0.0
	if action.begins_with("locked_"):
		var direction:=Vector3.LEFT if action=="locked_left" else Vector3.RIGHT
		rig.position=Vector3(0,.05,0)+direction*3.25*RollMotion.travel(clampf(local_time/.70,0,1))
		action="roll" if time>=0 and time<=.70 else "idle";local_time=minf(local_time,.70)
		rigs.boss.pose("idle",0,DT,0,Vector3.ZERO)
		camera.position=rig.position+Vector3(0,1.85,4.9);camera.fov=59;camera.look_at(rig.position+Vector3(0,1.05,-1.2))
	elif clip.kind=="boss":
		var m:Dictionary=BeastMoves.ATTACKS[action];var end:=BeastMoves.finish(action)
		if m.has("retreat"):
			var d:Array=m.retreat;var u:=BeastMoves.smooth_motion((local_time-d[0])/(d[1]-d[0]))
			rig.position=Vector3(-float(d[3])*u,.05,-float(d[2])*u)
		else:
			travel=float(m.get("step",0))*BeastMoves.smooth_motion((local_time-.25)/.65);rig.position=Vector3(0,.05,travel)
		if time>end:action="recover_"+action;local_time=time-end
	else:
		var sequence:Array=[]
		if action=="light_series":sequence=["light1","light2","light3","light4"]
		elif action=="heavy_series":sequence=["heavy","heavy2"]
		else:sequence=[action]
		for i in sequence.size():
			var id:String=sequence[i];var m:Dictionary=KnightMoves.MOVES[id]
			var span:float=m.chain if i<sequence.size()-1 else m.length
			if local_time>span and i<sequence.size()-1:local_time-=span;travel+=float(m.travel);continue
			action=id
			var d:Array=m.drive;travel+=float(m.travel)*BeastMoves.smooth_motion((local_time-d[0])/(d[1]-d[0]))
			if local_time>float(m.length):action="idle";local_time=0
			break
		rig.position=Vector3(0,.05,travel)
		if action.begins_with("light"):variant=int(action.trim_prefix("light"))-1;action="light"
		elif action=="heavy2":action="heavy";variant=1
	if time<0:action="idle";local_time=0
	rig.pose(action,local_time,DT,0,Vector3.ZERO,variant)
	label.text="%s / %s"%[String(clip.kind).to_upper(),String(clip.id).to_upper().replace("_"," ")]

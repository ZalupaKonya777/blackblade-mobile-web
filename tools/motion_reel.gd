extends Node3D
## Deterministic 30 fps review of the real rigs, advancing the simulation at60Hz.
## No arena/AI/hit effects. Root translation follows the shipped move timelines.
const FPS:=30
const DT:=1.0/60.0
const PRE_ROLL:=.20
const TAIL:=.28
const DEFAULT_CLIPS=[
 {"kind":"knight","id":"light1","view":"three_quarter"},
 {"kind":"knight","id":"light2","view":"side"},
 {"kind":"knight","id":"heavy","view":"three_quarter"},
 {"kind":"boss","id":"sweep","view":"three_quarter"},
 {"kind":"boss","id":"overhead","view":"side"}]
var rigs:={}
var clips:Array=[]
var clip_index:=0
var tick:=0
var clip_frame:=0
var busy:=false
var camera:Camera3D
var manifest:={"fps":FPS,"simulation_hz":60,"resolution":[640,480],"silent_pose_rehearsal":true,"clips":[]}
var clip:Dictionary={}
var rig:FighterRig
var data:Dictionary={}
var clip_dir:=""
var frame_count:=0
var label:Label
var manifest_path:="res://artifacts/motion_reel_manifest.json"
func _ready() -> void:
	if "--parse-only" in OS.get_cmdline_user_args():set_process(false);get_tree().quit();return
	G.mobile=true;G.settings.quality=1
	_world()
	for kind in ["knight","boss"]:
		var actor:=FighterRig.new();actor.position.y=.05
		if kind=="boss":actor.scale=Vector3.ONE*1.20
		add_child(actor);actor.setup(kind);actor.visible=false;rigs[kind]=actor
	clips=DEFAULT_CLIPS.duplicate(true)
	if "--all" in OS.get_cmdline_user_args():
		clips.clear()
		for kind in ["knight","boss"]:
			var catalog:Dictionary=KnightMoves.MOVES if kind=="knight" else BeastMoves.ATTACKS
			for id in catalog:clips.append({"kind":kind,"id":id,"view":"three_quarter"})
	if "--leap" in OS.get_cmdline_user_args():clips.append({"kind":"boss","id":"leap","view":"three_quarter"})
	for i in clips.size():clips[i]["output_index"]=i
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--clip="):
			var selected:=arg.trim_prefix("--clip=")
			clips=clips.filter(func(item:Dictionary) -> bool:return "%s:%s"%[item.kind,item.id]==selected)
			manifest_path="res://artifacts/motion_reel_single_manifest.json"
	if clips.is_empty():push_error("No matching review clip");get_tree().quit(1);return
	_begin_clip()
func _world() -> void:
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.075,.09,.115)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.72,.78,.86);env.ambient_light_energy=.68
	var world:=WorldEnvironment.new();world.environment=env;add_child(world)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-48,-34,0);key.light_color=Color(1,.91,.79);key.light_energy=1.25
	key.shadow_enabled=true;key.shadow_bias=.08;key.shadow_normal_bias=.8;key.directional_shadow_max_distance=15;add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-28,140,0);fill.light_color=Color(.48,.65,1);fill.light_energy=.42;add_child(fill)
	RenderingServer.directional_shadow_atlas_set_size(1024,true)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(24,24);floor.mesh=plane;floor.position.y=.03
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.18,.20,.23);mat.roughness=.92;floor.material_override=mat
	floor.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(floor)
	var grid:=ImmediateMesh.new();var grid_mat:=StandardMaterial3D.new();grid_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;grid_mat.albedo_color=Color(.25,.28,.32)
	grid.surface_begin(Mesh.PRIMITIVE_LINES,grid_mat)
	for i in range(-16,17):
		var f:=i*.5
		grid.surface_add_vertex(Vector3(f,.031,-8));grid.surface_add_vertex(Vector3(f,.031,8))
		grid.surface_add_vertex(Vector3(-8,.031,f));grid.surface_add_vertex(Vector3(8,.031,f))
	grid.surface_end();var lines:=MeshInstance3D.new();lines.mesh=grid;lines.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(lines)
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.near=.05
	var layer:=CanvasLayer.new();add_child(layer);label=Label.new();label.position=Vector2(32,24);label.add_theme_font_size_override("font_size",32);label.add_theme_color_override("font_color",Color(.94,.94,.93));layer.add_child(label)
	get_viewport().msaa_3d=Viewport.MSAA_2X
func _begin_clip() -> void:
	clip=clips[clip_index];rig=rigs[clip.kind];data=KnightMoves.MOVES[clip.id] if clip.kind=="knight" else BeastMoves.ATTACKS[clip.id]
	for kind in rigs:rigs[kind].visible=kind==clip.kind
	rig.position=Vector3(0,.05,0);rig.rotation=Vector3.ZERO;rig.initialized=false
	tick=0;clip_frame=0
	frame_count=int(ceil((PRE_ROLL+float(data.length)+float(data.get("recover",.12))+TAIL)*FPS))
	clip_dir="res://artifacts/motion_reel/%02d_%s_%s_%s"%[clip.output_index,clip.kind,clip.id,clip.view]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(clip_dir))
	if clip.kind=="knight":
		camera.position=Vector3(-3.3,1.55,0.9) if clip.view=="side" else Vector3(-2.8,1.65,3.6)
		camera.fov=40;camera.look_at(Vector3(0,1.04,.25+float(data.travel)*.5))
		if clip.id=="heavy":
			camera.position*=1.18;camera.look_at(Vector3(0,1.24,.25+float(data.travel)*.5))
	else:
		var overhead:bool=clip.id in ["overhead","death_storm","leap","air_blades"]
		camera.position=Vector3(-6.8,2.9,1.1) if clip.view=="side" else Vector3(-4.2,2.8,5.8)
		if overhead:camera.position*=1.16
		# The sweep extends the entire blade to the camera's right at release.
		# Leave enough room to assess its full arc and the rear-leg pivot.
		if clip.id=="sweep":camera.position*=1.30
		camera.fov=44;camera.look_at(Vector3(0,2.30 if overhead else 1.12,.5))
	print("MOTION REEL BEGIN ",clip.kind," ",clip.id," ",frame_count," frames")
func _tick() -> void:
	var time:=tick*DT-PRE_ROLL;tick+=1
	var attack_t:=clampf(time,0,float(data.length))
	var travel:=0.0;var height:=.05
	if clip.kind=="knight":
		var drive:Array=data.drive;travel=float(data.travel)*BeastMoves.drive_progress((attack_t-float(drive[0]))/(float(drive[1])-float(drive[0])))
	else:
		if data.has("step"):travel=float(data.step)*BeastMoves.smooth_motion((attack_t-.25)/.65)
		elif data.has("drive"):
			var drive:Array=data.drive;travel=3.0*BeastMoves.drive_progress((attack_t-float(drive[0]))/(float(drive[1])-float(drive[0])))
		elif data.has("flight"):
			var flight:Array=data.flight;var u:=clampf((attack_t-float(flight[0]))/(float(flight[1])-float(flight[0])),0,1)
			travel=(2.0 if clip.id=="leap" else -1.65)*BeastMoves.smooth_motion(u);height+=4.0*float(flight[2])*u*(1-u)
	rig.position=Vector3(0,height,travel)
	var action:String=clip.id;var pose_time:=attack_t;var variant:=0
	if action.begins_with("light"):variant=int(action.trim_prefix("light"))-1;action="light"
	if time<0:action="idle";pose_time=0
	elif time>float(data.length):
		action="recover_"+String(clip.id) if clip.kind=="boss" else "idle"
		pose_time=time-float(data.length)
	rig.pose(action,pose_time,DT,0,Vector3.ZERO,variant)
	label.text="%s  /  %s  /  %.2f s"%[String(clip.kind).to_upper(),String(clip.id).to_upper(),maxf(0,time)]
func _process(_dt:float) -> void:
	if busy:return
	busy=true
	for i in 2:_tick()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var frame_path:="%s/frame_%05d.png"%[clip_dir,clip_frame]
		get_viewport().get_texture().get_image().save_png(frame_path)
	clip_frame+=1
	if clip_frame%15==0:print("REEL FRAME ",clip.kind," ",clip.id," ",clip_frame,"/",frame_count)
	if clip_frame>=frame_count:
		manifest.clips.append({"kind":clip.kind,"id":clip.id,"view":clip.view,"frames":frame_count,"directory":ProjectSettings.globalize_path(clip_dir),"fps":FPS})
		var file:=FileAccess.open(manifest_path,FileAccess.WRITE);file.store_string(JSON.stringify(manifest,"  "));file.close()
		clip_index+=1
		if clip_index>=clips.size():print("MOTION REEL COMPLETE");get_tree().quit();return
		_begin_clip()
	busy=false

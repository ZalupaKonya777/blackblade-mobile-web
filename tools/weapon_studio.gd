extends "res://tools/roll_studio.gd"
const WEAPON_SHOTS=[
 ["light1",.27],["light1",.42],["light2",.30],["light2",.48],
 ["light3",.39],["light3",.58],["heavy",.50],["heavy",.77],
 ["counter",.52],["roll_attack",.31],["jump_attack",.44]]
var shots:Array=[]

func _ready() -> void:
	super._ready()
	shots=WEAPON_SHOTS.duplicate()
	if "--heavy-only" in OS.get_cmdline_user_args():shots=[["heavy",.50],["heavy",.77]]
	cam.position=Vector3(3.2,1.65,4.0);cam.look_at(Vector3(0,1.12,.18));cam.fov=42
	print("WEAPON STUDIO READY")

func _process(_dt:float) -> void:
	frames+=1
	if frames<3:return
	if frames%3==0:
		if sample_id>=shots.size():
			var file:=FileAccess.open("res://artifacts/weapon_mesh_audit.json",FileAccess.WRITE);file.store_string(JSON.stringify(samples,"  "));file.close();get_tree().quit();return
		rig.position.y=1.0 if shots[sample_id][0]=="jump_attack" else 0.0
		rig.initialized=false
		for i in 8:rig.pose(shots[sample_id][0],shots[sample_id][1],1.0/60,0,Vector3.ZERO)
	if frames%3==2:
		var sample:Array=shots[sample_id]
		if DisplayServer.get_name()!="headless":get_viewport().get_texture().get_image().save_png("res://artifacts/weight_pose_%s_%02d.png"%[sample[0],int(sample[1]*100)])
		var result:Dictionary=audit_mesh();result.id=sample[0];result.t=sample[1];samples.append(result);print("WEAPON SKIN ",result);sample_id+=1

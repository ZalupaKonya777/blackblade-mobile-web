extends Node3D
## Samples the production rig with controller-identical root travel at 60 Hz.
var failures:=0
var checks:Array=[]
func check(label:String,ok:bool,details:Variant) -> void:
	checks.append({"check":label,"ok":ok,"details":details})
	if not ok:failures+=1
	print("KNIGHT CHOREOGRAPHY ","PASS " if ok else "FAIL ",label," ",details)
func _ready() -> void:run.call_deferred()
func run() -> void:
	G.mobile=true
	var rig:=FighterRig.new();add_child(rig);rig.position.y=.05;rig.setup("knight")
	var metrics:={}
	var cases:Array=[]
	for id:String in KnightMoves.MOVES:
		for amount in [1.0,0.0,.35]:cases.append({"id":id,"amount":amount})
	for spec:Dictionary in cases:
		var id:String=spec.id;var case_name:=id+("" if float(spec.amount)==1 else ("_blocked" if float(spec.amount)==0 else "_partial"))
		rig.position=Vector3(0,.05,0);rig.initialized=false
		for i in 12:rig.pose("idle",0,1.0/60,0,Vector3.ZERO)
		var m:Dictionary=KnightMoves.MOVES[id];var mx:=0.0;var err:=0.0;var ankle_jump:=0.0;var knee_side:=0.0;var reach:=0.0;var socket:=0.0;var finite:=true;var old:={}
		var action:=id;var variant:=0
		if id.begins_with("light"):action="light";variant=int(id.trim_prefix("light"))-1
		elif id=="heavy2":action="heavy";variant=1
		for frame in int(ceil(float(m.length)*60))+1:
			var time:=frame/60.0;var drive:Array=m.drive
			rig.position=Vector3(0,.05,float(spec.amount)*float(m.travel)*BeastMoves.smooth_motion((time-drive[0])/(drive[1]-drive[0])))
			rig.pose(action,time,1.0/60,0,Vector3.ZERO,variant)
			for side in ["l","r"]:
				var hip:Vector3=rig.globals["thigh_"+side].origin;var knee:Vector3=rig.globals["shin_"+side].origin;var ankle:Vector3=rig.globals["foot_"+side].origin
				finite=finite and hip.is_finite() and knee.is_finite() and ankle.is_finite()
				err=maxf(err,maxf(absf(hip.distance_to(knee)-rig.lengths["thigh_"+side]),absf(knee.distance_to(ankle)-rig.lengths["shin_"+side])))
				reach=maxf(reach,hip.distance_to(ankle)/(rig.lengths["thigh_"+side]+rig.lengths["shin_"+side]))
				knee_side=maxf(knee_side,absf(knee.x-hip.x))
				var world:Vector3=rig.to_global(ankle)
				if old.has(side):ankle_jump=maxf(ankle_jump,world.distance_to(old[side]))
				old[side]=world
				if rig.weapon_plants[side].has("error") and float(rig.weapon_plants[side].error)>mx:
					mx=float(rig.weapon_plants[side].error);metrics[case_name+"_max_target"]={"time":time,"side":side,"hip":str(hip),"ankle":str(ankle),"plant":str(rig.weapon_plants[side])}
			var palm:Vector3=rig.skel.to_global(rig.skel.get_bone_global_pose(rig.ids.hand_r)*rig.rest.hand_r.affine_inverse()*rig.right_socket)
			socket=maxf(socket,palm.distance_to(rig.weapon.to_global(rig.source_grip)))
		metrics[case_name]={"finite":finite,"limb_error":err,"target_error":mx,"ankle_step":ankle_jump,"knee_lateral":knee_side,"max_reach_ratio":reach,"palm_error":socket}
		check(case_name+" rigid limb lengths and palm socket",finite and err<.0001 and socket<.001,metrics[case_name])
		check(case_name+" reachable foot targets",mx<.025,metrics[case_name])
		check(case_name+" no foot teleport at 60 Hz",ankle_jump<.16,ankle_jump)
	# Real four-hit source-to-destination pose carrythrough, including first frame.
	rig.position=Vector3(0,.05,0);rig.initialized=false
	for i in 12:rig.pose("idle",0,1.0/60,0,Vector3.ZERO)
	var total:=0.0
	for combo in 4:
		var id:="light%d"%(combo+1);var m:Dictionary=KnightMoves.MOVES[id];var span:float=m.chain if combo<3 else m.length
		for frame in int(ceil(span*60)):
			var time:=frame/60.0;var drive:Array=m.drive
			rig.position=Vector3(0,.05,total+float(m.travel)*BeastMoves.smooth_motion((time-drive[0])/(drive[1]-drive[0])))
			var before:Dictionary=rig.globals.duplicate(true)
			rig.pose("light",time,1.0/60,0,Vector3.ZERO,combo)
			if frame==0 and combo>0:
				var head_step:float=rig.globals.head.origin.distance_to(before.head.origin);var hand_step:float=rig.globals.hand_r.origin.distance_to(before.hand_r.origin)
				check("chain %d continues outgoing whole-body pose"%(combo+1),head_step<.015 and hand_step<.025,{"head_step":head_step,"hand_step":hand_step,"carry":not rig.weapon_pose_from.is_empty()})
				check("chain %d bypasses ready guard"%(combo+1),not rig.weapon_pose_from.is_empty() and absf(float(rig.weapon_pose.chest_yaw)-float(rig.weapon_pose_from.chest_yaw))<.001,[rig.weapon_pose.chest_yaw,rig.weapon_pose_from.chest_yaw])
		total+=float(m.travel)
	var f:=FileAccess.open("res://artifacts/knight_choreography_v9.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"metrics":metrics,"failures":failures},"  "));f.close()
	print("KNIGHT CHOREOGRAPHY COMPLETE ",checks.size()," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)

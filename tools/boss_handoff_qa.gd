extends "res://tools/balance_lab.gd"
## Real controller-to-rig follow-up transitions, including non-melee probes.
var handoffs:Array=[]

func palm() -> Vector3:
	return b.rig.motion.to_global(b.rig.globals.hand_r*b.rig.rest.hand_r.affine_inverse()*b.rig.right_socket)

func head() -> Vector3:
	return b.rig.motion.to_global(b.rig.globals.head.origin)

func run() -> void:
	var pairs:Array=[]
	for outgoing in EclipseBeast.FOLLOWUPS:
		for incoming in EclipseBeast.FOLLOWUPS[outgoing]:pairs.append([outgoing,incoming])
	# These forced transitions exercise the no-melee-hit branch; they are not
	# additional AI follow-up choices and do not change the production move list.
	pairs.append(["sweep","air_blades"]);pairs.append(["sweep","death_storm"])
	if "--spin-only" in OS.get_cmdline_user_args():pairs=pairs.filter(func(pair:Array) -> bool:return pair[0]=="spin")
	for pair in pairs:
		var outgoing:String=pair[0];var incoming:String=pair[1]
		await reset(8);G.training=true;p.set_physics_process(false);b.phase=2
		b.start_move(outgoing)
		for frame in 240:
			await step(1)
			if b.state=="recover":break
		check(outgoing+" reaches its authored recovery",b.state=="recover",b.state)
		# Place the stationary target in the next move's range without moving
		# the boss, then use the production recovery/follow-up state machine.
		var gap:=6.0 if incoming in ["lunge","air_blades"] else 3.0
		p.global_position=b.global_position+Vector3(sin(b.yaw),0,cos(b.yaw))*gap;p.global_position.y=.05
		b.followup=incoming;b.ai_enabled=true
		var last_head:=head();var last_palm:=palm();var prior_pose:Dictionary=b.rig.beast_pose.duplicate()
		var head_entry:=INF;var palm_entry:=INF;var pose_entry:=INF
		var root_entry:=Vector3.ZERO
		for frame in 10:
			last_head=head();last_palm=palm();prior_pose=b.rig.beast_pose.duplicate()
			var previous_root:Vector3=b.global_position
			await step(1)
			if b.state=="attack" and b.attack==incoming:
				# Controller floor settling is physical travel, not an animation
				# discontinuity. Subtract it for the carry test, retain it below.
				root_entry=b.global_position-previous_root
				head_entry=(head()-root_entry).distance_to(last_head);palm_entry=(palm()-root_entry).distance_to(last_palm);pose_entry=0
				for key in ["blade_yaw","blade_pitch","twist","pelvis_yaw","chest_yaw"]:
					pose_entry=maxf(pose_entry,absf(float(b.rig.beast_pose[key])-float(prior_pose[key])))
				break
		var entry_ok:bool=b.state=="attack" and b.attack==incoming and b.t<.02 and b.rig.beast_chain_blend
		check(outgoing+" -> "+incoming+" carries the actual outgoing pose",entry_ok and head_entry<.01 and palm_entry<.01 and pose_entry<.001,[head_entry,palm_entry,pose_entry,b.state,b.attack])
		var finite:=true;var max_head:=0.0;var max_palm:=0.0;var length_error:=0.0;var grip_error:=0.0
		last_head=head();last_palm=palm()
		for frame in 36:
			await step(1)
			max_head=maxf(max_head,head().distance_to(last_head));max_palm=maxf(max_palm,palm().distance_to(last_palm))
			last_head=head();last_palm=palm()
			for bone in b.rig.globals:
				var xf:Transform3D=b.rig.globals[bone]
				finite=finite and xf.origin.is_finite() and is_finite(xf.basis.determinant())
			for side in ["l","r"]:
				for chain in [["thigh_","shin_","foot_"],["upper_","fore_","hand_"]]:
					for i in 2:
						var bone:String=chain[i]+side;var next:String=chain[i+1]+side
						length_error=maxf(length_error,absf(b.rig.globals[bone].origin.distance_to(b.rig.globals[next].origin)-float(b.rig.lengths[bone])))
			b.rig.skel.force_update_all_bone_transforms()
			var wrist:Vector3=b.rig.skel.global_transform*b.rig.skel.get_bone_global_pose(b.rig.ids.hand_r)*b.rig.rest.hand_r.affine_inverse()*b.rig.right_socket
			grip_error=maxf(grip_error,wrist.distance_to(b.rig.weapon.to_global(b.rig.source_grip)))
		var data:={"from":outgoing,"to":incoming,"entry_head_after_root_travel":head_entry,"entry_palm_after_root_travel":palm_entry,"entry_root_travel":[root_entry.x,root_entry.y,root_entry.z],"entry_pose":pose_entry,"max_head_step":max_head,"max_palm_step":max_palm,"length_error":length_error,"grip_error":grip_error}
		handoffs.append(data)
		check(outgoing+" -> "+incoming+" keeps continuous rigid limbs and an attached blade",finite and max_head<.30 and max_palm<.50 and length_error<.001 and grip_error<.005,data)
	var out:=FileAccess.open("res://artifacts/boss_handoff_verification.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"handoffs":handoffs},"  "));out.close()
	print("BOSS HANDOFF COMPLETE ",checks.size()," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)

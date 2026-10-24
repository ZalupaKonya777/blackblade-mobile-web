extends "res://tools/balance_lab.gd"
## Real physics checks for the beast's short, non-damaging reposition bounds.
func run() -> void:
	var arcs:Array=[]
	for id in ["bound_left","bound_right","bound_forward"]:
		await reset(8);p.set_physics_process(false)
		var delta:=Vector3(-1.90,0,.35) if id=="bound_left" else Vector3(1.90,0,.35)
		if id=="bound_forward":delta=Vector3(.5,0,2.45)
		var start:Vector3=b.global_position
		check(id+" starts on clear ground",b._start_reposition(delta,id))
		var high:=0.0;var jump:=0.0;var previous:Vector3=start;var frames:=0;var hp:float=p.hp
		while b.state=="reposition" and frames<90:
			await step(1);frames+=1
			high=maxf(high,b.global_position.y-start.y)
			jump=maxf(jump,b.global_position.distance_to(previous));previous=b.global_position
		var detail:={"id":id,"distance":G.flat(b.global_position-start).length(),"height":high,"max_frame_step":jump,"frames":frames}
		arcs.append(detail)
		check(id+" follows a short continuous collision arc",absf(G.flat(b.global_position-start).length()-delta.length())<.04 and high>.24 and high<.37 and jump<.22,detail)
		check(id+" lands before returning to decisions",b.is_on_floor() and b.state=="idle" and frames<42,[b.state,frames])
		check(id+" does not damage the knight",p.hp==hp)
		var before:float=b.hp;b.take_damage(100,0,b.global_position,"test")
		check(id+" remains vulnerable",b.hp==before-100)
		b.ai_enabled=true
		check(id+" cooldown prevents consecutive bounds",not b._try_reposition() and b.maneuver_cooldown>3)
	await reset(8);p.set_physics_process(false);b._start_reposition(Vector3(1.9,0,.35),"bound_right")
	await step(17)
	check("stance break interrupts a bound in the air",not b.is_on_floor())
	b._stagger()
	check("airborne stance break waits for the ground",b.state=="fall" and not b.critical_ready())
	await step(35)
	check("interrupted bound lands in critical-ready stagger",b.state=="stagger" and b.is_on_floor() and b.critical_ready(),[b.state,b.global_position.y,b.t])
	await reset(8);p.set_physics_process(false);b._start_reposition(Vector3(1.9,0,.35),"bound_right")
	await step(17);b.take_damage(EclipseBeast.MAX_HP*.51,0,b.global_position,"test")
	check("phase change is queued while airborne",b.transition_pending and b.state=="reposition")
	await step(25)
	check("phase change begins only after landing",b.state=="transition" and b.is_on_floor(),b.state)
	await reset(8);b.global_position=Vector3(16,0,0);await step(2)
	check("bound rejects an arena-edge destination",not b._start_reposition(Vector3(1.9,0,0),"bound_right"))
	await reset(3)
	check("bound rejects landing through the knight",not b._start_reposition(Vector3(0,0,2),"bound_forward"))
	var wall:=StaticBody3D.new();wall.collision_layer=1
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.2,3,4);collision.shape=box;wall.add_child(collision);wall.position=Vector3(1,1.5,0);add_child(wall)
	await step(2)
	check("bound rejects a wall along its path",not b._start_reposition(Vector3(1.9,0,.35),"bound_right"))
	wall.queue_free();await step(2)
	await reset(8)
	check("reset clears the maneuver and its cooldown",b.maneuver_id=="" and b.maneuver_delta==Vector3.ZERO and b.maneuver_cooldown==0 and b.maneuvers_started==0)
	var selections:={}
	for phase in [1,2]:
		await reset(6);G.training=true;b.ai_enabled=true;b.phase=phase;b.wait=0
		var attacks:=0;var last:="";var max_chain:=0
		for frame in 3000:
			if frame%420==0:
				var radius:float=[3.0,7.5,10.0,2.6,5.8,3.2,8.2][(frame/420)%7]
				p.global_position=b.global_position+Vector3(sin(b.yaw),0,cos(b.yaw))*radius;p.global_position.y=.05
			await step(1);max_chain=maxi(max_chain,b.pressure)
			if b.state=="attack" and b.attack!=last:attacks+=1;last=b.attack
			elif b.state!="attack":last=""
		selections[phase]={"bounds":b.maneuvers_started,"attacks":attacks,"max_followups":max_chain}
		check("phase %d uses reposition while retaining measured attack pressure"%phase,b.maneuvers_started>=2 and b.maneuvers_started<=13 and attacks>=16 and max_chain<=1,selections[phase])
	var out:=FileAccess.open("res://artifacts/mobility_verification.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"arcs":arcs,"AI":selections},"  "));out.close()
	print("MOBILITY COMPLETE ",checks.size()," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)

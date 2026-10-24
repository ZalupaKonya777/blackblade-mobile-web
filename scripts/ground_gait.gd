extends RefCounted
## World-space stance, predicted touchdown, zero-velocity swing endpoints.
## All target distances use the actor's real world velocity and scale.
var feet:Dictionary={}
static func blend_phase(u:float) -> float:
	u=clampf(u,0,1);return u*u*u*(10+u*(-15+u*6))
func reset() -> void:feet.clear()
func sample(id:String,home:Vector3,xf:Transform3D,velocity:Vector3,phase:float,stance:float,frequency:float,dt:float,lift:float,moving:bool,seed:Vector3,heading:Vector3,exclusive:=false,reach:=Vector2.ZERO) -> Dictionary:
	var world_home:=xf*home
	if not feet.has(id):feet[id]={"plant":seed,"point":seed,"swing":false,"heading":xf.basis*Vector3.BACK,"cycle":0,"last_step":-1,"last_phase":phase,"was_moving":false,"stance_t":0.0}
	var state:Dictionary=feet[id]
	var point:Vector3=state.point
	var grounded:=false;var landed:=false;var swing_u:=0.0;var stance_u:=0.0
	var landing:=world_home
	if not moving:
		if not state.has("stop_from"):
			state.stop_from=point;state.stop_t=0.0;state.swing=false
		state.stop_t+=dt
		var order:float={"l":0.0,"r":1.0,"paw":.5}.get(id,0.0)
		var u:=clampf((float(state.stop_t)-order*.12)/.19,0,1)
		swing_u=u
		point=Vector3(state.stop_from).lerp(world_home,blend_phase(u))
		var distance:=G.flat(Vector3(state.stop_from)-world_home).length()
		point.y+=16*u*u*(1-u)*(1-u)*lift*minf(.65,distance/.18)
		grounded=u>=1 or distance<.025
		state.plant=point
		state.heading=Vector3(state.heading).slerp(heading,blend_phase(u)*.25).normalized()
		state.was_moving=false
		state.pending=false;state.erase("reach_offset")
	else:
		state.erase("stop_from");state.erase("stop_t")
		if not state.was_moving:
			state.cycle=0;state.last_step=-1;state.last_phase=phase;state.stance_t=0.0
		elif phase<float(state.last_phase)-.5:state.cycle+=1
		state.last_phase=phase;state.was_moving=true
		if phase>=stance and state.last_step!=state.cycle:state.pending=true
		if reach.x>0 and reach.y>0 and not state.swing:
			# A planted foot can leave its safe reach before its nominal
			# phase when the body turns. Predict that strain early enough
			# to finish the other support's swing, then replant normally.
			var offset:Vector3=xf.affine_inverse()*point-home
			var rate:Vector3=(offset-Vector3(state.get("reach_offset",offset)))/maxf(.001,dt)
			var future:=offset+rate*.16
			if Vector2(future.x/reach.x,future.z/reach.y).length()>1:state.pending=true
			state.reach_offset=offset
		else:state.erase("reach_offset")
		var blocked:=false
		if exclusive:
			for other in feet:
				if other!=id and bool(feet[other].swing):blocked=true
		if not state.swing and bool(state.get("pending",false)) and not blocked:
			state.swing=true;state.from=point;state.from_heading=state.heading
			state.elapsed=0.0;state.duration=clampf((1-stance)/maxf(.1,frequency),.10,.38)
			var lead:=.42 if exclusive and id=="paw" else .5
			state.to=world_home+velocity*(float(state.duration)+stance/frequency*lead)
			state.to.y=world_home.y;state.last_step=state.cycle
			state.pending=false
		if state.swing:
			# Once a foot leaves the ground, braking must not change its phase
			# into an instant touchdown. Finish the continuous timed swing.
			state.elapsed+=dt;swing_u=clampf(float(state.elapsed)/float(state.duration),0,1)
			var lead:=.42 if exclusive and id=="paw" else .5
			var prediction:=world_home+velocity*((1-swing_u)*float(state.duration)+stance/frequency*lead)
			prediction.y=world_home.y
			if swing_u<.96:state.to=Vector3(state.to).lerp(prediction,1-exp(-24*dt))
			landing=state.to
			point=Vector3(state.from).lerp(state.to,blend_phase(swing_u))
			point.y+=16*swing_u*swing_u*(1-swing_u)*(1-swing_u)*lift
			state.heading=Vector3(state.from_heading).slerp(heading,blend_phase(swing_u)).normalized()
			if swing_u>=1:
				state.plant=state.to;state.swing=false;landed=true;grounded=true;state.stance_t=0.0
		else:
			point=state.plant;point.y=world_home.y
			state.stance_t+=dt
			grounded=true;stance_u=clampf(float(state.stance_t)/(stance/frequency),0,1)
	state.point=point
	var local_heading:=xf.basis.orthonormalized().inverse()*Vector3(state.heading)
	return {"position":xf.affine_inverse()*point,"world":point,"grounded":grounded,"landed":landed,"swing_u":swing_u,"stance_u":stance_u,"landing":landing,"load":1.0 if grounded else smoothstep(.15,.90,swing_u),"yaw":atan2(local_heading.x,local_heading.z)}

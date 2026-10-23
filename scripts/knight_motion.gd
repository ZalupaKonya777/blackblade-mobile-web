class_name KnightMotion
extends RefCounted
## Anticipation loads the hips, release drives the hands, recovery brakes the blade.
static func sample(id:String,time:float) -> Dictionary:
	var m:Dictionary=KnightMoves.MOVES[id]
	var load:=BeastMoves.smooth_motion(time/float(m.wind))
	var cut:=BeastMoves.smooth_motion((time-float(m.wind))/(float(m.hits[1])-float(m.wind)))
	var settle:=BeastMoves.smooth_motion((time-float(m.hits[1])-.10)/(float(m.length)-float(m.hits[1])-.10))
	var weight:=load*(1-settle)
	var side:float=m.side
	var a:=lerpf(-.14,lerpf(-1.65*side,1.58*side,cut),weight)
	var pitch:=lerpf(-.76,lerpf(.10,-.12,cut),weight)
	var heavy:=id in ["heavy","jump_attack"]
	var diagonal:=id in ["light3","counter"]
	if heavy:
		a=lerpf(-.14,.06,weight);pitch=lerpf(-.76,lerpf(1.19,-1.03,cut),weight)
	elif diagonal:pitch=lerpf(-.76,lerpf(.64,-.40,cut),weight)
	var lean:=.08+(.06*load+.13*cut)*weight
	var twist:=(-.34+cut*.76)*weight*side
	if heavy:lean=.08+(-.14*load+.34*cut)*weight;twist=(-.18+cut*.37)*weight
	var hand:=Vector3(-.25+sin(a)*.18,1.16+(.18 if heavy else .06)*load-.16*cut,.25+cos(a)*.13+.14*cut)
	var free:=Vector3(.23,1.12,.27)
	if heavy or id=="counter":free=hand+Vector3(.09,-.055,-.045)
	var sword:=Vector3(sin(a)*cos(pitch),sin(pitch),cos(a)*cos(pitch))
	return {"height":.94-(.05*load+.025*cut)*weight,"lean":lean,"twist":twist,"bank":side*(-.025+.06*cut)*weight,"hand":hand,"free":free,"sword":sword,"weight":weight,"cut":cut,"settle":settle,"lead":"l" if side>0 else "r"}

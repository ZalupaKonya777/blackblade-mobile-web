extends Node
## Reports stretched skin edges, rather than mistaking a mesh fault for a texture.
func _ready() -> void:run.call_deferred()
func run() -> void:
	var main=get_parent();main.set_process(false)
	main.boss.set_physics_process(false);main.player.set_physics_process(false)
	var report:=[]
	for rig:FighterRig in [main.player.rig,main.boss.rig]:
		for sample in [{"action":"idle","t":0.0,"speed":0.0},{"action":"move","t":.35,"speed":3.6},{"action":"sweep","t":.72,"speed":0.0},{"action":"leap","t":.82,"speed":0.0}]:
			rig.initialized=false
			for i in 24:rig.pose(sample.action,sample.t,1.0/60.0,sample.speed,Vector3(0,0,1))
			rig.skel.force_update_all_bone_transforms()
			var result:={"kind":rig.kind,"action":sample.action,"max_ratio":0.0,"over_3x":0,"over_5x":0,"edges":0,"worst":[]}
			for mi in rig.model.find_children("*","MeshInstance3D",true,false):
				if not mi.skin:continue
				var transforms:Array[Transform3D]=[];var names:=[]
				for bind in mi.skin.get_bind_count():
					var bone:int=mi.skin.get_bind_bone(bind)
					if bone<0:bone=rig.skel.find_bone(mi.skin.get_bind_name(bind))
					transforms.append(rig.skel.global_transform*rig.skel.get_bone_global_pose(bone)*mi.skin.get_bind_pose(bind));names.append(String(rig.skel.get_bone_name(bone)))
				for surface in mi.mesh.get_surface_count():
					var arr:Array=mi.mesh.surface_get_arrays(surface)
					var vertices:PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
					var bones:PackedInt32Array=arr[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arr[Mesh.ARRAY_WEIGHTS]
					var indices:PackedInt32Array=arr[Mesh.ARRAY_INDEX]
					var influences:=bones.size()/vertices.size()
					var posed:=PackedVector3Array();posed.resize(vertices.size())
					for v in vertices.size():
						var p:=Vector3.ZERO
						for k in influences:p+=(transforms[bones[v*influences+k]]*vertices[v])*weights[v*influences+k]
						posed[v]=p
					for triangle in indices.size()/3:
						for e in 3:
							var a:int=indices[triangle*3+e];var b:int=indices[triangle*3+(e+1)%3]
							var rest_length:float=(mi.global_transform*vertices[a]).distance_to(mi.global_transform*vertices[b])
							if rest_length<.015:continue
							var ratio:float=posed[a].distance_to(posed[b])/rest_length
							result.edges+=1
							result.max_ratio=maxf(result.max_ratio,ratio)
							if ratio>3:result.over_3x+=1
							if ratio>5:result.over_5x+=1
							if ratio>4 and (result.worst.size()<8 or ratio>float(result.worst.back().ratio)):
								var links:=[]
								for v in [a,b]:
									var at:=[]
									for k in influences:
										if weights[v*influences+k]>.01:at.append([names[bones[v*influences+k]],weights[v*influences+k]])
									links.append(at)
								result.worst.append({"ratio":ratio,"rest_length":rest_length,"vertices":[a,b],"source_points":[vertices[a],vertices[b]],"bones":links})
								result.worst.sort_custom(func(a,b):return a.ratio>b.ratio)
								if result.worst.size()>8:result.worst.resize(8)
			report.append(result);print("SKIN AUDIT ",sample.action," stretched ",result.over_3x," / ",result.edges)
	var file:=FileAccess.open("res://artifacts/skin_audit.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();get_tree().quit()

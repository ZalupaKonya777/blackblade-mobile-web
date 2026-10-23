"""Inspect the complete posed skins using the native engine's bone transforms."""
from pathlib import Path
import json,numpy as np
from asset_geometry_audit import GLB
ROOT=Path(__file__).resolve().parents[1]
report=[]
for r in json.loads((ROOT/'artifacts/pose_dump.json').read_text()):
 g=GLB(ROOT/('assets/characters/'+r['kind']+'_mobile.glb'));p=np.c_[g.positions,np.ones(len(g.positions))];posed=np.zeros((len(p),3))
 for i,n in enumerate(g.names):posed+=(p@np.array(r['transforms'][n]).reshape(3,4).T)*g.weights[:,i,None]
 world=np.c_[posed,np.ones(len(p))]@np.array(r['motion_world']).reshape(3,4).T
 edges=np.unique(np.sort(np.concatenate([g.triangles[:,[0,1]],g.triangles[:,[1,2]],g.triangles[:,[2,0]]]),axis=1),axis=0)
 lengths=np.linalg.norm(g.positions[edges[:,0]]-g.positions[edges[:,1]],axis=1);mask=lengths>.015;edges=edges[mask];lengths=lengths[mask]
 ratios=np.linalg.norm(posed[edges[:,0]]-posed[edges[:,1]],axis=1)/lengths
 worst=[]
 for i in np.argsort(ratios)[-3:][::-1]:
  worst.append({'ratio':float(ratios[i]),'vertices':edges[i].tolist(),'source':g.positions[edges[i]].tolist(),'weights':[[[n,float(w)] for n,w in zip(g.names,g.weights[v]) if w>.01] for v in edges[i]]})
 low=int(world[:,1].argmin());entry={'kind':r['kind'],'action':r['action'],'min_y':float(world[low,1]),'min_source':g.positions[low].tolist(),'max_ratio':float(ratios.max()),'over_3x':int(sum(ratios>3)),'over_5x':int(sum(ratios>5)),'worst':worst,'finite':bool(np.isfinite(world).all())}
 report.append(entry);print(entry['kind'],entry['action'],'floor',round(entry['min_y'],3),'stretch',round(entry['max_ratio'],2),'over5',entry['over_5x'],worst[0]['source'])
(ROOT/'artifacts/pose_mesh_audit.json').write_text(json.dumps(report,indent=2))

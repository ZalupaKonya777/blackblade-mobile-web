"""Prepare body support probes from the immutable mobile mesh, without modifying it."""
from pathlib import Path
import json,numpy as np
from asset_geometry_audit import GLB
ROOT=Path(__file__).resolve().parents[1]
g=GLB(ROOT/'assets/characters/boss_mobile.glb');cloth=np.array([n.startswith('cape_') or n=='loin' for n in g.names]);w=g.weights.copy();total=w[:,cloth].sum(1);w[:,cloth]=0;w/=np.maximum(w.sum(1)[:,None],1e-15)
dominant=w.argmax(1);eligible=total<.1;directions=np.array([(a,b,c) for a in [-1,0,1] for b in [-1,0,1] for c in [-1,0,1] if (a,b,c)!=(0,0,0)]);selected=set()
for ji,name in enumerate(g.names):
 if cloth[ji]:continue
 ix=np.flatnonzero((dominant==ji)&eligible)
 if len(ix):selected.update(ix[np.unique(np.argmax(g.positions[ix]@directions.T,axis=0))].tolist())
path=ROOT/'artifacts/pose_dump.json'
if path.exists():
 for pose in json.loads(path.read_text()):
  if pose['kind']!='boss' or pose['action']!='dead':continue
  p=np.c_[g.positions,np.ones(len(g.positions))];posed=np.zeros((len(p),3))
  for ji,name in enumerate(g.names):
   if cloth[ji]:continue
   posed+=(p@np.array(pose['transforms'][name]).reshape(3,4).T)*w[:,ji,None]
  ix=np.flatnonzero(eligible);selected.update(ix[np.argsort(posed[ix,1])[:64]].tolist())
probes=[{'point':g.positions[i].tolist(),'influences':[{'bone':name,'weight':float(weight)} for name,weight in zip(g.names,w[i]) if weight>.00001]} for i in sorted(selected)]
(ROOT/'assets/characters/boss_body_contacts.json').write_text(json.dumps(probes,separators=(',',':')))
print('body contact probes:',len(probes))

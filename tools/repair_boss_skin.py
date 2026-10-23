"""Repair discontinuous cloth/limb weights in a separate mobile-derived GLB.

The supplied mesh, normals, UVs, textures, skeleton and source boss.glb are
preserved. Only skin influence attributes change in boss_mobile.glb.
Requires numpy and scipy; this is an asset preparation step, not a web dependency.
"""
from pathlib import Path
import hashlib, json, struct
import numpy as np
from scipy.sparse import coo_matrix, diags

ROOT = Path(__file__).resolve().parents[1]
assets = ROOT / 'assets/characters'
raw = (assets / 'boss.glb').read_bytes()
length = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20+length])
start = 28 + length
binary = bytearray(raw[start:])
widths = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
types = {5126:'<f4',5121:'u1',5123:'<u2',5125:'<u4'}
def array(i):
    a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']]
    return np.ndarray((a['count'],widths[a['type']]), dtype=types[a['componentType']],
                      buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0))

primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes']
pos=array(attrs['POSITION']);joints=array(attrs['JOINTS_0']);weights=array(attrs['WEIGHTS_0'])
indices=array(primitive['indices']).reshape(-1,3)
names=[doc['nodes'][i]['name'] for i in doc['skins'][0]['joints']]
meta=json.loads((assets/'boss.json').read_text())
scale=meta['bones']['pelvis']['head'][1]/.49
p=pos.astype(np.float64)/scale
cloth=np.array([name.startswith('cape_') for name in names])
original=np.zeros((len(pos),len(names)))
np.add.at(original,(np.arange(len(pos))[:,None],joints),weights)
body=np.zeros_like(original)
x,y,z=p.T
for i,name in enumerate(names):
    if name=='root' or cloth[i]:continue
    bone=meta['bones'][name];head=np.array(bone['head'])/scale;tail=np.array(bone['tail'])/scale
    axis=tail-head
    nearest=head+np.clip(((p-head)*axis).sum(1)/np.dot(axis,axis),0,1)[:,None]*axis
    w=1/(np.linalg.norm(p-nearest,axis=1)+.008)**4
    if name in ['head','neck']:w*=np.where(y>.75,1,.00001)
    elif name in ['pelvis','spine1','spine2']:w*=np.where((y>.46)&(y<.82),1,.00001)
    elif name.startswith(('upper_','fore_','hand_')):
        side=1 if name.endswith('l') else -1
        w*=np.where((x*side>.105)&(y>.56)&(y<.79),1,.0000001)
    else:
        side=1 if name.endswith('l') else -1
        w*=np.where((x*side>-.015)&(y<.51),1,.000001)
    body[:,i]=w
body/=np.maximum(body.sum(1)[:,None],1e-15)
body[y>.82]=0;body[y>.82,names.index('head')]=1
# Keep established body/arm binding wherever the original still has it.
old_body=original.copy();old_body[:,cloth]=0
old_total=old_body.sum(1)
known=old_total>.10
body[known]=old_body[known]/old_total[known,None]

def smoothstep(lo,hi,v):
    t=np.clip((v-lo)/(hi-lo),0,1)
    return t*t*(3-2*t)

old_cloth=original[:,cloth].sum(1)
cape_weights=original.copy();cape_weights[:,~cloth]=0
cape_weights/=np.maximum(old_cloth[:,None],1e-15)
# The old flat cutoff at z=-0.168m cuts through calf/forearm armour. Cloth is
# now restricted to the rear mantle, with a gradual attachment zone.
rear=smoothstep(.20,.58,-pos[:,2])
arm=smoothstep(.48,.70,np.abs(pos[:,0]))*smoothstep(1.95,2.25,pos[:,1])
amount=old_cloth*rear*(1-arm)
result=body*(1-amount[:,None])+cape_weights*amount[:,None]

# Weld only for weight solving: UV seam duplicates remain separate vertices in
# the GLB, but receive identical weights. No geometry is merged or moved.
_,inverse=np.unique(np.round(pos/0.00001).astype(np.int64),axis=0,return_inverse=True)
count=int(inverse.max())+1
unified=np.zeros((count,len(names)));np.add.at(unified,inverse,result)
counts=np.bincount(inverse);unified/=counts[:,None]
centres=np.zeros((count,3));np.add.at(centres,inverse,pos);centres/=counts[:,None]
edges=np.concatenate([indices[:,[0,1]],indices[:,[1,2]],indices[:,[2,0]]])
edges=np.unique(np.sort(inverse[edges],axis=1),axis=0);edges=edges[edges[:,0]!=edges[:,1]]
values=1/np.maximum(.02,np.linalg.norm(centres[edges[:,0]]-centres[edges[:,1]],axis=1))
rows=np.concatenate([edges[:,0],edges[:,1]]);cols=np.concatenate([edges[:,1],edges[:,0]])
graph=coo_matrix((np.concatenate([values,values]),(rows,cols)),shape=(count,count)).tocsr()
degree=np.asarray(graph.sum(1)).ravel();graph=diags(1/np.maximum(degree,1))@graph
for _ in range(60):
    neighbours=graph@unified
    unified=np.where((degree>0)[:,None],unified*.55+neighbours*.45,unified)
result=unified[inverse]
top=np.argsort(result,axis=1)[:,-8:][:,::-1]
out=np.take_along_axis(result,top,axis=1);out/=np.maximum(out.sum(1)[:,None],1e-15)
changed=int(np.sum(np.max(np.abs(result-original),axis=1)>.02))
joints[:]=top[:,:4];weights[:]=out[:,:4]
# Eight influences keep the attachment zone continuous. Cutting a smooth solve
# back to four made equally weighted left/right leg joints swap at the midline.
new_binary=bytes(binary)
for semantic,values,component in [
    ('JOINTS_1',top[:,4:].astype(joints.dtype),doc['accessors'][attrs['JOINTS_0']]['componentType']),
    ('WEIGHTS_1',out[:,4:].astype('<f4'),5126),
]:
    new_binary+=b'\0'*((-len(new_binary))%4)
    view=len(doc['bufferViews']);payload=values.tobytes()
    doc['bufferViews'].append({'buffer':0,'byteOffset':len(new_binary),'byteLength':len(payload),'target':34962})
    attrs[semantic]=len(doc['accessors'])
    doc['accessors'].append({'bufferView':view,'componentType':component,'count':len(pos),'type':'VEC4'})
    new_binary+=payload
doc['buffers'][0]['byteLength']=len(new_binary)
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
new_binary+=b'\0'*((-len(new_binary))%4)
destination=assets/'boss_mobile.glb'
destination.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(new_binary))+
    struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(new_binary),b'BIN\0')+new_binary)

# Floor contacts must describe the new binding, otherwise they would constrain
# an obsolete mesh and pull unused cloth bones around.
dominant=top[np.arange(len(pos)),out.argmax(axis=1)]
directions=np.array([(a,b,c) for a in [-1,0,1] for b in [-1,0,1] for c in [-1,0,1] if (a,b,c)!=(0,0,0)])
selected=set()
for ji,name in enumerate(names):
    if not name.startswith('cape_'):continue
    candidates=np.flatnonzero(dominant==ji)
    if not len(candidates):continue
    selected.update(candidates[np.unique(np.argmax(pos[candidates]@directions.T,axis=0))].tolist())
    selected.update(candidates[::120].tolist())
probes=[{'point':pos[vi].astype(float).tolist(),'influences':[
    {'bone':names[int(b)],'weight':float(w)} for b,w in zip(top[vi],out[vi]) if w>.005]} for vi in sorted(selected)]
(assets/'boss_cloth_contacts.json').write_text(json.dumps(probes,separators=(',',':')))
report={'vertices':len(pos),'changed_weights':changed,'cloth_probes':len(probes),
        'source_sha256':hashlib.sha256(raw).hexdigest(),'mobile_sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
        'preserved':['positions','normals','UVs','indices','textures','skeleton','source boss.glb'],
        'method':'anatomical limb binding; gradual rear mantle attachment; welded topology weight smoothing; eight normalised influences'}
(ROOT/'artifacts/skin_repair.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

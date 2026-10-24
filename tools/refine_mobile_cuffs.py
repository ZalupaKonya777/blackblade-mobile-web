"""Harmonic hand/cuff weights on the already prepared knight.

Run after repair_mobile_skins.py. Hand geometry, morphs, UVs, textures and all
other body weights are retained. Pins cover the raised thumb as well as palm;
the transition follows mesh topology rather than cutting across the glove.
"""
from pathlib import Path
import argparse, json, struct, hashlib
import numpy as np
from scipy.sparse import coo_matrix, diags
from scipy.spatial import cKDTree
from asset_geometry_audit import GLB

ROOT=Path(__file__).resolve().parents[1];ASSETS=ROOT/'assets/characters'
parser=argparse.ArgumentParser();parser.add_argument('--source-dir',type=Path,default=ASSETS);args=parser.parse_args()
mesh=GLB(args.source_dir/'knight_mobile.glb')
if mesh.doc.get('extras',{}).get('harmonic_cuffs')==1:
    print('Cuffs already prepared; regenerate the input skin to rebuild.');raise SystemExit()
p,tri,edges,weights,inverse=mesh.welded();names=mesh.names
lengths=np.maximum(.002,np.linalg.norm(p[edges[:,0]]-p[edges[:,1]],axis=1));values=1/lengths
graph=coo_matrix((np.r_[values,values],(np.r_[edges[:,0],edges[:,1]],np.r_[edges[:,1],edges[:,0]])),shape=(len(p),len(p))).tocsr()
degree=np.asarray(graph.sum(1)).ravel();graph=diags(1/np.maximum(degree,1e-12))@graph
original=weights.copy();x,y,z=p.T
for side,sign in [('l',1),('r',-1)]:
    hand=names.index('hand_'+side);fore=names.index('fore_'+side)
    domain=(x*sign>.34)&(y>.77)&(y<1.14)&(z>-.04)&(z<.24)
    pin=domain&(((x*sign>.400)&(y<.985))|((x*sign>.385)&(z>.075)&(y<1.005))|(original[:,hand]>.98))
    t=original[:,hand].copy()
    for i in range(200):
        t[domain]=.5*t[domain]+.5*(graph@t)[domain]
        t[pin]=1;t[~domain]=original[~domain,hand]
    body=weights.copy();body[:,hand]=0
    total=body.sum(1);body[total<1e-9,fore]=1;total=body.sum(1);body/=total[:,None]
    result=body*(1-t[:,None]);result[:,hand]+=t
    weights[domain]=result[domain]
weights=weights[inverse];weights/=weights.sum(1)[:,None]
top=np.argsort(weights,axis=1)[:,-8:][:,::-1];out=np.take_along_axis(weights,top,axis=1);out/=out.sum(1)[:,None]
doc=mesh.doc;binary=bytearray(mesh.binary)
for channel in [0,1]:
    for semantic,values in [(f'JOINTS_{channel}',top[:,channel*4:channel*4+4]),(f'WEIGHTS_{channel}',out[:,channel*4:channel*4+4])]:
        a=doc['accessors'][mesh.attributes[semantic]];v=doc['bufferViews'][a['bufferView']];dtype={5126:'<f4',5123:'<u2',5121:'u1'}[a['componentType']]
        target=np.ndarray((a['count'],4),dtype=dtype,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',np.dtype(dtype).itemsize*4),np.dtype(dtype).itemsize));target[:]=values
doc.setdefault('extras',{})['harmonic_cuffs']=1
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4);payload=bytes(binary);payload+=b'\0'*(-len(payload)%4)
dest=ASSETS/'knight_mobile.glb';dest.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(payload))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(payload),b'BIN\0')+payload)
check=GLB(dest)
assert np.array_equal(mesh.positions,check.positions) and np.array_equal(mesh.triangles,check.triangles)
assert np.array_equal(mesh.array(mesh.attributes['TEXCOORD_0']),check.array(check.attributes['TEXCOORD_0']))
probes=json.loads((ASSETS/'knight_contacts.json').read_text());tree=cKDTree(mesh.positions)
for probe in probes:
    distance,vertex=tree.query(probe['point']);assert distance<1e-5
    probe['influences']=[{'bone':n,'weight':float(w)} for n,w in zip(names,check.weights[vertex]) if w>1e-6]
(ASSETS/'knight_contacts.json').write_text(json.dumps(probes,separators=(',',':')))
report={'vertices_changed':int((np.max(abs(mesh.weights-check.weights),axis=1)>.02).sum()),'geometry_uv_topology_preserved':True,'source_sha256':hashlib.sha256(mesh.raw).hexdigest(),'output_sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
(ROOT/'artifacts/harmonic_cuffs.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))

"""Fit prepared skin weights to preserve surface lengths in representative poses.

This is an offline, constrained optimization. Existing bone supports, rigid
palms/soles/head, rest geometry, UVs, topology and grip shapes are preserved.
Runtime stays ordinary eight-influence skinning; there is no per-frame mesh solve.
"""
from pathlib import Path
import argparse,json,struct,hashlib
import numpy as np
from scipy.sparse import coo_matrix
from scipy.spatial import cKDTree
from asset_geometry_audit import GLB

ROOT=Path(__file__).resolve().parents[1];ASSETS=ROOT/'assets/characters'
parser=argparse.ArgumentParser();parser.add_argument('kind',choices=['knight','boss']);parser.add_argument('--iterations',type=int,default=160);parser.add_argument('--source',type=Path)
args=parser.parse_args();kind=args.kind;source=args.source or ASSETS/f'{kind}_mobile.glb';mesh=GLB(source)
if args.source is None and mesh.doc.get('extras',{}).get('pose_rigidity_fit')==1:
    print('Skin already fitted; regenerate prepared inputs before rebuilding.');raise SystemExit()
p,tri,edges,dense,inverse=mesh.welded();p=p.astype(np.float32);dense=dense.astype(np.float32);n=len(p)
top=np.argsort(dense,axis=1)[:,-8:][:,::-1];w0=np.take_along_axis(dense,top,axis=1);w0/=w0.sum(1)[:,None];allowed=w0>1e-6
fixed=np.zeros(n,dtype=bool)
for i,name in enumerate(mesh.names):
    if name.startswith(('hand_','foot_')) or name=='head':fixed|=dense[:,i]>.90
lengths=np.linalg.norm(p[edges[:,0]]-p[edges[:,1]],axis=1);keep=lengths>(.008 if kind=='knight' else .016);edges=edges[keep];lengths=lengths[keep]
edge_weight=np.clip((.018 if kind=='knight' else .036)/lengths,.4,2.0).astype(np.float32)
inc=coo_matrix((np.tile([1.,-1.],len(edges)).astype(np.float32),(np.repeat(np.arange(len(edges)),2),edges.reshape(-1))),shape=(len(edges),n)).tocsr()
degree=np.bincount(edges.ravel(),weights=np.repeat(edge_weight,2),minlength=n).astype(np.float32)
frames=json.loads((ROOT/'artifacts/locomotion_after.json').read_text())['frames'];poses=[]
times={'knight':{'run':[.4,.7,1.0,1.3,1.6],'sprint':[.9,1.5],'strafe':[.7,1.4],'backward':[.7,1.4],'turn':[1.2]},'boss':{'approach':[.4,.7,1.,1.3,1.6],'charge':[.7,1.4],'orbit':[.7,1.4],'retreat':[.7,1.4],'turn':[1.2,1.6]}}[kind]
for case,at in times.items():
    for t in at:
        frame=min((f for f in frames if f['kind']==kind and f['case']==case),key=lambda f:abs(f['time']-t));poses.append(frame)
for pose in json.loads((ROOT/'artifacts/pose_dump.json').read_text()):
    if pose['kind']==kind and pose['action'] in ['idle','light','sweep','overhead','leap','roll','dead']:poses.append(pose)
transforms=np.array([[np.array(q['transforms'][name]).reshape(3,4) for name in mesh.names] for q in poses],dtype=np.float32)
selected=transforms[:,top]
points=np.einsum('pvkij,vj->pvki',selected[...,:3],p,optimize=True)+selected[...,3]
base=np.einsum('pvkc,vk->pvc',points,w0,optimize=True)
centered=points-base[:,:,None,:]
variation=np.mean(np.max(np.sum(centered*centered,axis=3),axis=2),axis=0)
denominator=2*(degree*variation+.03*variation+.02)
planes=[]
for pose in poses:
    xf=np.array(pose['motion_world']).reshape(3,4)
    planes.append((.030-float(xf[1,3]))/max(.1,float(np.linalg.norm(xf[1,:3]))))
planes=np.array(planes,dtype=np.float32)

def project(a):
    a=np.where(allowed,a,-1e5);u=-np.sort(-a,axis=1);s=np.cumsum(u,axis=1)-1
    count=(u-s/np.arange(1,9)>0).sum(1);theta=s[np.arange(n),count-1]/count
    result=np.maximum(a-theta[:,None],0);result[fixed]=w0[fixed];return result.astype(np.float32)

def evaluate(w,gradient=False):
    delta=np.einsum('pvkc,vk->pvc',centered,w-w0,optimize=True);posed=base+delta
    e=posed[:,edges[:,0]]-posed[:,edges[:,1]];length=np.maximum(np.linalg.norm(e,axis=2),1e-7)
    error=length-np.clip(length,lengths[None,:]*.75,lengths[None,:]*1.20)
    loss=float(np.mean(np.sum(error*error*edge_weight[None,:],axis=1))+.03*np.sum(delta*delta)/len(poses)+.02*np.sum((w-w0)**2))
    ratios=length/lengths[None,:]
    if not gradient:return loss,float(ratios.max()),float(np.quantile(ratios,.99))
    edge_gradient=2*e*(error/length*edge_weight[None,:])[:,:,None]
    v=(inc.T@edge_gradient.transpose(1,0,2).reshape(len(edges),-1)).reshape(n,len(poses),3).transpose(1,0,2)
    v+=.06*delta
    v[:,:,1]+=np.minimum(posed[:,:,1]-planes[:,None],0)*2
    grad=np.einsum('pvkc,pvc->vk',centered,v,optimize=True)/len(poses)+.04*(w-w0)
    return loss,grad

w=w0.copy();before=evaluate(w);print(kind,'before loss/max/p99',before,'poses',len(poses),'vertices',n,flush=True)
for i in range(args.iterations):
    loss,gradient=evaluate(w,True)
    step=np.clip(gradient/denominator[:,None],-.04,.04)
    w=project(w-step*.8)
    if (i+1)%20==0:print(kind,'iteration',i+1,'loss',loss,flush=True)
after=evaluate(w);print(kind,'after loss/max/p99',after,flush=True)
assert after[0]<before[0], 'Optimization did not improve surface rigidity'
out=w[inverse];top=top[inverse]
assert np.isfinite(out).all() and out.min()>=0 and np.max(abs(out.sum(1)-1))<1e-5
doc=mesh.doc;binary=bytearray(mesh.binary)
for channel in [0,1]:
    for semantic,values in [(f'JOINTS_{channel}',top[:,channel*4:channel*4+4]),(f'WEIGHTS_{channel}',out[:,channel*4:channel*4+4])]:
        a=doc['accessors'][mesh.attributes[semantic]];v=doc['bufferViews'][a['bufferView']];dtype={5126:'<f4',5123:'<u2',5121:'u1'}[a['componentType']]
        target=np.ndarray((a['count'],4),dtype=dtype,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',np.dtype(dtype).itemsize*4),np.dtype(dtype).itemsize));target[:]=values
doc.setdefault('extras',{})['pose_rigidity_fit']=1
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4);payload=bytes(binary);payload+=b'\0'*(-len(payload)%4)
dest=ASSETS/f'{kind}_mobile.glb';dest.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(payload))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(payload),b'BIN\0')+payload)
check=GLB(dest);assert np.array_equal(mesh.positions,check.positions) and np.array_equal(mesh.triangles,check.triangles)
assert np.array_equal(mesh.array(mesh.attributes['TEXCOORD_0']),check.array(check.attributes['TEXCOORD_0']))
tree=cKDTree(mesh.positions);path=ASSETS/(kind+('_contacts' if kind=='knight' else '_cloth_contacts')+'.json');probes=json.loads(path.read_text())
for probe in probes:
    distance,vertex=tree.query(probe['point']);assert distance<1e-5
    probe['influences']=[{'bone':name,'weight':float(weight)} for name,weight in zip(mesh.names,check.weights[vertex]) if weight>1e-6]
path.write_text(json.dumps(probes,separators=(',',':')))
report={'kind':kind,'before':before,'after':after,'poses':len(poses),'iterations':args.iterations,'geometry_uv_topology_preserved':True,'source_sha256':hashlib.sha256(mesh.raw).hexdigest(),'output_sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
(ROOT/f'artifacts/{kind}_rigidity_fit.json').write_text(json.dumps(report,indent=2))

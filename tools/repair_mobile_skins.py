"""Prepare mobile skins from immutable supplied GLBs: welded weights and sword grips.

UVs, textures, mesh topology and original assets are preserved. Only the derived
hand geometry is curled; normals follow that geometry. No external runtime dependency.
"""
from pathlib import Path
import hashlib,json,struct
import numpy as np
from PIL import Image
from scipy.sparse import coo_matrix,diags
ROOT=Path(__file__).resolve().parents[1];ASSETS=ROOT/'assets/characters'
def smooth(lo,hi,v):
 t=np.clip((v-lo)/(hi-lo),0,1);return t*t*(3-2*t)
def repair(kind):
 raw=(ASSETS/(kind+'.glb')).read_bytes();size=struct.unpack_from('<I',raw,12)[0]
 doc=json.loads(raw[20:20+size]);binary=bytearray(raw[28+size:])
 def array(i):
  a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']]
  return np.ndarray((a['count'],{'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]),dtype={5126:'<f4',5121:'u1',5123:'<u2',5125:'<u4'}[a['componentType']],buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0))
 prim=doc['meshes'][0]['primitives'][0];attrs=prim['attributes'];pos=array(attrs['POSITION']);original_pos=pos.copy()
 triangles=array(prim['indices']).reshape(-1,3);joints=array(attrs['JOINTS_0']);weights=array(attrs['WEIGHTS_0'])
 names=[doc['nodes'][i]['name'] for i in doc['skins'][0]['joints']];meta=json.loads((ASSETS/(kind+'.json')).read_text())
 if kind=='boss':
  names.append('loin');meta['bones']['loin']={'head':[0,1.90,.22],'tail':[0,1.12,.35],'parent':'pelvis'}
 scale=meta['bones']['pelvis']['head'][1]/.49;p=pos.astype(float)/scale;x,y,z=p.T
 cape=np.array([n.startswith('cape_') for n in names]);original=np.zeros((len(pos),len(names)))
 np.add.at(original,(np.arange(len(pos))[:,None],joints),weights);body=np.zeros_like(original)
 for i,name in enumerate(names):
  if name in ['root','loin'] or cape[i]:continue
  b=meta['bones'][name];a=np.array(b['head'])/scale;v=np.array(b['tail'])/scale-a
  nearest=a+np.clip(((p-a)*v).sum(1)/(v@v),0,1)[:,None]*v
  w=1/(np.linalg.norm(p-nearest,axis=1)+.008)**4
  if name in ['head','neck']:w*=np.where(y>.75,1,1e-5)
  elif name in ['pelvis','spine1','spine2']:w*=np.where((y>.46)&(y<.82),1,1e-5)
  elif name.startswith(('upper_','fore_','hand_')):
   side=1 if name.endswith('l') else -1;w*=np.where((x*side>.105)&(y>.56)&(y<.79),1,1e-7)
  else:
   side=1 if name.endswith('l') else -1;w*=np.where((x*side>-.015)&(y<.51),1,1e-6)
  body[:,i]=w
 body/=np.maximum(body.sum(1)[:,None],1e-15);body[y>.82]=0;body[y>.82,names.index('head')]=1
 known=original.copy();known[:,cape]=0;total=known.sum(1);mask=(total>.1) if kind=='knight' else np.zeros(len(pos),dtype=bool);body[mask]=known[mask]/total[mask,None]
 if kind=='boss':body=body**1.5;body/=np.maximum(body.sum(1)[:,None],1e-15)
 oldcloth=original[:,cape].sum(1);cloth=original.copy();cloth[:,~cape]=0;cloth/=np.maximum(oldcloth[:,None],1e-15)
 if kind=='boss':
  rear=smooth(.20,.58,-pos[:,2]);arms=smooth(.48,.70,abs(pos[:,0]))*smooth(1.95,2.25,pos[:,1]);amount=oldcloth*rear*(1-arms)
 else:
  # Front tabard and rear cape remain cloth. The old horizontal cutoff had
  # accidentally attached solid calves and boots to the lower cape chains.
  rear=smooth(.09,.19,-pos[:,2]);front=smooth(.11,.20,pos[:,2])*(1-smooth(.12,.24,abs(pos[:,0])))
  uv=array(attrs['TEXCOORD_0']);orm=np.array(Image.open(ASSETS/'knight_armor_orm.png').convert('RGB'))
  tx=np.clip((uv[:,0]*orm.shape[1]).astype(int),0,orm.shape[1]-1);ty=np.clip((uv[:,1]*orm.shape[0]).astype(int),0,orm.shape[0]-1)
  material=orm[ty,tx].astype(float)/255
  fabric=smooth(.64,.78,material[:,1])*(1-smooth(.15,.60,material[:,2]))
  amount=oldcloth*np.maximum(np.maximum(rear,front)*(1-smooth(.15,.60,material[:,2])),fabric)
 result=body*(1-amount[:,None])+cloth*amount[:,None]
 if kind=='boss':
  front=smooth(-.015,.22,pos[:,2])*(1-smooth(1.85,2.30,pos[:,1]))*(1-smooth(.45,.80,abs(pos[:,0])))*smooth(.65,.90,pos[:,1])
  centre=(1-smooth(.14,.48,abs(pos[:,0])))*smooth(.68,.92,pos[:,1])*(1-smooth(1.75,2.12,pos[:,1]))*(1-smooth(.18,.40,-pos[:,2]))
  loin=np.maximum(front,centre)
  result*=1-loin[:,None];result[:,names.index('loin')]+=loin
 _,inverse=np.unique(np.round(pos/.00001).astype(np.int64),axis=0,return_inverse=True);count=inverse.max()+1
 counts=np.bincount(inverse);u=np.zeros((count,len(names)));np.add.at(u,inverse,result);u/=counts[:,None]
 centres=np.zeros((count,3));np.add.at(centres,inverse,pos);centres/=counts[:,None]
 edges=np.concatenate([triangles[:,[0,1]],triangles[:,[1,2]],triangles[:,[2,0]]]);edges=np.unique(np.sort(inverse[edges],axis=1),axis=0);edges=edges[edges[:,0]!=edges[:,1]]
 values=1/np.maximum(.02,np.linalg.norm(centres[edges[:,0]]-centres[edges[:,1]],axis=1))
 graph=coo_matrix((np.r_[values,values],(np.r_[edges[:,0],edges[:,1]],np.r_[edges[:,1],edges[:,0]])),shape=(count,count)).tocsr();degree=np.asarray(graph.sum(1)).ravel();graph=diags(1/np.maximum(degree,1))@graph
 for _ in range(160 if kind=='boss' else 96):u=np.where((degree>0)[:,None],u*.55+(graph@u)*.45,u)
 result=u[inverse]
 # Rigid palms, smoothly attached at the glove/cuff. A socket must follow the
 # actual palm, rather than a wrist averaged between forearm and upper arm.
 rigid_masks=[]
 for side in ['l','r']:
  sign=1 if side=='l' else -1
  if kind=='knight':
   envelope=smooth(.39,.415,pos[:,0]*sign)*smooth(.035,.060,pos[:,2]);rigid=envelope*(1-smooth(.952,1.015,pos[:,1]))*smooth(.78,.815,pos[:,1])
  else:
   envelope=smooth(.59,.76,pos[:,0]*sign)*(1-smooth(.055,.12,pos[:,2]))*smooth(-.39,-.33,pos[:,2]);rigid=envelope*(1-smooth(2.82,3.20,pos[:,1]))*smooth(2.47,2.53,pos[:,1])
  result*=1-rigid[:,None];result[:,names.index('hand_'+side)]+=rigid
  rigid_masks.append((side,rigid.copy()))
 if kind=='boss':
  # Smooth the cuff along mesh topology, pinning the actual palm to its hand.
  u[:]=0;np.add.at(u,inverse,result);u/=counts[:,None]
  collar=(np.abs(centres[:,0])>.60)&(centres[:,1]>2.40)&(centres[:,1]<3.30)
  pins=[]
  for side,rigid in rigid_masks:
   pinned=np.zeros(count);np.maximum.at(pinned,inverse,rigid);pins.append((pinned>.999,names.index('hand_'+side)))
  for _ in range(64):
   u[collar]=u[collar]*.5+(graph@u)[collar]*.5
   for mask,ji in pins:u[mask]=0;u[mask,ji]=1
  result=u[inverse]
 # Close only the sword hand. Each main digit bends from its own knuckle;
 # the thumb opposes the grip independently. The open support claw is kept.
 if kind=='knight':
  root_y=.901;socket=np.array([-.437,.901,.115]);envelope=(pos[:,0]<-.405)&(pos[:,2]>.049)&(pos[:,1]>.815)&(pos[:,1]<1.0)
  thumb=envelope&(pos[:,2]>.151)&(pos[:,1]>.898);main=envelope&~thumb
 else:
  root_y=2.725;socket=np.array([-1.054,2.725,-.170]);envelope=(pos[:,0]<-.94)&(pos[:,2]>-.31)&(pos[:,2]<.045)&(pos[:,1]>2.535)&(pos[:,1]<2.88)
  thumb=envelope&(pos[:,2]>-.035)&(pos[:,1]>2.68);main=envelope&~thumb
 source=pos.astype(float).copy();s=np.maximum(0,root_y-source[:,1]);radius=np.maximum(.026 if kind=='knight' else .065,socket[0]-source[:,0]);theta=np.minimum(s/radius,2.95)
 # Radius follows the finger's thickness; across-grip Z and UVs stay unchanged.
 pos[main,0]=(source[:,0]+radius*(1-np.cos(theta)))[main]
 pos[main,1]=(root_y-radius*np.sin(theta))[main]
 # Thumb moves toward the outer end of the handle, forming an opposing pinch.
 pivot=np.array([-.414566,.945,.164]) if kind=='knight' else np.array([-1.008931,2.745,0.0])
 v=source-pivot;amount_thumb=np.clip(np.linalg.norm(v,axis=1)/(.047 if kind=='knight' else .15),0,1)
 angle=amount_thumb*(.72 if kind=='knight' else .85);c=np.cos(angle);sn=np.sin(angle)
 curled=np.c_[v[:,0]*c-v[:,1]*sn,v[:,0]*sn+v[:,1]*c,v[:,2]]+pivot
 curled[:,2]-=amount_thumb*(.018 if kind=='knight' else .045)
 pos[thumb]=curled[thumb]
 left_delta=None
 if kind=='knight':
  mirrored=original_pos.astype(float).copy();mirrored[:,0]*=-1;curled_left=mirrored.copy()
  region=(mirrored[:,0]<-.405)&(mirrored[:,2]>.049)&(mirrored[:,1]>.815)&(mirrored[:,1]<1.0)
  thumb_l=region&(mirrored[:,2]>.151)&(mirrored[:,1]>.898);main_l=region&~thumb_l
  dist=np.maximum(0,.901-mirrored[:,1]);r=np.maximum(.026,-.437-mirrored[:,0]);angle=np.minimum(dist/r,2.95)
  curled_left[main_l,0]=(mirrored[:,0]+r*(1-np.cos(angle)))[main_l];curled_left[main_l,1]=(.901-r*np.sin(angle))[main_l]
  pivot_l=np.array([-.414566,.945,.164]);v=mirrored-pivot_l;f=np.clip(np.linalg.norm(v,axis=1)/.047,0,1);angle=f*.72
  thumb_pos=np.c_[v[:,0]*np.cos(angle)-v[:,1]*np.sin(angle),v[:,0]*np.sin(angle)+v[:,1]*np.cos(angle),v[:,2]]+pivot_l;thumb_pos[:,2]-=f*.018
  curled_left[thumb_l]=thumb_pos[thumb_l];curled_left[:,0]*=-1
  left_delta=(curled_left-original_pos).astype('<f4')
 # Bake the beast's longer forelimbs into its REST mesh and bind poses.
 # Runtime no longer scales bones: palm/forearm vertices share a consistent
 # rest skeleton, so crouches and twists do not pull the cuff apart.
 extra={};mobile_meta=json.loads(json.dumps(meta))
 if kind=='boss':
  for side in ['l','r']:
   upper='upper_'+side;fore='fore_'+side;hand='hand_'+side
   uh=np.array(meta['bones'][upper]['head']);fh=np.array(meta['bones'][fore]['head']);hh=np.array(meta['bones'][hand]['head'])
   newfore=uh+(fh-uh)*1.6;newhand=newfore+(hh-fh)*1.6
   for name,newhead in [(upper,uh),(fore,newfore),(hand,newhand)]:
    oldhead=np.array(meta['bones'][name]['head']);oldtail=np.array(meta['bones'][name]['tail']);axis=oldtail-oldhead;axis/=np.linalg.norm(axis)
    stretch=np.eye(3)+(.6*np.outer(axis,axis) if name!=hand else 0)
    extra[name]=(oldhead,newhead,stretch)
    mobile_meta['bones'][name]['head']=newhead.tolist();mobile_meta['bones'][name]['tail']=(newhead+stretch@(oldtail-oldhead)).tolist()
  closed=pos.astype(float).copy();baked=closed.copy()
  for name,(oldhead,newhead,stretch) in extra.items():
   moved=(closed-oldhead)@stretch.T+newhead;baked+=(moved-closed)*result[:,names.index(name),None]
  pos[:]=baked
  # Update local joint translations and inverse bind matrices, preserving axes.
  from asset_geometry_audit import node_transform
  parents={c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])};cache={}
  def global_rest(i):
   if i not in cache:cache[i]=(global_rest(parents[i]) if i in parents else np.eye(4))@node_transform(doc['nodes'][i])
   return cache[i]
  for i in range(len(doc['nodes'])):global_rest(i)
  pelvis_node=next(i for i,n in enumerate(doc['nodes']) if n.get('name')=='pelvis')
  loin_global=np.eye(4);loin_global[:3,3]=meta['bones']['loin']['head']
  local=np.linalg.inv(cache[pelvis_node])@loin_global;loin_node=len(doc['nodes'])
  doc['nodes'].append({'name':'loin','matrix':local.T.reshape(-1).tolist()});doc['nodes'][pelvis_node].setdefault('children',[]).append(loin_node)
  doc['skins'][0]['joints'].append(loin_node);cache[loin_node]=loin_global
  changed={i:cache[i].copy() for i in range(len(doc['nodes']))}
  for i,node in enumerate(doc['nodes']):
   if node.get('name') in extra:changed[i][:3,3]=extra[node['name']][1]
  for i,node in enumerate(doc['nodes']):
   if node.get('name') not in extra:continue
   local=np.linalg.inv(changed[parents[i]])@changed[i] if i in parents else changed[i]
   node.pop('matrix',None);node['translation']=local[:3,3].tolist()
  new_inverse_binds=np.array([np.linalg.inv(changed[ni]).T.reshape(-1) for ni in doc['skins'][0]['joints']],dtype='<f4')
  socket+=extra['hand_r'][1]-extra['hand_r'][0]
 (ASSETS/(kind+'_mobile.json')).write_text(json.dumps(mobile_meta,indent=2))
 # Recompute normals only in changed hand geometry, welding UV duplicates.
 moved=np.linalg.norm(pos-original_pos,axis=1)>1e-7
 normals=array(attrs['NORMAL']);face=np.cross(pos[triangles[:,1]]-pos[triangles[:,0]],pos[triangles[:,2]]-pos[triangles[:,0]])
 n=np.zeros((count,3))
 for k in range(3):np.add.at(n,inverse[triangles[:,k]],face)
 n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-15);normals[moved]=n[inverse[moved]]
 # Average again at exact seams after the rigid collar operations.
 u[:]=0;np.add.at(u,inverse,result);u/=counts[:,None];result=u[inverse]
 top=np.argsort(result,axis=1)[:,-8:][:,::-1];out=np.take_along_axis(result,top,axis=1);out/=out.sum(1)[:,None]
 joints[:]=top[:,:4];weights[:]=out[:,:4];new=bytes(binary)
 if kind=='boss':
  new+=b'\0'*((-len(new))%4);view=len(doc['bufferViews']);payload=new_inverse_binds.tobytes()
  doc['bufferViews'].append({'buffer':0,'byteOffset':len(new),'byteLength':len(payload)})
  doc['skins'][0]['inverseBindMatrices']=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(names),'type':'MAT4'});new+=payload
 for semantic,values,component in [('JOINTS_1',top[:,4:].astype(joints.dtype),doc['accessors'][attrs['JOINTS_0']]['componentType']),('WEIGHTS_1',out[:,4:].astype('<f4'),5126)]:
  new+=b'\0'*((-len(new))%4);payload=values.tobytes();view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':len(new),'byteLength':len(payload),'target':34962});attrs[semantic]=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':component,'count':len(pos),'type':'VEC4'});new+=payload
 if left_delta is not None:
  # A pose-controlled left fist: open for rolls, closed for two-hand cuts.
  target={};shape_pos=pos+left_delta;shape_face=np.cross(shape_pos[triangles[:,1]]-shape_pos[triangles[:,0]],shape_pos[triangles[:,2]]-shape_pos[triangles[:,0]])
  shape_normals=np.zeros((count,3))
  for k in range(3):np.add.at(shape_normals,inverse[triangles[:,k]],shape_face)
  shape_normals/=np.maximum(np.linalg.norm(shape_normals,axis=1)[:,None],1e-15)
  left_moved=np.linalg.norm(left_delta,axis=1)>1e-7;normal_delta=np.zeros_like(normals);normal_delta[left_moved]=shape_normals[inverse[left_moved]]-normals[left_moved]
  for semantic,values in [('POSITION',left_delta),('NORMAL',normal_delta)]:
   new+=b'\0'*((-len(new))%4);view=len(doc['bufferViews']);payload=values.astype('<f4').tobytes();doc['bufferViews'].append({'buffer':0,'byteOffset':len(new),'byteLength':len(payload),'target':34962})
   target[semantic]=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(pos),'type':'VEC3','min':values.min(0).astype(float).tolist(),'max':values.max(0).astype(float).tolist()});new+=payload
  prim['targets']=[target];doc['meshes'][0]['weights']=[0];doc['meshes'][0].setdefault('extras',{})['targetNames']=['LeftGrip']
 for semantic in ['POSITION','NORMAL']:
  a=doc['accessors'][attrs[semantic]];data=pos if semantic=='POSITION' else normals;a['min']=data.min(0).astype(float).tolist();a['max']=data.max(0).astype(float).tolist()
 doc['buffers'][0]['byteLength']=len(new);encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);new+=b'\0'*((-len(new))%4)
 dest=ASSETS/(kind+'_mobile.glb');dest.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(new))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(new),b'BIN\0')+new)
 directions=np.array([(a,b,c) for a in [-1,0,1] for b in [-1,0,1] for c in [-1,0,1] if (a,b,c)!=(0,0,0)]);dominant=top[:,0];selected=set()
 for ji,name in enumerate(names):
  if kind=='boss' and not (name.startswith('cape_') or name=='loin'):continue
  candidates=np.flatnonzero(dominant==ji)
  if len(candidates):selected.update(candidates[np.unique(np.argmax(pos[candidates]@directions.T,axis=0))].tolist())
  if kind=='boss':selected.update(candidates[::160].tolist())
 if kind=='boss':
  seed=ASSETS/'boss_contact_vertices.json'
  if seed.exists():selected.update(json.loads(seed.read_text())['vertices'])
 probes=[{'point':pos[vi].astype(float).tolist(),'influences':[{'bone':names[int(b)],'weight':float(w)} for b,w in zip(top[vi],out[vi]) if w>.00001]} for vi in sorted(selected)]
 (ASSETS/(kind+('_cloth_contacts' if kind=='boss' else '_contacts')+'.json')).write_text(json.dumps(probes,separators=(',',':')))
 left_support=np.array([.979114,2.76,-.17] if kind=='boss' else [.44874,.915,.115])
 if kind=='boss':
  normal=np.array([-.479,-.875,-.074]);normal/=np.linalg.norm(normal)
  candidates=np.flatnonzero(result[:,names.index('hand_l')]>.85);projection=pos[candidates]@normal
  left_support=pos[candidates[projection>projection.max()-.004]].mean(0)
 socketdata={'right_grip':socket.tolist(),'left_grip':[-socket[0],socket[1],socket[2]],'left_support':left_support.tolist(),'support_normal':[-.479,-.875,-.074] if kind=='boss' else [-.874,-.441,-.203]}
 (ASSETS/(kind+'_sockets.json')).write_text(json.dumps(socketdata,indent=2))
 return {'kind':kind,'vertices':len(pos),'changed_weights':int(np.sum(np.max(abs(result-original),axis=1)>.02)),'curled_vertices':int(moved.sum()),'floor_probes':len(probes),'source_sha256':hashlib.sha256(raw).hexdigest(),'mobile_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'seam_weight_error':float(np.max(abs(result-u[inverse]))),'socket':socketdata,'preserved':['original GLB','UVs','textures','triangle topology','bone hierarchy and axes']}
if __name__=='__main__':
 report=[repair(k) for k in ['knight','boss']];(ROOT/'artifacts/mobile_skin_repair.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

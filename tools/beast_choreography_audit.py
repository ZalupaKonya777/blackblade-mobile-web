"""Check the authored beast's weight transfers against unchanged combat timing.

This verifies data and support choreography. motion_qa.gd independently inspects
actual native skeleton transforms; curve values alone do not establish motion.
"""
from pathlib import Path
import ast,json,math,re
ROOT=Path(__file__).resolve().parents[1]
def literal(path,name):
 text=path.read_text();begin=text.index('const '+name+'=')+len('const '+name+'=')
 depth=0
 for end in range(begin,len(text)):
  if text[end]=='{':depth+=1
  elif text[end]=='}':
   depth-=1
   if not depth:
    return ast.literal_eval(re.sub(r'\btrue\b','True',text[begin:end+1]))
 raise ValueError('Missing constant '+name)
source=ROOT/'scripts/beast_motion.gd'
rest=literal(source,'REST');base=literal(source,'TRACKS');body=literal(source,'BODY_TRACKS');moves=literal(ROOT/'scripts/beast_moves.gd','ATTACKS')
EXPECTED={'sweep':(1.48,[(.61,.86,340.0)]),'combo':(2.88,[(.61,.86,300.0),(1.35,1.60,320.0),(2.11,2.34,410.0)]),'drag':(1.70,[(.65,.96,350.0)]),'overhead':(2.05,[(1.00,1.19,520.0)]),'lunge':(1.65,[(.65,.93,440.0)]),'leap':(2.75,[(1.42,1.65,500.0)]),'air_blades':(3.20,[]),'spin':(2.05,[(.55,.80,340.0),(1.20,1.42,370.0)]),'death_storm':(3.35,[])}
assert set(moves)==set(body)==set(EXPECTED)
for name,(length,hits) in EXPECTED.items():assert moves[name]['length']==length and [tuple(h) for h in moves[name]['hits']]==hits

def slope(keys,i):
 if i==0 or i==len(keys)-1:return 0.0
 a=(keys[i][1]-keys[i-1][1])/(keys[i][0]-keys[i-1][0]);b=(keys[i+1][1]-keys[i][1])/(keys[i+1][0]-keys[i][0])
 return 0.0 if a*b<=0 else 2*a*b/(a+b)
def curve(keys,time):
 if time<=keys[0][0]:return keys[0][1]
 for i in range(1,len(keys)):
  if time>keys[i][0]:continue
  span=keys[i][0]-keys[i-1][0];u=(time-keys[i-1][0])/span;u2=u*u;u3=u2*u
  return (2*u3-3*u2+1)*keys[i-1][1]+(u3-2*u2+u)*span*slope(keys,i-1)+(-2*u3+3*u2)*keys[i][1]+(u3-u2)*span*slope(keys,i)
 return keys[-1][1]
def sample(name,time):
 pose=rest.copy()
 for layer in [base[name],body[name]]:
  for field,keys in layer.items():pose[field]=curve(keys,time)
 return pose
report=[]
for name,move in moves.items():
 for field,keys in body[name].items():
  assert field in rest,(name,field)
  assert keys[0][0]==0 and keys[-1][0]==move['length'],(name,field,'coverage')
  assert all(a[0]<b[0] for a,b in zip(keys,keys[1:])),(name,field,'time order')
  assert abs(keys[-1][1]-rest[field])<1e-8,(name,field,'return to guard',keys[-1][1],rest[field])
  assert all(math.isfinite(value) for key in keys for value in key)
 samples=[sample(name,move['length']*i/360) for i in range(361)]
 min_contacts=3;bad_support=[]
 for i,q in enumerate(samples):
  if q['flight']>.12:continue
  contacts=int(q['paw_weight']>=.92 and q['paw_y']<.003)+int(q['foot_lift_l']<.003)+int(q['foot_lift_r']<.003)
  min_contacts=min(min_contacts,contacts)
  if contacts<2:bad_support.append(round(move['length']*i/360,4))
 # A simple test catches trying to pick up a hind foot while already rearing.
 assert not bad_support,(name,'unstable unsupported transfer',bad_support[:8])
 if name in ['sweep','combo','drag','spin']:
  for start,end,_ in move['hits']:
   for i in range(61):
    q=sample(name,start+(end-start)*i/60)
    assert q['paw_weight']>=.92 and q['paw_y']<.003,(name,'support paw raised during strike')
    assert q['foot_lift_l']<.003 and q['foot_lift_r']<.003,(name,'hind foot raised during strike')
 q0=sample(name,0);ql=sample(name,move['length']);assert all(abs(ql[f]-q0[f])<1e-7 for f in rest),(name,'pose discontinuity at recovery')
 pelvis=[q['twist']*.35+q['pelvis_yaw'] for q in samples];chest=[q['twist']+q['chest_yaw'] for q in samples]
 entry={'move':name,'samples':len(samples),'pelvis_yaw_range_rad':max(pelvis)-min(pelvis),'chest_yaw_range_rad':max(chest)-min(chest),'root_x_travel_units':max(q['root_x'] for q in samples)-min(q['root_x'] for q in samples),'root_z_travel_units':max(q['root_z'] for q in samples)-min(q['root_z'] for q in samples),'grounded_min_contacts':min_contacts,'timing_unchanged':True,'returns_to_guard':True}
 report.append(entry);print(name,'pelvis %.3f chest %.3f'%(entry['pelvis_yaw_range_rad'],entry['chest_yaw_range_rad']),'min ground contacts',min_contacts)
(ROOT/'artifacts/beast_choreography_curve_audit.json').write_text(json.dumps({'moves':report,'timings_unchanged':True,'sample_count':sum(r['samples'] for r in report)},indent=2))
print('PASS: all nine attack timelines retained; finite/continuous body curves and supported transfers')

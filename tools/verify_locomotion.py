"""Check actual skeleton/contact measurements and fully posed walking skins."""
from pathlib import Path
import json,math
ROOT=Path(__file__).resolve().parents[1]
motion=json.loads((ROOT/'artifacts/locomotion_after.json').read_text())
skins={(r['kind'],r['case']):r for r in json.loads((ROOT/'artifacts/locomotion_skin_after.json').read_text())}
checks=[]
for case in motion['cases']:
    key=(case['kind'],case['case']);m=case['metrics'];skin=skins[key]
    frames=[f for f in motion['frames'] if (f['kind'],f['case'])==key]
    criteria={
        'finite_unit_scale':m['finite'] and max(f['scale_error'] for f in frames)<1e-4,
        'limbs_keep_their_length':m['max_limb_length_error']<1e-4,
        'weapon_follows_palm':m['max_socket_error']<.001,
        'planted_feet_reachable':m['max_plant_error']<.05,
        'body_has_no_large_frame_jump':m['max_pelvis_step']<(.065 if key[0]=='knight' else .055),
        'skin_floor_clearance':math.isfinite(skin['min_skin_y']) and skin['min_skin_y']>-.04,
        'surface_distortion_bounded':skin['max_ratio']<4.5 and skin['p95_ratio']<1.60,
    }
    if key[0]=='boss':
        criteria['support_palm_reachable']=m['max_paw_error']<.005
        criteria['two_ground_supports']=m['min_boss_supports']>=2
    ok=all(criteria.values());checks.append({'kind':key[0],'case':key[1],'ok':ok,'criteria':criteria,'samples':m['samples']})
    print('PASS' if ok else 'FAIL',*key,[name for name,value in criteria.items() if not value])
report={'scenarios':len(checks),'physics_samples':sum(r['samples'] for r in checks),'failures':sum(not r['ok'] for r in checks),'checks':checks}
(ROOT/'artifacts/locomotion_verification.json').write_text(json.dumps(report,indent=2))
print('LOCOMOTION VERIFICATION',report['scenarios'],'scenarios,',report['physics_samples'],'samples,',report['failures'],'failures')
raise SystemExit(bool(report['failures']))

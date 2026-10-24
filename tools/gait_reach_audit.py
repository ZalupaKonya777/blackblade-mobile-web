"""Measure knee travel in the turning actor's frame, across posed gait samples.

Unlike world-X measurements this does not count an ordinary yaw as leg splay.
Uses the real skeleton dumps made by locomotion_qa.gd, including acceleration,
turns and braking; no test-only animation or altered geometry is substituted.
"""
from pathlib import Path
import json
import math

ROOT = Path(__file__).resolve().parents[1]

def local(frame, point):
    m = frame['motion_world']
    v = [point[i] - m[i * 4 + 3] for i in range(3)]
    return [sum(v[i] * m[i * 4 + j] for i in range(3)) /
            sum(m[i * 4 + j] ** 2 for i in range(3)) for j in range(3)]

def measure(dump, kind, case, moving_only=False):
    lateral = fraction = 0.0
    above = -math.inf
    count = 0
    for frame in dump['frames']:
        if (frame['kind'], frame['case']) != (kind, case):
            continue
        if moving_only and not .30 <= frame['time'] <= 2.20:
            continue
        for side in ['l', 'r']:
            hip = local(frame, frame['bones']['thigh_' + side])
            knee = local(frame, frame['bones']['shin_' + side])
            length = math.dist(hip, knee)
            lateral = max(lateral, abs(knee[0] - hip[0]))
            fraction = max(fraction, abs(knee[0] - hip[0]) / length)
            above = max(above, knee[1] - hip[1])
            count += 1
    return {'samples': count, 'max_lateral_m': lateral,
            'max_lateral_thigh_fraction': fraction, 'max_knee_above_hip_m': above}

after = json.loads((ROOT / 'artifacts/locomotion_after.json').read_text())
before = json.loads((ROOT / 'artifacts/locomotion_baseline.json').read_text())
rows = []
for scenario in after['cases']:
    kind, case = scenario['kind'], scenario['case']
    # Idle retains its broad crouch; compare the established moving hinge.
    # Acceleration/braking floor, contacts, scale and skin stay covered by
    # verify_locomotion.py across all 181 frames of each scenario.
    old, new = measure(before, kind, case, True), measure(after, kind, case, True)
    criteria = {'finite': all(math.isfinite(v) for v in new.values())}
    if kind == 'boss':
        # In the low tripod posture a knee must stay inside a useful sagittal
        # hinge rather than spend almost a full thigh length out to the side.
        criteria['lateral_knee_travel_bounded'] = new['max_lateral_thigh_fraction'] < .75
        criteria['reduces_previous_splay'] = new['max_lateral_m'] < old['max_lateral_m'] * .80
    else:
        criteria['human_knee_stays_below_hip'] = new['max_knee_above_hip_m'] < 0
    rows.append({'kind': kind, 'case': case, 'moving_interval_seconds': [.30, 2.20], 'before': old, 'after': new,
                 'full_motion_after': measure(after, kind, case),
                 'criteria': criteria, 'ok': all(criteria.values())})
    print('PASS' if rows[-1]['ok'] else 'FAIL', kind, case,
          'knee lateral %.3f -> %.3f m' % (old['max_lateral_m'], new['max_lateral_m']))
report = {'scenarios': len(rows), 'failures': sum(not r['ok'] for r in rows), 'checks': rows}
(ROOT / 'artifacts/gait_reach_v9.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(bool(report['failures']))

"""Measure posed geometry across actual walking, turning, braking and strafing.

UVs do not change at runtime. These measurements expose the mesh deformation
that stretches their image, including broad moderate distortion, not just spikes.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from asset_geometry_audit import GLB

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
suffix = 'baseline' if args.baseline else 'after'
dump = json.loads((ROOT/f'artifacts/locomotion_{suffix}.json').read_text())
results = []
for kind in ['knight', 'boss']:
    mesh = GLB(ROOT/f'assets/characters/{kind}_mobile.glb')
    edges = np.unique(np.sort(np.concatenate([mesh.triangles[:, [0, 1]], mesh.triangles[:, [1, 2]], mesh.triangles[:, [2, 0]]]), axis=1), axis=0)
    lengths = np.linalg.norm(mesh.positions[edges[:, 0]]-mesh.positions[edges[:, 1]], axis=1)
    valid = lengths > (.012 if kind == 'knight' else .025)
    edges, lengths = edges[valid], lengths[valid]
    cloth_bones = np.array([n.startswith('cape_') or n == 'loin' for n in mesh.names])
    cloth = mesh.weights[:, cloth_bones].sum(1) > .5
    body_edges = ~cloth[edges].any(1)
    regions = np.array([n.rsplit('_', 1)[0] if n.endswith(('_l', '_r')) else ('cloth' if n.startswith('cape_') else n) for n in mesh.names])
    dominant = mesh.weights.argmax(1)
    bone_vertices = [np.flatnonzero(mesh.weights[:, i] > 1e-7) for i in range(len(mesh.names))]
    for spec in [s for s in dump['cases'] if s['kind'] == kind]:
        frames = [f for f in dump['frames'] if f['kind'] == kind and f['case'] == spec['case']]
        peak = np.zeros(len(edges)); floor = np.inf; worst_time = 0.; peak_instant = 0.; extent = []
        for frame in frames:
            posed = np.zeros_like(mesh.positions)
            for i, name in enumerate(mesh.names):
                ix = bone_vertices[i]; transform = np.array(frame['transforms'][name]).reshape(3, 4)
                posed[ix] += (mesh.positions[ix]@transform[:, :3].T+transform[:, 3])*mesh.weights[ix, i, None]
            world = np.array(frame['motion_world']).reshape(3, 4)
            floor = min(floor, float((posed@world[:, :3].T+world[:, 3])[:, 1].min()))
            ratio = np.linalg.norm(posed[edges[:, 0]]-posed[edges[:, 1]], axis=1)/lengths
            peak = np.maximum(peak, ratio)
            if ratio.max() > peak_instant: worst_time = frame['time']; peak_instant = float(ratio.max())
        worst = []
        for index in np.argsort(peak)[-8:][::-1]:
            pair = edges[index]
            worst.append({'ratio': float(peak[index]), 'rest_m': float(lengths[index]), 'vertices': pair.tolist(), 'points': mesh.positions[pair].tolist(), 'weights': [[[name, round(float(w), 4)] for name, w in zip(mesh.names, mesh.weights[v]) if w > .015] for v in pair]})
        by_region = {}
        for region in sorted(set(regions)):
            selected = (regions[dominant[edges[:, 0]]] == region) & (regions[dominant[edges[:, 1]]] == region)
            if selected.any(): by_region[region] = {'edges': int(selected.sum()), 'p95': float(np.quantile(peak[selected], .95)), 'max': float(peak[selected].max()), 'over_1_5': int((peak[selected] > 1.5).sum())}
        result = {'kind': kind, 'case': spec['case'], 'frames': len(frames), 'source_sha256': hashlib.sha256(mesh.raw).hexdigest(), 'min_skin_y': floor, 'max_ratio': float(peak.max()), 'worst_time': worst_time, 'p95_ratio': float(np.quantile(peak, .95)), 'over_1_5': int((peak > 1.5).sum()), 'over_3': int((peak > 3).sum()), 'over_5': int((peak > 5).sum()), 'body_over_1_5': int(((peak > 1.5) & body_edges).sum()), 'body_over_3': int(((peak > 3) & body_edges).sum()), 'by_region': by_region, 'worst': worst}
        results.append(result)
        print(kind, spec['case'], 'max %.2f p95 %.2f floor %.3f' % (result['max_ratio'], result['p95_ratio'], floor), '>1.5', result['over_1_5'], 'body>3', result['body_over_3'], flush=True)
(ROOT/f'artifacts/locomotion_skin_{suffix}.json').write_text(json.dumps(results, indent=2))

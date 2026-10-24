"""Audit animated damage proxies against the rendered, skinned mobile mesh.

Run with the analysis Python environment (NumPy/SciPy), after the native encounter
QA has written artifacts/encounter_pose_samples.json. This tool never runs Godot
or changes assets. Only the requested JSON report is written.

Each sample provides rig-local global bone poses and a motion_transform as
[[basis.x], [basis.y], [basis.z], [origin]], plus world-space hurt_segments.
The older flattened 3x4 row format is also accepted. Optional melee_probes are
{id, old_blade:[[x,y,z],[x,y,z]], blade:[[x,y,z],[x,y,z]], radius:.13}.

Coverage is measured on actual non-cloth vertices and four barycentric samples
per non-cloth triangle, weighted by its posed area. Capsule protrusion uses
exposed core surfaces and radial rays, so inward distance is not called phantom
reach. This is a geometric audit, not a judgment of final combat feel.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import numpy as np

from asset_geometry_audit import GLB

ROOT = Path(__file__).resolve().parents[1]
CORE_BONES = {"pelvis", "spine1", "spine2", "neck", "head"}
BARYCENTRIC = np.array([[1/3, 1/3, 1/3], [.6, .2, .2], [.2, .6, .2], [.2, .2, .6]])


def transform(value):
    """Godot basis columns + origin, or the existing flat row representation."""
    a = np.asarray(value, dtype=float)
    out = np.eye(4)
    if a.shape == (4, 3):
        out[:3, :3] = a[:3].T
        out[:3, 3] = a[3]
    elif a.shape in ((3, 4), (12,)):
        out[:3] = a.reshape(3, 4)
    elif a.shape == (4, 4):
        out = a.copy()
    else:
        raise ValueError(f"Unsupported transform shape: {a.shape}")
    if not np.isfinite(out).all():
        raise ValueError("A sampled transform is not finite")
    return out


def apply(points, matrix):
    return points @ matrix[:3, :3].T + matrix[:3, 3]


def point_segment_distance(points, a, b):
    delta = b-a
    u = np.clip(np.sum((points-a)*delta, axis=-1)/np.maximum(np.sum(delta*delta, axis=-1), 1e-12), 0, 1)
    return np.linalg.norm(points-(a+u[..., None]*delta), axis=-1)


def proxy_gap(points, capsules):
    gap = np.full(len(points), np.inf)
    for a, b, radius in capsules:
        gap = np.minimum(gap, point_segment_distance(points, a, b)-radius)
    return gap


def quantiles(values, weights=None):
    levels = [.05, .5, .9, .95, .99, 1.0]
    if weights is None:
        answer = np.quantile(values, levels)
    else:
        order = np.argsort(values)
        cumulative = np.cumsum(weights[order])
        answer = np.interp(np.array(levels)*cumulative[-1], cumulative, values[order])
    return {str(int(p*100)): float(value) for p, value in zip(levels, answer)}


def ray_triangle_distances(origin, direction, triangles, limit=np.inf):
    if not len(triangles):
        return np.empty(0)
    e1 = triangles[:, 1]-triangles[:, 0]
    e2 = triangles[:, 2]-triangles[:, 0]
    cross = np.cross(direction, e2)
    determinant = np.sum(e1*cross, axis=1)
    valid = np.abs(determinant) > 1e-10
    inv = np.divide(1.0, determinant, out=np.zeros_like(determinant), where=valid)
    offset = origin-triangles[:, 0]
    u = np.sum(offset*cross, axis=1)*inv
    q = np.cross(offset, e1)
    v = np.sum(q*direction, axis=1)*inv
    t = np.sum(e2*q, axis=1)*inv
    return t[valid & (u >= -1e-8) & (v >= -1e-8) & (u+v <= 1+1e-8) & (t >= 0) & (t <= limit)]


def capsule_rays(a, b):
    axis = b-a
    axis /= max(np.linalg.norm(axis), 1e-12)
    seed = np.array([0., 1., 0.]) if abs(axis[1]) < .8 else np.array([1., 0., 0.])
    tangent = np.cross(axis, seed)
    tangent /= max(np.linalg.norm(tangent), 1e-12)
    other = np.cross(axis, tangent)
    angles = np.arange(12)*2*np.pi/12
    ring = np.cos(angles)[:, None]*tangent+np.sin(angles)[:, None]*other
    for fraction in [.2, .5, .8]:
        for direction in ring:
            yield a+(b-a)*fraction, direction
    for end, sign in [(a, -1), (b, 1)]:
        for latitude in [.35, .75]:
            for radial in ring[::2]:
                yield end, radial*np.sqrt(1-latitude*latitude)+axis*latitude*sign


def phantom_core(capsules, body_triangles, tolerance):
    """Outward radial excess; rays without a visible core surface stay unresolved."""
    results = []
    for index, (a, b, radius) in enumerate(capsules[:3]):
        excess, unresolved, hidden, confirmed, worst, worst_confirmed = [], 0, 0, 0, None, None
        for origin, direction in capsule_rays(a, b):
            surface_point = origin+direction*radius
            if any(other != index and point_segment_distance(surface_point, ca, cb) < cr-.005
                   for other, (ca, cb, cr) in enumerate(capsules)):
                hidden += 1
                continue
            hits = ray_triangle_distances(origin, direction, body_triangles, radius+.75)
            if not len(hits):
                unresolved += 1
                continue
            surface = float(hits.max())
            protrusion = max(0.0, radius-surface)
            excess.append(protrusion)
            nearest = float(point_triangle_distance(surface_point, body_triangles).min()) if protrusion > tolerance else None
            if nearest is not None and nearest > tolerance:
                confirmed += 1
                if worst_confirmed is None or nearest > worst_confirmed["nearest_rendered_surface_m"]:
                    worst_confirmed = {"axis_point": origin.tolist(), "surface_point": surface_point.tolist(),
                                       "direction": direction.tolist(), "outward_gap_m": protrusion,
                                       "nearest_rendered_surface_m": nearest}
            if worst is None or protrusion > worst["outward_gap_m"]:
                worst = {"axis_point": origin.tolist(), "direction": direction.tolist(),
                         "capsule_radius_m": radius, "rendered_radius_m": surface,
                         "outward_gap_m": protrusion, "nearest_rendered_surface_m": nearest}
        results.append({"capsule_index": index, "resolved_rays": len(excess),
                        "unresolved_rays": unresolved, "hidden_by_other_capsules": hidden,
                        "radial_candidates_over_tolerance": int(np.sum(np.array(excess) > tolerance)),
                        "rays_over_tolerance": confirmed,
                        "outward_gap_m": quantiles(np.array(excess)) if excess else None,
                        "worst": worst, "worst_confirmed": worst_confirmed})
    return {"tolerance_m": tolerance, "capsules": results,
            "obvious_protrusion": any(item["rays_over_tolerance"] >= 3 for item in results),
            "note": "Only exposed surfaces of the first three torso/head capsules are examined, against all non-cloth body triangles. A flag requires both radial excess and nearest actual surface distance above tolerance. Overlaps hidden by another capsule and unresolved rays are excluded."}


def point_triangle_distance(point, triangles):
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    ab, ac, ap = b-a, c-a, point-a
    normal = np.cross(ab, ac)
    normal2 = np.sum(normal*normal, axis=1)
    height = np.sum(ap*normal, axis=1)
    projection = point-np.divide(height, normal2, out=np.zeros_like(height), where=normal2 > 1e-16)[:, None]*normal
    projected = projection-a
    d00, d01, d11 = np.sum(ab*ab, axis=1), np.sum(ab*ac, axis=1), np.sum(ac*ac, axis=1)
    d20, d21 = np.sum(projected*ab, axis=1), np.sum(projected*ac, axis=1)
    denominator = d00*d11-d01*d01
    v = np.divide(d11*d20-d01*d21, denominator, out=np.full(len(a), -1.), where=np.abs(denominator) > 1e-16)
    w = np.divide(d00*d21-d01*d20, denominator, out=np.full(len(a), -1.), where=np.abs(denominator) > 1e-16)
    inside = (v >= 0) & (w >= 0) & (v+w <= 1) & (normal2 > 1e-16)
    edge = np.minimum.reduce([point_segment_distance(point, a, b), point_segment_distance(point, b, c), point_segment_distance(point, c, a)])
    plane = np.divide(np.abs(height), np.sqrt(normal2), out=np.full(len(a), np.inf), where=normal2 > 1e-16)
    return np.where(inside, plane, edge)


def segment_segments_distance(a, b, c, d):
    """One segment against vectorized segments; checks all closed-box optima."""
    u, v, w = b-a, d-c, a-c
    aa = float(u@u)
    if aa < 1e-16:
        return point_segment_distance(a, c, d)
    bb, cc = np.sum(v*u, axis=1), np.sum(v*v, axis=1)
    dd, ee = np.sum(w*u, axis=1), np.sum(w*v, axis=1)
    def at(s, t):
        return np.linalg.norm(w+np.asarray(s)[..., None]*u-np.asarray(t)[..., None]*v, axis=1)
    safe_cc = np.maximum(cc, 1e-16)
    distance = np.minimum.reduce([
        at(np.zeros(len(c)), np.clip(ee/safe_cc, 0, 1)),
        at(np.ones(len(c)), np.clip((ee+bb)/safe_cc, 0, 1)),
        at(np.clip(-dd/aa, 0, 1), np.zeros(len(c))),
        at(np.clip((bb-dd)/aa, 0, 1), np.ones(len(c))),
    ])
    denominator = aa*cc-bb*bb
    s = np.divide(bb*ee-cc*dd, denominator, out=np.full(len(c), -1.), where=denominator > 1e-16)
    t = np.divide(aa*ee-bb*dd, denominator, out=np.full(len(c), -1.), where=denominator > 1e-16)
    valid = (s >= 0) & (s <= 1) & (t >= 0) & (t <= 1)
    return np.minimum(distance, np.where(valid, at(s, t), np.inf))


def segment_mesh_distance(a, b, triangles):
    delta = b-a
    length = float(np.linalg.norm(delta))
    if length > 1e-10 and len(ray_triangle_distances(a, delta/length, triangles, length)):
        return 0.0
    distance = np.minimum(point_triangle_distance(a, triangles), point_triangle_distance(b, triangles))
    for i, j in [(0, 1), (1, 2), (2, 0)]:
        distance = np.minimum(distance, segment_segments_distance(a, b, triangles[:, i], triangles[:, j]))
    return float(distance.min())


def melee_probes(probes, triangles, capsules, default_radius):
    results = []
    starts = np.array([a for a, _, _ in capsules])
    ends = np.array([b for _, b, _ in capsules])
    radii = np.array([r for _, _, r in capsules])
    for index, probe in enumerate(probes):
        current = np.asarray(probe.get("blade", probe.get("current_blade")), dtype=float)
        previous = np.asarray(probe.get("old_blade", current), dtype=float)
        radius = float(probe.get("radius", default_radius))
        fibers = [(current[0], current[1])]
        fibers.extend((previous[0]*(1-u)+previous[1]*u, current[0]*(1-u)+current[1]*u) for u in np.linspace(0, 1, 6))
        proxy = min(float((segment_segments_distance(a, b, starts, ends)-radii).min()) for a, b in fibers)
        rendered = min(segment_mesh_distance(a, b, triangles) for a, b in fibers)
        results.append({"id": probe.get("id", str(index)), "radius_m": radius,
                        "proxy_hit": proxy <= radius, "rendered_surface_hit": rendered <= radius,
                        "proxy_axis_gap_m": proxy, "rendered_surface_distance_m": rendered,
                        "proxy_hit_without_nearby_rendered_surface": proxy <= radius and rendered > radius+.25})
    return results


class Skin:
    def __init__(self, kind):
        self.mesh = GLB(ROOT/f"assets/characters/{kind}_mobile.glb")
        self.rest_inv = [np.linalg.inv(self.mesh.global_transform(joint)) for joint in self.mesh.doc["skins"][0]["joints"]]
        self.indices = [np.flatnonzero(self.mesh.weights[:, i] > 1e-8) for i in range(len(self.mesh.names))]
        cloth_bones = [i for i, n in enumerate(self.mesh.names) if n.startswith("cape_") or n == "loin"]
        core_bones = [i for i, n in enumerate(self.mesh.names) if n in CORE_BONES]
        cloth = self.mesh.weights[:, cloth_bones].sum(1)
        core = self.mesh.weights[:, core_bones].sum(1)
        self.body_vertices = cloth < .5
        self.body_faces = np.max(cloth[self.mesh.triangles], axis=1) < .5
        self.core_faces = self.body_faces & (np.mean(core[self.mesh.triangles], axis=1) > .55)

    def pose(self, sample):
        posed = np.zeros_like(self.mesh.positions)
        poses = sample.get("bones")
        deltas = sample.get("transforms")
        if poses is None and deltas is None:
            raise ValueError("Sample needs bones (global bone poses) or transforms (rest-to-pose deltas)")
        for i, name in enumerate(self.mesh.names):
            matrix = transform(poses[name]) @ self.rest_inv[i] if poses is not None else transform(deltas[name])
            ix = self.indices[i]
            posed[ix] += apply(self.mesh.positions[ix], matrix)*self.mesh.weights[ix, i, None]
        return apply(posed, transform(sample.get("motion_transform", sample.get("motion_world"))))


def audit(sample, skin, blade_radius, phantom_tolerance, check_phantom):
    world = skin.pose(sample)
    if not np.isfinite(world).all():
        raise ValueError(f"Non-finite posed mesh: {sample['id']}")
    capsules = [(np.array(a, dtype=float), np.array(b, dtype=float), float(r)) for a, b, r in sample["hurt_segments"]]
    triangles = world[skin.mesh.triangles[skin.body_faces]]
    areas = np.linalg.norm(np.cross(triangles[:, 1]-triangles[:, 0], triangles[:, 2]-triangles[:, 0]), axis=1)*.5
    valid = areas > 1e-12
    triangles, areas = triangles[valid], areas[valid]
    surface = np.einsum("kj,njl->nkl", BARYCENTRIC, triangles).reshape(-1, 3)
    area_weights = np.repeat(areas/len(BARYCENTRIC), len(BARYCENTRIC))
    vertex_gap = proxy_gap(world[skin.body_vertices], capsules)
    surface_gap = proxy_gap(surface, capsules)
    result = {"id": sample["id"], "kind": sample.get("kind", "boss"), "capsules": len(capsules),
              "body_vertices": int(skin.body_vertices.sum()), "body_triangles": len(triangles),
              "vertex_covered_percent": float((vertex_gap <= 0).mean()*100),
              "vertex_within_blade_radius_percent": float((vertex_gap <= blade_radius).mean()*100),
              "surface_area_covered_percent": float(area_weights[surface_gap <= 0].sum()/area_weights.sum()*100),
              "surface_area_within_blade_radius_percent": float(area_weights[surface_gap <= blade_radius].sum()/area_weights.sum()*100),
              "vertex_signed_gap_m": quantiles(vertex_gap), "area_signed_gap_m": quantiles(surface_gap, area_weights),
              "melee_probes": melee_probes(sample.get("melee_probes", []), triangles, capsules, blade_radius)}
    if check_phantom:
        result["phantom_core"] = phantom_core(capsules, triangles, phantom_tolerance)
    return result


def local_path(value):
    path = Path(value)
    path = (ROOT/path).resolve() if not path.is_absolute() else path.resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError("Inputs and reports must stay inside this project")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="artifacts/encounter_pose_samples.json")
    parser.add_argument("--output", default="artifacts/encounter_surface_audit.json")
    parser.add_argument("--blade-radius", type=float, default=.13)
    parser.add_argument("--phantom-tolerance", type=float, default=.25)
    parser.add_argument("--skip-phantom", action="store_true")
    parser.add_argument("--max-poses", type=int, default=0)
    args = parser.parse_args()
    source, output = local_path(args.input), local_path(args.output)
    source_bytes = source.read_bytes()
    payload = json.loads(source_bytes)
    samples = payload if isinstance(payload, list) else payload.get("samples", payload.get("poses", payload.get("frames")))
    if not isinstance(samples, list) or not samples:
        raise ValueError("Pose input must contain a nonempty sample list")
    if args.max_poses > 0:
        samples = samples[:args.max_poses]
    skins, results = {}, []
    for sample in samples:
        kind = sample.get("kind", "boss")
        if kind not in skins:
            skins[kind] = Skin(kind)
        result = audit(sample, skins[kind], args.blade_radius, args.phantom_tolerance, not args.skip_phantom)
        results.append(result)
        phantom = result.get("phantom_core", {}).get("obvious_protrusion", False)
        print(f"{result['id']}: rendered body area {result['surface_area_covered_percent']:.2f}% inside proxy, "
              f"{result['surface_area_within_blade_radius_percent']:.2f}% within blade radius; phantom core flag={phantom}", flush=True)
    summary = {"samples": len(results), "min_body_area_within_blade_radius_percent": min(r["surface_area_within_blade_radius_percent"] for r in results),
               "phantom_core_samples": [r["id"] for r in results if r.get("phantom_core", {}).get("obvious_protrusion")],
               "melee_probes": sum(len(r["melee_probes"]) for r in results),
               "proxy_contact_without_nearby_surface": sum(p["proxy_hit_without_nearby_rendered_surface"] for r in results for p in r["melee_probes"])}
    report = {"schema": 1, "input": str(source.relative_to(ROOT)), "input_sha256": hashlib.sha256(source_bytes).hexdigest(),
              "blade_radius_m": args.blade_radius, "phantom_tolerance_m": args.phantom_tolerance,
              "method": "Actual linear-blend skinning; non-cloth vertices; four area-weighted triangle samples; optional real blade/swept-fiber distance against rendered triangles; outward radial core rays.",
              "limits": ["Coverage samples rendered triangles rather than computing exact capsule/triangle surface integrals.",
                         "Core protrusion checks examine torso/head capsules only, exclude hidden capsule overlaps, and ignore cloth. Rays through open gaps are unresolved.",
                         "Melee rendered_surface_hit tests surface distance; a stationary blade wholly enclosed by a closed body may be inside without touching its surface."],
              "meshes": {kind: {"path": str(skin.mesh.path.relative_to(ROOT)), "sha256": hashlib.sha256(skin.mesh.raw).hexdigest()} for kind, skin in skins.items()},
              "summary": summary, "samples": results}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()

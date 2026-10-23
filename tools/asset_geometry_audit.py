"""Read-only numerical audit of supplied geometry, sockets and skin weights.

Run with PYTHONDONTWRITEBYTECODE=1. Geometry, UVs, materials and gameplay
sources are never modified. --write-report writes only the JSON audit artifact.
All distances are root-space metres, with +Y up and +Z forward.
"""
from __future__ import annotations

from pathlib import Path
import argparse
from collections import Counter
import hashlib
import json
import struct

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
DTYPES = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def node_transform(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rotation = np.array([
        [1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
        [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
        [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
    ])
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(node.get("scale", [1, 1, 1]))
    result[:3, 3] = node.get("translation", [0, 0, 0])
    return result


class GLB:
    def __init__(self, path):
        self.path = Path(path)
        self.raw = self.path.read_bytes()
        offset = 12
        while offset < len(self.raw):
            size, kind = struct.unpack_from("<I4s", self.raw, offset)
            payload = self.raw[offset + 8:offset + 8 + size]
            if kind == b"JSON":
                self.doc = json.loads(payload)
            elif kind == b"BIN\0":
                self.binary = payload
            offset += size + 8
        self.parents = {c: i for i, n in enumerate(self.doc["nodes"]) for c in n.get("children", [])}
        self._global = {}
        self.mesh_nodes = [i for i, n in enumerate(self.doc["nodes"]) if "mesh" in n]
        if len(self.mesh_nodes) != 1:
            raise ValueError("Audit expects exactly one mesh node per supplied asset")
        self.node = self.mesh_nodes[0]
        self.primitive = self.doc["meshes"][self.doc["nodes"][self.node]["mesh"]]["primitives"][0]
        self.attributes = self.primitive["attributes"]
        local = self.array(self.attributes["POSITION"]).astype(float)
        transform = self.global_transform(self.node)
        self.positions = (np.c_[local, np.ones(len(local))] @ transform.T)[:, :3]
        self.triangles = self.array(self.primitive["indices"]).reshape(-1, 3).astype(int)
        self.names = []
        self.weights = None
        if self.doc.get("skins"):
            skin = self.doc["skins"][0]
            self.names = [self.doc["nodes"][i]["name"] for i in skin["joints"]]
            self.weights = np.zeros((len(local), len(self.names)))
            for channel in (0, 1):
                if f"JOINTS_{channel}" not in self.attributes:
                    continue
                joints = self.array(self.attributes[f"JOINTS_{channel}"])
                weights = self.array(self.attributes[f"WEIGHTS_{channel}"])
                np.add.at(self.weights, (np.arange(len(local))[:, None], joints), weights)

    def array(self, index):
        accessor = self.doc["accessors"][index]
        view = self.doc["bufferViews"][accessor["bufferView"]]
        dtype = np.dtype(DTYPES[accessor["componentType"]])
        width = WIDTHS[accessor["type"]]
        data = np.ndarray(
            (accessor["count"], width), dtype=dtype, buffer=self.binary,
            offset=view.get("byteOffset", 0) + accessor.get("byteOffset", 0),
            strides=(view.get("byteStride", dtype.itemsize * width), dtype.itemsize),
        ).copy()
        if accessor.get("normalized") and accessor["componentType"] != 5126:
            info = np.iinfo(dtype)
            data = data.astype(float) / info.max
            if info.min < 0:
                data = np.maximum(data, -1)
        return data

    def global_transform(self, index):
        if index not in self._global:
            parent = self.global_transform(self.parents[index]) if index in self.parents else np.eye(4)
            self._global[index] = parent @ node_transform(self.doc["nodes"][index])
        return self._global[index]

    def welded(self, tolerance=1e-5):
        # For analysis only. No positions, indices or UV seam vertices are changed.
        _, inverse = np.unique(np.round(self.positions / tolerance).astype(np.int64), axis=0, return_inverse=True)
        count = inverse.max() + 1
        totals = np.bincount(inverse)
        positions = np.zeros((count, 3))
        np.add.at(positions, inverse, self.positions)
        positions /= totals[:, None]
        weights = None
        if self.weights is not None:
            weights = np.zeros((count, len(self.names)))
            np.add.at(weights, inverse, self.weights)
            weights /= totals[:, None]
        triangles = inverse[self.triangles]
        edges = np.unique(np.sort(np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]]), axis=1), axis=0)
        edges = edges[edges[:, 0] != edges[:, 1]]
        return positions, triangles, edges, weights, inverse


def bounds(points):
    return [points.min(0).tolist(), points.max(0).tolist()] if len(points) else None


def unit(vector):
    return vector / np.linalg.norm(vector)


def section(mesh, y):
    """Intersect all triangles with a horizontal plane, without vertex-density bias."""
    tri = mesh.positions[mesh.triangles]
    relevant = (tri[:, :, 1].min(1) <= y) & (tri[:, :, 1].max(1) >= y)
    tri = tri[relevant]
    points = []
    for a, b in [(0, 1), (1, 2), (2, 0)]:
        p, q = tri[:, a], tri[:, b]
        crossing = (p[:, 1] - y) * (q[:, 1] - y) < 0
        p, q = p[crossing], q[crossing]
        amount = (y - p[:, 1]) / (q[:, 1] - p[:, 1])
        points.extend(p + (q - p) * amount[:, None])
    return np.array(points)


def profile(mesh, step=0.01):
    rows = []
    for y in np.arange(np.ceil(mesh.positions[:, 1].min() / step) * step, mesh.positions[:, 1].max(), step):
        points = section(mesh, y)
        if len(points):
            low, high = points.min(0), points.max(0)
            rows.append([float(y), *(high - low)[[0, 2]].tolist(), *((low + high) / 2)[[0, 2]].tolist()])
    return rows


def baseline(mesh):
    return {
        "file": str(mesh.path.relative_to(ROOT)), "sha256": hashlib.sha256(mesh.raw).hexdigest(),
        "vertices": len(mesh.positions), "triangles": len(mesh.triangles),
        "bounds_m": bounds(mesh.positions), "mesh_root_transform": mesh.global_transform(mesh.node).tolist(),
    }


def ray_samples(mesh, y, z, side):
    """Surface intersections and interpolated skin weights along a palm X ray."""
    tri = mesh.positions[mesh.triangles]
    origin = tri[:, 0, 1:]
    a = tri[:, 1, 1:] - origin
    b = tri[:, 2, 1:] - origin
    p = np.array([y, z]) - origin
    determinant = a[:, 0]*b[:, 1] - b[:, 0]*a[:, 1]
    valid = np.abs(determinant) > 1e-12
    u = np.zeros(len(tri))
    v = np.zeros(len(tri))
    u[valid] = (p[valid, 0]*b[valid, 1] - b[valid, 0]*p[valid, 1]) / determinant[valid]
    v[valid] = (a[valid, 0]*p[valid, 1] - p[valid, 0]*a[valid, 1]) / determinant[valid]
    valid &= (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1 + 1e-7)
    x = tri[:, 0, 0] + u*(tri[:, 1, 0] - tri[:, 0, 0]) + v*(tri[:, 2, 0] - tri[:, 0, 0])
    # Separate the selected hand from the torso and the other hand.
    valid &= x*side > (0.39 if mesh.path.stem == "knight" else 0.65)
    indices = np.flatnonzero(valid)
    indices = indices[np.argsort(x[indices])]
    result = []
    for index in indices:
        if result and abs(result[-1]["point_m"][0] - x[index]) < 1e-6:
            continue
        barycentric = np.array([1 - u[index] - v[index], u[index], v[index]])
        weights = barycentric @ mesh.weights[mesh.triangles[index]]
        result.append({
            "point_m": [float(x[index]), y, z], "triangle": int(index),
            "barycentric": barycentric.tolist(),
            "weights": {name: float(weight) for name, weight in zip(mesh.names, weights) if weight > 1e-7},
        })
    return result


def ray_midpoint(mesh, y, z, side):
    samples = ray_samples(mesh, y, z, side)
    if len(samples) < 2:
        raise ValueError(f"Palm sample did not cross two surfaces: {mesh.path}, {y}, {z}")
    return (np.array(samples[0]["point_m"]) + np.array(samples[-1]["point_m"])) / 2


def weapon_landmarks(mesh):
    player = mesh.path.stem == "player_sword"
    grip_range = (0.85, 1.03) if player else (-0.01, 0.17)
    guard_range = (0.77, 0.84) if player else (0.18, 0.32)
    centres = []
    for y in np.linspace(*grip_range, 101):
        points = section(mesh, y)
        centres.append((points.min(0) + points.max(0)) / 2)
    grip = np.mean(centres, axis=0)
    positions = mesh.positions
    wings = positions[(positions[:, 1] >= guard_range[0]) & (positions[:, 1] <= guard_range[1])]
    left = wings[wings[:, 0].argmin()]
    right = wings[wings[:, 0].argmax()]
    tip = positions[positions[:, 1].argmin() if player else positions[:, 1].argmax()]
    pommel = positions[positions[:, 1].argmax() if player else positions[:, 1].argmin()]
    middle_y = float(np.mean(grip_range))
    points = section(mesh, middle_y)
    dimensions = points.max(0) - points.min(0)
    scale = 1 if player else 1.38
    info = {
        "usable_grip_y_range_m": list(grip_range),
        "grip_center_m": grip.tolist(),
        "grip_section_xz_size_m": dimensions[[0, 2]].tolist(),
        "pommel_tip_m": pommel.tolist(),
        "guard_wing_endpoints_m": [left.tolist(), right.tolist()],
        "guard_wing_midpoint_m": ((left + right)/2).tolist(),
        "crossguard_axis_nominal": [1, 0, 0],
        "crossguard_extreme_chord_axis": unit(right - left).tolist(),
        "guard_core_y_range_m": [0.79, 0.825] if player else [0.185, 0.31],
        "guard_core_reference_m": [0, 0.805, 0] if player else [0, 0.2455, 0],
        "blade_shoulder_reference_m": [0, 0.775, 0] if player else [0, 0.31, 0],
        "blade_axis_nominal": [0, -1, 0] if player else [0, 1, 0],
        "blade_tip_m": tip.tolist(),
        "grip_to_tip_axis": unit(tip - grip).tolist(),
        "grip_to_tip_distance_m": float(np.linalg.norm(tip - grip)),
        "runtime_uniform_scale": scale,
        "runtime_grip_to_tip_distance_m": float(np.linalg.norm(tip - grip) * scale),
        "landmark_method": "Plane/triangle section envelope centres over the cylindrical grip; exact tip vertex; anatomical grip/collar boundaries selected from the section profile. Guard/shoulder references have about 5-10 mm semantic uncertainty.",
    }
    if player:
        info["two_hand_grip_samples_m"] = {}
        for label, y in [("right_near_guard", 0.89), ("left_near_pommel", 0.99)]:
            points = section(mesh, y)
            info["two_hand_grip_samples_m"][label] = ((points.min(0) + points.max(0))/2).tolist()
    return info


def hand_landmarks(mesh, meta):
    knight = mesh.path.stem == "knight"
    # Semantic sampling planes were selected after inspecting numerical sections
    # and orthographic triangle projections in memory. They exclude fingertips
    # and the proximal cuff. The resulting points are exact for those planes;
    # the anatomical interpretation is intentionally approximate.
    queries = [(0.93, 0.115), (0.97, 0.11), (0.89, 0.115), (0.93, 0.075), (0.93, 0.145)] if knight else [
        (2.76, -0.17), (2.845, -0.17), (2.70, -0.17), (2.76, -0.23), (2.76, -0.10),
    ]
    output = {}
    for side_name, side in [("r", -1), ("l", 1)]:
        palm, wrist, finger_root, width_a, width_b = [ray_midpoint(mesh, *query, side) for query in queries]
        longitudinal = unit(finger_root - wrist)
        width = width_b - width_a
        width = unit(width - longitudinal*np.dot(longitudinal, width))
        inward_normal = unit(np.cross(longitudinal, width)) * side
        head = np.array(meta["bones"]["hand_" + side_name]["head"])
        tail = np.array(meta["bones"]["hand_" + side_name]["tail"])
        samples = ray_samples(mesh, *queries[0], side)
        surfaces = [samples[0], samples[-1]]
        mean_weights = {name: sum(sample["weights"].get(name, 0) for sample in surfaces)/2 for name in mesh.names}
        mean_weights = {name: weight for name, weight in mean_weights.items() if weight > 1e-6}
        inner = surfaces[-1] if side < 0 else surfaces[0]
        normals = mesh.array(mesh.attributes["NORMAL"])
        inner_normal = unit(np.array(inner["barycentric"]) @ normals[mesh.triangles[inner["triangle"]]])
        # The actual grasp should sit nearer the knuckle row than the geometric
        # centre of the palm, so that the open digits can reach around it.
        grasp_yz = (0.915, 0.115) if knight else (2.735, -0.17)
        grasp_samples = ray_samples(mesh, *grasp_yz, side)
        grasp_surface = grasp_samples[-1] if side < 0 else grasp_samples[0]
        grasp_normal = unit(np.array(grasp_surface["barycentric"]) @ normals[mesh.triangles[grasp_surface["triangle"]]])
        radial = grasp_normal.copy()
        radial[2] = 0  # Orthogonal to the nominal +Z rest-space handle axis.
        radial = unit(radial)
        handle_radius = 0.017 if knight else 0.0443
        cavity = np.array(grasp_surface["point_m"]) + radial*handle_radius
        output[side_name] = {
            "palm_core_m": palm.tolist(), "bone_head_m": head.tolist(),
            "bone_head_to_palm_offset_m": (palm-head).tolist(),
            "bone_head_to_palm_distance_m": float(np.linalg.norm(palm-head)),
            "bone_longitudinal_axis": unit(tail-head).tolist(),
            "geometric_wrist_reference_m": wrist.tolist(),
            "finger_root_reference_m": finger_root.tolist(),
            "geometric_wrist_to_palm_offset_m": (palm-wrist).tolist(),
            "geometric_fingers_axis_approx": longitudinal.tolist(),
            "palm_width_handle_axis_approx": width.tolist(),
            "palm_inward_normal_approx": inward_normal.tolist(),
            "palm_crossing_surface_samples": surfaces,
            "palm_mean_surface_weights": mean_weights,
            "open_palm_support_surface_m": inner["point_m"],
            "open_palm_support_surface_normal": inner_normal.tolist(),
            "distal_grasp_surface_m": grasp_surface["point_m"],
            "distal_grasp_surface_normal": grasp_normal.tolist(),
            "recommended_grasp_cavity_center_m": cavity.tolist(),
            "bone_head_to_grasp_cavity_offset_m": (cavity-head).tolist(),
            "grasp_handle_axis_nominal": [0, 0, 1],
            "grasp_handle_radius_m_including_runtime_weapon_scale": handle_radius,
            "interpretation": "Palm core lies inside the solid mesh. A handle centre resting against an open palm needs an offset from the inward surface by its radius, or a local finger-closing pose. It cannot be seated physically by translating an open hand alone.",
            "anatomical_uncertainty_m": 0.005 if knight else 0.015,
            "orientation_note": "Approximate geometric wrist/finger/width landmarks; use the skin's actual rest basis when constructing the socket transform, not JSON head-to-tail alone.",
        }
    positions, _, edges, _, _ = mesh.welded()
    cutoff = 0.87 if knight else 2.70
    mask = (positions[:, 0] < (-0.4 if knight else -0.95)) & (positions[:, 1] > (0.8 if knight else 2.5)) & (positions[:, 1] < cutoff)
    if knight:
        mask &= positions[:, 2] > 0.04
    selected = np.flatnonzero(mask)
    remap = np.full(len(positions), -1)
    remap[selected] = np.arange(len(selected))
    subset_edges = edges[mask[edges].all(1)]
    graph = coo_matrix((np.ones(2*len(subset_edges)), (
        np.r_[remap[subset_edges[:, 0]], remap[subset_edges[:, 1]]],
        np.r_[remap[subset_edges[:, 1]], remap[subset_edges[:, 0]]],
    )), shape=(len(selected), len(selected))).tocsr()
    _, labels = connected_components(graph, directed=False)
    components = []
    for label, size in Counter(labels).most_common():
        if size >= 6:
            p = positions[selected[labels == label]]
            components.append({"vertices": int(size), "bounds_m": bounds(p)})
    output["open_digits_evidence"] = {
        "right_distal_cutoff_y_m": cutoff,
        "disconnected_distal_components_min_6_vertices": components,
        "conclusion": "Open gauntlet: four separate distal finger lobes plus the proximal side thumb." if knight else "Open claw: five separate distal digit lobes remain disconnected below y=2.70 m.",
        "existing_digit_bones": [n for n in mesh.names if any(s in n.lower() for s in ["finger", "thumb", "index", "pinky"])],
    }
    # Seed the individually disconnected distal components; a closure tool can
    # grow these up to their knuckle row without assigning by UV vertex index.
    seed_y = 0.875 if knight else 2.70
    mask = (positions[:, 0] < (-0.4 if knight else -0.95)) & (positions[:, 1] > (0.8 if knight else 2.5)) & (positions[:, 1] < seed_y)
    if knight:
        mask &= positions[:, 2] > 0.04
    selected = np.flatnonzero(mask)
    remap = np.full(len(positions), -1)
    remap[selected] = np.arange(len(selected))
    subset_edges = edges[mask[edges].all(1)]
    graph = coo_matrix((np.ones(2*len(subset_edges)), (
        np.r_[remap[subset_edges[:, 0]], remap[subset_edges[:, 1]]],
        np.r_[remap[subset_edges[:, 1]], remap[subset_edges[:, 0]]],
    )), shape=(len(selected), len(selected))).tocsr()
    _, labels = connected_components(graph, directed=False)
    components = []
    for label, size in Counter(labels).items():
        if size < 6:
            continue
        p = positions[selected[labels == label]]
        proximal = p[p[:, 1] > seed_y - (0.01 if knight else 0.025)]
        tip = p[p[:, 1].argmin()]
        components.append({
            "vertices": int(size), "bounds_m": bounds(p),
            "proximal_seed_center_m": proximal.mean(0).tolist(),
            "tip_m": tip.tolist(), "distal_axis_approx": unit(tip-proximal.mean(0)).tolist(),
        })
    components.sort(key=lambda item: item["proximal_seed_center_m"][2])
    mcp_queries = [(0.895, z) for z in [0.075, 0.097, 0.124, 0.15]] if knight else [(2.715, z) for z in [-0.26, -0.225, -0.155, -0.04]]
    thumb_query = (0.945, 0.164) if knight else (2.745, 0.0)
    output["right_grip_closure_guidance"] = {
        "digit_component_seed_y_max_m": seed_y,
        "digit_components_sorted_by_z": components,
        "four_main_MCP_references_m": [ray_midpoint(mesh, *query, -1).tolist() for query in mcp_queries],
        "thumb_MCP_reference_m": ray_midpoint(mesh, *thumb_query, -1).tolist(),
        "candidate_hand_envelope": {"x_max": -0.4, "y_range": [0.825, 1.00], "z_min": 0.05} if knight else {"x_max": -0.95, "y_range": [2.54, 2.87], "z_range": [-0.31, 0.04]},
        "rigid_palm_and_digit_y_max_m": 0.955 if knight else 2.79,
        "gradual_forearm_collar_y_range_m": [0.955, 1.005] if knight else [2.79, 2.89],
        "digit_rotation_ramp_y_max_m": 0.905 if knight else 2.725,
        "thumb_seed": {"x_max": -0.4, "y_range": [0.88, 0.96], "z_min": 0.15, "disambiguation": "Keep index separate using topology and proximal thumb y>0.905,z>0.157."} if knight else {"component": "Largest-Z distal component; MCP at z=0.0. Keep it separate from the adjacent index."},
        "closure_rule": "For the right hand, positive rotation about the nominal +Z handle axis bends the four main digits from -Y towards inward +X. Use segment arcs at MCP/PIP/DIP, with a smooth short proximal collar. Grow distal component seeds to the knuckle row on welded topology. Keep palm fixed; do not compress the whole palm to the cylinder.",
        "thumb_rule": "Adduct the largest-Z thumb towards -Z and inward +X, then curl about its own MCP. Do not reuse the four-finger transform for the thumb.",
        "target_rule": "Target distance from each finger's centreline to the handle axis = measured handle radius + local finger half-thickness. Preserve digit lengths and weld-equivalent vertex transforms; do not alter UV coordinates or indices.",
        "mask_warning": "The boxes are conservative local starting regions, not a substitute for topology growth and a short smooth collar. Broad forearm/cuff vertices should not be forced to the hand or curled.",
    }
    return output


def bone_distances(names, meta):
    parents = {name: bone["parent"] for name, bone in meta["bones"].items()}
    result = np.zeros((len(names), len(names)), dtype=int)
    for i, name in enumerate(names):
        ancestors = {}
        node, distance = name, 0
        while node is not None:
            ancestors[node] = distance
            node, distance = parents[node], distance + 1
        for j, other in enumerate(names):
            node, distance = other, 0
            while node not in ancestors:
                node, distance = parents[node], distance + 1
            result[i, j] = distance + ancestors[node]
    return result


def skin_audit(mesh, meta):
    positions, triangles, edges, weights, inverse = mesh.welded()
    names = mesh.names
    cloth_bones = np.array([name.startswith("cape_") for name in names])
    cloth = weights[:, cloth_bones].sum(1)
    dominant = weights.argmax(1)
    length = np.linalg.norm(positions[edges[:, 0]] - positions[edges[:, 1]], axis=1)
    variation = np.abs(weights[edges[:, 0]] - weights[edges[:, 1]]).sum(1)/2
    distance = bone_distances(names, meta)
    far = distance[dominant[edges[:, 0]], dominant[edges[:, 1]]] >= 4
    knight = mesh.path.stem == "knight"
    short = 0.015 if knight else 0.03
    bad = far & (variation > 0.65) & (length < short)
    cloth_body = cloth_bones[dominant[edges[:, 0]]] != cloth_bones[dominant[edges[:, 1]]]
    a, b = dominant[edges[:, 0]], dominant[edges[:, 1]]
    codes = np.minimum(a, b)*len(names) + np.maximum(a, b)
    worst = []
    for code, count in Counter(codes[bad]).most_common(15):
        mask = bad & (codes == code)
        worst.append({
            "bones": [names[code//len(names)], names[code % len(names)]],
            "edges": int(count), "bounds_m": bounds(positions[np.unique(edges[mask])]),
            "edge_length_mm_min_median_max": np.quantile(length[mask]*1000, [0, 0.5, 1]).tolist(),
            "weight_TV_min_median_max": np.quantile(variation[mask], [0, 0.5, 1]).tolist(),
        })
    arm_x, arm_lo, arm_hi, leg_x0, leg_x1, leg_lo, leg_hi, leg_z = (0.36, 0.82, 1.25, 0.08, 0.25, 0.08, 0.50, 0.11) if knight else (0.90, 2.40, 2.90, 0.16, 0.52, 0.16, 1.02, 0.23)
    p = positions
    regions = {
        "outer_arms": (np.abs(p[:, 0]) > arm_x) & (p[:, 1] > arm_lo) & (p[:, 1] < arm_hi),
        "lower_legs": (np.abs(p[:, 0]) > leg_x0) & (np.abs(p[:, 0]) < leg_x1) & (p[:, 1] > leg_lo) & (p[:, 1] < leg_hi) & (np.abs(p[:, 2]) < leg_z),
    }
    if knight:
        regions["right_palm"] = (p[:, 0] < -0.4) & (p[:, 1] > 0.90) & (p[:, 1] < 0.96) & (p[:, 2] > 0.07) & (p[:, 2] < 0.15)
    else:
        regions["right_palm"] = (p[:, 0] < -0.95) & (p[:, 1] > 2.72) & (p[:, 1] < 2.85) & (p[:, 2] > -0.25) & (p[:, 2] < -0.05)
    region_stats = {}
    for label, mask in regions.items():
        values = cloth[mask]
        region_stats[label] = {
            "welded_vertices": int(mask.sum()), "bounds_m": bounds(p[mask]),
            "mean_cape_weight": float(values.mean()),
            "fraction_cape_weight_gt_0_05": float(np.mean(values > 0.05)),
            "fraction_cape_weight_gt_0_5": float(np.mean(values > 0.5)),
            "max_cape_weight": float(values.max()),
            "cape_gt_0_5_bounds_m": bounds(p[mask & (cloth > 0.5)]),
        }
    # Check duplicated UV seam positions for divergent bindings. Averaging in
    # welded() is only an audit convenience; no actual accessor is altered.
    seam_error = np.abs(mesh.weights - weights[inverse]).max(1)
    _, exact_inverse = np.unique(mesh.positions, axis=0, return_inverse=True)
    exact_mean = np.zeros((exact_inverse.max()+1, len(names)))
    np.add.at(exact_mean, exact_inverse, mesh.weights)
    exact_mean /= np.bincount(exact_inverse)[:, None]
    exact_error = np.abs(mesh.weights - exact_mean[exact_inverse]).max(1)
    seam_examples, used = [], set()
    for index in np.argsort(exact_error)[::-1]:
        group = exact_inverse[index]
        if exact_error[index] <= 0.001 or len(seam_examples) >= 3:
            break
        if group in used:
            continue
        used.add(group)
        copies = np.flatnonzero(exact_inverse == group)
        seam_examples.append({
            "point_m": mesh.positions[index].tolist(),
            "max_weight_error_from_group_mean": float(exact_error[index]),
            "copies": [{names[j]: float(row[j]) for j in np.flatnonzero(row > 0.001)} for row in mesh.weights[copies]],
        })
    return {
        "weld_tolerance_m": 1e-5, "welded_vertices": len(positions), "edges": len(edges),
        "weight_sum_min_max": [float(weights.sum(1).min()), float(weights.sum(1).max())],
        "max_adjacent_weight_total_variation": float(variation.max()),
        "short_edge_threshold_m": short, "far_bone_threshold_tree_edges": 4,
        "hard_weight_jump_threshold_TV": 0.65,
        "short_hard_far_edges": int(bad.sum()),
        "short_hard_far_cloth_body_edges": int((bad & cloth_body).sum()),
        "worst_bone_pairs": worst, "region_cape_statistics": region_stats,
        "region_warning": "Anatomical boxes may include nearby cloth. Region fractions flag influence overlap; actual connected-triangle weight cliffs are stronger evidence of limb/cloth contamination.",
        "uv_seam_vertices_weight_error_gt_0_001": int(np.sum(seam_error > 0.001)),
        "uv_seam_max_weight_error": float(seam_error.max()),
        "exact_XYZ_seam_vertices_weight_error_gt_0_001": int(np.sum(exact_error > 0.001)),
        "exact_XYZ_seam_max_weight_error": float(exact_error.max()),
        "exact_XYZ_seam_examples": seam_examples,
    }


def preserved_attributes(a, b):
    result = {}
    for semantic in ["POSITION", "NORMAL", "TEXCOORD_0"]:
        x, y = a.array(a.attributes[semantic]), b.array(b.attributes[semantic])
        result[semantic] = {"equal": bool(np.array_equal(x, y)), "sha256": hashlib.sha256(x.tobytes()).hexdigest()}
    result["indices_equal"] = bool(np.array_equal(a.triangles, b.triangles))
    result["nodes_equal"] = a.doc["nodes"] == b.doc["nodes"]
    result["skins_equal"] = a.doc["skins"] == b.doc["skins"]
    result["inverse_bind_matrices_equal"] = bool(np.array_equal(
        a.array(a.doc["skins"][0]["inverseBindMatrices"]), b.array(b.doc["skins"][0]["inverseBindMatrices"]),
    ))
    result["materials_equal"] = a.doc.get("materials") == b.doc.get("materials")
    result["embedded_images_equal"] = all(
        a.binary[a.doc["bufferViews"][x["bufferView"]].get("byteOffset", 0):a.doc["bufferViews"][x["bufferView"]].get("byteOffset", 0)+a.doc["bufferViews"][x["bufferView"]]["byteLength"]]
        == b.binary[b.doc["bufferViews"][y["bufferView"]].get("byteOffset", 0):b.doc["bufferViews"][y["bufferView"]].get("byteOffset", 0)+b.doc["bufferViews"][y["bufferView"]]["byteLength"]]
        for x, y in zip(a.doc.get("images", []), b.doc.get("images", []))
    ) and len(a.doc.get("images", [])) == len(b.doc.get("images", []))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-report", action="store_true")
    parser.add_argument("--profiles", action="store_true")
    args = parser.parse_args()
    report = {"units": "metres", "space": "GLB scene root; +Y up, +Z forward", "assets": {}}
    loaded = {}
    for folder, name in [("weapons", "player_sword"), ("weapons", "boss_sword"), ("characters", "knight"), ("characters", "boss"), ("characters", "boss_mobile")]:
        mesh = GLB(ASSETS / folder / (name + ".glb"))
        loaded[name] = mesh
        info = baseline(mesh)
        if folder == "weapons":
            info["weapon_landmarks"] = weapon_landmarks(mesh)
        else:
            metadata = json.loads((ASSETS / "characters" / ("knight.json" if name == "knight" else "boss.json")).read_text())
            info["hands"] = hand_landmarks(mesh, metadata)
            info["skin_audit"] = skin_audit(mesh, metadata)
        if args.profiles and folder == "weapons":
            info["section_columns"] = ["y", "x_width", "z_depth", "x_center", "z_center"]
            info["sections_m"] = profile(mesh)
        report["assets"][name] = info
    report["boss_mobile_preserves_source"] = preserved_attributes(loaded["boss"], loaded["boss_mobile"])
    report["recommendations"] = [
        "Place the weapon with T.origin = animated_socket - T.basis * source_grip_center; player blade is -Y, boss blade is +Y. Derive collision/trails from the transformed measured tip, rather than a scalar tip on assumed +Y.",
        "For a two-hand player grip use the near-guard source sample y=0.89 for the right palm and y=0.99 for the left palm. Preserve their 0.10 m separation along the handle.",
        "Make palm/gauntlet and distal finger weights rigid to their hand bone, with a short gradual collar into forearm weights. Existing boss_mobile palm is predominantly upper/forearm weighted, so a hand-only socket otherwise diverges from the skin.",
        "Both assets have open fingers and no digit bones. A physically closed grip requires local finger articulation or a small local, UV-preserving grip variant; socket translation cannot close the digits.",
        "Repair knight weights with welded-for-solving topology and identical seam weights; preserve actual mesh positions, UVs, normals, textures and indices. Restrict cloak influence to actual cloth using seeded local regions; avoid the present flat z≈-0.082 cutoff through calves/hips.",
        "Protect rigid shin/boot and arm-plate patches from global weight diffusion, and smooth only narrow joint/cloth attachment collars. Eight weights can retain broad attachment blends without abrupt truncation.",
        "boss_mobile removed hard cape/limb edges, but diffuse palm binding and runtime upper/forearm uniform scale=1.6 remain deformation risks. Resolve the hand binding/socket together; smoothing alone cannot correct the anatomical wrist location.",
    ]
    encoded = json.dumps(report, indent=2)
    if args.write_report:
        (ROOT / "artifacts" / "asset_geometry_audit.json").write_text(encoded + "\n")
    print(encoded)


if __name__ == "__main__":
    main()

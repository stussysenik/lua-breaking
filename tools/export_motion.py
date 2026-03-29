#!/usr/bin/env python3
"""
export_motion.py — Export bboy-analytics motion data to JSON for Love2D visualization.

Converts joints.npy + world_state scalars → JSON format readable by lua-breaking.

Usage:
    python tools/export_motion.py \
        --joints path/to/joints.npy \
        --output data/bcone_seq4.json \
        --fps 29.97 \
        --source bcone_seq4 \
        --model josh

Optional (if available):
    --audio-beats path/to/beats.npy
    --audio-downbeats path/to/downbeats.npy
    --musicality-mu 0.72
    --musicality-tau 0.15
    --brace-segments path/to/segments.yaml
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np


def compute_velocities(joints_3d: np.ndarray, fps: float) -> np.ndarray:
    """Compute per-joint velocity via finite differences. Shape: (T, J, 3)."""
    vel = np.zeros_like(joints_3d)
    vel[1:] = (joints_3d[1:] - joints_3d[:-1]) * fps
    return vel


def compute_kinetic_energy(velocities: np.ndarray, mass: float = 1.0) -> np.ndarray:
    """K(t) = (1/2) * m * Σ_j ||v_j(t)||². Shape: (T,)."""
    return 0.5 * mass * np.sum(velocities ** 2, axis=(1, 2))


def compute_compactness(joints_3d: np.ndarray) -> np.ndarray:
    """C(t) = (1/J) Σ_j ||p_j - centroid||. Shape: (T,)."""
    centroid = joints_3d.mean(axis=1, keepdims=True)  # (T, 1, 3)
    dists = np.linalg.norm(joints_3d - centroid, axis=2)  # (T, J)
    return dists.mean(axis=1)


def compute_com(joints_3d: np.ndarray) -> np.ndarray:
    """Approximate center of mass as pelvis position (joint 0). Shape: (T, 3)."""
    return joints_3d[:, 0, :]


CONTACT_JOINTS = {
    "l_ankle": 7,   # 0-indexed
    "r_ankle": 8,
    "l_foot": 10,
    "r_foot": 11,
    "l_wrist": 20,
    "r_wrist": 21,
    "l_hand": 22,
    "r_hand": 23,
}


def compute_contacts(joints_3d: np.ndarray, threshold: float = 0.10) -> list[dict]:
    """Detect ground contacts by joint height. Returns per-frame contact dicts."""
    contacts = []
    for t in range(joints_3d.shape[0]):
        frame_contacts = {}
        for name, idx in CONTACT_JOINTS.items():
            height = joints_3d[t, idx, 1]  # Y is up
            confidence = max(0, 1.0 - height / threshold)
            frame_contacts[name] = round(float(confidence), 3)
        contacts.append(frame_contacts)
    return contacts


JOINT_NAMES = [
    "pelvis", "l_hip", "r_hip", "spine1", "l_knee", "r_knee",
    "spine2", "l_ankle", "r_ankle", "spine3", "l_foot", "r_foot",
    "neck", "l_collar", "r_collar", "head", "l_shoulder", "r_shoulder",
    "l_elbow", "r_elbow", "l_wrist", "r_wrist", "l_hand", "r_hand",
]


def export(args):
    # Load joints
    joints_3d = np.load(args.joints)  # Expected shape: (T, 24, 3)
    assert joints_3d.ndim == 3, f"Expected 3D array, got shape {joints_3d.shape}"
    T, J, D = joints_3d.shape
    assert J == 24, f"Expected 24 joints, got {J}"
    assert D == 3, f"Expected 3D coordinates, got {D}D"

    fps = args.fps
    print(f"[export] {T} frames, {J} joints, {fps} fps, {T/fps:.2f}s")

    # Compute derived quantities
    velocities = compute_velocities(joints_3d, fps)
    kinetic_energy = compute_kinetic_energy(velocities)
    compactness = compute_compactness(joints_3d)
    com = compute_com(joints_3d)
    contacts = compute_contacts(joints_3d)

    # Build frames
    frames = []
    for t in range(T):
        frame = {
            "t": round(t / fps, 4),
            "joints_3d": joints_3d[t].tolist(),
            "velocity": velocities[t].tolist(),
            "kinetic_energy": round(float(kinetic_energy[t]), 4),
            "compactness": round(float(compactness[t]), 4),
            "contacts": contacts[t],
            "com": com[t].tolist(),
            "segment": "unknown",  # filled from BRACE if available
        }
        frames.append(frame)

    # Build output
    output = {
        "source": args.source,
        "model": args.model,
        "fps": fps,
        "joint_names": JOINT_NAMES,
        "frames": frames,
    }

    # Audio (optional)
    audio = {}
    if args.audio_beats:
        audio["beats"] = np.load(args.audio_beats).tolist()
    if args.audio_downbeats:
        audio["downbeats"] = np.load(args.audio_downbeats).tolist()
    if audio:
        output["audio"] = audio

    # Musicality (optional)
    if args.musicality_mu is not None:
        output["musicality"] = {
            "mu": args.musicality_mu,
            "grade": mu_to_grade(args.musicality_mu),
            "optimal_tau": args.musicality_tau or 0,
        }

    # Write
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(output, f, separators=(",", ":"))

    size_mb = out_path.stat().st_size / (1024 * 1024)
    print(f"[export] Written to {out_path} ({size_mb:.1f} MB)")


def mu_to_grade(mu: float) -> str:
    """Grade thresholds match lua-breaking sections/3_3_musicality."""
    if mu >= 0.90:
        return "S"
    elif mu >= 0.75:
        return "A"
    elif mu >= 0.55:
        return "B"
    elif mu >= 0.35:
        return "C"
    return "D"


def main():
    parser = argparse.ArgumentParser(description="Export bboy-analytics data for Love2D")
    parser.add_argument("--joints", required=True, help="Path to joints.npy (T, 24, 3)")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--fps", type=float, default=29.97, help="Frames per second")
    parser.add_argument("--source", default="unknown", help="Source clip name")
    parser.add_argument("--model", default="josh", help="Model name (josh/gvhmr)")
    parser.add_argument("--audio-beats", help="Path to beats.npy")
    parser.add_argument("--audio-downbeats", help="Path to downbeats.npy")
    parser.add_argument("--musicality-mu", type=float, help="Musicality μ score")
    parser.add_argument("--musicality-tau", type=float, help="Optimal τ lag")
    args = parser.parse_args()

    export(args)


if __name__ == "__main__":
    main()

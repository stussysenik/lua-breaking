#!/usr/bin/env python3
"""
sync_manifest.py — Scan bboy-analytics commits for new concepts and update lua-breaking manifest.

Detects:
- New files in experiments/components/
- New metrics in experiments/world_state.py
- Commit messages tagged with [concept: name]

Generates stub section folders and updates manifest.lua.

Usage:
    python tools/sync_manifest.py \
        --repo-dir /path/to/bboy-analytics \
        --manifest-dir /path/to/lua-breaking \
        --since last-sync

    # Or with a specific commit range:
    python tools/sync_manifest.py \
        --repo-dir /path/to/bboy-analytics \
        --manifest-dir /path/to/lua-breaking \
        --since abc1234
"""

import argparse
import os
import re
import subprocess
from pathlib import Path


def get_commits_since(repo_dir: str, since: str) -> list[dict]:
    """Get commits since a reference (commit hash, tag, or 'last-sync')."""
    # Read last sync marker
    marker_file = Path(repo_dir) / ".lua-breaking-sync"
    if since == "last-sync":
        if marker_file.exists():
            since = marker_file.read_text().strip()
        else:
            since = "HEAD~10"  # default: last 10 commits

    cmd = [
        "git", "-C", repo_dir, "log",
        f"{since}..HEAD",
        "--format=%H|%s|%an|%aI",
        "--name-only",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[sync] git log failed: {result.stderr}")
        return []

    commits = []
    current = None
    for line in result.stdout.strip().split("\n"):
        if "|" in line and line.count("|") >= 3:
            parts = line.split("|", 3)
            current = {
                "hash": parts[0],
                "message": parts[1],
                "author": parts[2],
                "date": parts[3],
                "files": [],
            }
            commits.append(current)
        elif current and line.strip():
            current["files"].append(line.strip())

    return commits


def detect_concepts(commits: list[dict]) -> list[dict]:
    """Detect new concepts from commits."""
    concepts = []

    for commit in commits:
        # Check for [concept: name] tags in commit messages
        matches = re.findall(r"\[concept:\s*([^\]]+)\]", commit["message"], re.IGNORECASE)
        for match in matches:
            concepts.append({
                "name": match.strip().lower().replace(" ", "_"),
                "source": "commit_tag",
                "commit": commit["hash"][:8],
                "message": commit["message"],
            })

        # Check for new component files
        for f in commit["files"]:
            if f.startswith("experiments/components/") and f.endswith(".py"):
                name = Path(f).stem
                if name not in ("__init__", "base", "panel"):
                    concepts.append({
                        "name": name,
                        "source": "new_component",
                        "commit": commit["hash"][:8],
                        "file": f,
                    })

        # Check for new functions in world_state.py
        for f in commit["files"]:
            if f == "experiments/world_state.py":
                concepts.append({
                    "name": "world_state_update",
                    "source": "world_state_change",
                    "commit": commit["hash"][:8],
                    "message": commit["message"],
                })

    # Deduplicate by name
    seen = set()
    unique = []
    for c in concepts:
        if c["name"] not in seen:
            seen.add(c["name"])
            unique.append(c)

    return unique


def generate_stub(manifest_dir: str, concept: dict) -> str:
    """Generate a stub section folder for a new concept."""
    section_name = concept["name"]
    section_dir = Path(manifest_dir) / "sections" / section_name

    if section_dir.exists():
        print(f"[sync] Section already exists: {section_name}")
        return section_name

    section_dir.mkdir(parents=True, exist_ok=True)

    init_lua = f'''--- Section: {concept["name"].replace("_", " ").title()}
--- Auto-generated stub from bboy-analytics commit {concept.get("commit", "unknown")}
--- Source: {concept.get("file", concept.get("message", "unknown"))}
---
--- TODO: Implement this visualization

local Theme = require("shell.theme")
local Draw = require("lib.draw")

local Section = {{}}
Section.__index = Section

Section.meta = {{
    id = "?.?",  -- assign an ID
    title = "{concept["name"].replace("_", " ").title()}",
    layer = "system",  -- assign a layer
    description = "Auto-generated stub — needs implementation",
    research_mapping = "{concept.get("file", "")}",
    data_bridge = false,
    prerequisites = {{}},
}}

function Section:load()
end

function Section:update(dt)
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.setFont(Theme.fonts().heading)
    love.graphics.printf(
        "Stub section — awaiting implementation\\n\\n" ..
        "Source: {concept.get("file", concept.get("message", "unknown"))}",
        sw * 0.2, sh * 0.4, sw * 0.6, "center"
    )
end

function Section:mousepressed(x, y, button) end
function Section:mousereleased(x, y, button) end
function Section:mousemoved(x, y, dx, dy) end
function Section:keypressed(key) end
function Section:unload() end

return Section
'''

    (section_dir / "init.lua").write_text(init_lua)
    print(f"[sync] Generated stub: {section_name}")
    return section_name


def update_sync_marker(repo_dir: str, latest_hash: str):
    """Write the latest synced commit hash."""
    marker_file = Path(repo_dir) / ".lua-breaking-sync"
    marker_file.write_text(latest_hash + "\n")
    print(f"[sync] Updated sync marker to {latest_hash[:8]}")


def main():
    parser = argparse.ArgumentParser(description="Sync bboy-analytics concepts to lua-breaking")
    parser.add_argument("--repo-dir", required=True, help="Path to bboy-analytics repo")
    parser.add_argument("--manifest-dir", required=True, help="Path to lua-breaking project")
    parser.add_argument("--since", default="last-sync", help="Commit ref or 'last-sync'")
    args = parser.parse_args()

    print(f"[sync] Scanning {args.repo_dir} since {args.since}...")

    commits = get_commits_since(args.repo_dir, args.since)
    print(f"[sync] Found {len(commits)} commits")

    concepts = detect_concepts(commits)
    print(f"[sync] Detected {len(concepts)} new concepts")

    for concept in concepts:
        print(f"  - {concept['name']} ({concept['source']}) from {concept['commit']}")
        generate_stub(args.manifest_dir, concept)

    if commits:
        update_sync_marker(args.repo_dir, commits[0]["hash"])

    print("[sync] Done.")


if __name__ == "__main__":
    main()

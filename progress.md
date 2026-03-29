# Progress

Tracking what's been built, reviewed, and fixed.

---

## 2026-03-29 — Initial Build

### Built (Phase 1-4)

**Core infrastructure:**
- `main.lua` + `conf.lua` — Love2D 11.4 entry point, 1440x900 window, HiDPI, MSAA 4x
- `shell/graph.lua` — Graph navigation with zoom/pan, bezier edges, layer-colored nodes
- `shell/theme.lua` — Full light/dark mode system with layer color palettes
- 9 shared libraries in `lib/` — vector, skeleton, physics, signal, draw, widgets, data_loader, json, timeline
- `manifest.lua` — Concept-to-section mapping for 24 sections
- `tools/export_motion.py` — Python data bridge (joints.npy to JSON)
- `tools/sync_manifest.py` — Git hook for concept detection

**10 interactive sections:**

| Section | Lines | Key Feature |
|---------|-------|-------------|
| 1.1 Joint Model | 230 | Clickable 24-joint SMPL skeleton with hierarchy chain |
| 2.1 Joint Velocity | 350 | Per-joint velocity arrows, speed color ramp, timeline |
| 2.2 Energy Flow | 280 | Kinetic energy heat visualization, body-part bar chart |
| 2.5 Force Vector Field | 500 | Coulomb-like contact forces, draggable, cached to Canvas |
| 2.6 Center of Mass | 370 | COM tracking, support polygon, stability margin |
| 3.1 Beat Detection | ~400 | Waveform, energy envelope, onset function, threshold |
| 3.2 8D Audio Signature | ~500 | Radar chart, 8 psychoacoustic dimensions, presets |
| 3.3 Musicality (mu) | 660 | Cross-correlation, tau slider, grade display |
| 4.3 Gate Pipeline | 850 | Animated frame particles, 5 gates, expand-on-click |
| 5.2 Powermove Physics | 1014 | Windmill/flare/headspin tabs, real physics |

### Code Review (Staff Engineer Level)

Reviewed by AI agent simulating principal staff engineer at DeepMind.

**Verdict:** "Not a half-finished prototype — a working educational tool that needs targeted fixes."

**Strengths identified:**
- Clean section module interface and architecture
- Textbook-correct cross-correlation in musicality section
- Faithful Coulomb-like force field with field line tracing
- Correct angular momentum conservation in powermove physics
- Thoughtful data bridge design with frame interpolation

**Critical issues found and fixed:**

| Issue | Severity | Fix |
|-------|----------|-----|
| JSON parser used `load()` — code injection | Critical | Replaced with rxi/json.lua (MIT) |
| Kinetic energy missing 1/2 * m factor | Critical | Added to physics.lua, exporter, and displays |
| `Widgets.beginFrame()` called twice | Critical | Removed duplicate calls from 2 sections |
| Manifest marked implemented section as "stub" | Critical | Corrected center_of_mass status |
| Vector field O(n^2) uncached per frame | Important | Cached to Canvas, ~90% frame time reduction |
| Graham scan broke with colinear contacts | Important | Fixed strict less-than comparison |
| Python/Lua grade thresholds mismatched | Important | Unified to S>=0.90/A>=0.75/B>=0.55/C>=0.35 |

**Remaining important issues (tracked for next sprint):**
- I1: Section state in module-level locals creates stale state across visits
- I2: Toggle widget is dead code
- I3: `Graph.sections` shared on class metatable
- M1: No custom fonts (using Love2D built-in)

### Light/Dark Mode

Added full theme system with:
- Light mode as default (clean, readable)
- Dark mode toggle with `T` key
- 92 hardcoded white text calls replaced with Theme-aware colors
- Layer colors adjusted for contrast in both modes

---

## Stats

- **Total Lua files:** 22
- **Total lines of code:** ~8,500 Lua + 400 Python
- **Sections implemented:** 10 / 24
- **Libraries:** 10 (vector, skeleton, physics, signal, draw, widgets, data_loader, json, timeline, theme)
- **Tools:** 2 Python scripts (export, sync)

# Roadmap

What's next for lua-breaking, ordered by priority and grouped by milestone.

---

## M1: Core Complete (current)

**Goal:** All foundation, physics, and signal sections working with proper theming.

- [x] 1.1 Joint Model
- [x] 2.1 Joint Velocity Vectors
- [x] 2.2 Kinetic Energy Flow
- [x] 2.5 Force Vector Field
- [x] 2.6 Center of Mass & Stability
- [x] 3.1 Beat Detection
- [x] 3.2 8D Audio Signature
- [x] 3.3 Musicality (mu)
- [x] 4.3 Validation Gate Pipeline
- [x] 5.2 Powermove Physics
- [x] Light/dark mode
- [x] Code review fixes (security, physics accuracy, performance)
- [x] README, progress, roadmap docs

---

## M2: Foundation & Physics Complete

**Goal:** Fill remaining gaps in L1 and L2. These are the building blocks everything else depends on.

- [ ] 1.2 Coordinate Systems — World/camera/screen transform demo. Shows why monocular 3D recovery is hard. Interactive camera orbit with live 2D projection.
- [ ] 1.3 FK/IK Basics — Split view: forward kinematics (rotate joints) vs inverse kinematics (drag endpoints). Foundation for understanding pose estimation.
- [ ] 2.3 Energy Acceleration — dK/dt plotted with beat markers overlaid. Shows energy bursts at musical hits.
- [ ] 2.4 Angular Momentum — L = I*omega conservation demo. Tuck slider changes spin speed. Critical prereq for powermove section.
- [ ] 2.7 Compactness — Body shape morphing slider. Sphere visualization. Links tuck angle to spin physics.
- [ ] 2.8 Balance & Stability — Box2D simulation. Pick a freeze pose, release, watch if it stands or falls.

**Estimated effort:** 6 sections, ~2400 lines

---

## M3: Computer Vision Story

**Goal:** Explain how 3D poses are estimated from video and why breakdancing breaks every model.

- [ ] 4.1 3D Reconstruction Challenge — The core ambiguity: many 3D poses project to the same 2D shadow. Interactive camera rotation reveals the depth guessing problem.
- [ ] 4.2 Why Inversions Break Models — Training distribution point cloud (AMASS/BEDLAM). Drag skeleton upside down, watch confidence drop as it enters OOD territory. Explains JOSH failure modes.
- [ ] 4.4 BRACE Ground Truth — Side-by-side model vs annotation. PCK@0.2 threshold slider. Explains why ground truth is essential and how the Red Bull BC One dataset enables this research.

**Estimated effort:** 3 sections, ~1500 lines

---

## M4: Breakdancing Domain

**Goal:** Connect all physics, signal, and CV concepts to actual breakdancing moves.

- [ ] 5.1 Move Taxonomy — Interactive tree: toprock > footwork > powermove > freeze. Click any leaf to see a physics mini-sim and relevant metrics. BRACE segment colors on a timeline.
- [ ] 5.3 Freeze Balance — Gallery of freeze types (baby, chair, air, hollow back). Each shows COM, support polygon, stability margin. Interactive pose tweaking.
- [ ] 5.4 Musicality in Practice — The payoff section. Full integration: audio waveform + animated skeleton + live mu score. Compare high-mu and low-mu rounds side by side.

**Estimated effort:** 3 sections, ~2000 lines

---

## M5: Signal Processing Complete

**Goal:** Fill the remaining signal section.

- [ ] 3.4 Cycle Detection — Windowed autocorrelation on pelvis + wrist signals. Peaks indicate powermove periodicity. Interactive window size and lag range.

**Estimated effort:** 1 section, ~400 lines

---

## M6: Polish & Data

**Goal:** Production polish and real data integration.

- [ ] Custom fonts (Inter + JetBrains Mono)
- [ ] Section state encapsulation (fix stale state on re-entry)
- [ ] Transition animations between graph and sections
- [ ] Window resize handling in all sections
- [ ] Wire real JOSH data into all data-bridge sections
- [ ] Export 3-5 real clips from bboy-analytics
- [ ] Help overlay (? key) showing all shortcuts
- [ ] Graph search/filter by layer

---

## M7: Distribution

**Goal:** Make it easy for others to run and learn from.

- [ ] Package as .love file for cross-platform distribution
- [ ] GitHub release with screenshots
- [ ] Web export via love.js (experimental)
- [ ] Landing page with embedded GIFs of each section
- [ ] Integration test: load exported JSON, verify all sections render

---

## Priority Order

```
M1 (done) → M2 (foundation gaps) → M3 (CV story) → M4 (bboy domain) → M5 → M6 → M7
```

The key insight: **M2 and M3 should come before M4** because the breakdancing domain sections need the physics and CV concepts as prerequisites. You can't explain why a windmill works without angular momentum (2.4), and you can't explain why models fail without the reconstruction challenge (4.1).

---

## Section Dependency Graph

```
1.1 ──┬── 2.1 ── 2.2 ── 2.3
      │── 2.5 ── 2.6 ── 5.3
      │── 1.2 ── 4.1 ── 4.2
      │── 1.3
      └── 2.4 ── 2.7 ── 5.2

3.1 ── 3.2 ── 3.3 ── 3.4
                └──── 5.4

4.3 ── 4.4

5.1 (standalone, references all)
```

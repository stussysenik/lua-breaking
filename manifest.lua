--- manifest.lua
--- Concept → section mapping, synced with bboy-analytics research repo.
--- Each entry maps a research concept to a lua-breaking visualization module.
--- tools/sync_manifest.py can scan bboy-analytics commits and update this file.

return {
    -- L1: Foundation
    {
        concept = "skeleton_topology",
        research_file = "experiments/components/panel.py",
        section = "1_1_joint_model",
        status = "implemented",
    },
    {
        concept = "coordinate_systems",
        research_file = "KNOWLEDGE_MAP.md",
        section = "1_2_coordinates",
        status = "stub",
    },
    {
        concept = "forward_inverse_kinematics",
        research_file = "pipeline/extract.py",
        section = "1_3_kinematics_basics",
        status = "stub",
    },

    -- L2: Physics
    {
        concept = "joint_velocity",
        research_file = "experiments/world_state.py",
        research_function = "per_joint_velocity",
        section = "2_1_joint_velocity",
        status = "implemented",
    },
    {
        concept = "kinetic_energy",
        research_file = "experiments/components/energy_flow.py",
        section = "2_2_energy_flow",
        status = "implemented",
    },
    {
        concept = "energy_acceleration",
        research_file = "experiments/world_state.py",
        research_function = "energy_accel",
        section = "2_3_energy_accel",
        status = "stub",
    },
    {
        concept = "angular_momentum",
        research_file = nil,  -- new concept for powermove analysis
        section = "2_4_angular_momentum",
        status = "stub",
    },
    {
        concept = "force_vector_field",
        research_file = "experiments/components/contact_light.py",
        section = "2_5_vector_field",
        status = "implemented",
    },
    {
        concept = "center_of_mass",
        research_file = "experiments/components/com_tracker.py",
        section = "2_6_center_of_mass",
        status = "implemented",
    },
    {
        concept = "compactness",
        research_file = "experiments/world_state.py",
        research_function = "compactness",
        section = "2_7_compactness",
        status = "stub",
    },
    {
        concept = "balance_stability",
        research_file = nil,  -- contact detection thresholds
        section = "2_8_balance",
        status = "stub",
    },

    -- L3: Signal Processing
    {
        concept = "beat_detection",
        research_file = nil,  -- BeatNet+ integration
        section = "3_1_beat_detection",
        status = "stub",
    },
    {
        concept = "audio_signature_8d",
        research_file = nil,  -- 8D psychoacoustic features
        section = "3_2_audio_signature",
        status = "stub",
    },
    {
        concept = "musicality_cross_correlation",
        research_file = nil,  -- core μ metric
        section = "3_3_musicality",
        status = "implemented",
    },
    {
        concept = "cycle_detection",
        research_file = "experiments/world_state.py",
        research_function = "cyclic_score",
        section = "3_4_cycle_detection",
        status = "stub",
    },

    -- L4: Computer Vision
    {
        concept = "3d_reconstruction_challenge",
        research_file = "ARCHITECTURE.md",
        section = "4_1_reconstruction",
        status = "stub",
    },
    {
        concept = "inversion_failure_modes",
        research_file = "experiments/josh_research_report.md",
        section = "4_2_inversions",
        status = "stub",
    },
    {
        concept = "validation_gate_pipeline",
        research_file = "experiments/evaluate_powermove_gates.py",
        section = "4_3_gate_pipeline",
        status = "implemented",
    },
    {
        concept = "brace_ground_truth",
        research_file = "data/",
        section = "4_4_brace_ground_truth",
        status = "stub",
    },

    -- L5: Breakdancing Domain
    {
        concept = "move_taxonomy",
        research_file = nil,  -- BRACE segment labels
        section = "5_1_move_taxonomy",
        status = "stub",
    },
    {
        concept = "powermove_physics",
        research_file = nil,  -- powermove failure analysis
        section = "5_2_powermove_physics",
        status = "implemented",
    },
    {
        concept = "freeze_balance",
        research_file = nil,  -- contact detection + COM
        section = "5_3_freeze_balance",
        status = "stub",
    },
    {
        concept = "musicality_in_practice",
        research_file = nil,  -- μ metric + BRACE beats
        section = "5_4_musicality_practice",
        status = "stub",
    },
}

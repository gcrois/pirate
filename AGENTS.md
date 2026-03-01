# AGENTS.md

This file defines project-specific guidance for coding agents working in this repository.

## Goal

Maintain a stable Godot 4.5 prototype while reducing coupling and improving maintainability.

## Repository Facts

- Engine: Godot 4.5
- Main scene: `res://scenes/main.tscn`
- Ship scene: `res://scenes/ship.tscn`
- Core gameplay script: `res://scripts/ship_controller.gd`
- Diagnostics scene: `res://scenes/diagnostics/buoyancy_smoke.tscn`

## Required Checks

Run these before finishing meaningful code changes:

```bash
pip install "gdtoolkit==4.*"
gdformat --check scripts
gdlint scripts
godot --headless --path . res://scenes/diagnostics/buoyancy_smoke.tscn
```

## Implementation Rules

- Keep `scenes/main.tscn` free of always-on diagnostics/test nodes.
- Prefer typed node references over dynamic `get("...")` property access.
- Do not introduce new gameplay key handling with raw keycodes; use `InputMap` actions.
- Keep scripts focused; avoid expanding monolithic files when a new module is more appropriate.
- Keep third-party addon code under `addons/` untouched unless a task explicitly requires it.

## File Placement

- Gameplay logic: `scripts/`
- Scene composition: `scenes/`
- Diagnostic or test scenes: `scenes/diagnostics/`
- Architecture and process docs: `docs/`
- CI workflows: `.github/workflows/`

## Safe Change Strategy

- Prefer small, reviewable patches.
- If behavior changes, update `README.md` or `docs/architecture.md` as needed.
- Avoid destructive git operations; preserve unrelated local changes.

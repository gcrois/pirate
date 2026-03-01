# Pirates (Godot 4.5)

Top-down pirate prototype with buoyancy, wakes, combat, trading, and AI ships.

## Requirements

- Godot 4.5 (standard, non-dotnet)
- Python 3.11+ (for local `gdtoolkit` checks)

## Run Locally

```bash
godot --path .
```

## Controls

- `W` / `Up`: accelerate
- `Down`: reverse
- `A` / `Left`: turn port
- `D` / `Right`: turn starboard
- `Q`: fire port broadside
- `E`: fire starboard broadside
- `S`: toggle ship or surfboard
- `Ctrl` or `Cmd` + arrows: dev free-fly override

## Quality Checks

```bash
pip install "gdtoolkit==4.*"
gdformat --check scripts
gdlint scripts
godot --headless --path . res://scenes/diagnostics/buoyancy_smoke.tscn
```

The buoyancy smoke test scene is separate from gameplay and exits non-zero on failure.

## Build and Deploy

- Web export command (used by CI deploy workflow):

```bash
godot --headless --export-release "Web" build/web/index.html
```

- Deployment workflow: `.github/workflows/deploy.yml`
- Quality workflow: `.github/workflows/quality.yml`

## Project Layout

- `scenes/`: main world and reusable scenes
- `scripts/`: gameplay, UI, and simulation logic
- `shaders/`: water and wake shaders
- `addons/`: third-party Godot addon(s)
- `infra/`: OpenTofu configuration for repository automation
- `docs/`: architecture and contributor notes

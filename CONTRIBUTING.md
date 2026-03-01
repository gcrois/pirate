# Contributing

## Workflow

- Create focused PRs that solve one problem at a time.
- Keep behavior changes and refactors separate when possible.
- Update docs when commands, workflows, or architecture change.

## Coding Guidelines

- Prefer typed GDScript values and explicit return types.
- Avoid broad `get("field")` usage when a typed node reference is available.
- Keep scene scripts small and focused; extract subsystems instead of growing monoliths.
- Keep diagnostics and test runners out of `scenes/main.tscn`.
- Use `InputMap` actions for gameplay inputs instead of hardcoded keys when adding new controls.

## Local Checks Before PR

```bash
pip install "gdtoolkit==4.*"
gdformat --check scripts
gdlint scripts
godot --headless --path . res://scenes/diagnostics/buoyancy_smoke.tscn
```

## PR Checklist

- [ ] Gameplay still runs from `scenes/main.tscn`
- [ ] Formatting and lint checks pass
- [ ] Buoyancy smoke test passes
- [ ] New behavior has tests or a clear rationale if tests were not added
- [ ] Docs updated for user-facing or workflow changes

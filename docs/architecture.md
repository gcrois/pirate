# Architecture Overview

## Runtime Structure

- Entry scene: `res://scenes/main.tscn`
- Primary actor scene: `res://scenes/ship.tscn`
- Ocean simulation: `res://scripts/ocean.gd`
- World generation and economy data: `res://scripts/island.gd`, `res://scripts/economy.gd`
- UI overlays: trade menu, minimap, labels, health bars, debug overlay

## Script Responsibilities

- `ship_controller.gd`: actor orchestration for movement, combat, buoyancy, inventory, upgrades, AI decisions
- `cannonball.gd`: projectile simulation and hit detection
- `wake_controller.gd`: per-actor wake texture generation in a `SubViewport`
- `ocean.gd`: shader parameter updates and wave height sampling
- UI scripts (`trade_menu.gd`, `minimap_view.gd`, `health_bar_overlay.gd`, `island_name_overlay.gd`): world-to-UI projection and controls

## Diagnostics and Tests

- Smoke diagnostics scene: `res://scenes/diagnostics/buoyancy_smoke.tscn`
- Test script: `res://scripts/test_buoyancy.gd`
- CI runs diagnostics headlessly and fails the build when assertions fail.

## Current Coupling Hotspots

- `ship_controller.gd` currently mixes multiple domains and is the main refactor target.
- Several systems rely on group scans and dynamic property access for cross-node communication.

## Refactor Direction

- Split actor behavior into components (`movement`, `combat`, `ai`, `inventory`, `buoyancy`).
- Introduce typed references or a lightweight registry instead of repeated group queries.
- Keep scene files declarative and move logic into focused scripts or resources.

# Changelog

## [Unreleased]

### Added

- Smart whitespace trimming: highlights shrink wrap to drop leading indentation,
  trailing whitespace, and blank lines at selection edges.
- Headless self-checks: `test/trim_spec.lua`, `test/trim_edge_spec.lua`.

### Fixed

- Oversized/stale exclusive end (`ec` past EOL) no longer walks off the buffer and drops the highlight; clamped to line length.

## [0.1.0] - 2026-07-23

### Added

- `gh` (operator/visual): toggle a yellow highlight over a motion or selection.
- `gH`: clear all highlights in the buffer.
- Persistence: on `$data/highlighter_marks.json`, key is the filepath; reload on
  buffer autcmds
- Eraser mode: toggling a region overlapping existing highlights carves it out

### Changed

- Format of lua/highlighter/init.lua

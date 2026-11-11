# TubeTiles

An art and maze construction tool for iPhone and iPad. You draw hex tiles whose
tubes run between ports on their sides, collect them in a library, and let a
generator assemble them into woven, labyrinth-style mazes.

TubeTiles is a ground-up rewrite of two older Processing sketches (a tile
editor and a tile-set generator), brought together in one codebase.

## Concepts

- **Tile**: a flat-top hexagon with a fixed number of ports on each edge.
- **Pipe**: a tube joining two ports. Kinds are bezier, corner, and circular
  rooms in three sizes.
- **Edge code**: which ports on each edge are in use. Two tiles can sit next
  to each other when their touching edges agree.
- **Variants**: tiles with the same edge code but different internal
  connections. Swapping variants is how separate loops get merged into a
  single path.
- **Overlap rule**: at most two pipes may cross at any point, which is what
  makes a clean over/under weave possible.

## Roadmap

| Phase | Scope |
|---|---|
| 0. Core | Hex and port geometry, tile model, edge codes, rotation and mirroring |
| 1. Editor | Draw pipes port to port, validation, random fill |
| 2. Library | Browse, filter and manage saved tiles |
| 3. Generator | Grow tilings on a hex grid with symmetry modes and hand editing |
| 4. Single path | Trace loops and merge them by swapping tile variants |
| 5. Weave and export | Over/under weaving, layered SVG export |

## Layout

- `TubeKit/` is a Swift package holding all model and logic, with no UI.
- `App/` is the SwiftUI app, built from `TubeTiles.xcodeproj`.
- `docs/screenshots/` holds images linked from pull requests.

## Development

Open `TubeTiles.xcodeproj` in Xcode to run the app. The core logic has its
own tests:

```bash
cd TubeKit && swift test
```

### Workflow

- Branch from `main` as `<category>/<kebab-case-name>`, for example
  `feat/add-tile-gen`.
- Open a pull request back to `main` and squash merge it.
- Pull requests that change UI or graphics include screenshots, committed
  under `docs/screenshots/`.

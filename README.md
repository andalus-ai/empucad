# EmpuCAD

Offline 3D design with CNC and laser output. A Flutter port of
[DabbleCAD](https://github.com/DJMcNewgent/DabbleCAD) (Apache-2.0, see `NOTICE`) with the geometry,
CAM and G-code work done by a Rust engine.

Stack: Flutter + `flutter_riverpod` (hand-written providers, **no freezed, no code generation in
the app**) + `flutter_scene` for drawing + a Rust FFI plugin (`flutter_rust_bridge`) for everything else.

## Status: what is verified and what is not

| Part | State |
|---|---|
| Rust engine (`packages/empucad_engine/rust`) | **Built and tested here**: 59 tests, `clippy` clean (Rust 1.89) |
| Pure-Dart layers (`core`, `domain`, `application`, `data/codec`, camera) | **Analyzed and tested here**: `dart analyze` clean, 40 tests (Dart 3.14.1) |
| Rust to Dart bridge (`flutter_rust_bridge` codegen) | **Not run.** Needs Flutter; run `tool/bootstrap_engine.sh` |
| `data/engine/*` adapters, `presentation/*` (Riverpod, widgets, renderers), `main.dart` | **Written, never compiled.** pub.dev and the Flutter SDK were unreachable where this was built. Expect a round of small compile fixes. |
| `flutter_scene` renderer | Written against the `flutter_scene` source on GitHub (main, 0.24.x), never run. |

The Dart tests were executed with a tiny stand-in for `package:test` (pub.dev unreachable); they use only
`test`, `group`, `setUp`, `expect` and the common matchers, so `dart test` should run them unchanged.

## Quick start

```bash
# needs: Flutter >= 3.47, Rust >= 1.88, cmake, a C++ compiler (Manifold is compiled from source)
./tool/bootstrap_engine.sh                    # one time: cargokit glue, pin versions, generate Dart bindings
flutter run --enable-flutter-gpu              # GPU renderer (flutter_scene)
flutter run --dart-define=EMPUCAD_RENDERER=canvas   # software fallback, no Flutter GPU needed
```

Engine only, no Flutter: `cd packages/empucad_engine/rust && cargo test --workspace`.

## Architecture

Dependencies point inward. Nothing in `domain` or `application` imports Flutter, Riverpod or FFI.

```
presentation/   widgets, Riverpod notifiers, viewport + renderers        (Flutter)
   │ depends on
application/    document ops, history, scene evaluator, picking,         (pure Dart)
   │            footprint extraction, mesh shading, export
   │ depends on
domain/         entities (Document, SceneNode, Placement) and PORTS      (pure Dart)
   ▲            (GeometryEngine, CamEngine) as interfaces
   │ implemented by
data/           RustGeometryEngine, RustCamEngine, JSON codec, file I/O  (adapters)
```

How the principles show up:

* **Separation of concerns.** The notifiers decide *when*; `DocumentOps`, `SceneEvaluator` and
  `Picker` decide *what*. Rendering (`SceneRenderer`) never edits, picks or evaluates.
* **Single responsibility.** One reason to change per module, e.g. `geom2d` (polygon maths), `csg`
  (3D booleans), `cam` (toolpaths), `gcode` (controllers), `laser` in Rust; `scene_evaluator` (tree to
  meshes) in Dart.
* **Open/closed.** A new toolpath is a new `ToolpathStrategy`. A new controller is a new row in
  `gcode::POSTS`. A new renderer implements `SceneRenderer`. None edit existing code.
* **Liskov / interface segregation.** `FakeGeometryEngine` (tests) and `RustGeometryEngine` are
  interchangeable behind the six-method `GeometryEngine` port.
* **Dependency inversion.** The app depends on ports; `main.dart` is the only place that wires in Rust,
  `file_selector` and the renderer, through Riverpod overrides.
* **Reusable components.** `PanelSection`, `NumberField`, `ToolButton`, `ToolpathPreview`.
* **Immutability without freezed.** Entities are `final` classes with hand-written `copyWith`; sealed
  `SceneNode` gives exhaustive `switch`.

### Layout

```
lib/
  core/math/            Vec3, Ray, Mat4
  domain/entities/      Document, SceneNode (sealed: ShapeNode, GroupNode), Placement
  domain/ports/         GeometryEngine, CamEngine (+ CamOperation, CamSettings, MeshData)
  application/          document_ops, history, scene_evaluator, picking, footprint, mesh_shading, export_stl
  data/codec/           DocumentCodec (versioned JSON, strict validation)
  data/engine/          Rust adapters (the only files that import the bridge)
  data/storage/         FileDocumentStorage (atomic save), file_selector adapter
  presentation/state/   Riverpod providers and notifiers
  presentation/viewport OrbitCamera, SceneRenderer + FlutterSceneRenderer + CanvasSceneRenderer, Viewport
  presentation/widgets  reusable panels and fields
  presentation/screens  EditorScreen
packages/empucad_engine/
  rust/crates/empucad_core/   pure-Rust engine (the tested part)
  rust/src/api/               thin flutter_rust_bridge adapter (flat typed arrays, no freezed)
```

## Rust engine: what is reused and what is new

| Need | Existing crate used | Notes |
|---|---|---|
| 3D mesh booleans | `manifold-csg` | The same Manifold kernel DabbleCAD runs as WASM, so boolean behaviour matches |
| 2D polygon union / offset | `i_overlay` | Replaces `clipper-lib` |
| SVG to G-code | `svg2gcode` + `g-code` | Fast path for plotters and simple laser line work (`api/svg.rs`) |
| SVG import to outlines | `usvg` | Resolves transforms/units/`use`, arcs become curves; curves flattened to a mm tolerance |
| 2D outline to 3D solid | `manifold-csg` (`CrossSection::extrude`) | Nested outlines become holes |
| CAM toolpaths (profile, pocket, engrave, drill) | none suitable, written here | `cnccoder` is GRBL-only with hand-authored cuts and no V-carve; nothing existing converts a design to CAM toolpaths |
| G-code posts (GRBL, LinuxCNC, Mach, Marlin, generic) | written here | data-driven table |
| Laser layer planner (line, fill, passes, overscan, GRBL M3/M4) | written here | `svg2gcode` has no per-layer speed/power model |

## DabbleCAD feature map

| DabbleCAD | EmpuCAD |
|---|---|
| Shapes, groups, holes, union/intersect/bundle | done (`SceneEvaluator`) |
| Undo/redo | done (`History`) |
| Save/open | done, own `.empucad` JSON (DabbleCAD files are not imported yet) |
| STL export | done |
| CNC: profile, pocket, engrave, drill; 5 controller posts; time estimate | done (engine + panel) |
| CNC: holding tabs, ramp entry | engine done and tested; **no UI fields yet** |
| Laser raster (grayscale / dither), depth-map style power | engine done and tested; **no UI yet** |
| SVG import, extrude outline to solid | engine done and tested; **no UI / document node yet** |
| Laser G-code planner | engine done and tested; **no UI yet** |
| CNC: V-carve, helix entry, dogbones, tool library, GRBL simulator | not started |
| Text, STL import UI, mesh tools, align/mirror/array | not started |
| Arc output (G2/G3) | not started (`cavalier_contours` is the candidate; offsets are polylines today) |

## Known limits

* **CAM footprints** are the base outline projected to XY: exact for shapes lying flat and for any Z rotation.
* **Ungroup** supports groups rotated about Z only; a group tilted about X/Y is left unchanged.
* **Picking** is CPU ray-triangle per frame on click; fine for hundreds of thousands of triangles, not millions.
* **`flutter_scene` is pre-1.0**; minor releases can break the API. Pin it and read its CHANGELOG.
* The mobile save dialog is not implemented (`file_selector` has none); desktop and web only.

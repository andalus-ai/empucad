# EmpuCAD

Offline 3D design with CNC and laser output. A Flutter port of
[DabbleCAD](https://github.com/DJMcNewgent/DabbleCAD) (Apache-2.0, see `NOTICE`) with the geometry,
CAM and G-code work done by a Rust engine.

Stack: Flutter + `flutter_riverpod` (hand-written providers, **no freezed, no code generation in
the app**) + `flutter_scene` for drawing + a Rust FFI plugin (`flutter_rust_bridge`) for everything else.

## Status: what is verified and what is not

| Part | State |
|---|---|
| Rust engine (`packages/empucad_engine/rust`) | **Built and tested here**: 99 tests, `clippy` clean (Rust 1.89) |
| Pure-Dart layers (`core`, `domain`, `application`, `data/codec`, camera) | **Analyzed and tested here**: `dart analyze` clean, 156 tests (Dart 3.14.1) |
| Rust to Dart bridge (`flutter_rust_bridge` codegen) | **Not run.** Needs Flutter; run `tool/bootstrap_engine.sh` |
| `data/engine/*` Rust adapters | **Type-checked** against a hand-written stub of the API codegen should produce (not against real generated code) |
| `presentation/*` (Riverpod, widgets, renderers), `main.dart` | **Written, never compiled.** pub.dev and the Flutter SDK were unreachable where this was built. Expect a round of small compile fixes. |
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

**After changing anything in `packages/empucad_engine/rust/src/api/`** (the bridge surface), regenerate the
Dart and Rust glue, or the crate will not compile against the stale `frb_generated.rs`:

```bash
cd packages/empucad_engine && flutter_rust_bridge_codegen generate
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
| Save/open | done: own `.empucad` JSON; **DabbleCAD `.dabble` files open too** (see below) |
| STL export | done |
| CNC: profile, pocket, engrave, drill; 5 controller posts; time estimate | done (engine + panel) |
| CNC: holding tabs, ramp entry | done (engine + CNC panel fields) |
| Laser image engraving (grayscale / dither / invert), depth-map style power | done (engine + laser workspace UI) |
| SVG import to an extruded, editable node (`OutlineNode`) | done (engine, document, codec, CAM footprint, toolbar button, thickness field) |
| Laser layers (line / fill, passes, power, overscan), per-shape layer assignment, bed check, G-code preview | done (engine, document, laser workspace UI) |
| CNC: V-carve | done as a contour-parallel approximation (see below); not a medial-axis V-carve |
| CNC tool library (end mill, ball nose, V-bit, drill; feed, plunge, rpm, angle; saved in the file) | done; operations only offer tools that suit them |
| CNC: dogbone corners (inside profiles, pocket walls) | done; relief reaches exactly one tool radius from the true corner |
| CNC program check (independent G-code re-reader) | done: every generated program is checked and the CNC panel shows the result |
| CNC: helix entry, 3D G-code simulator | not started (ramp entry covers most of what helix does) |
| STL import (binary or ASCII) as a saved, movable mesh node | done: centred on the workplane, saved in the file, silhouette for CNC/laser |
| Text, mesh repair/simplify, align/mirror/array | not started |
| Arc output (G2/G3) | done as an opt-in fit: runs of short cuts on a circle become one arc (planar only, tolerance 0.005 mm); true arc-preserving offsets (`cavalier_contours`) are still future work |

## Laser workspace

Switch with the **Design / CNC / Laser** control in the app bar.

* **Layers** (name, colour, line or fill, speed, power, passes, fill gap/angle, overscan, on/off) and the
  **machine** (bed size, S max, M3/M4) are stored in the document, so they are saved and undoable.
* Select shapes, open a layer, **Assign selection here**. A shape with no layer uses its group's layer,
  else layer 1. Overlapping shapes in a fill layer merge instead of cancelling.
* **Image engraving**: load a PNG/JPEG/etc., set size and bottom-left position, power range and mode.
  The image (downscaled to at most 2000 px) and its settings are saved in the `.empucad` file, run-length
  encoded, so they reopen with the design and are covered by undo.
* Coordinates are machine coordinates everywhere (origin bottom-left, Y up): the Y that goes in is the Y
  in the G-code. This is covered by Rust tests, because getting it wrong mirrors every burn.
* A bed check warns when shapes or the image leave the bed.
* In the Laser workspace the 3D viewport colours each shape by the layer it burns on (faded if that layer
  is switched off), using the same rule as the job builder, so what you see is what gets planned.

## Program check

Every generated CNC program is re-read from its **text** by a separate G-code parser
(`gcode::sim`) that replays the moves, including arcs, incremental mode, inches and comments. The CNC
panel shows "Program check passed" or the problems found, such as:

* a rapid (`G0`) move into the stock or sideways inside it,
* cutting deeper than the stock, or below the surface with the spindle off,
* an arc whose start and end are not the same distance from its centre (controllers alarm on this),
* a feed move before any `F`, or an unsupported word (`R` arcs, cutter compensation, other planes).

Because it parses only the text, it is also an independent test of the generator: a test runs it over
1,040 combinations of operation, controller, units, arcs, tabs, ramps and dogbones on four different
shapes and requires zero findings and a matching time estimate. That test found that inch programs
printed only three decimals (0.001 in = 25 microns); they now use four, like conventional inch posts.
It assumes the machine starts at the XY origin (the same convention as the time estimate).

## Importing STL meshes

**Import STL…** adds the mesh as a node. It is centred in X and Y with its lowest point on the workplane
(like every built-in shape), and can then be moved, rotated, coloured, grouped and exported. The mesh is
stored in the `.empucad` file (little-endian float32/uint32, base64) and validated strictly on open: a
corrupt file cannot produce out-of-range indices. Limit: 500,000 triangles.

* A mesh that is **not a closed solid** still imports but with a warning, because boolean operations need
  one; combining it with other shapes falls back to showing the parts separately.
* For CNC and laser a mesh contributes its **top-view silhouette (convex hull)**, so a concave part is
  covered by its hull.
* Imported meshes cannot be resized in the inspector yet (position and rotation only).

## Dogbones

A round cutter cannot make a sharp inside corner; a 6 mm bit leaves 3 mm corner radii, so a square part
will not fit. Switch on **Dogbone corners** for an inside profile or a pocket and the cutter runs out
along each sharp corner's bisector and back, far enough that its edge reaches the true corner
(`r / sin(angle / 2) - r` of extra travel: 0.41 r for a square corner). Rounded corners, reflex corners,
very acute corners (under 20 degrees) and island corners are left alone; in a pocket only the wall pass
gets them. Outside profiles ignore the setting.

## Opening DabbleCAD files

**Open…** accepts `.empucad` and DabbleCAD `.dabble` files and tells them apart by content. After a
DabbleCAD import a dialog lists everything that did not carry across exactly.

* **Imported:** box, cylinder, sphere and cone shapes; groups (union, intersect, bundle); holes; names;
  colours; positions, rotations and sizes; laser layer settings for layers 1 to 5.
* **Skipped and reported:** every other shape kind (roof, torus, text, mesh, ...), hidden shapes, laser
  shapes and image-mode layers, laser layers 6 and up.
* **Simplified and reported:** rounded boxes and bevels lose their rounding; few-sided cylinders (hexagonal
  prisms) become round; cones with a flat top become pointed; stretched round shapes become circular.
* **How sizes map:** DabbleCAD stores size as a scale in the node matrix. EmpuCAD stores size and placement
  separately, so each matrix is decomposed. A group's scale is pushed into its children, which is exact
  unless a rotated child sits in a non-uniformly scaled group (that case is detected and reported).
* Verified by tests that compare the world-space corners of hundreds of random shapes and groups against
  DabbleCAD's own matrix maths.

## Tools

The CNC panel picks a tool from the design's tool library (stored in the `.empucad` file; position in the
list is the controller tool number, `T1`, `T2`, ...). Only tools that suit the chosen operation are
offered: V-carve needs a V-bit, cutting out and pocketing need an end mill or ball nose, drilling needs a
drill or end mill, and engraving takes anything but a drill. Edit a tool's diameter, angle, feed, plunge
and spindle speed in place, or duplicate it for a new material.

## V-carve

Pick **V-carve** in the CNC panel, set the bit's included angle (e.g. 60 or 90 degrees) and its widest
cut (Tool diameter). The groove deepens with the shape width so its top edge lands on the outline.

* It is built from concentric inward offsets, each cut at the depth `distance / tan(angle / 2)`. Ring
  spacing is capped at 0.5 mm (finish quality), regardless of bit size or stepover.
* Depth is limited by your Depth setting and by the bit itself: a 2 mm bit at 90 degrees cannot cut
  deeper than 1 mm, whatever you ask for.
* **Approximation:** inner corners come out slightly rounded and there are fine ridges between rings,
  unlike a true medial-axis V-carve. Shapes wider than the bit can reach are carved to the depth limit
  and the middle is left uncut; clear it with a pocket pass.

## Continuous integration

`.github/workflows/ci.yml` runs: the Rust tests and clippy; the pure-Dart tests and analyzer; a **bridge
drift check** that regenerates `flutter_rust_bridge` output with the version pinned in `Cargo.toml` and
fails if it differs from what is committed (the usual cause of a Rust crate that suddenly does not
compile after an API edit); and `flutter analyze` plus the widget tests. The Flutter jobs have not run
yet, and the widget-test step is allowed to fail until they have.

## Known limits

* **CAM footprints** are the base outline projected to XY: exact for shapes lying flat and for any Z rotation.
* **Ungroup** supports groups rotated about Z only; a group tilted about X/Y is left unchanged.
* **Laser** uses each shape's top-view footprint, and there is no text tool.
* **Picking** is CPU ray-triangle per frame on click; fine for hundreds of thousands of triangles, not millions.
* **`flutter_scene` is pre-1.0**; minor releases can break the API. Pin it and read its CHANGELOG.
* The mobile save dialog is not implemented (`file_selector` has none); desktop and web only.

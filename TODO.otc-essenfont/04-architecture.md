# 04 — Architecture

## Principles

The `Essenfont::Otc` subsystem follows the constraints set in
`~/.claude/CLAUDE.md`:

- **OCP** — Partitioner, Writer are interfaces; concrete classes
  plug in without build-pipeline changes.
- **DRY** — Plane catalog, block catalog, naming convention each
  live in exactly one module.
- **MECE** — Models own state; services own behavior; they don't
  overlap.
- **Model-driven** — `Plane`, `Partition`, `Blueprint` are domain
  objects, not hashes.
- **Encapsulation** — Public API is small (`Build#call`,
  `Partitioner#partition`, `Writer#write`). Internal state is
  immutable (frozen on construction).
- **No `require_relative`** — All intra-library loads go through
  `autoload`, declared in the immediate parent namespace file.
- **No `send` / `instance_variable_set` / `instance_variable_get` /
  `respond_to?`** — Anywhere.
- **No doubles in specs** — Real objects or `Struct` instances.

## File layout

```
lib/
├── essenfont.rb                       # module Essenfont; autoloads :Otc
└── essenfont/
    ├── otc.rb                         # module Otc; autoloads all classes
    └── otc/
        ├── plane.rb                   # Plane value object
        ├── plane_catalog.rb           # Plane::Catalog (constant plane list)
        ├── block_catalog.rb           # Block::Catalog (ucode-sourced)
        ├── partition.rb               # Partition value object
        ├── blueprint.rb               # Blueprint (list of Partition)
        ├── partitioner.rb             # abstract interface
        ├── plane_partitioner.rb       # default concrete impl
        ├── naming.rb                  # subfont + face naming convention
        ├── stitcher_session.rb        # applies Blueprint to Stitcher
        ├── writer.rb                  # drives Collection::Builder
        ├── build.rb                   # top-level orchestrator
        ├── errors.rb                  # error hierarchy
        └── version.rb                 # Essenfont::Otc::VERSION string
```

## Class responsibilities

### Models (immutable value objects)

#### `Essenfont::Otc::Plane`

A Unicode plane.

- Attributes: `number` (Integer), `name` (Symbol, e.g. `:SIP`),
  `range` (Range<Integer>), `display_name` (String, "SIP")
- Constructor: `Plane.new(number: 2)` — derives `range` and `name`
  from `number`.
- Public methods: `cover?(cp)`, `to_label` (returns `:plane_2`),
  `to_face_name` (returns `"SIP"`).
- Frozen on construction.

#### `Essenfont::Otc::Partition`

A named grouping of codepoints assigned to a single subfont.

- Attributes: `name` (Symbol, e.g. `:plane_2`), `cps` (SortedSet<Integer>)
- Constructor: `Partition.new(name:, cps:)` — freezes `cps`.
- Public methods: `size`, `merge(other)`, `each_cp(&block)`, `to_a`.
- Frozen on construction.

#### `Essenfont::Otc::Blueprint`

A complete plan for the OTC: ordered list of `Partition`s.

- Attributes: `partitions` (Array<Partition>, frozen)
- Constructor: `Blueprint.new(partitions)` — freezes input.
- Public methods: `partition_for(name)`, `each_partition(&block)`,
  `total_codepoints`, `subfont_names`, `validate!`
- `validate!` checks: ≥1 partition; partition names unique; cps
  disjoint across partitions (no overlap).

### Catalogs (read-only constants)

#### `Essenfont::Otc::Plane::Catalog`

The essenfont plane list — the 5 planes we ship subfonts for.

- Constant: `ALL` (Array<Plane> for planes 0, 1, 2, 3, 14)
- Class methods: `find_by_number(n)`, `find_by_codepoint(cp)`,
  `find_by_label(sym)`, `each(&block)`, `all`

#### `Essenfont::Otc::BlockCatalog`

Block boundaries within a plane, for the (dormant) sub-split path.

- Sources from ucode's `output/blocks/index.json`.
- Class methods: `blocks_in_plane(n)`, `find_by_codepoint(cp)`
- Returns `Block` structs: `Block = Struct.new(:id, :first_cp,
  :last_cp, :plane_number, :name, keyword_init: true)`

### Services

#### `Essenfont::Otc::Partitioner` (abstract)

The interface every partitioner implements.

```ruby
class Partitioner
  def partition(cp_map)
    raise NotImplementedError,
          "#{self.class} did not implement #partition(cp_map)"
  end
end
```

#### `Essenfont::Otc::PlanePartitioner < Partitioner`

The default. Partitions `cp_map` by plane; sub-splits by block when
a plane exceeds the cap.

- Constructor: `PlanePartitioner.new(cap: PlanePartitioner::DEFAULT_CAP)`
- DEFAULT_CAP = 65_484 (65,535 − 1 .notdef − 50 safety margin)
- Public method: `partition(cp_map)` returns `Blueprint`

#### `Essenfont::Otc::StitcherSession`

Applies a `Blueprint` + donor map to a `Fontisan::Stitcher`.

- Constructor: `StitcherSession.new(donors:, blueprint:)`
  - `donors`: Hash<Symbol, donor_info> (label → {font:, coverage:, ...})
- Public method: `apply(stitcher)` — calls
  `stitcher.add_source`, `stitcher.include_codepoints`, and
  `stitcher.include_notdef` per partition.
- Doesn't write anything. The caller chooses between `write_to`
  (single TTF) and the Writer (OTC).

#### `Essenfont::Otc::Writer`

Emits the OTC binary.

- Constructor: `Writer.new(stitcher:, session:, format: :ttf,
  collection_format: :otc, optimize: true)`
- Public method: `write(path)` — for each partition:
  1. Write a temp TTF via `stitcher.write_to(tmp, format:, subfont:)`
  2. Load it via `Fontisan::FontLoader.load`
  3. Collect loaded fonts
  Then call `Collection::Builder.new(fonts, format: collection_format,
  optimize:).build_to_file(path)`.
- Cleanup: temp files removed in an `ensure` block.
- Returns the bytes written.

#### `Essenfont::Otc::Build` (orchestrator)

Top-level entry point. The build.rb call site.

- Constructor: `Build.new(cp_map:, donors:, partitioner:
  PlanePartitioner.new, format: :ttf, collection_format: :otc)`
- Public method: `call(output_path:)` — wires session → writer,
  runs post-write sanity checks (per-subfont maxp ≤ 65,535,
  fc-query nfonts ≥ 2).
- Returns a `Build::Result` Struct: `output_path`, `bytes`,
  `subfonts` (Array<{name:, glyph_count:, codepoint_count}>).

#### `Essenfont::Otc::Naming`

Subfont + face naming convention. Single source of truth for the
`name` table values per subfont.

- Class methods: `face_name(plane)`, `ps_name(plane)`,
  `family_name`, `version_string`
- Constants: `FAMILY = "essenfont"`, `VERSION = "0.1"`
- Returns `Naming::Entry` structs:
  `Entry = Struct.new(:family, :subfamily, :unique_id, :full_name,
   :version, :ps_name, keyword_init: true)`

#### `Essenfont::Otc::Errors`

Error hierarchy.

- `Errors::Base < StandardError`
- `Errors::SubfontBudgetExceeded < Base`
- `Errors::UnknownPlane < Base`
- `Errors::PartitionerError < Base`
- `Errors::WriteError < Base`

## Autoload map

`lib/essenfont.rb`:

```ruby
module Essenfont
  autoload :Otc, "essenfont/otc"
end
```

`lib/essenfont/otc.rb`:

```ruby
module Essenfont
  module Otc
    autoload :Errors,          "essenfont/otc/errors"
    autoload :Version,         "essenfont/otc/version"
    autoload :Plane,           "essenfont/otc/plane"
    autoload :BlockCatalog,    "essenfont/otc/block_catalog"
    autoload :Partition,       "essenfont/otc/partition"
    autoload :Blueprint,       "essenfont/otc/blueprint"
    autoload :Partitioner,     "essenfont/otc/partitioner"
    autoload :PlanePartitioner,"essenfont/otc/plane_partitioner"
    autoload :Naming,          "essenfont/otc/naming"
    autoload :StitcherSession, "essenfont/otc/stitcher_session"
    autoload :Writer,          "essenfont/otc/writer"
    autoload :Build,           "essenfont/otc/build"
  end
end
```

No `require_relative`, no `require "essenfont/otc/..."`. The gemspec
(or the build.rb `require "essenfont"`) is the only entry point.

## Dependencies

The subsystem depends on:

- `fontisan` (Stitcher, FontLoader, Collection::Builder, Ufo::Glyph)
- ucode's `output/blocks/index.json` (read at runtime by BlockCatalog,
  via the same path that `scripts/build.rb` already uses)

It does NOT depend on:

- Any other essenfont internal module (the build.rb is a *caller* of
  `Otc::Build`, not a peer module).
- AFDKO, fonttools, or any external binary.

## Test layout

```
spec/
├── spec_helper.rb
└── essenfont/
    ├── otc/
    │   ├── plane_spec.rb
    │   ├── plane_catalog_spec.rb
    │   ├── block_catalog_spec.rb
    │   ├── partition_spec.rb
    │   ├── blueprint_spec.rb
    │   ├── partitioner_spec.rb             # abstract
    │   ├── plane_partitioner_spec.rb       # default concrete
    │   ├── naming_spec.rb
    │   ├── stitcher_session_spec.rb
    │   ├── writer_spec.rb                  # integration with fontisan
    │   └── build_spec.rb                   # end-to-end (smoke)
    └── otc_spec.rb                          # top-level autoload smoke
```

All specs use real `Fontisan::Stitcher`, real `Fontisan::Ufo::Glyph`,
and real temp-file I/O. No `double()` anywhere.

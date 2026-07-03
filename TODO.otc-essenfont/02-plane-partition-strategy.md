# 02 — Plane Partition Strategy

## Goal

Partition the per-codepoint donor map (`Hash<Integer, {label:, gid:}>`)
into named groups, each group bounded by the subfont glyph cap of
65,535. Each group becomes one subfont in the OTC.

## Why planes

Unicode planes are Mutually Exclusive and Collectively Exhaustive
across the assigned codepoint space:

- **MECE** — Every codepoint lives in exactly one plane; planes
  tile the codepoint space without gaps.
- **Stable** — Plane assignment is invariant under Unicode version
  bumps (a codepoint's plane never changes).
- **Discoverable** — `cp >> 16` gives the plane number in O(1).
- **Semantically meaningful** — BMP = world scripts; SMP/TIP = rare
  historical; SSP = tags; PUA = excluded.

Script-family partitioning (Latin vs CJK vs Symbols) is finer but
fragile: script boundaries shift, and a codepoint can belong to
multiple scripts (e.g., `U+002D -` is "Common" script).

## Plane catalog

essenfont ships subfonts for these planes only:

| Number | Symbol      | Range              | Notes                                  |
|--------|-------------|--------------------|----------------------------------------|
| 0      | `:plane_0`  | U+0000..U+FFFF     | BMP — world scripts, ~62k assigned     |
| 1      | `:plane_1`  | U+10000..U+1FFFF   | SMP — historical, emoji, music         |
| 2      | `:plane_2`  | U+20000..U+2FFFF   | SIP — CJK ideographs Ext B/C/D/E/F/I   |
| 3      | `:plane_3`  | U+30000..U+3FFFF   | TIP — CJK Ext C+J, Tangut, Khitan      |
| 14     | `:plane_14` | U+E0000..U+EFFFF   | SSP — language tags (small)            |

Excluded by build-level filter:

| Number | Reason                          |
|--------|---------------------------------|
| 15     | PUA-A — not assigned            |
| 16     | PUA-B — not assigned            |
| 4–13   | Reserved (no assignments)       |

## Algorithm

```
Input: cp_map (Hash<Integer, {label:, gid:}>), cap (default 65_534)
Output: Blueprint (list of Partition, each {name:, cps:, donor_map:})

1. Group cps by plane → Hash<plane_num, Array<cp>>
2. For each plane group:
     if group.size ≤ cap - 1:           # .notdef reservation
       partitions << Partition.new(name: plane_name(plane_num),
                                    cps: group)
     else:
       partitions += sub_split_by_block(plane_num, group, cap)
3. Return Blueprint.new(partitions)
```

## Block sub-split (rare path)

Triggered only when a single plane exceeds `cap - 1` unique glyphs.
Algorithm:

```
sub_split_by_block(plane_num, cps, cap):
  blocks = ucode_blocks_in_plane(plane_num)  # sorted by first_cp
  chunks = []
  current = []
  current_size = 0
  blocks.each do |block|
    block_cps = cps.select { |cp| block.cover?(cp) }
    if current_size + block_cps.size > cap - 1 && current.any?
      chunks << current
      current = []
      current_size = 0
    end
    current.concat(block_cps)
    current_size += block_cps.size
  end
  chunks << current if current.any?

  chunks.map.with_index do |chunk, i|
    Partition.new(name: "#{plane_name(plane_num)}_#{('a'.ord + i).chr}",
                  cps: chunk)
  end
```

Properties:

- **Block-bounded** — no chunk splits a Unicode block across two
  subfonts. A block lives entirely in one subfont.
- **Greedy fill** — each chunk is filled maximally before starting
  the next.
- **Stable naming** — chunks are suffixed `_a`, `_b`, `_c`, ... in
  codepoint order, so they don't reshuffle across Unicode versions.

## Why "cap - 1"?

Each subfont reserves gid 0 for `.notdef`. The cap is
`maxp.num_glyphs ≤ 65_535`, and `.notdef` is one of those, so the
maximum codepoint count per subfont is `65_534`.

In practice, Unicode 17's largest plane (BMP) has ~62k assigned
codepoints, well under the limit. The sub-split path is defensive —
it kicks in only if a future Unicode version balloons a plane.

## Donor map inheritance

The partition does NOT change donor assignment. `cp_map[cp][:label]`
remains the donor of record for `cp`. The partition only chooses
*which subfont's cmap* the cp ends up in.

The Stitcher session applies partitions in donor-grouped batches:

```ruby
blueprint.partitions.each do |partition|
  partition.cps.group_by { |cp| cp_map[cp][:label] }.each do |label, cps_in|
    stitcher.include_codepoints(cps_in, from: label, into: partition.name)
  end
  # Each subfont needs its own .notdef. Use the partition's first donor.
  first_donor = cp_map[partition.cps.first][:label]
  stitcher.include_notdef(from: first_donor, into: partition.name)
end
```

This minimizes round-trips through donor cmap lookups.

## Edge cases

1. **Empty partition.** If a plane has zero codepoints (e.g., SSP
   has no donors), the partition is *not* created. The OTC will
   have fewer subfonts. `Collection::Builder` requires ≥2 fonts;
   if only 1 plane has glyphs, fall back to single-TTF output.

2. **C0/C1 backfill.** Control codepoints (U+0000..U+001F,
   U+007F..U+009F) are assigned to donor gid 0 (.notdef). They
   still go into the BMP partition; the Stitcher's deduplicator
   collapses them onto a single glyph.

3. **Remapped donors.** Donors with `codepoint_remap` (Kelly
   Tolong → Tolong Siki, etc.) have their cmap mutated in-memory
   before stitching. The partition sees the *target* codepoints,
   not the source codepoints.

4. **PUA bleed.** Filtered before partition (existing build.rb
   behavior). Plane 15/16 never reach the partitioner.

5. **Out-of-range codepoints.** Codepoints > U+10FFFF (impossible
   per Unicode) are dropped with a warning.

## Pluggability (OCP)

`Partitioner` is an interface with one method:

```ruby
class Partitioner
  # @param cp_map [Hash<Integer, {label:, gid:}>]
  # @return [Blueprint]
  def partition(cp_map)
    raise NotImplementedError
  end
end
```

`PlanePartitioner` is the default. A future `ScriptPartitioner`
(partition by Unicode script property) or `LicensePartitioner`
(partition by donor license — useful for shipping an OFL-only OTC
separately from the FSung-NC OTC) plugs in without build changes.

The build pipeline accepts `partitioner:` as a constructor argument
to `Essenfont::Otc::Build`:

```ruby
Essenfont::Otc::Build.new(cp_map:, donors:, partitioner: PlanePartitioner.new)
                     .call(output_path: "Essenfont-Regular.otc")
```

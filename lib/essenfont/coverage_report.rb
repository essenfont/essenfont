# frozen_string_literal: true

module Essenfont
  # CoverageReport: per-block coverage computation for a set of codepoints.
  #
  # The core loop — iterate catalog blocks, count covered codepoints,
  # compute pct, classify status — was reimplemented in three scripts
  # (coverage_report.rb, gen-coverage-ttc.rb, gen-coverage-json.rb).
  # Each had a slightly different status classification and denominator.
  # This module is the single source of truth.
  #
  # Named CoverageReport (flat) rather than Coverage::Report because
  # Ruby's built-in coverage gem prevents the Coverage constant from
  # being defined under another module namespace.
  #
  # @example Basic usage
  #   report = Essenfont::CoverageReport.new(cmap_codepoints)
  #   report.per_block  # [{id, name, range, first, last, covered, total, pct, status}]
  #   report.summary    # {blocks, covered, total, pct, ...}
  #
  # @example UCD-aware denominator (only count assigned codepoints)
  #   report = Essenfont::CoverageReport.new(cmap_cps, assigned_filter: assigned_set)
  #
  class CoverageReport
    attr_reader :codepoints, :catalog, :assigned_filter

    # @param codepoints [Enumerable<Integer>] the covered codepoints
    # @param catalog [Ucode::Unicode::Catalog] defaults to UcodeRef.catalog
    # @param assigned_filter [Set<Integer>, nil] if given, only count
    #   these codepoints in the denominator (UCD-aware mode)
    def initialize(codepoints, catalog: nil, assigned_filter: nil)
      @codepoints = codepoints.to_set
      @catalog = catalog || Essenfont::UcodeRef.catalog
      @assigned_filter = assigned_filter
    end

    # Per-block coverage results, sorted by first codepoint.
    # @return [Array<Hash>]
    def per_block
      @per_block ||= catalog.all_blocks.map { |b| build_row(b) }.sort_by { |r| r[:first] }
    end

    # Aggregate summary across all blocks.
    # @return [Hash]
    def summary
      rows = per_block
      assigned = rows.reject { |r| r[:status] == "RESERVED" }

      total = assigned.sum { |r| r[:total] }
      covered = assigned.sum { |r| [r[:covered], r[:total]].min }

      {
        blocks: rows.size,
        assigned_blocks: assigned.size,
        reserved_blocks: rows.size - assigned.size,
        empty: assigned.count { |r| r[:covered].zero? },
        complete: assigned.count { |r| ["COMPLETE", "FULL"].include?(r[:status]) },
        covered: covered,
        total: total,
        pct: total.positive? ? (100.0 * covered / total).round(4) : 0
      }
    end

    private

    def build_row(block)
      first = block.first_cp
      last = block.last_cp

      total = denominator(first, last)
      covered = count_covered(first, last)
      pct = total.positive? ? (100.0 * covered / total).round(2) : 0

      {
        id: block.id,
        name: block.name,
        range: "U+#{first.to_s(16).upcase}..U+#{last.to_s(16).upcase}",
        first: first,
        last: last,
        covered: covered,
        total: total,
        pct: pct,
        status: classify(pct, covered, total)
      }
    end

    def denominator(first, last)
      return (first..last).size unless assigned_filter

      (first..last).count { |cp| assigned_filter.include?(cp) }
    end

    def count_covered(first, last)
      if assigned_filter
        codepoints.count { |cp| cp.between?(first, last) && assigned_filter.include?(cp) }
      else
        codepoints.count { |cp| cp.between?(first, last) }
      end
    end

    def classify(pct, covered, total)
      if total.zero? then "RESERVED"
      elsif covered >= total then "COMPLETE"
      elsif pct >= 95 then "FULL"
      elsif pct >= 50 then "MOSTLY"
      elsif pct.positive? then "PARTIAL"
      else "EMPTY"
      end
    end
  end
end

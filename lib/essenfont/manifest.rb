# frozen_string_literal: true

require "yaml"

module Essenfont
  # Manifest: typed access to sources/manifest.yml.
  #
  # Single source of truth for the donor registry. Replaces the
  # YAML.safe_load + iterate pattern duplicated across 6 scripts.
  module Manifest
    autoload :Entry, "essenfont/manifest/entry"

    DEFAULT_PATH = File.expand_path("../../sources/manifest.yml", __dir__)

    # Load the manifest from a YAML file.
    #
    # @param path [String] defaults to sources/manifest.yml relative to the lib root
    # @return [Manifest::Collection]
    def self.load(path: DEFAULT_PATH)
      Collection.new(path: path)
    end

    # In-memory manifest built from a pre-parsed hash. Useful in tests.
    def self.from_hash(hash)
      Collection.new(entries: hash.fetch("donors", []).map { |h| Entry.new(h) })
    end

    class Collection
      include Enumerable

      def initialize(path: nil, entries: nil)
        if entries
          @entries = entries
        elsif path
          raise Essenfont::Otc::Errors::ManifestMissing,
                "manifest not found: #{path}" unless File.exist?(path)

          @entries = parse(File.read(path))
        else
          raise ArgumentError, "Manifest::Collection requires path: or entries:"
        end
        freeze
      end

      attr_reader :entries

      def each(&)
        @entries.each(&)
      end

      def size
        @entries.size
      end

      # Donors that aren't disabled (`enabled: false` in the manifest).
      def active
        @entries.reject { |e| e.enabled == false }
      end

      # Find an entry by label (Symbol or String).
      def find(label)
        target = label.to_sym
        @entries.find { |e| e.label.to_sym == target }
      end

      # All distinct Unicode blocks declared across all entries' `covers:` lists.
      def declared_blocks
        @entries.flat_map(&:covers).uniq
      end

      private

      def parse(yaml_str)
        data = YAML.safe_load(yaml_str)
        donors = data.fetch("donors", [])
        donors.map { |h| Entry.new(h) }
      end
    end
  end
end

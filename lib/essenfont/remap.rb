# frozen_string_literal: true

require "yaml"

module Essenfont
  # Remap: loads a codepoint remap YAML file into a {from_cp => to_cp} Hash.
  #
  # Previously duplicated between DonorLoader#load_remap and
  # donor_audit.rb's self.load_remap — two adapters with the same YAML
  # parsing logic but different path resolution. This module is the
  # single source of truth.
  #
  # The YAML format is:
  #   mappings:
  #     - from: 0xE000    # source codepoint in the donor's cmap
  #       to: 0x11100     # target Unicode codepoint
  #
  module Remap
    module_function

    # Load a remap YAML, searching multiple directories for the file.
    #
    # @param spec [String, nil] filename or path to the remap YAML
    # @param search_dirs [Array<String>] directories to search if spec
    #   is not an existing path
    # @return [Hash<Integer, Integer>, nil] {from_cp => to_cp}, or nil
    #   if spec is nil, the file is not found, or has no mappings
    def load(spec, search_dirs: [])
      return nil unless spec

      path = resolve(spec, search_dirs)
      return nil unless path

      data = YAML.safe_load_file(path)
      mappings = data&.fetch("mappings", []) || []
      return nil if mappings.empty?

      mappings.to_h { |m| [m.fetch("from"), m.fetch("to")] }
    end

    def resolve(spec, search_dirs)
      return spec if File.exist?(spec)

      search_dirs.each do |dir|
        candidate = File.join(dir, File.basename(spec))
        return candidate if File.exist?(candidate)
      end

      nil
    end
  end
end

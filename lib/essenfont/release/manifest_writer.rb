# frozen_string_literal: true

require "json"
require "time"

module Essenfont
  module Release
    # ManifestWriter: emits release-manifest.json — the top-level index
    # of every artifact in the release directory.
    module ManifestWriter
      module_function

      # @param out_dir [String] release output directory
      def emit(out_dir:)
        data = {
          essenfont_version: Essenfont::Otc::Version::STRING,
          ucd_version: Essenfont::UcodeRef.unicode_version,
          generated_at: Time.now.utc.iso8601,
          artifacts: Dir.children(out_dir).sort
        }
        File.write(File.join(out_dir, "release-manifest.json"), JSON.pretty_generate(data))
      end
    end
  end
end

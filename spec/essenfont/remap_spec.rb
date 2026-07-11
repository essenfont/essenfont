# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Essenfont::Remap do
  let(:remap_yaml) do
    <<~YAML
      mappings:
        - from: 0xE000
          to: 0x11100
        - from: 0xE001
          to: 0x11101
    YAML
  end

  let(:dir) { Dir.mktmpdir("remap-spec-") }

  after { FileUtils.rm_rf(dir) }

  def write_remap(name, content = remap_yaml)
    path = File.join(dir, name)
    File.write(path, content)
    path
  end

  describe ".load" do
    it "parses a remap YAML into a {from => to} Hash" do
      path = write_remap("test-remap.yml")
      result = described_class.load(path, search_dirs: [])

      expect(result).to eq({ 0xE000 => 0x11100, 0xE001 => 0x11101 })
    end

    it "returns nil when spec is nil" do
      expect(described_class.load(nil, search_dirs: [])).to be_nil
    end

    it "returns nil when the file is not found" do
      expect(described_class.load("nonexistent.yml", search_dirs: [dir])).to be_nil
    end

    it "finds the file by basename in search_dirs" do
      write_remap("coptic.yml")
      result = described_class.load("coptic.yml", search_dirs: [dir])
      expect(result).to eq({ 0xE000 => 0x11100, 0xE001 => 0x11101 })
    end

    it "uses the spec directly if it is an existing path" do
      path = write_remap("absolute.yml")
      result = described_class.load(path, search_dirs: [])
      expect(result).not_to be_nil
    end

    it "returns nil when mappings is empty" do
      write_remap("empty.yml", "mappings: []\n")
      result = described_class.load("empty.yml", search_dirs: [dir])
      expect(result).to be_nil
    end

    it "returns nil when mappings key is absent" do
      write_remap("no-key.yml", "other: stuff\n")
      result = described_class.load("no-key.yml", search_dirs: [dir])
      expect(result).to be_nil
    end

    it "searches multiple directories" do
      dir2 = Dir.mktmpdir("remap-spec2-")
      begin
        File.write(File.join(dir2, "multi.yml"), remap_yaml)
        result = described_class.load("multi.yml", search_dirs: [dir, dir2])
        expect(result).not_to be_nil
      ensure
        FileUtils.rm_rf(dir2)
      end
    end
  end
end

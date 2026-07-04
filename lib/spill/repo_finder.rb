module Spill
  module RepoFinder
    def self.find(root)
      root = File.expand_path(root)
      candidates = [ root ] + Dir.glob(File.join(root, "*")) + Dir.glob(File.join(root, "*", "*"))
      candidates.select { |dir| File.directory?(File.join(dir, ".git")) }.sort
    end
  end
end

require_relative 'lib/buttress/version'

Gem::Specification.new do |spec|
  spec.name          = "buttress"
  spec.version       = Buttress::VERSION
  spec.authors       = ["Robert Fletcher"]
  spec.email         = ["lobatifricha@gmail.com"]

  spec.summary       = %q{Buttress helps automate testing for your codebase}
  spec.homepage      = "https://github.com/mockdeep/buttress"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 1.8.7")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mockdeep/buttress"
  spec.metadata["source_code_uri"] = "https://github.com/mockdeep/buttress"
  spec.metadata["changelog_uri"] = "https://github.com/mockdeep/buttress/blob/main/CHANGELOG.md"

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(spec)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end

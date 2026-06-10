module Buttress
  # Represents the Ruby version of the codebase under analysis. Owns
  # everything that varies by version: which parser grammar to use, and
  # eventually the emitted spec dialect and core method semantics.
  class Target
    PARSERS = {
      '1.8' => 'Parser::Ruby18',
      '1.9' => 'Parser::Ruby19',
      '2.0' => 'Parser::Ruby20',
      '2.1' => 'Parser::Ruby21',
      '2.2' => 'Parser::Ruby22',
      '2.3' => 'Parser::Ruby23',
      '2.4' => 'Parser::Ruby24',
      '2.5' => 'Parser::Ruby25',
      '2.6' => 'Parser::Ruby26',
      '2.7' => 'Parser::Ruby27',
      '3.0' => 'Parser::Ruby30',
      '3.1' => 'Parser::Ruby31',
      '3.2' => 'Parser::Ruby32',
      '3.3' => 'Parser::Ruby33',
    }.freeze

    # The newest grammar shipped by the parser gem. Used instead of
    # 'parser/current' to avoid mismatch warnings when the host Ruby is
    # newer than the gem's grammars.
    DEFAULT_VERSION = PARSERS.keys.last

    attr_reader :version

    def self.default
      new(nil)
    end

    def initialize(version)
      @version = version || DEFAULT_VERSION
      return if PARSERS.key?(@version)

      raise Error, "unsupported target Ruby version: #{@version.inspect} " \
                   "(supported: #{PARSERS.keys.join(', ')})"
    end

    # Versions from the RSpec 1.x/2.x era get the classic dialect (bare
    # describe, should syntax); everything newer gets the modern dialect
    # (RSpec.describe, expect syntax).
    LEGACY_RSPEC_VERSIONS = %w[1.8 1.9].freeze

    def parse(code)
      parser.parse(Parser::Source::Buffer.new('(buttress)', source: code))
    end

    def describe
      legacy_rspec? ? 'describe' : 'RSpec.describe'
    end

    def assertion(actual, expected)
      if legacy_rspec?
        "#{actual}.should == #{expected}"
      else
        "expect(#{actual}).to eq(#{expected})"
      end
    end

    # RSpec 3 fails a pending example whose body passes, so modern targets
    # get skip; legacy RSpec predates skip, so they get pending.
    def skip(reason)
      message = reason.gsub("'", '"')
      legacy_rspec? ? "pending '#{message}'" : "skip '#{message}'"
    end

    # Keyword-style hash syntax only exists from 1.9 on.
    def hash_pair(key, rendered_value)
      if version == '1.8'
        ":#{key} => #{rendered_value}"
      else
        "#{key}: #{rendered_value}"
      end
    end

    private

    def legacy_rspec?
      LEGACY_RSPEC_VERSIONS.include?(version)
    end

    # A parser that raises on syntax errors without also printing
    # diagnostics to stderr, unlike the Parser::Base.parse shortcut.
    def parser
      require "parser/ruby#{version.delete('.')}"
      parser = Object.const_get(PARSERS.fetch(version)).new
      parser.diagnostics.all_errors_are_fatal = true
      parser.diagnostics.ignore_warnings = true
      parser
    end
  end
end

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

    def parser
      require "parser/ruby#{version.delete('.')}"
      Object.const_get(PARSERS.fetch(version))
    end
  end
end

module Buttress
  # An expected value only the target runtime can compute: a message
  # chain on the subject instance, rendered into the assertion's
  # expected side so both sides evaluate in the same process. This is
  # how process-seeded methods (String#hash) become assertable — the
  # seed cancels out, and because the chain reads the very object the
  # method used, equality holds under any hash semantics, identity
  # included.
  class SubjectCall
    def initialize(subject:, messages:)
      @subject = subject
      @messages = messages
    end

    def render
      ([@subject] + @messages).join('.')
    end

    def inspect
      render
    end
  end
end

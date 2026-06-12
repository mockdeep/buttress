module Buttress
  # A symbolic Array#cycle: the cycled items plus a cursor, standing in
  # for the host Enumerator (which is infinite and can't Marshal across
  # the replay's deep-dup boundary). #next answers deterministically
  # because every interpreted cycle starts fresh, exactly like the one
  # the generated test's constructor call will build. Holds only plain
  # values, like InstanceValue.
  class CycleValue
    def initialize(items)
      @items = items
      @cursor = 0
    end

    def next
      value = @items.fetch(@cursor % @items.size)
      @cursor += 1
      value
    end
  end
end

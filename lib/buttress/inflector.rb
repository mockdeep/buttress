module Buttress
  # The bare minimum of inflection buttress needs, kept dependency-free.
  # Irregular plurals are out of scope: a miss means a model's table
  # isn't found and its tests degrade gracefully.
  module Inflector
    def self.underscore(name)
      name.split('::').last
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
    end

    def self.pluralize(word)
      case word
      when /(?:s|x|z|ch|sh)\z/ then "#{word}es"
      when /[^aeiou]y\z/ then "#{word[0..-2]}ies"
      else "#{word}s"
      end
    end

    def self.tableize(class_name)
      pluralize(underscore(class_name))
    end
  end
end

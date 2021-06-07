# frozen_string_literal: true

module ActiveRecord
  module PGExtensions
    # Contains general additions to the PostgreSQLAdapter
    module PostgreSQLAdapter
      Extension = Struct.new(:name, :schema, :version)
    end
  end
end

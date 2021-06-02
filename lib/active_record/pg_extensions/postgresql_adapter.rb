# frozen_string_literal: true

module ActiveRecord
  module PGExtensions
    # Contains general additions to the PostgreSQLAdapter
    module PostgreSQLAdapter
      # set constraint check timing for the current transaction
      # see https://www.postgresql.org/docs/current/sql-set-constraints.html
      def set_constraints(deferred, *constraints)
        raise ArgumentError, "deferred must be :deferred or :immediate" unless %w[deferred
                                                                                  immediate].include?(deferred.to_s)

        constraints = constraints.map { |c| quote_table_name(c) }.join(", ")
        constraints = "ALL" if constraints.empty?
        execute("SET CONSTRAINTS #{constraints} #{deferred.to_s.upcase}")
      end
    end
  end
end

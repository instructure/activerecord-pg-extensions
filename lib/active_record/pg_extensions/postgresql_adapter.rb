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

      # defers constraints, yields to the caller, and then resets back to immediate
      # note that the reset back to immediate is _not_ in an ensure block, since any
      # error thrown would likely mean the transaction is rolled back, and setting
      # constraint checking back to immediate would also fail
      def defer_constraints(*constraints)
        set_constraints(:deferred, *constraints)
        yield
        set_constraints(:immediate, *constraints)
      end

      # see https://www.postgresql.org/docs/current/sql-altertable.html#SQL-CREATETABLE-REPLICA-IDENTITY
      def set_replica_identity(table, identity = :default)
        identity_clause = case identity
                          when :default, :full, :nothing
                            identity.to_s.upcase
                          else
                            "USING INDEX #{quote_column_name(identity)}"
                          end
        execute("ALTER TABLE #{quote_table_name(table)} REPLICA IDENTITY #{identity_clause}")
      end
    end
  end
end

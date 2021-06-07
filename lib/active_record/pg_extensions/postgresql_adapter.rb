# frozen_string_literal: true

require "active_record/pg_extensions/extension"

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

      # see https://www.postgresql.org/docs/current/sql-createextension.html
      def create_extension(extension, if_not_exists: false, schema: nil, version: nil, cascade: false)
        sql = +"CREATE EXTENSION "
        sql <<= "IF NOT EXISTS " if if_not_exists
        sql << extension.to_s
        sql << " SCHEMA #{schema}" if schema
        sql << " VERSION #{quote(version)}" if version
        sql << " CASCADE" if cascade
        execute(sql)
        @extensions&.delete(extension.to_s)
      end

      # see https://www.postgresql.org/docs/current/sql-alterextension.html
      def alter_extension(extension, schema: nil, version: nil)
        if schema && version
          raise ArgumentError, "Cannot change schema and upgrade to a particular version in a single statement"
        end

        sql = +"ALTER EXTENSION #{extension}"
        sql << " UPDATE" if version
        sql << " TO #{quote(version)}" if version && version != true
        sql << " SET SCHEMA #{schema}" if schema
        execute(sql)
        @extensions&.delete(extension.to_s)
      end

      # see https://www.postgresql.org/docs/current/sql-dropextension.html
      def drop_extension(*extensions, if_exists: false, cascade: false)
        raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if extensions.empty?

        sql = +"DROP EXTENSION "
        sql << "IF EXISTS " if if_exists
        sql << extensions.join(", ")
        sql << " CASCADE" if cascade
        execute(sql)
        @extensions&.except!(*extensions.map(&:to_s))
      end

      # check if a particular extension can be installed
      def extension_available?(extension, version = nil)
        sql = +"SELECT 1 FROM "
        sql << version ? "pg_available_extensions" : "pg_available_extension_versions"
        sql << " WHERE name=#{quote(extension)}"
        sql << " AND version=#{quote(version)}" if version
        select_value(sql).to_i == 1
      end

      # returns an Extension object for a particular extension
      def extension(extension)
        @extensions ||= {}
        @extensions.fetch(extension.to_s) do
          rows = select_rows(<<~SQL, "SCHEMA")
            SELECT nspname, extversion
            FROM pg_extension
              INNER JOIN pg_namespace ON extnamespace=pg_namespace.oid
            WHERE extname=#{quote(extension)}
          SQL
          next nil if rows.empty?

          Extension.new(extension.to_s, rows[0][0], rows[0][1])
        end
      end

      # temporarily adds schema to the search_path (i.e. so you can use an extension that won't work
      # without being on the search path, such as postgis)
      def add_schema_to_search_path(schema)
        if schema_search_path.split(",").include?(schema)
          yield
        else
          old_search_path = schema_search_path
          manual_rollback = false
          transaction(requires_new: true) do
            self.schema_search_path += ",#{schema}"
            yield
            self.schema_search_path = old_search_path
          rescue ActiveRecord::StatementInvalid, ActiveRecord::Rollback => e
            # the transaction rolling back will revert the search path change;
            # we don't need to do another query to set it
            @schema_search_path = old_search_path
            manual_rollback = e if e.is_a?(ActiveRecord::Rollback)
            raise
          end
          # the transaction call will swallow ActiveRecord::Rollback,
          # but we want it this method to be transparent
          raise manual_rollback if manual_rollback
        end
      end

      # see https://www.postgresql.org/docs/current/sql-vacuum.html
      def vacuum(*table_and_columns,
                 full: false,
                 freeze: false,
                 verbose: false,
                 analyze: false,
                 disable_page_skipping: false,
                 skip_locked: false,
                 index_cleanup: false,
                 truncate: false,
                 parallel: nil)
        if parallel && !(parallel.is_a?(Integer) && parallel.positive?)
          raise ArgumentError, "parallel must be a positive integer"
        end

        sql = +"VACUUM"
        sql << " FULL" if full
        sql << " FREEZE" if freeze
        sql << " VERBOSE" if verbose
        sql << " ANALYZE" if analyze
        sql << " DISABLE_PAGE_SKIPPING" if disable_page_skipping
        sql << " SKIP_LOCKED" if skip_locked
        sql << " INDEX_CLEANUP" if index_cleanup
        sql << " TRUNCATE" if truncate
        sql << " PARALLEL #{parallel}" if parallel
        sql << " " unless table_and_columns.empty?
        sql << table_and_columns.map do |table|
          if table.is_a?(Hash)
            raise ArgumentError, "columns may only be specified if a analyze is specified" unless analyze

            table.map do |table_name, columns|
              "#{quote_table_name(table_name)} (#{Array.wrap(columns).map { |c| quote_column_name(c) }.join(', ')})"
            end.join(", ")
          else
            quote_table_name(table)
          end
        end.join(", ")
        execute(sql)
      end
    end
  end
end

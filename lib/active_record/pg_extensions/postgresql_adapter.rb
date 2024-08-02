# frozen_string_literal: true

require "active_record/pg_extensions/extension"

module ActiveRecord
  module PGExtensions
    # Contains general additions to the PostgreSQLAdapter
    module PostgreSQLAdapter
      # set constraint check timing for the current transaction
      # see https://www.postgresql.org/docs/current/sql-set-constraints.html
      def set_constraints(deferred, *constraints)
        raise ArgumentError, "deferred must be :deferred or :immediate" unless %i[deferred
                                                                                  immediate].include?(deferred.to_sym)

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
        reload_type_map
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
        reload_type_map
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
        reload_type_map
        @extensions&.except!(*extensions.map(&:to_s))
      end

      # check if a particular extension can be installed
      def extension_available?(extension, version = nil)
        sql = +"SELECT 1 FROM "
        sql << (version ? "pg_available_extension_versions" : "pg_available_extensions")
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
          result = nil
          transaction(requires_new: true) do
            self.schema_search_path += ",#{schema}"
            result = yield
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

          result
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
              "#{quote_table_name(table_name)} (#{Array.wrap(columns).map { |c| quote_column_name(c) }.join(", ")})"
            end.join(", ")
          else
            quote_table_name(table)
          end
        end.join(", ")
        execute(sql)
      end

      # Amazon Aurora doesn't have a WAL
      def wal?
        unless instance_variable_defined?(:@has_wal)
          function_name = pre_pg10_wal_function_name("pg_current_wal_lsn")
          @has_wal = select_value("SELECT true FROM pg_proc WHERE proname='#{function_name}' LIMIT 1")
        end
        @has_wal
      end

      # see https://www.postgresql.org/docs/current/functions-admin.html#id-1.5.8.33.5.5.2.2.4.1.1.1
      def current_wal_lsn
        return nil unless wal?

        select_value("SELECT #{pre_pg10_wal_function_name("pg_current_wal_lsn")}()")
      end

      # see https://www.postgresql.org/docs/current/functions-admin.html#id-1.5.8.33.5.5.2.2.2.1.1.1
      def current_wal_flush_lsn
        return nil unless wal?

        select_value("SELECT #{pre_pg10_wal_function_name("pg_current_wal_flush_lsn")}()")
      end

      # see https://www.postgresql.org/docs/current/functions-admin.html#id-1.5.8.33.5.5.2.2.3.1.1.1
      def current_wal_insert_lsn
        return nil unless wal?

        select_value("SELECT #{pre_pg10_wal_function_name("pg_current_wal_insert_lsn")}()")
      end

      # https://www.postgresql.org/docs/current/functions-admin.html#id-1.5.8.33.6.3.2.2.2.1.1.1
      def last_wal_receive_lsn
        return nil unless wal?

        select_value("SELECT #{pre_pg10_wal_function_name("pg_last_wal_receive_lsn")}()")
      end

      # see https://www.postgresql.org/docs/current/functions-admin.html#id-1.5.8.33.6.3.2.2.3.1.1.1
      def last_wal_replay_lsn
        return nil unless wal?

        select_value("SELECT #{pre_pg10_wal_function_name("pg_last_wal_replay_lsn")}()")
      end

      # see https://www.postgresql.org/docs/current/functions-admin.html#id-1.5.8.33.5.5.2.2.4.1.1.1
      # lsns can be literals, or :current, :current_flush, :current_insert, :last_receive, or :last_replay
      def wal_lsn_diff(lsn1 = :current, lsn2 = :last_replay)
        return nil unless wal?

        lsns = [lsn1, lsn2].map do |lsn|
          case lsn
          when :current then pre_pg10_wal_function_name("pg_current_wal_lsn()")
          when :current_flush then pre_pg10_wal_function_name("pg_current_flush_wal_lsn()")
          when :current_insert then pre_pg10_wal_function_name("pg_current_insert_wal_lsn()")
          when :last_receive then pre_pg10_wal_function_name("pg_last_wal_receive_lsn()")
          when :last_replay then pre_pg10_wal_function_name("pg_last_wal_replay_lsn()")
          else; quote(lsn)
          end
        end

        select_value("SELECT #{pre_pg10_wal_function_name("pg_wal_lsn_diff")}(#{lsns[0]}, #{lsns[1]})")
      end

      def in_recovery?
        select_value("SELECT pg_is_in_recovery()")
      end

      def set(configuration_parameter, value, local: false)
        value = value.nil? ? "DEFAULT" : quote(value)
        execute("SET#{" LOCAL" if local} #{configuration_parameter} TO #{value}")
      end

      def reset(configuration_parameter)
        execute("RESET #{configuration_parameter}")
      end

      TIMEOUTS = %i[lock_timeout statement_timeout idle_in_transaction_session_timeout].freeze

      TIMEOUTS.each do |kind|
        class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{kind}
            current_transaction.#{kind}
          end

          def #{kind}=(timeout)
            raise ArgumentError, "Timeouts can only be set inside of a transaction" unless current_transaction.open?

            current_transaction.send(:#{kind}=, timeout)
          end
        RUBY
      end

      # @deprecated: manage the transaction yourself and set statement_timeout directly
      #
      # otherwise, if you're already in a transaction, or you nest with_statement_timeout,
      # the value will unexpectedly "stick" even after the block returns
      def with_statement_timeout(timeout = nil)
        timeout = 30 if timeout.nil? || timeout == true

        transaction do
          self.statement_timeout = timeout
          yield
        end
      end

      private

      def initialize_type_map(map = type_map)
        map.register_type "pg_lsn", ActiveRecord::ConnectionAdapters::PostgreSQL::OID::SpecializedString.new(:pg_lsn)

        super
      end

      def pre_pg10_wal_function_name(func)
        return func if postgresql_version >= 100_000

        func.sub("wal", "xlog").sub("lsn", "location")
      end
    end
  end
end

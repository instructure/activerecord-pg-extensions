# frozen_string_literal: true

module ActiveRecord
  module PGExtensions
    # Changes several DDL commands to trigger background queries to warm caches prior
    # to executing, in order to reduce the amount of time the actual DDL takes to
    # execute (and thus how long it needs the lock)
    module PessimisticMigrations
      # does a query first to warm the db cache, to make the actual constraint adding fast
      def change_column_null(table, column, nullness, default = nil)
        # no point in pre-warming the cache to avoid locking if we're already in a transaction
        return super if nullness != false || open_transactions.positive?

        transaction do
          # make sure the query ignores indexes, because the actual ALTER TABLE will also ignore
          # indexes
          execute("SET LOCAL enable_indexscan=off")
          execute("SET LOCAL enable_bitmapscan=off")
          execute("SELECT COUNT(*) FROM #{quote_table_name(table)} WHERE #{quote_column_name(column)} IS NULL")
          raise ActiveRecord::Rollback
        end
        super
      end

      # several improvements:
      #  * support if_not_exists
      #  * delay_validation automatically creates the FK as NOT VALID, and then immediately validates it
      #  * if delay_validation is used, and the index already exists but is NOT VALID, it just re-tries
      #    the validation, instead of failing
      def add_foreign_key(from_table, to_table, delay_validation: false, if_not_exists: false, **options)
        # pointless if we're in a transaction
        delay_validation = false if open_transactions.positive?
        options[:validate] = false if delay_validation

        options = foreign_key_options(from_table, to_table, options)

        if if_not_exists || delay_validation
          scope = quoted_scope(options[:name])
          valid = select_value(<<~SQL, "SCHEMA")
            SELECT convalidated FROM pg_constraint INNER JOIN pg_namespace ON pg_namespace.oid=connamespace WHERE conname=#{scope[:name]} AND nspname=#{scope[:schema]}
          SQL
          return if valid == true && if_not_exists
        end

        super(from_table, to_table, **options) unless valid == false
        validate_constraint(from_table, options[:name]) if delay_validation
      end
    end
  end
end

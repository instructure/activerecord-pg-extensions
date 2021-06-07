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
        return super if nullness != false || open_transactions != 0

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
    end
  end
end

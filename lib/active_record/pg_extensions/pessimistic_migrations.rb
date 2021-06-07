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

      # will automatically remove a NOT VALID index before trying to add
      def add_index(table_name, column_name, options = {})
        # catch a concurrent index add that fails because it already exists, and is invalid
        if options[:algorithm] == :concurrently || options[:if_not_exists]
          column_names = index_column_names(column_name)
          index_name = options[:name].to_s if options.key?(:name)
          index_name ||= index_name(table_name, column_names)

          index = quoted_scope(index_name)
          table = quoted_scope(table_name)
          valid = select_value(<<~SQL, "SCHEMA")
            SELECT indisvalid
            FROM pg_class t
            INNER JOIN pg_index d ON t.oid = d.indrelid
            INNER JOIN pg_class i ON d.indexrelid = i.oid
            WHERE i.relkind = 'i'
              AND i.relname = #{index[:name]}
              AND t.relname = #{table[:name]}
              AND i.relnamespace IN (SELECT oid FROM pg_namespace WHERE nspname = #{index[:schema]} )
            LIMIT 1
          SQL
          if valid == false && options[:algorithm] == :concurrently
            remove_index(table_name, name: index_name,
                                     algorithm: :concurrently)
          end
          return if options[:if_not_exists] && valid == true
        end
        # Rails.version: can stop doing this in Rails 6.2, when it's natively supported
        options.delete(:if_not_exists)
        super
      end
    end
  end
end

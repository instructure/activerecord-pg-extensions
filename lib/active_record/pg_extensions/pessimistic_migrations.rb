# frozen_string_literal: true

module ActiveRecord
  module PGExtensions
    # Changes several DDL commands to trigger background queries to warm caches prior
    # to executing, in order to reduce the amount of time the actual DDL takes to
    # execute (and thus how long it needs the lock)
    module PessimisticMigrations
      # adds a temporary check constraint to reduce locking when changing to NOT NULL, and we're not in a transaction
      def change_column_null(table, column, nullness, default = nil)
        # no point in doing extra work to avoid locking if we're already in a transaction
        return super if nullness != false || open_transactions.positive?
        return if columns(table).find { |c| c.name == column.to_s }&.null == false

        # PG identifiers max out at 63 characters
        temp_constraint_name = "chk_rails_#{table}_#{column}_not_null"[0...63]
        scope = quoted_scope(temp_constraint_name)
        # check for temp constraint
        valid = select_value(<<~SQL, "SCHEMA")
          SELECT convalidated FROM pg_constraint INNER JOIN pg_namespace ON pg_namespace.oid=connamespace WHERE conname=#{scope[:name]} AND nspname=#{scope[:schema]}
        SQL
        if valid.nil?
          add_check_constraint(table,
                               "#{quote_column_name(column)} IS NOT NULL",
                               name: temp_constraint_name,
                               validate: false)
        end
        begin
          validate_constraint(table, temp_constraint_name)
        rescue PG::CheckViolation => e
          raise ActiveRecord::NotNullViolation.new(sql: e.sql, binds: e.binds)
        end

        transaction do
          super
          remove_check_constraint(table, name: temp_constraint_name)
        end
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
      def add_index(table_name, column_name, **options)
        # catch a concurrent index add that fails because it already exists, and is invalid
        if options[:algorithm] == :concurrently && options[:if_not_exists]
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
          return if valid == true

          remove_index(table_name, name: index_name, algorithm: :concurrently) if valid == false
        end
        super
      end

      # Replace one check constraint with another
      #
      # @param table [Symbol] The table name
      # @param from [String, Hash] The check constraint to be replaced.
      #   If a Hash is provided, it must contain an :expression key with the check constraint expression.
      #   Other options are merged with `options` and passed through.
      # @param to [String, Hash] The new check constraint to be added.
      #   If a Hash is provided, it must contain an :expression key with the check constraint expression.
      #   Other options are merged with `options` and passed through.
      # @param if_exists [true, false] If true, the entire operation should be idempotent (only
      #   dropping/renaming the old constraint if it exists, only adding the new constraint if it doesn't exist.)
      # @param delay_validation [true, false] If true, the new check constraint will be added as NOT VALID and
      #   validated before removing the old check constraint.
      def change_check_constraint(table, from:, to:, if_exists: false, delay_validation: false, **options)
        delay_validation = false if open_transactions.positive?
        options[:validate] = false if delay_validation

        from_expression, from_options = split_arg(from, :expression, options)
        to_expression, to_options = split_arg(to, :expression, options)

        new_constraint_name = check_constraint_name(table, expression: to_expression, **to_options)
        # when delaying validation, we don't drop the old constraint until after the new one is validated,
        # so we need to rename it if the names are the same
        if delay_validation
          old_constraint_name = check_constraint_name(table, expression: from_expression, **from_options)
          if old_constraint_name == new_constraint_name
            new_old_constraint_name = temporary_name(old_constraint_name)
            unless check_constraint_exists?(table, name: new_old_constraint_name)
              rename_constraint(table, old_constraint_name, new_old_constraint_name, if_exists:)
            end
            old_constraint_name = new_old_constraint_name
          end
        else
          remove_check_constraint(table, from_expression, if_exists:, **from_options)
        end

        add_check_constraint(table,
                             to_expression,
                             **to_options,
                             if_not_exists: if_exists || delay_validation,
                             validate: !delay_validation)

        return unless delay_validation

        validate_constraint(table, new_constraint_name)
        remove_check_constraint(table, name: old_constraint_name, if_exists: true)
      end

      # Replace one index with another
      #
      # @param table [Symbol] The table name
      # @param from [String, Symbol, Array, Hash] The index to be replaced.
      #   If a Hash is provided, it must contain a :column key with the indexed column(s).
      #   Other options are merged with `options` and passed through.
      # @param to [String, Symbol, Array, Hash] The new index to be added.
      #   If a Hash is provided, it must contain a :column key with the indexed column(s).
      #   Other options are merged with `options` and passed through.
      # @param if_exists [true, false] If true, the entire operation should be idempotent (only
      #   dropping/renaming the old index if it exists, only adding the new index if it doesn't exist.)
      # @param algorithm [Symbol, nil] If :concurrently, the new index is created concurrently and the
      #   old index is only removed after the new one exists.
      def change_index(table, from:, to:, if_exists: false, algorithm: nil, **options)
        algorithm = nil if open_transactions.positive?
        concurrently = algorithm == :concurrently

        from_column, from_options = split_arg(from, :column, options)
        to_column, to_options = split_arg(to, :column, options)

        new_index_name = to_options[:name]&.to_s || index_name(table, column: to_column)
        # when creating concurrently, we don't drop the old index until after the new one is created,
        # so we need to rename it if the names are the same
        if concurrently
          old_index_name = from_options[:name]&.to_s || index_name(table, column: from_column)
          if old_index_name == new_index_name
            new_old_index_name = temporary_name(old_index_name)
            # rename_index has no if_exists option, so guard it: skip if the old index is missing
            # (only relevant when if_exists makes the whole operation idempotent) or the temp name is taken
            old_missing = if_exists && !index_name_exists?(table, old_index_name)
            unless old_missing || index_name_exists?(table, new_old_index_name)
              rename_index(table, old_index_name, new_old_index_name)
            end
            old_index_name = new_old_index_name
          end
        else
          remove_index(table, from_column, if_exists:, **from_options)
        end

        add_index(table,
                  to_column,
                  **to_options,
                  if_not_exists: if_exists || concurrently,
                  algorithm:)

        return unless concurrently

        remove_index(table, name: old_index_name, if_exists: true, algorithm: :concurrently)
      end

      private

      # splits a from/to argument into its subject and options. If a Hash is given, the given key
      # (e.g. :column or :expression) is extracted and the rest is merged with options; otherwise
      # the argument is treated as the subject itself.
      def split_arg(arg, key, options)
        return [arg, options] unless arg.is_a?(Hash)

        arg_options = arg.merge(options)
        [arg_options.delete(key), arg_options]
      end

      # derives a temporary name from +name+ to rename an existing index/constraint out of the way.
      # Prefers a readable "<name>_to_be_replaced", but falls back to a hashed (still deterministic,
      # still unique to +name+) form when that would exceed the database's identifier length limit,
      # following the same scheme Rails uses for long index names.
      def temporary_name(name)
        suffixed = "#{name}_to_be_replaced"
        return suffixed if suffixed.bytesize <= max_identifier_length

        hashed_identifier = "_#{OpenSSL::Digest::SHA256.hexdigest(name.to_s).first(10)}"
        short_name = name.to_s.truncate_bytes(max_identifier_length - hashed_identifier.bytesize, omission: nil)
        "#{short_name}#{hashed_identifier}"
      end
    end
  end
end

# frozen_string_literal: true

module ActiveRecord
  module PGExtensions
    # adds support for reverting migration methods added by this gem
    module CommandRecorder
      def rename_constraint(table_name, old_name, new_name, **options)
        record(:rename_constraint, [table_name, old_name, new_name, options])
      end

      def invert_rename_constraint(args)
        table_name, old_name, new_name, options = args
        options ||= {}
        # flag the trailing hash as keyword arguments so it's replayed as
        # `rename_constraint(..., if_exists:)` rather than a positional hash
        [:rename_constraint, [table_name, new_name, old_name, Hash.ruby2_keywords_hash(options)]]
      end

      def change_constraint(table, constraint, **options)
        record(:change_constraint, [table, constraint, options])
      end

      def invert_change_constraint(args)
        table, constraint, options = args
        options ||= {}
        inverted = options.to_h do |key, value|
          [key, invert_change_constraint_option(key, value)]
        end
        [:change_constraint, [table, constraint, Hash.ruby2_keywords_hash(inverted)]]
      end

      private

      def invert_change_constraint_option(key, value)
        return value if value.nil?

        case key
        when :deferrable, :enforced, :inherit
          return !value if [true, false].include?(value)

          raise ArgumentError, "#{key} must be true or false"
        when :initially
          return :immediate if value == :deferred
          return :deferred if value == :immediate

          raise ArgumentError, "initially must be :deferred or :immediate"
        else
          raise ArgumentError, "unknown change_constraint option: #{key.inspect}"
        end
      end
    end
  end
end

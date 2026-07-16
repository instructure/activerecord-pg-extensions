# frozen_string_literal: true

module ActiveRecord
  module PGExtensions
    # adds support for reverting migration methods added by this gem
    module CommandRecorder
      def rename_constraint(table_name, old_name, new_name, **options)
        record(:rename_constraint, [table_name, old_name, new_name, options])
      end

      def change_constraint(table, constraint, **options)
        record(:change_constraint, [table, constraint, options])
      end

      private

      def invert_rename_constraint(args)
        table_name, old_name, new_name, options = args
        options ||= {}
        # flag the trailing hash as keyword arguments so it's replayed as
        # `rename_constraint(..., if_exists:)` rather than a positional hash
        [:rename_constraint, [table_name, new_name, old_name, Hash.ruby2_keywords_hash(options)]]
      end

      def invert_change_constraint(args)
        table, constraint, options = args
        options ||= {}
        inverted = options.to_h do |key, value|
          [key, invert_change_constraint_option(key, value)]
        end
        [:change_constraint, [table, constraint, Hash.ruby2_keywords_hash(inverted)]]
      end

      # stock Rails carries :if_not_exists through to the inverse (remove_*) command
      # unchanged, but the remove side only understands :if_exists (and vice versa);
      # rewrite the existence option so the reverse migration stays idempotent
      def invert_add_index(args)
        change_option(args, from: :if_not_exists, to: :if_exists)
        super
      end

      def invert_remove_index(args)
        change_option(args, from: :if_exists, to: :if_not_exists)
        super
      end

      def invert_add_column(args)
        change_option(args, from: :if_not_exists, to: :if_exists)
        super
      end

      def invert_remove_column(args)
        change_option(args, from: :if_exists, to: :if_not_exists)
        super
      end

      def invert_add_foreign_key(args)
        change_option(args, from: :if_not_exists, to: :if_exists)
        super
      end

      def invert_remove_foreign_key(args)
        change_option(args, from: :if_exists, to: :if_not_exists)
        super
      end

      def invert_add_reference(args)
        change_reference_option(args, from: :if_not_exists, to: :if_exists)
        super
      end
      alias_method :invert_add_belongs_to, :invert_add_reference

      def invert_remove_reference(args)
        change_reference_option(args, from: :if_exists, to: :if_not_exists)
        super
      end
      alias_method :invert_remove_belongs_to, :invert_remove_reference

      # renames an option on the trailing options hash in place, e.g. so an inverted
      # command receives :if_exists where the original had :if_not_exists
      def change_option(args, from:, to:)
        options = args.last
        return unless options.is_a?(Hash) && options.key?(from)

        options[to] = options.delete(from)
      end

      # like change_option, but also rewrites the option nested inside a reference's
      # `index:` hash (e.g. `add_reference(..., index: { if_not_exists: true })`)
      def change_reference_option(args, from:, to:)
        change_option(args, from:, to:)
        options = args.last
        change_option([options[:index]], from:, to:) if options.is_a?(Hash) && options[:index].is_a?(Hash)
      end

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

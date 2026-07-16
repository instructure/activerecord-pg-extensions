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
    end
  end
end

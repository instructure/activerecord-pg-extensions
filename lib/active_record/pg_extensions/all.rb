# frozen_string_literal: true

require "active_record/pg_extensions/pessimistic_migrations"

module ActiveRecord
  module PGExtensions
    # includes all optional extensions at once
    module All
      def self.inject
        ConnectionAdapters::PostgreSQLAdapter.prepend(PessimisticMigrations)
      end
    end
  end
end

ActiveRecord::PGExtensions::All.inject if defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)

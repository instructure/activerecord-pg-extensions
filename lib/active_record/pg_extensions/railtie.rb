# frozen_string_literal: true

require "rails/railtie"

module ActiveRecord
  module PGExtensions
    # :nodoc:
    class Railtie < Rails::Railtie
      initializer "pg_extensions.extend_ar", after: "active_record.initialize_database" do
        ActiveSupport.on_load(:active_record) do
          require "active_record/pg_extensions/postgresql_adapter"

          ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(PostgreSQLAdapter)
          # if they've already require 'all', then inject now
          defined?(All) && All.inject
        end
      end
    end
  end
end

# frozen_string_literal: true

module ActiveRecord
  module PGExtensions
    # Contains general additions to Transaction
    module Transaction
      PostgreSQLAdapter::TIMEOUTS.each do |kind|
        class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{kind}(local: false)
            return @#{kind} if local
            @#{kind} || parent_transaction.#{kind}
          end

          private def #{kind}=(timeout)
            return if @#{kind} == timeout

            @#{kind} = timeout
            return unless materialized?
            connection.set(#{kind.inspect}, "\#{(timeout * 1000).to_i}ms", local: true)
          end
        RUBY
      end

      def materialize!
        PostgreSQLAdapter::TIMEOUTS.each do |kind|
          next if (timeout = send(kind, local: true)).nil?

          connection.set(kind, "#{(timeout * 1000).to_i}ms", local: true)
        end
        super
      end
    end

    # Contains general additions to NullTransaction
    module NullTransaction
      PostgreSQLAdapter::TIMEOUTS.each do |kind|
        class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{kind}
            nil
          end
        RUBY
      end
    end
  end
end

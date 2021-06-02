# frozen_string_literal: true

describe ActiveRecord::ConnectionAdapters::PostgreSQLAdapter do
  describe "#set_constraints" do
    around do |example|
      connection.dont_execute(&example)
    end

    it "requires :deferred or :immediate" do
      expect { connection.set_constraints("garbage") }.to raise_error(ArgumentError)
    end

    it "defaults to all" do
      connection.set_constraints(:deferred)
      expect(connection.executed_statements).to eq ["SET CONSTRAINTS ALL DEFERRED"]
    end

    it "quotes constraints" do
      connection.set_constraints(:deferred, :my_fk)
      expect(connection.executed_statements).to eq ['SET CONSTRAINTS "my_fk" DEFERRED']
    end

    it "quotes multiple constraints" do
      connection.set_constraints(:deferred, :my_fk1, :my_fk2)
      expect(connection.executed_statements).to eq ['SET CONSTRAINTS "my_fk1", "my_fk2" DEFERRED']
    end
  end
end

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

  describe "#defer_constraints" do
    around do |example|
      connection.dont_execute(&example)
    end

    it "defers and resets" do
      block_called = false
      connection.defer_constraints do
        block_called = true
      end
      expect(block_called).to eq true
      expect(connection.executed_statements).to eq ["SET CONSTRAINTS ALL DEFERRED", "SET CONSTRAINTS ALL IMMEDIATE"]
    end
  end

  describe "#set_replica_identity" do
    around do |example|
      connection.dont_execute(&example)
    end

    it "resets identity" do
      connection.set_replica_identity(:my_table)
      expect(connection.executed_statements).to eq ['ALTER TABLE "my_table" REPLICA IDENTITY DEFAULT']
    end

    it "sets full identity" do
      connection.set_replica_identity(:my_table, :full)
      expect(connection.executed_statements).to eq ['ALTER TABLE "my_table" REPLICA IDENTITY FULL']
    end

    it "sets an index" do
      connection.set_replica_identity(:my_table, :my_index)
      expect(connection.executed_statements).to eq ['ALTER TABLE "my_table" REPLICA IDENTITY USING INDEX "my_index"']
    end
  end
end

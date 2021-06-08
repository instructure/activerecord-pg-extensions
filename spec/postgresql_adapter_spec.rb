# frozen_string_literal: true

describe ActiveRecord::ConnectionAdapters::PostgreSQLAdapter do
  before do
    allow(connection).to receive(:reload_type_map)
  end

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

  context "extensions" do
    it "creates and drops an extension" do
      connection.create_extension(:pg_trgm, schema: "public")
      expect(connection.executed_statements).to eq ["CREATE EXTENSION pg_trgm SCHEMA public"]
      expect(ext = connection.extension(:pg_trgm)).not_to be_nil
      expect(ext.schema).to eq "public"
      expect(ext.version).not_to be_nil
      expect(ext.name).to eq "pg_trgm"
    ensure
      connection.executed_statements.clear
      connection.drop_extension(:pg_trgm, if_exists: true)
      expect(connection.executed_statements).to eq ["DROP EXTENSION IF EXISTS pg_trgm"]
      expect(connection.extension(:pg_trgm)).to be_nil
    end

    it "doesn't try to recreate" do
      connection.create_extension(:pg_trgm, schema: "public")
      connection.create_extension(:pg_trgm, schema: "public", if_not_exists: true)
      expect(connection.executed_statements).to eq ["CREATE EXTENSION pg_trgm SCHEMA public",
                                                    "CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public"]
    ensure
      connection.drop_extension(:pg_trgm, if_exists: true)
    end

    context "non-executing" do
      around do |example|
        connection.dont_execute(&example)
      end

      it "supports all options on create" do
        connection.create_extension(:my_extension, if_not_exists: true, schema: "public", version: "2.0", cascade: true)
        expect(connection.executed_statements).to eq(
          ["CREATE EXTENSION IF NOT EXISTS my_extension SCHEMA public VERSION '2.0' CASCADE"]
        )
      end

      it "supports all options on drop" do
        connection.drop_extension(:my_extension, if_exists: true, cascade: true)
        expect(connection.executed_statements).to eq ["DROP EXTENSION IF EXISTS my_extension CASCADE"]
      end

      it "can update an extensions" do
        connection.alter_extension(:my_extension, version: true)
        expect(connection.executed_statements).to eq ["ALTER EXTENSION my_extension UPDATE"]
      end

      it "can update to a specific version" do
        connection.alter_extension(:my_extension, version: "2.0")
        expect(connection.executed_statements).to eq ["ALTER EXTENSION my_extension UPDATE TO '2.0'"]
      end

      it "can change schemas" do
        connection.alter_extension(:my_extension, schema: "my_app")
        expect(connection.executed_statements).to eq ["ALTER EXTENSION my_extension SET SCHEMA my_app"]
      end

      it "cannot change schema and update" do
        expect { connection.alter_extension(:my_extension, schema: "my_app", version: "2.0") }
          .to raise_error(ArgumentError)
      end

      it "can drop multiple extensions" do
        connection.drop_extension(:my_extension1, :my_extension2)
        expect(connection.executed_statements).to eq ["DROP EXTENSION my_extension1, my_extension2"]
      end

      it "does not allow dropping no extensions" do
        expect { connection.drop_extension }.to raise_error(ArgumentError)
      end

      describe "#extension_available?" do
        it "works with no version constraint" do
          connection.extension_available?(:postgis)
          expect(connection.executed_statements).to eq ["SELECT 1 FROM pg_available_extensions WHERE name='postgis'"]
        end

        it "works with a version constraint" do
          connection.extension_available?(:postgis, "2.0")
          expect(connection.executed_statements).to eq(
            ["SELECT 1 FROM pg_available_extension_versions WHERE name='postgis' AND version='2.0'"]
          )
        end
      end
    end
  end

  describe "#add_schema_to_search_path" do
    around do |example|
      original_search_path = connection.schema_search_path
      connection.schema_search_path = "public"
      example.call
    ensure
      connection.schema_search_path = original_search_path
    end

    it "adds a schema to search path" do
      connection.add_schema_to_search_path("postgis") do
        expect(connection.schema_search_path).to eq "public,postgis"
      end
      expect(connection.schema_search_path).to eq "public"
    end

    it "doesn't duplicate an existing schema" do
      connection.add_schema_to_search_path("public") do
        expect(connection.schema_search_path).to eq "public"
      end
      expect(connection.schema_search_path).to eq "public"
    end

    it "is cleaned up properly when the transaction rolls back manually" do
      expect do
        connection.add_schema_to_search_path("postgis") do
          raise ActiveRecord::Rollback
        end
      end.to raise_error(ActiveRecord::Rollback)
      expect(connection.schema_search_path).to eq "public"
    end

    it "is cleaned up properly when the transaction rolls back" do
      expect do
        connection.add_schema_to_search_path("postgis") do
          connection.execute("gibberish")
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(connection.schema_search_path).to eq "public"
    end
  end

  describe "#vacuum" do
    it "does a straight vacuum of everything" do
      connection.vacuum
      expect(connection.executed_statements).to eq ["VACUUM"]
    end

    it "supports several options" do
      connection.vacuum(analyze: true, verbose: true)
      expect(connection.executed_statements).to eq ["VACUUM VERBOSE ANALYZE"]
    end

    it "validates parallel option is an integer" do
      expect { connection.vacuum(parallel: :garbage) }.to raise_error(ArgumentError)
    end

    it "validates parallel option is postive" do
      expect { connection.vacuum(parallel: -1) }.to raise_error(ArgumentError)
    end

    context "non-executing" do
      around do |example|
        connection.dont_execute(&example)
      end

      it "vacuums a table" do
        connection.vacuum(:my_table)
        expect(connection.executed_statements).to eq ['VACUUM "my_table"']
      end

      it "vacuums multiple tables" do
        connection.vacuum(:table1, :table2)
        expect(connection.executed_statements).to eq ['VACUUM "table1", "table2"']
      end

      it "requires analyze with specific columns" do
        expect { connection.vacuum({ my_table: :column1 }) }.to raise_error(ArgumentError)
      end

      it "analyzes a specific column" do
        connection.vacuum({ my_table: :column }, analyze: true)
        expect(connection.executed_statements).to eq ['VACUUM ANALYZE "my_table" ("column")']
      end

      it "analyzes multiples columns" do
        connection.vacuum({ my_table: %i[column1 column2] }, analyze: true)
        expect(connection.executed_statements).to eq ['VACUUM ANALYZE "my_table" ("column1", "column2")']
      end

      it "analyzes a mixture of tables and columns" do
        connection.vacuum(:table1, { my_table: %i[column1 column2] }, analyze: true)
        expect(connection.executed_statements).to eq ['VACUUM ANALYZE "table1", "my_table" ("column1", "column2")']
      end
    end

    describe "#wal_lsn_diff" do
      skip unless connection.wal?

      it "executes" do
        expect(connection.wal_lsn_diff(:current, :current)).to eq 0
      end
    end

    describe "#in_recovery?" do
      it "works" do
        expect(connection.in_recovery?).to eq false
      end
    end

    describe "#select_value" do
      it "casts numeric types" do
        expect(connection.select_value("SELECT factorial(2)")).to eq 2
      end
    end
  end
end

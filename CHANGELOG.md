## [Unreleased]

## [0.2.2] - 2021-06-22

- Fix bug in Ruby 2.6 calling format wrong.

## [0.2.1] - 2021-06-22

- Ensure numeric is in the PG type map for Rails 6.0. So that lsn_diff will
  return a numeric, instead of a string.

## [0.2.0] - 2021-06-07

- Add PostgreSQLAdapter#set_replica_identity
- Add methods for discovering and managing extensions
- Add method to temporarily add a schema to the search path
- Add PostgreSQLAdapter#vacuum
- Add optional module PessimisticMigrations

## [0.1.1] - 2021-06-07

- Add PostgreSQLAdapter#defer_constraints

## [0.1.0] - 2021-06-02

- Initial release

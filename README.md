# ActiveRecord PG Extensions

This gem includes a number of extensions to Rails' regular PostgreSQLAdapter to enable access to
more Postgres specific features.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activerecord-pg-extensions'
```
## Usage

See individual classes for available methods.

## Development

Development requires Docker. After checking out the repo, run `docker compose build` to install dependencies.

`docker compose run --rm app rake` will run both tests and Rubocop.

If using Visual Studio Code, simply click "Reopen in Container" when it pops up.

To release a new version, update the version number in `version.rb`, and then run `rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/instructure/activerecord-pg-extensions.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

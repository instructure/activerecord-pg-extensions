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

You will need to create a Postgres database locally called `travis_ci_test` in order to run tests. `rake` will run both tests and Rubocop.

After checking out the repo, run `bundle install` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/instructure/activerecord-pg-extensions.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

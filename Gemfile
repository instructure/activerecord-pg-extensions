# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-multilock", "1.3.4"
return unless Plugin.installed?("bundler-multilock")

Plugin.send(:load_plugin, "bundler-multilock")

gemspec

gem "zeitwerk", "< 2.7.0" # force a version still compatible with Ruby 2.7

ruby27 = Gem::Requirement.new("~> 2.7.0").satisfied_by?(Gem::Version.new(RUBY_VERSION))
ruby30or31 = Gem::Requirement.new(">= 3.0.0", "< 3.2.0").satisfied_by?(Gem::Version.new(RUBY_VERSION))

lockfile "rails-7.0" do
  gem "activerecord", "~> 7.0.0"
  gem "nokogiri", "< 1.16.0" # force a version still compatible with Ruby 2.7
  gem "railties", "~> 7.0.0"
end

lockfile "rails-7.1", default: ruby27 do
  gem "activerecord", "~> 7.1.0"
  gem "nokogiri", "< 1.16.0" # force a version still compatible with Ruby 2.7
  gem "railties", "~> 7.1.0"
end

lockfile "rails-7.2", default: ruby30or31 do
  gem "activerecord", "~> 7.2.0"
  gem "railties", "~> 7.2.0"
end

lockfile do
  gem "activerecord", "~> 8.0.0"
  # satisfy bundler-multilock that yes, indeed, we want nokogiri to differ between the lockfiles
  gem "nokogiri", ">= 1.16.0"
  gem "railties", "~> 8.0.0"
end

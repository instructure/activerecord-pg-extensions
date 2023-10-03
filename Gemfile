# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-multilock", "1.0.11"
return unless Plugin.installed?("bundler-multilock")

Plugin.send(:load_plugin, "bundler-multilock")

gemspec

lockfile "rails-7.0", default: true do
  gem "activerecord", "~> 7.0.0"
end

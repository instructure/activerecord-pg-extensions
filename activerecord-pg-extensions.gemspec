# frozen_string_literal: true

require_relative "lib/active_record/pg_extensions/version"

Gem::Specification.new do |spec|
  spec.name          = "activerecord-pg-extensions"
  spec.version       = ActiveRecord::PGExtensions::VERSION
  spec.authors       = ["Cody Cutrer"]
  spec.email         = ["cody@instructure.com"]

  spec.summary       = "Several extensions to ActiveRecord's PostgreSQLAdapter."
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/instructure/activerecord-pg-extensions"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["changelog_uri"] = "https://github.com/instructure/activerecord-pg-extensions/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*"] + ["LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2", "< 8.1"
  spec.add_dependency "railties", ">= 7.2", "< 8.1"
end

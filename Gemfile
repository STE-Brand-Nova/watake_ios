source "https://rubygems.org"

# Install: `bundle install`
# Run fastlane via `bundle exec fastlane <lane>`.

gem "fastlane", "~> 2.223"

plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)

# require 'rubygems'
require 'bundler'
Bundler::GemHelper.install_tasks

require 'rake'
require 'rspec/core'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |spec|
  # do not run integration tests, doesn't work on TravisCI
  spec.pattern = FileList[
      'spec/license_auto/*_spec.rb',
      'spec/license_auto/*/*_spec.rb',
  ]
end

require 'rubocop/rake_task'
RuboCop::RakeTask.new(:rubocop)

task default: [:rubocop, :spec]

require 'bundler'
require 'license_auto/package_manager'
require 'license_auto/website/ruby_gems_org'
# require 'license_auto/package_manager/gemfury'

module LicenseAuto
  class Bundler < LicenseAuto::PackageManager

    LANGUAGE = 'Ruby'

    def initialize(path)
      super(path)
    end

    def dependency_file_pattern
      /#{@path}\/[0-9a-zA-Z_.]*gem.*\.lock$/i
    end

    def gemfile_pattern
      /#{@path}\/[0-9a-zA-Z_.]*gemfile$/i
    end

    def parse_dependencies
      # gemfiles = dependency_file_path_names(pattern=gemfile_pattern)
      # definition = ::Bundler::Definition.build(gemfiles.first, nil, nil)

      # definition.dependencies.each {|dep|
      #   LicenseAuto.logger.debug(dep.name + ' ' + dep.source.remotes.to_s)
      # }

      lock_files = dependency_file_path_names
      gem_files = dependency_file_path_names(pattern=gemfile_pattern)
      if lock_files.empty? && !gem_files.empty?
        env_bundle_gemfile, ENV["BUNDLE_GEMFILE"] = ENV["BUNDLE_GEMFILE"], nil
        # Ruby Change the follow env variable also,if bundle lock different from outside,then can try the follow variable
        #ENV["GEM_HOME"] = nil
        #ENV["GEM_PATH"] = nil
        #ENV["BUNDLE_BIN_PATH"] = nil
        #ENV["RUBYLIB"] = nil
        #ENV["RUBYOPT"] = nil
        Dir.chdir(@path) do
          #http://blog.csdn.net/alada007/article/details/8035316
          #use bundle lock to generate gemfile.lock file
          cmd = 'bundle lock'
          stdout_str, stderr_str, _status = Open3.capture3(cmd)
          LicenseAuto.logger.debug(stdout_str) if stdout_str
          LicenseAuto.logger.error(stderr_str) if stderr_str
        end
        ENV["BUNDLE_GEMFILE"] = env_bundle_gemfile
      end

      lock_files = dependency_file_path_names
      if lock_files.empty?
        LicenseAuto.logger.info("#{LANGUAGE}: #{dependency_file_pattern} file not exist")
        gem_files = dependency_file_path_names(pattern=gemfile_pattern)
        # TODO: parse gem_files
        unless gem_files.empty?
          LicenseAuto.logger.warn("#{LANGUAGE}: Gemfile exisit: #{gem_files}")
        end
        return []
      else
        lock_files.map { |dep_file|
          LicenseAuto.logger.debug(dep_file)
          lockfile_parser = ::Bundler::LockfileParser.new(::Bundler.read_file(dep_file))
          {
              dep_file: dep_file,
              deps: lockfile_parser.specs.map { |spec|
                remote =
                    case
                      when spec.source.class == ::Bundler::Source::Git
                        spec.source.uri
                      when spec.source.class == ::Bundler::Source::Rubygems
                        if spec.source.remotes.size == 1
                          spec.source.remotes.first.to_s
                        elsif spec.source.remotes.size >= 1
                          # remotes =
                          #     if Gems.info(spec.name) == RubyGemsOrg::GEM_NOT_FOUND
                          #       spec.source.remotes.reject {|uri|
                          #         uri.to_s == RubyGemsOrg::URI
                          #       }
                          #     else
                          #       spec.source.remotes
                          #     end
                          # TODO: support http://www.gemfury.com, aka multi `source` DSL; requre 'rubygems'?
                          spec.source.remotes.map { |r|
                            r.to_s
                          }.join(',')
                        end
                      when spec.source.class == ::Bundler::Source::Path::Installer
                        # Untested
                        spec.full_gem_path
                      when spec.source.class == ::Bundler::Source::Path
                        "."
                      else
                        raise('Yo, this error should ever not occur!')
                    end
                {
                    name: spec.name,
                    version: spec.version.to_s,
                    remote: remote
                }
              }
          }
        }
      end
      # LicenseAuto.logger.debug(JSON.pretty_generate(dep_files))
    end

    def self.check_cli
      # TODO check bundle
      true
    end
  end
end
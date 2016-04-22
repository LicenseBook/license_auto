require 'bundler'
require 'license_auto/package_manager'

module LicenseAuto
  class CocoaPods < LicenseAuto::PackageManager

    LANGUAGE = 'Object-C'

    def initialize(path)
      super(path)
    end

    def dependency_file_pattern
      /#{@path}\/Podfile\.lock$/
    end

    def podfile_pattern
      /#{@path}\/Podfile$/i
    end

    def parse_dependencies
      pod_files = dependency_file_path_names
      if pod_files.empty?
        LicenseAuto.logger.info("#{LANGUAGE}: #{dependency_file_pattern} file not exisit")
        pod_files = dependency_file_path_names(pattern=podfile_pattern)
        # TODO: parse Podfile
        unless pod_files.empty?
          LicenseAuto.logger.warn("#{LANGUAGE}: Podfile exisit: #{pod_files}")
        end
        return []
      else
        pod_files.map {|pod_file|
          LicenseAuto.logger.debug(pod_file)
          pod_spec = YAML.load_file(pod_file)

          pod_spec["PODS"].map do |pod|
            pod = pod.keys.first if pod.is_a?(Hash)

            name, version = pod.scan(/(.*)\s\((.*)\)/).flatten

            CocoaPodsPackage.new(
                name,
                version,
                license_texts[name],
                logger: logger
            )
          end
        }

      end


      lock_files = dependency_file_path_names
      if lock_files.empty?
        LicenseAuto.logger.info("#{LANGUAGE}: #{dependency_file_pattern} file not exisit")
        gem_files = dependency_file_path_names(pattern=gemfile_pattern)
        # TODO: parse gem_files
        unless gem_files.empty?
          LicenseAuto.logger.warn("#{LANGUAGE}: Gemfile exisit: #{gem_files}")
        end
        return []
      else
        lock_files.map {|dep_file|
          LicenseAuto.logger.debug(dep_file)
          lockfile_parser = ::Bundler::LockfileParser.new(::Bundler.read_file(dep_file))
          {
              dep_file: dep_file,
              deps: lockfile_parser.specs.map {|spec|
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
                          spec.source.remotes.map {|r|
                            r.to_s
                          }.join(',')
                        end
                      when spec.source.class == ::Bundler::Source::Path::Installer
                        # Untested
                        spec.full_gem_path
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
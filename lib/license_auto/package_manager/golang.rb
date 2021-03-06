require 'open3'
require 'set'
require 'license_auto/package_manager'
require 'license_auto/var/golang_std_libs'
require 'license_auto/matcher'

module LicenseAuto
  class Golang < LicenseAuto::PackageManager

    LANGUAGE = 'Golang'

    def initialize(path)
      super(path)
    end

    # Fake
    def dependency_file_pattern
      /#{@path}\/.*\.go$/
    end

    def parse_dependencies
      contents = list_contents
      if contents.nil?
        LicenseAuto.logger.info("Golang dependencies not exist")
        return []
      else
        deps = filter_deps(contents)
        LicenseAuto.logger.debug(deps)
        dep_array = []
        ####
        GC::Profiler.enable
        deps.each {|dep|
          begin
            remote, latest_sha = fetch_remote_latest_sha(dep)
          rescue Github::Error::NotFound => e
            LicenseAuto.logger.fatal(e)
            remote, latest_sha = dep,""
          end

          dep_array.push({
              name: dep.split('/').last,
              version: latest_sha,
              remote: remote
          })
        }
        puts GC::Profiler.result

        GC::Profiler.disable

        [
          {
              dep_file: nil,
              deps: dep_array
          }
        ]
      end
      # LicenseAuto.logger.debug(JSON.pretty_generate(dep_files))
    end

    # @return [clone_url, latest_sha]
    def fetch_remote_latest_sha(repo_url)
      matcher = Matcher::SourceURL.new(repo_url)
      github_matched = matcher.match_github_resource
      if github_matched
        github = GithubCom.new({}, github_matched[:owner], github_matched[:repo])
        begin
          latest_commit = github.latest_commit
          latest_sha =
              if latest_commit.class == Array
                # Eg. ["message", "Moved Permanently"]:Array
                latest_commit[1]
              else
                latest_commit.sha
              end
        rescue
          latest_sha = "can't access"
        end

        url = github.url
        # LicenseAuto.logger.debug(latest_sha)
        [url, latest_sha]
      else
        [repo_url, nil]
      end
    end

    def filter_deps(listed_contents)
      dep_keys = ['Deps', 'Imports', 'TestImports', 'XTestImports']
      deps = Set.new()

      listed_contents.each {|content|
        deps_ = dep_keys.map {|key|
          content[key]
        }.flatten.compact

        deps_ = Set.new(deps_)
        deps = deps.merge(deps_)
      }

      filtered_deps = Set.new(deps.reject {|dep|
        bool = GOLANG_STD_LIBS.include?(dep) or not dep.include?('.')
        # LicenseAuto.logger.debug("#{dep}, #{bool}")
        # bool
      }.map {|dep|
        host, owner, repo, _subdir = dep.gsub(/\/$/, '').split('/')
        [host, owner, repo].join('/')
      })
    end

    def uniform_url

    end

    # @return
    #     {
    #         "Dir": "/Users/mic/vm/test-branch",
    #         "ImportPath": "_/Users/mic/vm/test-branch",
    #         "Name": "main",
    #         "Stale": true,
    #         "GoFiles": [
    #             "main.go"
    #         ],
    #         "Imports": [
    #             "fmt",
    #             "github.com/astaxie/beego",
    #             "math/rand"
    #         ],
    #         "Deps": [
    #             "errors",
    #             "fmt",
    #             "github.com/astaxie/beego",
    #             "internal/race",
    #             "io",
    #             "math",
    #             "math/rand",
    #             "os",
    #             "reflect",
    #             "runtime",
    #             "runtime/internal/atomic",
    #             "runtime/internal/sys",
    #             "strconv",
    #             "sync",
    #             "sync/atomic",
    #             "syscall",
    #             "time",
    #             "unicode/utf8",
    #             "unsafe"
    #         ],
    #         "Incomplete": true,
    #         "DepsErrors": [
    #             {
    #                 "ImportStack": [
    #                     ".",
    #                     "github.com/astaxie/beego"
    #                 ],
    #                 "Pos": "main.go:9:2",
    #                 "Err": "cannot find package \"github.com/astaxie/beego\" in any of:\n\t/usr/local/Cellar/go/1.6/libexec/src/github.com/astaxie/beego (from $GOROOT)\n\t($GOPATH not set)"
    #             }
    #         ]
    #     }
    def list_contents
      # contents = []
      Dir.chdir(@path) do
        cmd = 'go list -json ./...'
        stdout_str, stderr_str, status = Open3.capture3(cmd)
        # LicenseAuto.logger.debug('Yo Yo Yo')
        # LicenseAuto.logger.debug(stdout_str)
        # LicenseAuto.logger.debug('Check Now')
        if stdout_str.length > 0
          # out = stdout_str.gsub(/}\n{/, "}\n\n{").split(/\n\n/)
          out = stdout_str.gsub(/}\n{/, "}\n\n{").split(/\n\n/)
          out.map {|content_str|
            content_str = content_str.gsub(/\n/, '').gsub(/\t/, '')
            Hashie::Mash.new(JSON.parse(content_str))
          }
        end
      end
    end

    def self.check_cli
      bash_cmd = "go version"
      # LicenseAuto.logger.debug(bash_cmd)
      stdout_str, stderr_str, _status = Open3.capture3(bash_cmd)
      golang_version = /1\.[456]/

      if not stderr_str.empty?
        LicenseAuto.logger.error(stderr_str)
        return false
      elsif not stdout_str =~ golang_version
        error = "Golang version: #{stdout_str} not satisfied: #{golang_version}"
        LicenseAuto.logger.error(error)
        return false
      end

      return true
    end
  end
end
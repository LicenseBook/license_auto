require 'base64'

require 'fileutils'
require 'github_api'
require 'git'


require 'license_auto/config/config'
require 'license_auto/license/similarity'
require 'license_auto/license/readme'

class GithubCom < Website

  HOST = 'github.com'
  LANGUAGE = nil

  GIT_HASH_LENGTH = 40

  attr_reader :url

  ##
  # package: Hashie::Mash
  # user: string
  # repo: string
  # ref: string
  def initialize(package, user, repo, ref=nil, auto_pagination=false, last_commit=nil)
    super(package)
    @ref = ref
    @last_commit = last_commit
    @user = user
    @repo = repo
    @url = "https://github.com/#{user}/#{repo}"
    LicenseAuto.logger.debug(@url)

    @server =
        begin
          eval('WebMock')
          LicenseAuto.logger.debug("Running LicenseAuto in RSpec mode")
          Github.new(user: user, repo: repo)
        rescue NameError => e
          LicenseAuto.logger.debug("Running LicenseAuto in formal mode,username #{AUTO_CONF.github.username}")
          basic_auth = "#{AUTO_CONF.github.username}:#{AUTO_CONF.github.access_token}"
          server = Github.new(user: @user, repo: @repo, basic_auth: basic_auth, auto_pagination: auto_pagination)
          @repoinfo = server.repos.get
          if  @repoinfo.headers.status == 301
            response = HTTParty.get(@repoinfo.headers.location)
            if response["name"] && response["owner"]["login"]
              @user = response["owner"]["login"]
              @repo = response["name"]
              server = Github.new(user: @user, repo: @repo, basic_auth: basic_auth, auto_pagination: auto_pagination)
              @repoinfo = server.repos.get
            end
          end
          server
        end
  end

  def server
    @server
  end

  def ref=(ref=nil)
    @ref=ref
  end

  ##
  # @return LicenseInfoWrapper
  ## default_branch : nil, Get a specific version license
  ##                  true, Get a default branch license
  def get_license_info(default_branch = nil)
    pack_url = nil
    if default_branch
      possible_ref = nil
      pack_url = @url
    else
      possible_ref = @ref || match_versioned_ref
      pack_url = @url + "/tree/#{possible_ref}"
    end
    LicenseAuto.logger.debug("possible_ref: #{possible_ref}")
    # If possible_ref is nil, the Github API server will return the default branch contents
    contents = @server.repos.contents.get(path: '/', ref: possible_ref)

    license_files = []
    readme_files = []
    notice_files = []
    contents.each { |obj|
      if obj.type == 'file'
        filename_matcher = LicenseAuto::Matcher::FilepathName.new(obj.name)
        license_files.push(obj) if filename_matcher.match_license_file
        readme_files.push(obj) if filename_matcher.match_readme_file
        notice_files.push(obj) if filename_matcher.match_notice_file
      end
    }

    license_files = license_files.map { |obj|
      license_content = get_blobs(obj['sha'])
      license_name, sim_ratio = LicenseAuto::Similarity.new(license_content).most_license_sim
      LicenseAuto::LicenseWrapper.new(
          name: license_name,
          sim_ratio: sim_ratio,
          html_url: obj['html_url'],
          download_url: obj['download_url'],
          text: license_content
      )
    }

    readme_files = readme_files.map { |obj|
      readme_content = get_blobs(obj['sha'])
      license_content = LicenseAuto::Readme.new(obj['download_url'], readme_content).license_content
      LicenseAuto.logger.debug("readme_content:\n#{license_content}\n")
      if license_content.nil?
        next
      else
        license_name, sim_ratio = LicenseAuto::Similarity.new(license_content).most_license_sim
        LicenseAuto::LicenseWrapper.new(
            name: license_name,
            sim_ratio: sim_ratio,
            html_url: obj['html_url'],
            download_url: obj['download_url'],
            text: license_content
        )
      end
    }.compact

    notice_files = notice_files.map { |obj|
      notice_content = get_blobs(obj['sha'])
      LicenseAuto.logger.debug("notice_content:\n#{notice_content}\n")

      if notice_content.nil?
        next
      else
        LicenseAuto::NoticeWrapper.new(
            html_url: obj['html_url'],
            download_url: obj['download_url'],
            text: notice_content
        )
      end
    }.compact

    pack_wrapper = LicenseAuto::PackWrapper.new(
        homepage: nil,
        project_url: nil,
        source_url: pack_url || @url
    )
    if default_branch == nil and license_files.empty? and readme_files.empty?
      return get_license_info(true)
    end
    LicenseAuto::LicenseInfoWrapper.new(
        licenses: license_files,
        readmes: readme_files,
        notices: notice_files,
        pack: pack_wrapper
    )
  end

  def get_ref(ref)
    @server.git_data.references.get(ref: ref)
  end

  def match_versioned_ref()
    possible_ref = nil
    # If provided a Git SHA, use it directly
    if @package.version.size >= GIT_HASH_LENGTH
      possible_ref = @package.version
    else
      matcher = LicenseAuto::Matcher::FilepathName.new(@package.version)
      @server.repos.tags do |tag|
        matched = matcher.match_the_ref(tag.name)
        if matched
          possible_ref = tag.name
          break
        end
      end
    end
    possible_ref
  end

  def list_languages
    langs = @server.repos.languages
    LicenseAuto.logger.debug("All languaegs: #{langs}")
    langs
  end

  # @return
  # Array: [#<Hashie::Mash commit=#<Hashie::Mash sha="8065e5c64a22bd6d60e4df8d9be46b5805ec9355" url="https://api.github.com/repos/bower/bower/commits/8065e5c64a22bd6d60e4df8d9be46b5805ec9355"> name="v1.7.9" tarball_url="https://api.github.com/repos/bower/bower/tarball/v1.7.9" zipball_url="https://api.github.com/repos/bower/bower/zipball/v1.7.9">, #<Hashie::Mash commit=
  def list_tags
    @server.repos.tags.body
  end

  def list_commits
    commits = @server.repos.commits.list
  end

  def last_commit
    return @last_commit if ( @last_commit && @last_commit.size==40)
    if @ref
      LicenseAuto.logger.debug("get last_commit https://api.github.com/repos/"+@user+"/"+@repo+"/commits/"+@ref+" token #{AUTO_CONF.github.access_token[0..3]}")
      @last_commit =  HTTParty.get("https://api.github.com/repos/"+@user+"/"+@repo+"/commits/"+@ref,
                                     headers: {"Accept" => "application/vnd.github.VERSION.sha",
                                               "User-Agent"=>"LicenseBook",
                                               "Authorization"=> "token #{AUTO_CONF.github.access_token}"
                                     })
    else
      @last_commit = list_commits.first.sha
    end
  end

  def latest_commit
    list_commits.first
  end

  def clone
    info = repo_info

    clone_url = info.body.fetch('clone_url')
    LicenseAuto.logger.debug(clone_url)

    trimmed_url = clone_url.gsub(/^http[s]?:\/\//, '')
    clone_dir = "#{AUTO_CACHE_DIR}/#{trimmed_url}"+(@last_commit ? "/#{@last_commit}" : "")
    LicenseAuto.logger.debug(clone_dir)

    if Dir.exist?(clone_dir)
      git = Git.open(clone_dir, :log => LicenseAuto.logger)
      local_branch = git.branches.local[0].full
      if local_branch == @ref
        git.pull(remote='origin', branch=local_branch)
        git.checkout(git.gcommit(@last_commit))
      elsif @last_commit && local_branch=="(HEAD detached at "+@last_commit[0..6].downcase+")"
      else
        FileUtils::rm_rf(clone_dir)
        git = do_clone(clone_url, clone_dir)
        git.checkout(git.gcommit(@last_commit)) if @last_commit
      end
    else
      git = do_clone(clone_url, clone_dir)
      git.checkout(git.gcommit(@last_commit)) if @last_commit
    end
    clone_dir
  end

  def do_clone(clone_url, clone_dir)
    LicenseAuto.logger.debug(@ref)
    clone_opts = {
        #:depth => 1, # Only last commit history for fast
        :branch => @ref
    }
    LicenseAuto.logger.debug(clone_url)
    Git.clone(clone_url, clone_dir, clone_opts)
  end

  def repo_info
    return @repoinfo if @repoinfo
    @repoinfo = @server.repos.get
  end

  def filter_gitmodules
  end

  # http://www.rubydoc.info/github/piotrmurach/github/master/Github/Client/GitData/Blobs#get-instance_method
  def get_blobs(sha)
    response_wrapper = @server.git_data.blobs.get(@server.user, @server.repo, sha)
    # LicenseAuto.logger.debug(response_wrapper)
    content = response_wrapper.body.content
    encoding = response_wrapper.body.encoding
    if encoding == 'base64'
      Base64.decode64(content)
    else
      LicenseAuto.logger.error("Unknown encoding: #{encoding}")
    end
  end
end

require 'httparty'
require 'rubygems/package' # Gem::Package::TarReader
require 'zlib'
require 'xz'
require 'open3'
require 'anemone'

require 'license_auto/license/similarity'

class Helper
  def self.is_license_file(filename)
    return filename =~ /(licen[sc]e|copying)+/i
  end

  # file_pathname = 'foo/to/bar'
  def self.is_root_file(file_pathname)
    return file_pathname.split('/').size == 2
  end

  def self.is_readme_file(filename)
    return filename =~ /readme/i
  end

  def self.is_notice_file(filename)
    return filename =~ /(notice|copyright)/i
  end
  def self.is_debian_copyright_file(file_pathname)
    return file_pathname =~ /^[^\/]+\/debian\/copyright$/
  end
end

class UbuntuLaunchpad < Website

  FILE_TYPE_PATTERN = {
      :tar_gz => /(tar\.gz|\.tgz)$/,
      :tar_xz => /tar\.xz$/,
      :tar_bz2 => /tar\.bz2$/
  }

  def initialize(package, distribution = 'ubuntu', distro_series = 'trusty',
                 architecture = 'amd64', root_license_only=true)
    super(package)

    @site_url = 'https://launchpad.net'
    @distribution = distribution
    @distro_series = distro_series
    @architecture = architecture
    @binary_package_name = @package.name
    @binary_package_version = @package.version
    @source_url = nil
    @source_path = nil
    @root_license_only = root_license_only
    @binary_package_url = "#{@site_url}/#{@distribution}/#{@distro_series}/#{@architecture}/#{@binary_package_name}/#{@binary_package_version}"
  end

  def _find_source_code_download_url(source_package_homepage)
    source_code_download_url = nil

    opts = {:discard_page_bodies => true, :depth_limit => 0}
    Anemone.crawl(source_package_homepage, opts) do |anemone|
      anemone.on_every_page do |page|
        xpath = "//div[@id='source-files']/table/tbody/tr/td/a[contains(@href, '.orig.')]"
        target_links = page.doc.xpath(xpath)
        if target_links.size == 0
          # Eg. https://launchpad.net/ubuntu/+source/wireless-crda/1.16
          xpath = "//div[@id='source-files']/table/tbody/tr/td/a[not(contains(@href, '.dsc'))]"
          target_links = page.doc.xpath(xpath)
        end
        # puts target_links
        target_links.each {|text|
          full_href = text.attr('href')
          if full_href
            source_code_download_url = full_href
            break
          end
        }
      end
    end
    return source_code_download_url
  end

  def _find_source_package_homepage()
    source_package_homepage = nil
    opts = {:discard_page_bodies => true, :depth_limit => 0}

    LicenseAuto.logger.info("binary_package_link: #{@binary_package_url}")

    Anemone.crawl(@binary_package_url, opts) do |anemone|
      anemone.on_every_page do |page|
        xpath = "//dd[@id='source']/a[1]"
        page.doc.xpath(xpath).each {|text|
          abs_href = text.css('/@href')
          if abs_href
            source_package_homepage = "#{@site_url}#{abs_href}"
            break
          end
        }
      end
    end
    return source_package_homepage
  end

  # download ubuntu package source code to loacl
  def download_source_code(source_code_url)
    source_code_filename = source_code_url.split('/').last
    source_code_path = "#{AUTO_LAUNCHPAD_SOURCE_DIR}/#{source_code_filename}"
    File.open(source_code_path, 'wb') do |f|
      f.binmode
      http_option = {
          :timeout => AUTO_CONF.http.time_out
      }
      if AUTO_CONF.http.use_proxy == true
        http_option[:http_proxyaddr] = AUTO_CONF.http.host
        http_option[:http_proxyport] = AUTO_CONF.http.port
      end
      f.write(HTTParty.get(source_code_url, options=http_option).parsed_response)
    end

    return source_code_path
  end

  def find_source_package_homepage_and_download_url()
    homepage = _find_source_package_homepage
    download_url = nil
    if homepage
      download_url = _find_source_code_download_url(homepage)
    end
    return homepage, download_url
  end

  def fetch_license_info_from_local_source()

    license_url = nil
    license_text = nil

    # Attention, source package but binary package
    source_package_homepage, source_package_download_url = find_source_package_homepage_and_download_url
    LicenseAuto.logger.info("source_package_homepage: #{source_package_homepage}")
    LicenseAuto.logger.info("source_package_download_url: #{source_package_download_url}")
    pack_wrapper = LicenseAuto::PackWrapper.new(
        homepage: source_package_homepage,
        project_url: nil,
        source_url: source_package_download_url
    )

    if source_package_download_url
      source_code_path = download_source_code(source_package_download_url)
      LicenseAuto.logger.info("#{source_code_path}")
      if source_code_path
        reader = nil
        if source_code_path =~ FILE_TYPE_PATTERN[:tar_gz]
          reader = Zlib::GzipReader
        elsif source_code_path =~ FILE_TYPE_PATTERN[:tar_xz]
          reader = XZ::StreamReader
        elsif source_code_path =~ FILE_TYPE_PATTERN[:tar_bz2]
          # Bash script demo, MacOSX tar is not compatible
          # $ tar --version
          # tar (GNU tar) 1.27.1
          # >>> Copyright (C) 2013 Free Software Foundation, Inc.
          # >>> License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
          # >>> This is free software: you are free to change and redistribute it.
          # >> There is NO WARRANTY, to the extent permitted by law.
          # >> Written by John Gilmore and Jay Fenlason.
          # $ tar -tjvf bison_3.0.2.dfsg.orig.tar.bz2 | grep -i 'license\|copying\|readme' | awk '{ print $6 }'
          # $ tar -xj --file=bison_3.0.2.dfsg.orig.tar.bz2 bison-3.0.2.dfsg/COPYING
          # $ tar -xjO --file=bison_3.0.2.dfsg.orig.tar.bz2 bison-3.0.2.dfsg/COPYING
          # $ tar -xjO --file=bison_3.0.2.dfsg.orig.tar.bz2 bison-3.0.2.dfsg/COPYING -C /dev/null
          cmd_list_content = "tar -tjvf #{source_code_path} | grep -i 'license\\|copying' | awk '{ print $6 }'"
          # MacOSX
          # cmd_list_content = "tar -tjvf #{source_code_path} | grep -i 'license\\|copying' | awk '{ print $9 }'"
          # $plog.debug(cmd_list_content)
          Open3.popen3(cmd_list_content) {|i,o,e,t|
            out = o.readlines
            error = e.readlines
            if error.length > 0
              # todo: move into exception.rb
              raise "decompress error: #{source_code_path}, #{error}"
            elsif out.length > 0
              out.each {|line|
                license_file_path = line.gsub(/\n/, '')
                if @root_license_only and !Helper.is_root_file(license_file_path)
                  next
                end
                cmd_read_content = "tar -xjO --file=#{source_code_path} #{license_file_path} -C /dev/null"
                Open3.popen3(cmd_read_content) {|i,o,e,t|
                  out2 = o.read
                  error = e.readlines
                  if error.length > 0
                    raise "cmd_read_content error: #{source_code_path}, #{license_file_path}, #{error}"
                  elsif out2.length > 0
                    license_text = out2
                    license_url = license_file_path
                    LicenseAuto.logger.debug(license_text)
                    break
                  end
                }
              }
            end
          }
        else
          # $plog.error("source_package_download_url: #{source_package_download_url}, can NOT be uncompressed.")
          return [ [], pack_wrapper]
        end

        if reader
          tar_extract = Gem::Package::TarReader.new(reader.open(source_code_path))
          tar_extract.rewind # The extract has to be rewinded after every iteration
          tar_extract.each do |entry|
            # puts entry.full_name
            # puts entry.directory?
            # puts entry.file?
            # puts entry.read
            # Root dir files only
            if entry.directory? or !Helper.is_root_file(entry.full_name)
              # python-defaults-2.7.5/debian/copyright
              #if API::Helper.is_debian_copyright_file(entry.full_name)
              #  license_url = entry.full_name
              #  license_text = entry.read
              #  break
              #else
              next
              # end
            end

            if entry.file? and Helper.is_license_file(entry.full_name)
              license_url = entry.full_name
              license_text = entry.read

              # $plog.debug(entry.full_name)
              # $plog.debug(license_text)

              # TODO: parser license info
              break
            end

            # TODO:
            # if entry.file? and API::Helper.is_readme_file(entry.full_name)
            #   puts entry.full_name
            #   # puts entry.read
            #   # TODO: readme parser license info
            #   break
            # end

          end
          tar_extract.close ### to abstract out
        end
      end
    end


    if license_text
      # license = License_recognition.new.similarity(license_text, STD_LICENSE_DIR)
      license_name, sim_ratio = LicenseAuto::Similarity.new(license_text).most_license_sim
      license_files  = LicenseAuto::LicenseWrapper.new(
          name: license_name,
          sim_ratio: sim_ratio,
          html_url: license_url,
          download_url: nil,
          text: license_text
      )
      return [[license_files],pack_wrapper]
    else
      return [[],pack_wrapper]
    end



  end

  def get_license_info

    license_files,pack_wrapper = fetch_license_info_from_local_source


    readme_files = []
    notice_files = []
    LicenseAuto::LicenseInfoWrapper.new(
        licenses: license_files,
        readmes: readme_files,
        notices: notice_files,
        pack: pack_wrapper
    )
  end
end
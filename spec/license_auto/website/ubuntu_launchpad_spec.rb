require 'spec_helper'
require 'anemone'

describe LicenseAuto::Package do
  before do

    # opts = {:discard_page_bodies => true, :depth_limit => 0}
    # binary_package_url = "https://launchpad.net/ubuntu/trusty/amd64/anacron/2.3-20ubuntu1"
    # Anemone.crawl(binary_package_url, opts) do |anemone|
    #   anemone.on_every_page do |page|
    #     xpath = "//dd[@id='source']/a[1]"
    #     page.doc.xpath(xpath).each {|text|
    #       abs_href = text.css('/@href')
    #       if abs_href
    #         source_package_homepage = "#{@site_url}#{abs_href}"
    #         break
    #       end
    #     }
    #   end
    # end

  end

  let(:my_pack) { JSON.parse(File.read(fixture_path + '/' + 'my_packages/ubuntu_launchpad.json'))}

  it "get license information of Package" do

    package = LicenseAuto::Package.new(my_pack)
    expect(package.name).to eq(my_pack['name'])

    license_info = package.get_license_info()
    expect(license_info).to be_a(LicenseAuto::LicenseInfoWrapper)
    unless license_info.nil?
      expect(license_info.pack).to be_a(LicenseAuto::PackWrapper)
    end

    LicenseAuto.logger.debug(JSON.pretty_generate(license_info))
  end


end
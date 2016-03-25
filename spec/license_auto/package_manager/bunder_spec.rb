require 'spec_helper'
require 'license_auto/package_manager/bundler'

describe LicenseAuto::Bundler do
  before do
    uri_pattern = /https:\/\/(rubygems\.org|gem\.fury\.io\/mineworks)\/\/?api\/v1\/gems\/(?<gem_name>.+)\.yaml/
    stub_request(:get, uri_pattern).to_return {|request|
      body, status =
          begin
            [fixture(request.uri.to_s), 200]
          rescue FixtureFileNotExist
            ['', 404]
          end
      {
          body: body,
          status: status
      }
    }
  end

  let(:repo_dir) { 'spec/fixtures/rubygems.org:443/hello_world'}
  it 'can be initialed' do
    pm = LicenseAuto::Bundler.new(repo_dir)
    expect(pm).to be_instance_of(LicenseAuto::Bundler)

    expect(pm.dependency_file_path_names).to_not eq([])
    expect(pm.dependency_file_path_names).to be_instance_of(Array)

    expect(pm.parse_dependencies.size).to be > 0
  end

end
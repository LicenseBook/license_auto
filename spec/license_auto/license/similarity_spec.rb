require 'spec_helper'

require 'matrix'
require 'open-uri'
require 'tf-idf-similarity'

describe GithubCom do
  before do
    download_url = 'https://raw.githubusercontent.com/bundler/bundler/v1.11.2/LICENSE.md'
    stub_request(:get, download_url).
        to_return(:status => 200, :body => fixture(download_url), :headers => {})
  end

  let(:download_url) {'https://raw.githubusercontent.com/bundler/bundler/v1.11.2/LICENSE.md'}
  let(:mit_uri) {'lib/license_auto/license/templates/MIT.txt'}
  let(:apache2_uri) {'lib/license_auto/license/templates/Apache2.0.txt'}

  it 'get similarity ratio' do
    package_license = open(download_url).read
    package_document = TfIdfSimilarity::Document.new(package_license)

    mit_license = open(mit_uri).read
    mit_document = TfIdfSimilarity::Document.new(mit_license)

    apache2_license = open(apache2_uri).read
    apache2_document = TfIdfSimilarity::Document.new(apache2_license)

    corpus = [package_document, mit_document, apache2_document]
    model = TfIdfSimilarity::TfIdfModel.new(corpus)
    matrix = model.similarity_matrix

    mit_ratio = matrix[model.document_index(package_document), model.document_index(mit_document)]
    expect(mit_ratio).to be > 0.9

    apache2_ratio = matrix[model.document_index(package_document), model.document_index(apache2_document)]
    expect(apache2_ratio).to be < 0.4
  end

end

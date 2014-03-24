# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Initialize the Rails application.
BIPortalDataService::Application.initialize!

# RubyCAS
CASClient::Frameworks::Rails::Filter.configure(
    :cas_base_url => "https://login-test.cc.nd.edu/cas/",
    :service_url => "https://bitdata-db1-test.dc.nd.edu/"
  )
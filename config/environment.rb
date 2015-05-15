# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Initialize the Rails application.
BIPortalDataService::Application.initialize!

# RubyCAS
CASClient::Frameworks::Rails::Filter.configure(
    :cas_base_url => Rails.application.config.cas_url,
    :service_url => Rails.application.config.huginn_url
  )
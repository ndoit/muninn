BIPortalDataService::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations
  #config.active_record.migration_error = :page_load

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # If set to false, Muninn will accept whatever it's told by the front end
  # about who's connecting to it. If set to true, it will require a CAS
  # proxy ticket.
  config.require_proxy_auth = false

  # If set to false, Muninn will leave security role updates on the queue
  # after downloading them. If set to true, it will delete them after
  # download.
  # This should be set to true in prod, false in dev/test.
  config.delete_security_role_updates = false
end

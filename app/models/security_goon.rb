require "net/http"
require "json"
require "open-uri"

class SecurityGoon
  def self.who_is_this(params)
  	if !params.has_key?(:service) || !params.has_key?(:ticket)
  	  return nil
  	end
  	proxy_ticket = CASClient::ProxyTicket.new(params[:ticket],params[:service])
    validate_result = CASClient::Frameworks::Rails::Filter.client.validate_proxy_ticket(proxy_ticket)
    return validate_result
  end
end
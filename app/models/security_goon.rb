
class SecurityGoon
  def self.who_is_this(params)
  	if !params.has_key?(:service) || !params.has_key?(:ticket)
  	  return nil
  	end
  	proxy_ticket = CASClient::ProxyTicket.new(params[:ticket],params[:service])
    validate_result = CASClient::Frameworks::Rails::Filter.client.validate_proxy_ticket(proxy_ticket)
    LogTime.info(validate_result.to_s)
    if !validate_result.success
      return nil
    end
    return validate_result.user
  end
end
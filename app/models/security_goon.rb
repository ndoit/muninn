
class SecurityGoon
  def self.who_is_this(params)
    LogTime.info("Identifying user from params: " + params.to_s)

    if Rails.env.development? && params[:admin]
      LogTime.info("Impersonating generic admin.")
      return { success: true, user: {
        "id" => nil,
        "net_id" => "&admin",
        "is_admin" => true,
        "read_access_to" => [],
        "write_access_to" => []
        }}
    end

    if Rails.env.development? && params[:impersonate]
      LogTime.info("Impersonating: " + params[:impersonate])
      return UserRepository.new().security_get(params[:impersonate])
    end

  	if !params.has_key?(:service) || !params.has_key?(:ticket)
      LogTime.info("No proxy ticket found. Access granted per anonymous user.")
  	  return UserRepository.new().security_get("&anonymous")
  	end
  	proxy_ticket = CASClient::ProxyTicket.new(params[:ticket],params[:service])
    validate_result = CASClient::Frameworks::Rails::Filter.client.validate_proxy_ticket(proxy_ticket)
    LogTime.info(validate_result.to_s)
    if !validate_result.success
      LogTime.info("Ticket did not validate: " + proxy_ticket.to_s)
      return { success: false, message: "Proxy ticket received but failed to validate." }
    end
    LogTime.info("User identified: " + validate_result.user)
    return UserRepository.new().security_get(validate_result.user)
  end

  def self.check_for_full_read(user_obj, label)
    LogTime.info("Checking whether " + user_obj["net_id"] + " has full read access to " + label.to_s + ".")
    node_model = GraphModel.instance.nodes[label]
    #LogTime.info("Node is of a secured type: " + node_model.is_secured.to_s)
    LogTime.info("User has full read access to node type: " + user_obj["read_access_to"].include?(label.to_s).to_s)
    LogTime.info("User is admin: " + user_obj["is_admin"].to_s)
    #return (!node_model.is_secured) || (user_obj["is_admin"]==true) || user_obj["read_access_to"].include?(label.to_s)
    return (user_obj["is_admin"]==true) || user_obj["read_access_to"].include?(label.to_s)
  end

  def self.check_for_full_write(user_obj, label)
    LogTime.info("Checking whether " + user_obj["net_id"] + " has full write access to " + label.to_s + ".")
    node_model = GraphModel.instance.nodes[label]
    # There is no such thing as a non-secured node type for write access.
    LogTime.info("User has full write access to node type: " + user_obj["write_access_to"].include?(label.to_s).to_s)
    LogTime.info("User is admin: " + user_obj["is_admin"].to_s)
    return (user_obj["is_admin"]==true) || user_obj["write_access_to"].include?(label.to_s)
  end
end
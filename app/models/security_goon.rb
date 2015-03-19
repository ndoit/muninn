
class SecurityGoon
  def self.generic_admin
    return {
      "id" => nil,
      "net_id" => "&admin",
      "is_admin" => true,
      "roles" => {},
      "create_access_to" => [],
      "read_access_to" => [],
      "update_access_to" => [],
      "delete_access_to" => []
      }
  end

  def self.who_is_this(params)
    LogTime.info("Identifying user from params: " + params.to_s)

    if Rails.env.development? && params[:admin]
      LogTime.info("Impersonating generic admin.")
      return { success: true, user: generic_admin }
    end

    if !Rails.application.config.require_proxy_auth && params[:cas_user]
      LogTime.info("Accepting front end authentication for: " + params[:cas_user])
      return UserRepository.new().security_get(params[:cas_user])
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

  def self.check_for_full_create(user_obj, label)
    LogTime.info("Checking whether " + user_obj["net_id"] + " has full create access to " + label.to_s + ".")
    node_model = GraphModel.instance.nodes[label]
    LogTime.info("User has full create access to node type: " + user_obj["create_access_to"].include?(label.to_s).to_s)
    LogTime.info("User is admin: " + user_obj["is_admin"].to_s)
    return (user_obj["is_admin"]==true) || user_obj["create_access_to"].include?(label.to_s)
  end

  def self.check_for_full_read(user_obj, label)
    LogTime.info("Checking whether " + user_obj["net_id"] + " has full read access to " + label.to_s + ".")
    node_model = GraphModel.instance.nodes[label]
    LogTime.info("User has full read access to node type: " + user_obj["read_access_to"].include?(label.to_s).to_s)
    LogTime.info("User is admin: " + user_obj["is_admin"].to_s)
    return (user_obj["is_admin"]==true) || user_obj["read_access_to"].include?(label.to_s)
  end

  def self.check_for_full_update(user_obj, label)
    LogTime.info("Checking whether " + user_obj["net_id"] + " has full update access to " + label.to_s + ".")
    node_model = GraphModel.instance.nodes[label]
    LogTime.info("User has full update access to node type: " + user_obj["update_access_to"].include?(label.to_s).to_s)
    LogTime.info("User is admin: " + user_obj["is_admin"].to_s)
    return (user_obj["is_admin"]==true) || user_obj["update_access_to"].include?(label.to_s)
  end

  def self.check_for_full_delete(user_obj, label)
    LogTime.info("Checking whether " + user_obj["net_id"] + " has full delete access to " + label.to_s + ".")
    node_model = GraphModel.instance.nodes[label]
    LogTime.info("User has full delete access to node type: " + user_obj["delete_access_to"].include?(label.to_s).to_s)
    LogTime.info("User is admin: " + user_obj["is_admin"].to_s)
    return (user_obj["is_admin"]==true) || user_obj["delete_access_to"].include?(label.to_s)
  end
end

class SecurityGoon
  @@cached_user_results = {}
  @@cached_search_filters = {}

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

  def self.clear_cache
    LogTime.info("Clearing security goon cache.")
    @@cached_user_results = {}
  end

  # IMPORTANT: Much of this logic is duplicated (for performance reasons) in 
  # self.get_search_filter. If you change this, change that too.
  def self.who_is_this(params)
    LogTime.info("Identifying user from params: " + params.to_s)

    if Rails.env.development? && params[:admin]
      LogTime.info("Impersonating generic admin.")
      return { success: true, user: generic_admin }
    end

    if !Rails.application.config.require_proxy_auth && params[:cas_user]
      LogTime.info("Accepting front end authentication for: " + params[:cas_user])
      return get_user_obj(params[:cas_user])
    end

  	if !params.has_key?(:service) || !params.has_key?(:ticket)
      LogTime.info("No proxy ticket found. Access granted per anonymous user.")
  	  return get_user_obj("&anonymous")
  	end
  	proxy_ticket = CASClient::ProxyTicket.new(params[:ticket],params[:service])
    validate_result = CASClient::Frameworks::Rails::Filter.client.validate_proxy_ticket(proxy_ticket)
    LogTime.info(validate_result.to_s)
    if !validate_result.success
      LogTime.info("Ticket did not validate: " + proxy_ticket.to_s)
      return { success: false, message: "Proxy ticket received but failed to validate." }
    end
    LogTime.info("User identified: " + validate_result.user)
    return get_user_obj(validate_result.user)
  end

  def self.get_user_obj(user_name)
    if !@@cached_user_results.has_key?(user_name) ||
      (@@cached_user_results[user_name][:cached_at] < Time.now.to_i - 600) #Cache users for 10 minutes.

      @@cached_user_results[user_name] = {
        :cached_at => Time.now.to_i,
        :user_obj => UserRepository.new().security_get(user_name)
      }
      LogTime.info("Loaded user into cache.")
    end
    LogTime.info("Returning cached user.")
    return @@cached_user_results[user_name][:user_obj]
  end

  # We put the search filter logic into a single function for maximum performance.
  # Search must run as fast as possible.
  def self.get_search_filter(params)
    if Rails.env.development? && params[:admin] #Admin user, no security filter required.
      return {}
    elsif !Rails.application.config.require_proxy_auth && params.has_key?(:cas_user)
      user_name = params[:cas_user]
    elsif !params.has_key?(:service) || !params.has_key?(:ticket)
      user_name = "&anonymous"
    else
      proxy_ticket = CASClient::ProxyTicket.new(params[:ticket],params[:service])
      validate_result = CASClient::Frameworks::Rails::Filter.client.validate_proxy_ticket(proxy_ticket)
      if !validate_result.success
        return { success: false, message: "Proxy ticket received but failed to validate." }
      end
      user_name = validate_result.user
    end

    if !@@cached_search_filters.has_key?(user_name) ||
      (@@cached_search_filters[user_name][:cached_at] < Time.now.to_i - 600) #Cache search filters for 10 minutes.

      user_res = get_user_obj(user_name)
      if !user_res[:success]
        user_res = get_user_obj("&anonymous")
      end
      user_obj = user_res[:user]
      LogTime.info("Results for #{user_name}: #{user_obj.to_s}")
      if user_obj["is_admin"]
        @@cached_search_filters[user_name] = {
          :cached_at => Time.now.to_i,
          :filter => {}
        }
      else
        clauses = []
        user_obj["read_access_to"].each do |full_read|
          clauses << { "term" => { "_type" => full_read.to_s.downcase } }
        end
        user_obj["roles"].keys.each do |role|
          clauses << { "term" => { "&allows_access_with" => role.downcase } }
        end

        @@cached_search_filters[user_name] = {
          :cached_at => Time.now.to_i,
          :filter => { "or" => clauses }
        }
      end
    end
    return @@cached_search_filters[user_name][:filter]
  end

  def self.check_for_full_create(user_obj, label)
    LogTime.info("Checking whether " + user_obj["net_id"] + " has full create access to " + label.to_s + ".")
    node_model = GraphModel.instance.nodes[label]
    LogTime.info("User has full create access to node type: " + user_obj["create_access_to"].include?(label.to_s).to_s)
    LogTime.info("User is admin: " + user_obj["is_admin"].to_s)
    return (user_obj["is_admin"]==true) || user_obj["create_access_to"].include?(label.to_s)
  end

  # IMPORTANT: Much of this logic is duplicated (for performance reasons) in 
  # self.get_search_filter. If you change this, change that too.
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
class UserRepository < ModelRepository
  def initialize
  	super(:user)
  end

  def security_get(cas_user)
    # This is the method used when determining security access.
    # We break it out into its own method for a couple of reasons.

    # First, it's faster than going through the whole read() process.
    # This is key because this function is used by ElasticSearchIO as
    # well as the regular Muninn CRUD methods, and the whole point of
    # ElasticSearchIO is to be as responsive as possible.

    # Second, user is itself a node type, and we don't want to risk
    # being accidentally locked out of reading the very user we're
    # trying to authorize.
    if cas_user != nil
      net_id = cas_user
    else
      net_id = "&anonymous"
    end

    if net_id == "&new_anonymous"
      net_id = "&anonymous"
      no_recursion = true
    else
      no_recursion = false
    end

    result = CypherTools.execute_query_into_hash_array("
      MATCH (u:user)
      WHERE u.net_id = {net_id}
      OPTIONAL MATCH (u)-[:HAS_ROLE]-(s:security_role)
      RETURN
        u.net_id,
        Id(u) AS id,
        Id(s) AS role_id,
        s.name,
        s.is_admin,
        s.is_public,
        s.create_access_to,
        s.read_access_to,
        s.update_access_to,
        s.delete_access_to
      ", { "net_id" => net_id }, nil)
    if result.length > 0
      # We got a result, so the requested user exists.
      user_obj = {
        "net_id" => result[0]["net_id"],
        "id" => result[0]["id"],
        "is_admin" => false,
        "roles" => {},
        "create_access_to" => [],
        "read_access_to" => [],
        "update_access_to" => [],
        "delete_access_to" => []
      }
      result.each do |role|
        if role["name"] != nil
          LogTime.info "User_obj: " + user_obj.to_s
          LogTime.info "Role name: " + role["name"]
          user_obj["roles"][role["name"]] = {
            "id" => (role["role_id"]),
            "is_admin" => role["is_admin"],
            "is_public" => role["is_public"],
            "create_access_to" => (role["create_access_to"] == nil ? [] : role["create_access_to"]),
            "read_access_to" => (role["read_access_to"] == nil ? [] : role["read_access_to"]),
            "update_access_to" => (role["update_access_to"] == nil ? [] : role["update_access_to"]),
            "delete_access_to" => (role["delete_access_to"] == nil ? [] : role["delete_access_to"])
          }
        end
        if role["is_admin"]==true && (role["is_public"]==false || Rails.env.development?)
          # Public roles can't ever grant admin access, except in dev where we allow it for testing
          # purposes (as a way to "turn off" security temporarily).
          user_obj["is_admin"] = true
        end
        if role["create_access_to"] != nil
          role["create_access_to"].each do |node_type|
            if !user_obj["create_access_to"].include?(node_type)
              user_obj["create_access_to"] << node_type
            end
          end
        end
        if role["read_access_to"] != nil
          role["read_access_to"].each do |node_type|
            if !user_obj["read_access_to"].include?(node_type)
              user_obj["read_access_to"] << node_type
            end
          end
        end
        if role["update_access_to"] != nil
          role["update_access_to"].each do |node_type|
            if !user_obj["update_access_to"].include?(node_type)
              user_obj["update_access_to"] << node_type
            end
          end
        end
        if role["delete_access_to"] != nil
          role["delete_access_to"].each do |node_type|
            if !user_obj["delete_access_to"].include?(node_type)
              user_obj["delete_access_to"] << node_type
            end
          end
        end
        LogTime.info "Finished with role."
      end
      return { success: true, user: user_obj }
    else
      if net_id != "&anonymous"
        # Could not find the requested user. Try anonymous instead.
        return security_get("&anonymous")
      else
        # Could not find anonymous user. Create one and return that.
        if no_recursion
          # This means we already tried to create an anonymous user and somehow failed.
          return { success: false, message: "User not found, failed to create anonymous user (no error message)." }
        end
        
        tx = CypherTools.start_transaction()
        begin
          anonymous_params = { "net_id" => "&anonymous", "now" => Time.now.utc, "user" => "&anonymous" }
          create_result = CypherTools.execute_query_into_hash_array("
          
          MERGE (u:user { net_id: {net_id} })
          ON CREATE SET
            u.created_date = {now},
            u.modified_date = {now},
            u.created_by = {user},
            u.modified_by = {user},
            u.net_id = {net_id}
          RETURN
            u.net_id,
            Id(u) AS id

          ", anonymous_params, tx)
          if create_result.length == 0
            CypherTools.rollback(tx)
            return { success: false, message: "&anonymous user not found and could not be created." }
          end
          user_obj = {
            "net_id" => create_result[0]["net_id"],
            "id" => create_result[0]["id"],
            "is_admin" => false,
            "create_access_to" => [],
            "read_access_to" => [],
            "update_access_to" => [],
            "delete_access_to" => []
          }

          link_up_result = CypherTools.execute_query("

          MATCH (u:user { net_id: {net_id}}), (s:security_role { is_public: true })
          MERGE (u)-[r:HAS_ROLE]->(s)
          RETURN
            s.create_access_to,
            s.read_access_to,
            s.update_access_to,
            s.delete_access_to

            ", anonymous_params, tx)
          if create_result.length == 0
            CypherTools.rollback(tx)
            return { success: false, message: "&anonymous user not found and could not be created." }
          end
          CypherTools.commit_transaction(tx)
          return security_get("&new_anonymous")
        rescue Exception => e
          CypherTools.rollback(tx)
          return { success: false, message: "User not found, failed to create anonymous user: " + e.to_s }
        end
      end
    end
  end

  def get_public_roles
    role_unique_property = GraphModel.instance.nodes[:security_role].unique_property
    return CypherTools.execute_query_into_hash_array("
      MATCH (sr:security_role)
      WHERE sr.is_public = true
      RETURN
        Id(sr) AS id,
        sr.#{role_unique_property}
      ", {}, nil)
  end

  def add_public_roles(params)
    if !params.has_key?(:security_roles) || params[:security_roles] == nil
      params[:security_roles] = get_public_roles
      return params
    end

    role_unique_property = GraphModel.instance.nodes[:security_role].unique_property
    public_roles = get_public_roles
    public_roles.each do |public_role|
      role_found = false
      params[:security_roles].each do |role|
        if role.has_key?(:id) && public_role[:id] == role[:id]
          role_found = true
        elsif role.has_key?(role_unique_property) && public_role[role_unique_property] == role[role_unique_property]
          role_found = true
        end
      end
      if !role_found
        params[:security_roles] << public_role
      end
    end

    return params
  end

  def write(params, create_required, cas_user)
    #Any time we create or modify a user, we ensure that it gets assigned to all public security roles.
    if create_required || params.has_key?(:security_roles)
      params = add_public_roles(params)
    end

    return super(params, create_required, cas_user)
  end
end
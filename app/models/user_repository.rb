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

    result = CypherTools.execute_query_into_hash_array("
      MATCH (u:user)
      WHERE u.net_id = {net_id}
      OPTIONAL MATCH (u)-[:HAS_ROLE]-(s:security_role)
      RETURN
        u.net_id,
        Id(u) AS id,
        s.name,
        s.is_admin,
        s.read_access_to,
        s.write_access_to
      ", { "net_id" => net_id }, nil)
    if result.length > 0
      # We got a result, so the requested user exists.
      user_obj = {
        "net_id" => result[0]["net_id"],
        "id" => result[0]["id"],
        "is_admin" => false,
        "roles" => [],
        "read_access_to" => [],
        "write_access_to" => []
      }
      result.each do |role|
        if role["name"] != nil
          user_obj["roles"] << role["name"]
        end
        if role["is_admin"]==true && net_id != "&anonymous"
          # You can set is_admin on a public role if you really want to.
          # However, anonymous users never get admin rights.
          user_obj["is_admin"] = true
        end
        if role["read_access_to"] != nil
          role["read_access_to"].each do |node_type|
            if !user_obj["read_access_to"].include?(node_type)
              user_obj["read_access_to"] << node_type
            end
          end
        end
        if role["write_access_to"] != nil
          role["write_access_to"].each do |node_type|
            if !user_obj["write_access_to"].include?(node_type)
              user_obj["write_access_to"] << node_type
            end
          end
        end
      end
      return { success: true, user: user_obj }
    else
      if net_id != "&anonymous"
        # Could not find the requested user. Try anonymous instead.
        return security_get(nil)
      else
        # Could not find anonymous user. Create one and return that.
        begin
          anonymous_params = { "net_id" => "&anonymous", "now" => Time.now.utc, "user" => "&anonymous" }
          tx = CypherTools.start_transaction()
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
            return { success: false, message: "&anonymous user not found and could not be created." }
          end
          user_obj = {
            "net_id" => create_result[0]["net_id"],
            "id" => create_result[0]["id"],
            "is_admin" => false,
            "read_access_to" => [],
            "write_access_to" => []
          }

          link_up_result = CypherTools.execute_query("

          MATCH (u:user { net_id: {net_id}}), (s:security_role { is_public: true })
          MERGE (u)-[r:HAS_ROLE]->(s)
          RETURN
            s.read_access_to,
            s.write_access_to

            ", anonymous_params, tx)
          LogTime.info("Reading linkup results into output.")
          link_up_result.each do |role|
            if role["read_access_to"] != nil
              role["read_access_to"].each do |node_type|
                if !user_obj["read_access_to"].include?(node_type)
                  user_obj["read_access_to"] << node_type
                end
              end
            end
            if role["write_access_to"] != nil
              role["write_access_to"].each do |node_type|
                if !user_obj["write_access_to"].include?(node_type)
                  user_obj["write_access_to"] << node_type
                end
              end
            end
          end
          CypherTools.commit_transaction(tx)
          return { success: true, user: user_obj }
        rescue Exception => e
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
    if !params.has_key?(:security_roles)
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
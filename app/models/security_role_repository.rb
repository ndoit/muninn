class SecurityRoleRepository < ModelRepository
  def initialize
  	super(:security_role)
  end

  def get_all_users
    return CypherTools.execute_query_into_hash_array("
      MATCH (u:user)
      RETURN
        Id(u) AS id
      ", {}, nil)
  end

  def write(params, create_required, cas_user)
    #Any time we create a universal security role, or set an existing security role to universal, we apply it to all users.
    if params.has_key?(:security_role) && params[:security_role][:is_public] == true
      params[:users] = get_all_users
    end

    return super(params, create_required, cas_user)
  end
end
class UserRepository < ModelRepository
  def initialize
  	super(:user)
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
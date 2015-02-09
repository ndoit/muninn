class SecurityRoleRepository < ModelRepository
  def initialize
    super(:security_role)
  end

  def get_all_users
    model = GraphModel.instance.nodes[:user]
    return CypherTools.execute_query_into_hash_array("
      MATCH (u:user)
      RETURN
        Id(u) AS id,
        u.#{model.unique_property}
      ", {}, nil)
  end

  def write(params, create_required, cas_user)
    LogTime.info "****************************************************************************************************************************************************************************** WRITE CALLED IN SECURITY ROLE REPO! ************************************************************************************************************************************************************************************"
    #Any time we create a universal security role, or set an existing security role to universal, we apply it to all users.
    if params.has_key?(:security_role) && params[:security_role]["is_public"]
      LogTime.info("Public security role detected, adding all users.")
      params["users"] = get_all_users
    else
      LogTime.info("Writing non-public security role.")
    end

    return super(params, create_required, cas_user)
  end
end
class SecurityRolesController < GraphController

  def initialize()
    @primary_label = :security_role
  end

  def get_model_repository
    return SecurityRoleRepository.new
  end
end
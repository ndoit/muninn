class UsersController < GraphController

  def initialize()
    @primary_label = :user
  end

  def get_model_repository
    return UserRepository.new
  end

  def user_roles
  	role_hash = {}
  	role_hash["roles"] = []
  	role_hash["roles"] << "Report Publisher"
  	render json: role_hash.to_json
  end
end
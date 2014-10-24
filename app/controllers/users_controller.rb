class UsersController < GraphController

  def initialize()
    @primary_label = :user
  end

  def get_model_repository
    return UserRepository.new
  end

  def user_roles
    begin
    	role_hash = {}
    	role_hash["roles"] = []
    	role_hash["roles"] << "Report Publisher"

      if ( params[:netid] == 'afreda' )
        role_hash["roles"] << "Term Editor"
      end

    	render json: role_hash.to_json
    rescue (Exception e)
      render json: {}
    end
  end
end
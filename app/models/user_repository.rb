class UserRepository < ModelRepository
  def initialize
  	super(:user)
  end

  def add_to_public_role(base_output, tx)
  	public_security_role = CypherTools.execute_query("
  	  START u=node({id})
  	  MERGE (u)-[r:HAS_ROLE]->(sr:security_role { name: 'Public' })
  	  RETURN Id(sr)
  	  ", { :id => base_output[:id] }, tx)
  	return (public_security_role["data"].length > 0)
  end

  def create_public_role(tx)
  	security_role_repository = ModelRepository.new(:security_role)
  	return security_role_repository.write_with_transaction(
      { "security_role" => { "name" => "Public" } },
      true, tx
  	  )
  end

  def write_with_transaction(params, create_required, tx)
  	base_output = super(params, create_required, tx)
  	if !base_output[:success]
  	  return base_output
  	end
  	if !add_to_public_role(base_output, tx)
      create_public_result = create_public_role(tx)
      if !create_public_result[:success]
      	return {
      	  :success => false,
      	  :message => "Failed to create public security role: #{create_public_result[:message]}"
      	}
      end
      if !add_to_public_role(base_output, tx)
  	    return { :success => false, :message => "Failed to add user to public security role." }
  	  end
  	end
  	return base_output
  end
end
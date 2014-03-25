class UserRepository < ModelRepository
  def initialize
  	super(:user)
  end

  def add_to_public_role(base_output, role_id, tx)
  	public_security_role = CypherTools.execute_query("
  	  START u=node({id}), sr=node({role_id})
  	  MERGE (u)-[r:HAS_ROLE]->(sr)
  	  RETURN r
  	  ", { :id => base_output[:id], :role_id => role_id }, tx)
  	return (public_security_role["data"].length > 0)
  end

  def get_public_regime(tx)
  	repository = ModelRepository.new(:security_regime)
  	existing_regime = repository.read({ :unique_property => "Public" }, nil)
  	if !existing_regime[:success]
  	  return repository.write_with_transaction(
        { :security_regime => { "name" => "Public", "integrated_with_portal" => true } },
        true, tx
  	  )
  	else
  	  return existing_regime
  	end
  end

  def get_public_role(tx)
  	repository = ModelRepository.new(:security_role)
  	existing_role = repository.read({ :unique_property => "Public" }, nil)
  	if !existing_role[:success]
  	  return repository.write_with_transaction({
        :security_role => { "name" => "Public" },
        :security_regime => { "name" => "Public" }
        }, true, tx
  	  )
  	else
  	  return existing_role
  	end
  end

  def write_with_transaction(params, create_required, tx)
  	base_output = super(params, create_required, tx)
  	if !base_output[:success]
  	  return base_output
  	end
    public_regime = get_public_regime(tx)
    if !public_regime[:success]
  	  return {
  	    :success => false,
  	    :message => "Could not find or create Public security regime: #{public_regime[:message]}"
  	  }
    end
    public_role = get_public_role(tx)
    if !public_role[:success]
  	  return {
  	    :success => false,
  	    :message => "Could not find or create Public security role: #{public_role[:message]}"
  	  }
    end
    if !add_to_public_role(base_output, public_role[:id], tx)
  	  return { :success => false, :message => "Failed to add user to public security role." }
  	end
  	return base_output
  end
end
require "elasticsearch_io.rb"

class ModelRepository
  attr_accessor :primary_label
  
  def initialize(primary_label)
    @primary_label = primary_label
  end

  def validate_parameters(parameters)
  	parameters.keys.each do |key|
  	  if parameters[key] == nil
  	  	return { message: "#{key} is required.", success: false }
  	  end
  	  return { success: true }
  	end
  end

  def write(params, create_required, user_obj)
    tx = CypherTools.start_transaction
    result = nil
  	begin
  	  result = write_with_transaction(params, create_required, user_obj, tx)
  	  if result[:success]
  	    CypherTools.commit_transaction(tx)
  	  else
  	    CypherTools.rollback_transaction(tx)
  	  end
    rescue Exception => e
  	  CypherTools.rollback_transaction(tx)
  	  raise(e)
  	end

  	if result[:success]
  	  search_result = ElasticSearchIO.instance.update_node(@primary_label, result[:id])
  	  if !search_result[:success]
  	  	result[:searchable] = false
  	  	result[:searchable_message] = search_result[:message]
  	  else
  	  	result[:searchable] = true
  	  end
  	end
  	return result
  end
  
  def write_with_transaction(params, create_required, user_obj, tx)
  	LogTime.info("write_with_transaction invoked: create_required = #{create_required.to_s}, params = #{params.to_s}")
  	id = nil
    primary_model = GraphModel.instance.nodes[@primary_label]
    LogTime.info("primary node ********************* : #{primary_label}  " + primary_model.unique_property );
    if !params.has_key?(@primary_label)
    	 LogTime.info("No label? #{primary_label}.")
    	 #check_val =params[@primary_label].has_key?(primary_model.unique_property)
    	  
   	  if create_required  
   	  	LogTime.info("Cannot create without a #{primary_label} element.") 
  	    return { message: "Cannot create without a #{primary_label} element.", success: false }
	  	    
  	  end
    elsif !params[@primary_label].has_key?(primary_model.unique_property) ||
  		params[@primary_label][primary_model.unique_property] == ""
  	    #LogTime.info("Cannot create with blank or nil  #{primary_label} element and " + primary_model.unique_property);
  	  return { message: primary_model.unique_property + " cannot be blank or nil.", success: false }

    end
	
	if create_required
      LogTime.info("Creating new #{primary_label}.")
	  create_result = create_primary_node(params, user_obj, tx)
	  if !create_result[:success]
	  	return create_result
	  end
	  id = create_result[:id]
	else
      LogTime.info("Updating primary node.")
      update_result = update_primary_node(params, user_obj, tx)
      if !update_result[:success]
      	return update_result
      else
      	id = update_result[:id]
      end
	end

	relationship_result = write_relationships(id, params, create_required, tx, user_obj)
	if !relationship_result[:success]
	  return relationship_result
	end

	return { id: id, success: true }
  end

  def write_relationships(id, params, create_required, tx, user_obj)
  	LogTime.info("Writing relationships for node id=#{id.to_s}.")
    primary_model = GraphModel.instance.nodes[@primary_label]
  	primary_model.outgoing.each do |relation|
  	  if create_required || !relation.immutable #Immutable relationships can be created but not modified.
  	    params_key = relation.name_to_source
  		  is_required = relation.target_number == :one
  	    if params.has_key?(params_key)
  	      write_result = write_relationship(id, relation, :outgoing, params, params_key, tx, user_obj)
    		  if !write_result[:success]
    		    return write_result
    		  end
  	    elsif is_required
  	      return { message: "Cannot create #{primary_label} without #{params_key}.", success: false }
  	    end
  	  end
  	end
  	primary_model.incoming.each do |relation|
  	  if create_required || !relation.immutable #Immutable relationships can be created but not modified.
  	    params_key = relation.name_to_target
  		is_required = relation.source_number == :one
  	    if params.has_key?(params_key)
  	      write_result = write_relationship(id, relation, :incoming, params, params_key, tx, user_obj)
  		  if !write_result[:success]
  		    return write_result
  		  end
  	    elsif is_required
  	      return { message: "Cannot create #{primary_label} without #{params_key}.", success: false }
  	    end
  	  end
  	end
  	
  	return { success: true }
  end
  
  def create_primary_node(params, user_obj, tx)
  	node_contents = params[@primary_label]
    node_model = GraphModel.instance.nodes[@primary_label]
    now = Time.now.utc

    access_is_limited = !SecurityGoon.check_for_full_create(user_obj, @primary_label)
    if access_is_limited
      return { success: false, message: "Access denied." }
    end
  	
  	parameters = { :now => now, :user =>  user_obj["net_id"] }
  	node_model.properties.each do |property|
  	  if node_contents.has_key?(property) && node_contents[property] != nil
  	    parameters[property] = node_contents[property]
  	  else
  	  	parameters[property] = nil
  	  	#return { message: "Cannot create #{primary_label} without specifying #{property}.", success: false }
  	  end
  	end

  	LogTime.info(node_model.property_write_string("primary").to_s)
  	
    create_result = CypherTools.execute_query_into_hash_array("
  	
  	MERGE (primary:#{primary_label} { #{node_model.unique_property}: { #{node_model.unique_property} } })
  	ON CREATE SET
  	  primary.created_date = {now},
  	  primary.modified_date = {now},
  	  primary.created_by = {user},
  	  primary.modified_by = {user},
  	  " + node_model.property_write_string("primary") + "
  	RETURN
  	  primary.created_date = {now} AS created_new,
  	  Id(primary) AS id	

  	", parameters, tx)[0]
  	
  	if !create_result["created_new"]
  	  #Just as a note, the bulk loader depends on the Id being returned here.
  	  return { message: "#{primary_label} already exists.", id: create_result["id"], success: false }
  	end

    # The node was created new. Grant ownership rights if possible.
    ownership = grant_ownership_rights(params, user_obj, create_result["id"].to_i, node_model, tx)

  	return { id: create_result["id"], success: true, has_ownership_rights: ownership }
  end

  def grant_ownership_rights(params, user_obj, id, node_model, tx)
    # To be used when a node was just created. We want to ensure that the user who created it is given
    # update/delete access if possible. Returns true if successful, false if not.

    if user_obj["is_admin"]
      # No changes necessary, user is an admin.
      return true
    end

    if user_obj["update_access_to"].include?(node_model.label.to_s) &&
      user_obj["delete_access_to"].include?(node_model.label.to_s)
      # No changes necessary, user already has all required access.
      return true
    end

    ownership_possible = false
    node_model.outgoing.each do |relation|
      if relation.relation_name == "ALLOWS_ACCESS_WITH" && relation.target_label == :security_role
        ownership_possible = true
        break
      end
    end
    if !ownership_possible
      return false
    end

    # Now we know that the user does not have ownership rights, but that it is possible to grant those rights
    # for this node type. Now we need to determine which security role should get those rights.
    role_id = nil
    if params.has_key?(:create_as)
      target_role = params[:create_as]
      if !user_obj["roles"].has_key?(target_role)
        # You can't create under a role you don't belong to!
        raise "User does not have security role " + target_role.to_s + "."
        return
      end
      if !user_obj["roles"][target_role]["create_access_to"].include?(node_model.label.to_s)
        # This role doesn't have create access for the target node type.
        raise "Security role " + target_role + " does not have access to create " + node_model.label.to_s.pluralize + "."
        return
      end
      role_id = user_obj["roles"][target_role]["id"]
    else
      # You didn't say what role to create under, so we're just going to go through your roles and grab the
      # first one with create access for this node type. Good luck.
      user_obj["roles"].keys.each do |role|
        if user_obj["roles"][role]["create_access_to"].include?(node_model.label.to_s)
          role_id = user_obj["roles"][role]["id"]
          break
        end
      end
    end

    if role_id == nil
      # This should never happen; it should not be possible to get this far if you don't have a role with create
      # access for this node type. But just in case you somehow do get here...
      raise "User does not have a security role with access to create " + node_model.label.to_s.pluralize + "."
      return
    end

    # Okay! We have finally picked out an appropriate security role. Now to set up access:
    security_role_model = GraphModel.instance.nodes[:security_role]
    output = CypherTools.execute_query_into_hash_array("
      START n=node({id}), sr=node({role_id})
      CREATE (n)-[r:ALLOWS_ACCESS_WITH { allow_update_and_delete: true }]->(sr)
      RETURN Id(r)
    ", { :id => id, :role_id => role_id }, tx)
    return (output.length > 0)
  end
  
  def update_primary_node(params, user_obj, tx)
    node_model = GraphModel.instance.nodes[@primary_label]
    access_is_limited = !SecurityGoon.check_for_full_update(user_obj, @primary_label)

  	if !params.has_key?(@primary_label)
  	  #If the params does not contain a primary node, no update is required.
  	  #However, we fetch the id to simplify the process of doing relationship updates - and to verify that
  	  #the primary node exists!
  	  if params[:id] != nil
  	  	LogTime.info("\n\nBMR: Updating by id, which is #{params[:id]}")
  	  	result = CypherTools.execute_query_returning_scalar("
  	      START primary=node({id})" + (access_is_limited ? ", u=node({user_id})" : " ") + "
  	      MATCH (primary:#{primary_label})" + (access_is_limited ? "-[r:ALLOWS_ACCESS_WITH { allow_update_and_delete: true }]->(sr:security_role)<-[:HAS_ROLE]-(u:user)" : "") + "
  	      RETURN Id(primary)
  	      ", { :id => params[:id].to_i, :user_id => user_obj["id"] }, tx)
  	  else
  	  	LogTime.info("\n\nBMR: Updating by unique property, which is.. #{node_model.unique_property.to_s} ... value=#{params[:unique_property]}")
  	  	result = CypherTools.execute_query_returning_scalar(
          (access_is_limited ? "START u=node({user_id})" : "") + "
  	      MATCH (primary:#{primary_label} { " + node_model.unique_property.to_s + ": {unique_property} })" +
          (access_is_limited ? "-[r:ALLOWS_ACCESS_WITH { allow_update_and_delete: true }]->(sr:security_role)<-[:HAS_ROLE]-(u:user)" : "") + "
  	      RETURN Id(primary)
  	      ", { :unique_property => params[:unique_property], :user_id => user_obj["id"] }, tx)
      end
  	else
  	  node_contents = params[@primary_label]
  	  now = Time.now.utc
  		
      if params[:id] != nil
        parameters = { :id => params[:id].to_i, :now => now, :user =>  user_obj["net_id"], :user_id => user_obj["id"] }
        query_string = "
        START primary=node({id})" + (access_is_limited ? ", u=node({user_id})" : " ") + "
        MATCH (primary:#{primary_label})" + (access_is_limited ? "-[r:ALLOWS_ACCESS_WITH { allow_update_and_delete: true }]->(sr:security_role)<-[:HAS_ROLE]-(u:user)" : "") + "
        SET
        primary.modified_date = {now},
        primary.modified_by = {user},
        " + node_model.property_write_string("primary") + "
        RETURN Id(primary)"
      else
        parameters = { :unique_property => params[:unique_property], :now => now, :user => user_obj["net_id"], :user_id => user_obj["id"] }
        query_string =
        (access_is_limited ? "START u=node({user_id})" : "") + "
        MATCH (primary:#{primary_label} { " + node_model.unique_property.to_s + ": {unique_property} })" +
        (access_is_limited ? "-[r:ALLOWS_ACCESS_WITH { allow_update_and_delete: true }]->(sr:security_role)<-[:HAS_ROLE]-(u:user)" : "") + "
        SET
        primary.modified_date = {now},
        primary.modified_by = {user},
        " + node_model.property_write_string("primary") + "
        RETURN Id(primary)"
      end

      node_model.properties.each do |property|
	    if node_contents.has_key?(property) && node_contents[property] != nil
  		  parameters[property] = node_contents[property]
  		else
  		  parameters[property] = nil
  		end
	  end

	  result = CypherTools.execute_query_returning_scalar(query_string, parameters, tx)
    end

    if result == nil
      if params[:id] != nil
      	return { success: false, message: "#{primary_label.capitalize} with id = " + params[:id].to_s + " not found." }
      else
      	return { success: false, message: "#{primary_label.capitalize} with " + node_model.unique_property + " = \"" + 
      	  params[:unique_property] + "\" not found." }
      end
    end
	return { success: true, id: result }
  end
  
  def write_relationship(id, relation, direction, params, params_key, tx, user_obj)
    LogTime.info "Writing relationship: " + relation.relation_name.to_s
    if direction == :outgoing
  	  number_of = relation.target_number
  	else
  	  number_of = relation.source_number
  	end
  	
  	delete_relationships(id, relation, direction, tx)
  	params_element = params[params_key]
  	
  	if number_of == :many
  	  if params_element != nil
  	    params_element.each do |node|
  	      write_relation_result = write_relationship_to_node(id, relation, direction, node, tx, user_obj)
  	      if !write_relation_result[:success]
  	      	return write_relation_result
  	      end
  	    end
  	  end
  	elsif number_of == :one_or_zero
  	  if params_element != nil
  	    write_relation_result = write_relationship_to_node(id, relation, direction, params_element, tx, user_obj)
  	    if !write_relation_result[:success]
  	      return write_relation_result
  	    end
  	  end
  	elsif number_of == :one
  	  if params_element == nil
  	    return { message: "#{primary_label.capitalize} must have #{params_key}.", success: false }
  	  end
  	  write_relation_result = write_relationship_to_node(id, relation, direction, params_element, tx, user_obj)
  	  if !write_relation_result[:success]
  	    return write_relation_result
  	  end
  	end
  	return { success: true }
  end
  
  def delete_relationships(id, relation, direction, tx)
  	relationship_name = relation.relation_name
    if direction == :outgoing
  	  other_node_label = relation.target_label
  	  match_string = "(primary:#{primary_label})-[r:#{relationship_name}]->(other:#{other_node_label})"
  	else
  	  other_node_label = relation.source_label
  	  match_string = "(other:#{other_node_label})-[r:#{relationship_name}]->(primary:#{primary_label})"
  	end
      CypherTools.execute_query("
  	
  	  START primary=node({id})
  	  MATCH #{match_string}
  	  DELETE r
  	
  	", { :id => id }, tx
  	)
  end

  def has_existing_source(target_start, target_match, relationship_name, parameters)
  	if target_start
	  existing = CypherTools.execute_query_into_hash_array("
		
		START #{target_start}
		MATCH (other_source)-[r:#{relationship_name}]->#{target_match}
		RETURN Id(other_source) AS id

		", parameters, tx
		)
  	else
	  existing = CypherTools.execute_query_into_hash_array("
		
		MATCH (other_source)-[r:#{relationship_name}]->#{target_match}
		RETURN Id(other_source) AS id

		", parameters, tx
		)
	end
	return (existing.length > 0)
  end

  def has_existing_target(source_start, source_match, relationship_name, parameters, tx)
  	if source_start
	  existing = CypherTools.execute_query_into_hash_array("
		
		START #{source_start}
		MATCH #{source_match}-[r:#{relationship_name}]->(other_target)
		RETURN Id(other_target) AS id

		", parameters, tx
		)
  	else
	  existing = CypherTools.execute_query_into_hash_array("
		
		MATCH #{source_match}-[r:#{relationship_name}]->(other_target)
		RETURN Id(other_target) AS id

		", parameters, tx
		)
	end
	return (existing.length > 0)
  end
  
  def write_relationship_to_node(id, relation, direction, params_element, tx, user_obj)
  	relationship_name = relation.relation_name
  	parameters = {}
  	other_node_model = nil
    if direction == :outgoing
      other_node_model = GraphModel.instance.nodes[relation.target_label]
      parameters[:source_id] = id
      source_match = "(source)"
      source_start = "source=node({source_id})"
      if params_element.has_key?("id")
        parameters[:target_id] = params_element["id"]
        target_match = "(target:" + other_node_model.label.to_s + ")"
        target_start = "target=node({target_id})"
      else
      	parameters[:target_property] = params_element[other_node_model.unique_property.to_s]
        target_match = "(target:" + other_node_model.label.to_s + " { " +
          other_node_model.unique_property + ": {target_property}})"
        target_start = nil
      end
    else
      other_node_model = GraphModel.instance.nodes[relation.source_label]
      parameters[:target_id] = id
      target_match = "(target)"
      target_start = "target=node({target_id})"
      if params_element.has_key?("id")
        parameters[:source_id] = params_element["id"]
        source_match = "(source:" + other_node_model.label.to_s + ")"
        source_start = "source=node({source_id})"
      else
      	parameters[:source_property] = params_element[other_node_model.unique_property.to_s]
        source_match = "(source:" + other_node_model.label.to_s + " { " +
          other_node_model.unique_property + ": {source_property}})"
        source_start = nil
      end
    end

    # You do *not* need write access to the related node in order to create a relationship to it,
    # but you do need read access.
    access_is_limited = !SecurityGoon.check_for_full_read(user_obj, other_node_model.label)
    if access_is_limited
      parameters[:user_id] = user_obj["id"]
      if direction == :outgoing
        if target_start != nil
          target_start += ", u=node({user_id})"
        else
          target_start = "u=node({user_id})"
        end
        target_match += "-[:ALLOWS_ACCESS_WITH]->(sr:security_role)<-[:HAS_ROLE]-(u:user)"
      else
        if source_start != nil
          source_start += ", u=node({user_id})"
        else
          source_start = "u=node({user_id})"
        end
        source_match += "-[:ALLOWS_ACCESS_WITH]->(sr:security_role)<-[:HAS_ROLE]-(u:user)"
      end
    end

  	property_write_string = relation.property_write_string(nil)
  	relation.properties.each do |property|
	  if params_element.has_key?(property) && params_element[property] != nil
	    parameters[property] = params_element[property]
	  else
	  	return { message: "Cannot add #{relationship_name} connection without specifying #{property}.", success: false }
	  end
	end

	if relation.target_number == :one || relation.target_number == :one_or_zero
      if has_existing_target(source_start, source_match, relationship_name, parameters, tx)
	  	return { success: false, message: "Cannot assign multiple " + relation.name_to_source.to_s.pluralize +
	  		" to " + relation.source_label.to_s + " with id = " + parameters[:source_id].to_s + "." }
	  end
	end
	if relation.source_number == :one || relation.source_number == :one_or_zero
      if has_existing_source(target_start, target_match, relationship_name, parameters, tx)
	  	return { success: false, message: "Cannot assign multiple " + relation.name_to_target.to_s.pluralize +
	  		" to " + relation.target_label.to_s + " with id = " + parameters[:target_id].to_s + "." }
	  end
	end

    if source_start
      if target_start
      	start_string = "START #{source_start}, #{target_start}"
      else
      	start_string = "START #{source_start}"
      end
    else
      if target_start
      	start_string = "START #{target_start}"
      else
      	start_string = ""
      end
    end
    if direction == :outgoing
      match_string = "MATCH #{target_match}"
    else
      match_string = "MATCH #{source_match}"
    end
	result = CypherTools.execute_query_into_hash_array("
	    
	  #{start_string}
      #{match_string}
	  CREATE (source)-[r:#{relationship_name} #{property_write_string}]->(target)
	  RETURN id(source), id(target)
	    
	  ", parameters, tx
	)
	if result.length < 1
	  #We couldn't find a matching node to create the relationship.
	  if direction == :outgoing
	    if parameters.has_key?(:target_id)
	      return { success: false, message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " with Id=" + parameters[:target_id].to_s + " not found." }
	    else
	      return { success: false, message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " \"" + parameters[:target_property].to_s + "\" not found." }
	    end
      else
	    if parameters.has_key?(:source_id)
	      return { success: false, message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " with Id=" + parameters[:source_id].to_s + " not found." }
	    else
	      return { success: false, message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " \"" + parameters[:source_property].to_s + "\" not found." }
	    end
	  end
	elsif result.length > 1
	  #Somehow or other we found multiple matching nodes. This shouldn't ever happen, but... *shrug*
	  if direction == :outgoing
	    if parameters.has_key?(:target_id)
	      return { success: false, message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " with Id=" + parameters[:target_id].to_s + " found." }
	    else
	      return { success: false, message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " \"" + parameters[:target_property].to_s + "\" found." }
	    end
      else
	    if parameters.has_key?(:source_id)
	      return { success: false, message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " with Id=" + parameters[:source_id].to_s + " found." }
	    else
	      return { success: false, message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " \"" + parameters[:source_property].to_s + "\" found." }
	    end
	  end
	end
    return { success: true }
  end
  
  #identifier may be either the numeric id of the node, or the unique property of the term.
  #identifier_is_id indicates which it is.
  def read(params, user_obj)
  	if params.has_key?(:id)
  	  identifier = params[:id]
  	  identifier_is_id = true
  	else
  	  identifier = params[:unique_property]
  	  identifier_is_id = false
  	end

  	LogTime.info("identifier = #{identifier}, identifier_is_id = #{identifier_is_id}")
  	begin
  	  primary_node = read_primary_node(identifier, identifier_is_id, user_obj)
  	rescue Exception => e
  	  if e.to_s == "One of the ids given was invalid."
  	  	return { message: "#{primary_label} not found.", success: false }
  	  else
  	  	return { message: "Error retrieving #{primary_label}: " + e.to_s + " Please review data service logs.", success: false }
  	  end
  	end
	
	if primary_node == nil
	  LogTime.info "Not found, exiting."
	  return { message: "#{primary_label} not found.", success: false }
	end
	
	id = primary_node["id"]
	
	output = { @primary_label => primary_node, :success => true }
	
	model = GraphModel.instance.nodes[@primary_label]
	model.outgoing.each do |relation|
	  output[relation.name_to_source] = read_relationship(id, relation, :outgoing, user_obj)
	end
	model.incoming.each do |relation|
	  output[relation.name_to_target] = read_relationship(id, relation, :incoming, user_obj)
    end
	
	return output
  end
  
  def read_primary_node(identifier, identifier_is_id, user_obj)
    node_model = GraphModel.instance.nodes[@primary_label]
  	output = nil

    access_is_limited = !SecurityGoon.check_for_full_read(user_obj, @primary_label)
    if access_is_limited
      LogTime.info("Access limited.")
    end

    match_string = "MATCH (n:#{node_model.label})"
    if access_is_limited
      match_string += "-[:ALLOWS_ACCESS_WITH]->(s)<-[:HAS_ROLE]-(u)"
    end
    if identifier_is_id
      start_string = "START n=node({id})" + (access_is_limited ? ", u=node({user_id})" : "")
      where_string = ""
    else
      start_string = (access_is_limited ? "START u=node({user_id})" : "")
      where_string = "WHERE n.#{node_model.unique_property} = {unique_property}"
    end
    return_string = "RETURN
      n.created_date,
      n.modified_date,
      n.created_by,
      n.modified_by,
      #{node_model.property_string("n",user_obj!=nil)}"

    query_string = "
      #{start_string}
      #{match_string}
      #{where_string}
      #{return_string}
      "
    if access_is_limited && @primary_label == :security_role
      # Regardless of access, you can always see security roles to which you belong.
      query_string += "
      UNION
      #{start_string}
      MATCH (n:security_role)<-[:HAS_ROLE]-(u)
      #{where_string}
      #{return_string}"
    end

    if access_is_limited && @primary_label == :user && (!identifier_is_id || identifier == user_obj["id"])
      # Regardless of access, you can always see yourself.
      query_string += "
      UNION
      START n=node({user_id})
      #{where_string}
      #{return_string}"
    end

  	if identifier_is_id
  	  LogTime.info("Querying with id.")
  	  output = CypherTools.execute_query_into_hash_array(query_string,
  		{ :id => identifier.to_i, :user_id => user_obj["id"] },
  		nil)
  	else
  	  LogTime.info("Querying without id.")
  	  output = CypherTools.execute_query_into_hash_array(query_string,
  		{ :unique_property => identifier, :user_id => user_obj["id"] },
  		nil)
  	end
  	
  	if output.length > 0
  	  return output[0]
  	end
  	return nil
  end
  
  def read_relationship(id, relation, direction, user_obj)
    LogTime.info("Reading relation: " + relation.to_s)
  	relationship_name = relation.relation_name
      if direction == :outgoing
  	  other_node_label = relation.target_label
      other_node_model = GraphModel.instance.nodes[other_node_label]
  	  match_string = "(primary:#{primary_label})-[r:#{relationship_name}]->(other:#{other_node_label})"
  	  return_array = relation.target_number == :many #If this relationship is x-to-many, return an array.
  	else
  	  other_node_label = relation.source_label
      other_node_model = GraphModel.instance.nodes[other_node_label]
  	  match_string = "(other:#{other_node_label})-[r:#{relationship_name}]->(primary:#{primary_label})"
  	  return_array = relation.source_number == :many #If this relationship is many-to-x, return an array.
  	end

    access_is_limited = !SecurityGoon.check_for_full_read(user_obj, other_node_label)
    start_string = "START primary=node({id})" + (access_is_limited ? ", u=node({user_id})" : "")

    if access_is_limited
      if direction==:outgoing
        role_match_string = match_string + "<-[:HAS_ROLE]-(u)"
        secured_match_string = "(u)-[:HAS_ROLE]->(s:security_role)<-[:ALLOWS_ACCESS_WITH]-" + match_string
      else
        role_match_string = "(u)-[:HAS_ROLE]->" + match_string
        secured_match_string = match_string + "-[:ALLOWS_ACCESS_WITH]->(s:security_role)<-[:HAS_ROLE]-(u)"
      end
    else
      secured_match_string = match_string
    end
    return_string = "RETURN
      other.created_date,
      other.modified_date,
      other.created_by,
      other.modified_by,
      " + other_node_model.property_string("other") + relation.property_string("r")
  	
  	LogTime.info("return_array = " + return_array.to_s)

    query_string = "
      #{start_string}
      MATCH #{secured_match_string}
      #{return_string}"
    if access_is_limited && other_node_label == :security_role
      # Regardless of access, you can always see security roles to which you belong.
      query_string += "
      UNION
      #{start_string}
      MATCH #{role_match_string}
      #{return_string}"
    end
    if access_is_limited && other_node_label == :user
      # Regardless of access, you can always see yourself.
      query_string += "
      UNION
      START primary=node({id}), other=node({user_id})
      MATCH #{match_string}
      #{return_string}"
    end
  	  
    output = CypherTools.execute_query_into_hash_array(query_string,
  	  { :id => id, :user_id => user_obj["id"] }, nil)
  	  
  	if return_array
  	  return output
  	elsif output.length > 0
  	  return output[0]
  	else
  	  return nil
  	end
  end

  def relations_block_deletion(id, relation, direction)
  	if direction == :outgoing
  	  if relation.source_number != :one
  	    return false
  	  end
  	  match_string = "(primary)-[r:" + relation.relation_name + "]->(other:" +
  	  	relation.target_label.to_s + ")"
  	else
  	  if relation.target_number != :one
  	    return false
  	  end
  	  match_string = "(other:" + relation.source_label.to_s + ")-[r:" + relation.relation_name +
  	    "]->(primary)"
  	end

  	output = CypherTools.execute_query_into_hash_array("
  		START primary=node({id})
  		MATCH #{match_string}
  		RETURN Id(other)
  		", { :id => id }, nil)

  	return output.length > 0
  end

  def validate_delete(id)
  	LogTime.info("Determining if node can be deleted: #{id}")
  	model = GraphModel.instance.nodes[@primary_label]
  	model.outgoing.each do |relation|
  	  if relations_block_deletion(id, relation, :outgoing)
  	  	return { success: false, message: "Cannot delete a " + @primary_label.to_s + " that has " +
  	      relation.name_to_source.to_s + "." }
  	  end
  	end
  	model.incoming.each do |relation|
  	  if relations_block_deletion(id, relation, :incoming)
  	  	return { success: false, message: "Cannot delete a " + @primary_label.to_s + " that has " +
  	      relation.name_to_target.to_s + "." }
  	  end
  	end
    return { success: true }
  end

  def delete_with_transaction(id, tx)
    CypherTools.execute_query("
      START n=node({id})
      MATCH (n)-[r]-(other)
      DELETE r
      ", { :id => id }, tx)

    CypherTools.execute_query_returning_scalar("
      START n=node({id})
      MATCH (n:#{primary_label})
      DELETE n
      ", { :id => id }, tx)

    return { success: true }
  end

  def delete(params, user_obj)
  	if params.has_key?(:id)
  	  identifier = params[:id]
  	  identifier_is_id = true
  	else
  	  identifier = params[:unique_property]
  	  identifier_is_id = false
  	end

    access_is_limited = !SecurityGoon.check_for_full_delete(user_obj, @primary_label)
    tx = CypherTools.start_transaction

  	#Since we will probably have to delete a bunch of relationships too, we go ahead and
  	#retrieve the node Id first.
  	if identifier_is_id
  	  id = CypherTools.execute_query_returning_scalar("
  	  	START n=node({identifier})" + (access_is_limited ? ", u=node({user_id})" : "") + "
        MATCH (n:#{primary_label})" + (access_is_limited ? "-[:ALLOWS_ACCESS_WITH { allow_update_and_delete: true }]->(sr:security_role)<-[:HAS_ROLE]-(u:user)" : "") + "
        RETURN Id(n)
  	  	", { :identifier => identifier.to_i, :user_id => user_obj["id"] }, tx
  	  )
  	  if id == nil
  	  	return { success: false, message: "Could not find #{primary_label} with id = " + 
  	  	  identifier.to_s + "." }
  	  end
  	else
  	  node_model = GraphModel.instance.nodes[@primary_label]
  	  id = CypherTools.execute_query_returning_scalar(
        (access_is_limited ? "START u=node({user_id})" : "") + "
        MATCH (n:#{primary_label} { " + node_model.unique_property + ": {unique_property} })" +
        (access_is_limited ? "-[:ALLOWS_ACCESS_WITH { allow_update_and_delete: true }]->(sr:security_role)<-[:HAS_ROLE]-(u:user)" : "") + "
        RETURN Id(n)
  	  	", { :unique_property => identifier, :user_id => user_obj["id"] }, tx
  	  )
  	  if id == nil
  	  	return { success: false, message: "Could not find #{primary_label} with " + 
  	  	  node_model.unique_property + " = \"" + identifier + "\"." }
  	  end
  	end

    validate_result = validate_delete(id)
    if !validate_result[:success]
      return validate_result
    end

	begin
      result = delete_with_transaction(id, tx)
	  if result[:success]
	    CypherTools.commit_transaction(tx)
	  else
	    CypherTools.rollback_transaction(tx)
	  end
    rescue Exception => e
	  CypherTools.rollback_transaction(tx)
	  raise(e)
	end

	if result[:success]
	  search_result = ElasticSearchIO.instance.delete_node(@primary_label, id)
	  if !search_result[:success]
	  	result[:searchable] = false
	  	result[:searchable_message] = search_result[:message]
	  else
	  	result[:searchable] = true
	  end
	end
	return result
  end
end
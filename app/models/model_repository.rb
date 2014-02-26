require "elasticsearch_io.rb"

class ModelRepository
  attr_accessor :primary_label
  
  def initialize(primary_label)
    @primary_label = primary_label
  end

  def validate_parameters(parameters)
  	parameters.keys.each do |key|
  	  if parameters[key] == nil
  	  	return { Message: "#{key} is required.", Success: false }
  	  end
  	  return { Success: true }
  	end
  end

  def write(params, create_required, cas_user)
    tx = CypherTools.start_transaction
    result = nil
	begin
	  result = write_with_transaction(params, create_required, tx)
	  if result[:Success]
	    CypherTools.commit_transaction(tx)
	  else
	    CypherTools.rollback_transaction(tx)
	  end
    rescue Exception => e
	  CypherTools.rollback_transaction(tx)
	  raise(e)
	end

	if result[:Success]
	  search_result = ElasticSearchIO.instance.update_node(@primary_label, result[:Id])
	  if !search_result[:Success]
	  	result[:Searchable] = false
	  	result[:SearchableMessage] = search_result[:Message]
	  else
	  	result[:Searchable] = true
	  end
	end
	return result
  end
  
  def write_with_transaction(params, create_required, tx)
    id = nil
    primary_model = GraphModel.instance.nodes[@primary_label]

    if !params.has_key?(@primary_label)
   	  if create_required
  	    return { Message: "Cannot create without a #{primary_label} element.", Success: false }
  	  end
    elsif !params[@primary_label].has_key?(primary_model.unique_property) ||
  		params[@primary_label][primary_model.unique_property] == ""
  	  return { Message: primary_model.unique_property + " cannot be blank or nil.", Success: false }
    end
	
	if create_required
      LogTime.info("Creating new #{primary_label}.")
	  create_result = create_primary_node(params, tx)
	  if !create_result[:Success]
	  	return create_result
	  end
	  id = create_result[:Id]
	else
      LogTime.info("Updating primary node.")
      update_result = update_primary_node(params, tx)
      if !update_result[:Success]
      	return update_result
      else
      	id = update_result[:Id]
      end
	end

	relationship_result = write_relationships(id, params, tx)
	if !relationship_result[:Success]
	  return relationship_result
	end

	return { Id: id, Success: true }
  end

  def write_relationships(id, params, tx)
  	LogTime.info("Writing relationships for node Id=#{id.to_s}.")
    primary_model = GraphModel.instance.nodes[@primary_label]
	primary_model.outgoing.each do |relation|
	  if params[:CreateRequired] || !relation.immutable #Immutable relationships can be created but not modified.
	    params_key = relation.name_to_source
		is_required = relation.target_number == :one
	    if params.has_key?(params_key)
	      write_result = write_relationship(id, relation, :outgoing, params, params_key, tx)
		  if !write_result[:Success]
		    return write_result
		  end
	    elsif is_required && params[:CreateRequired]
	      return { Message: "Cannot create #{primary_label} without #{params_key}.", Success: false }
	    end
	  end
	end
	primary_model.incoming.each do |relation|
	  if params[:CreateRequired] || !relation.immutable #Immutable relationships can be created but not modified.
	    params_key = relation.name_to_target
		is_required = relation.source_number == :one
	    if params.has_key?(params_key)
	      write_result = write_relationship(id, relation, :incoming, params, params_key, tx)
		  if !write_result[:Success]
		    return write_result
		  end
	    elsif is_required && params[:CreateRequired]
	      return { Message: "Cannot create #{primary_label} without #{params_key}.", Success: false }
	    end
	  end
	end
	
	return { Success: true }
  end
  
  def create_primary_node(params, tx)
  	node_contents = params[@primary_label]
    node_model = GraphModel.instance.nodes[@primary_label]
    now = Time.now.utc
	
	parameters = { :now => now }
	node_model.properties.each do |property|
	  if node_contents.has_key?(property) && node_contents[property] != nil
	    parameters[property] = node_contents[property]
	  else
	  	return { Message: "Cannot create #{primary_label} without specifying #{property}.", Success: false }
	  end
	end

	LogTime.info(node_model.property_write_string("primary").to_s)
	
    create_result = CypherTools.execute_query_into_hash_array("
	
	MERGE (primary:#{primary_label} { #{node_model.unique_property}: { #{node_model.unique_property} } })
	ON CREATE SET
	  primary.CreatedDate = {now},
	  primary.ModifiedDate = {now},
	  " + node_model.property_write_string("primary") + "
	RETURN
	  primary.CreatedDate = {now} AS CreatedNew,
	  Id(primary) AS Id
	
	", parameters, tx)[0]
	
	if !create_result["CreatedNew"]
	  #Just as a note, the bulk loader depends on the Id being returned here.
	  return { Message: "#{primary_label} already exists.", Id: create_result["Id"], Success: false }
	end

	return { Id: create_result["Id"], Success: true }
  end
  
  def update_primary_node(params, tx)
    node_model = GraphModel.instance.nodes[@primary_label]

  	if !params.has_key?(@primary_label)
  	  #If the params does not contain a primary node, no update is required.
  	  #However, we fetch the id to simplify the process of doing relationship updates - and to verify that
  	  #the primary node exists!
  	  if params[:id] != nil
  	  	result = CypherTools.execute_query_returning_scalar("
  	      START primary=node({id})
  	      MATCH (primary:#{primary_label})
  	      RETURN Id(primary)
  	      ", { :id => params[:id] }, tx)
  	  else
  	  	result = CypherTools.execute_query_returning_scalar("
  	      MATCH (primary:#{primary_label} { " + node_model.unique_property.to_s + ": {unique_property} })
  	      RETURN Id(primary)
  	      ", { :unique_property => params[:unique_property] }, tx)
      end
  	else
	  node_contents = params[@primary_label]
	  now = Time.now.utc
		
	  if params[:id] != nil
		parameters = { :id => params[:id], :now => now }
		query_string = "
		  START primary=node({id})
		  MATCH (primary:#{primary_label})
		  SET
		    primary.ModifiedDate = {now},
		    " + node_model.property_write_string("primary") + "
		  RETURN Id(primary)"
	  else
		parameters = { :unique_property => params[:unique_property], :now => now }
		query_string = "
		  MATCH (primary:#{primary_label} { " + node_model.unique_property.to_s + ": {unique_property} })
		  SET
		    primary.ModifiedDate = {now},
		    " + node_model.property_write_string("primary") + "
		  RETURN Id(primary)"
      end

      node_model.properties.each do |property|
	    if node_contents.has_key?(property) && node_contents[property] != nil
		  parameters[property] = node_contents[property]
		else
		  return { Message: "Cannot modify #{primary_label} without specifying #{property}.", Success: false }
		end
	  end

	  result = CypherTools.execute_query_returning_scalar(query_string, parameters, tx)
    end

    if result == nil
      if params[:id] != nil
      	return { Success: false, Message: "#{primary_label} with Id = " + params[:id].to_s + " not found." }
      else
      	return { Success: false, Message: "#{primary_label} with " + node_model.unique_property + " = \"" + 
      	  params[:unique_property] + "\" not found." }
      end
    end
	return { Success: true, Id: result }
  end
  
  def write_relationship(id, relation, direction, params, params_key, tx)
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
	      write_relation_result = write_relationship_to_node(id, relation, direction, node, tx)
	      if !write_relation_result[:Success]
	      	return write_relation_result
	      end
	    end
	  end
	elsif number_of == :one_or_zero
	  if params_element != nil
	    write_relation_result = write_relationship_to_node(id, relation, direction, params_element, tx)
	    if !write_relation_result[:Success]
	      return write_relation_result
	    end
	  end
	elsif number_of == :one
	  if params_element == nil
	    return { Message: "#{primary_label} must have #{params_key}.", Success: false }
	  end
	  write_relation_result = write_relationship_to_node(id, relation, direction, params_element, tx)
	  if !write_relation_result[:Success]
	    return write_relation_result
	  end
	end
	return { Success: true }
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
		RETURN Id(other_source) AS Id

		", parameters, tx
		)
  	else
	  existing = CypherTools.execute_query_into_hash_array("
		
		MATCH (other_source)-[r:#{relationship_name}]->#{target_match}
		RETURN Id(other_source) AS Id

		", parameters, tx
		)
	end
	return (existing.length > 0)
  end

  def has_existing_target(source_start, source_match, relationship_name, parameters)
  	if source_start
	  existing = CypherTools.execute_query_into_hash_array("
		
		START #{source_start}
		MATCH #{source_match}-[r:#{relationship_name}]->(other_target)
		RETURN Id(other_target) AS Id

		", parameters, tx
		)
  	else
	  existing = CypherTools.execute_query_into_hash_array("
		
		MATCH #{source_match}-[r:#{relationship_name}]->(other_target)
		RETURN Id(other_target) AS Id

		", parameters, tx
		)
	end
	return (existing.length > 0)
  end
  
  def write_relationship_to_node(id, relation, direction, params_element, tx)
  	relationship_name = relation.relation_name
  	parameters = {}
  	other_node_model = nil
    if direction == :outgoing
      other_node_model = GraphModel.instance.nodes[relation.target_label]
      parameters[:source_id] = id
      source_match = "(source)"
      source_start = "source=node({source_id})"
      if params_element.has_key?("Id")
        parameters[:target_id] = params_element["Id"]
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
      if params_element.has_key?("Id")
        parameters[:source_id] = params_element["Id"]
        source_match = "(source:" + other_node_model.label.to_s + ")"
        source_start = "source=node({source_id})"
      else
      	parameters[:source_property] = params_element[other_node_model.unique_property.to_s]
        source_match = "(source:" + other_node_model.label.to_s + " { " +
          other_node_model.unique_property + ": {source_property}})"
        source_start = nil
      end
    end
	property_write_string = relation.property_write_string(nil)
	relation.properties.each do |property|
	  if params_element.has_key?(property) && params_element[property] != nil
	    parameters[property] = params_element[property]
	  else
	  	return { Message: "Cannot add #{relationship_name} connection without specifying #{property}.", Success: false }
	  end
	end

	if relation.target_number == :one || relation.target_number == :one_or_zero
      if has_existing_target(source_start, source_match, relationship_name, parameters)
	  	return { Success: false, Message: "Cannot assign multiple " + relation.name_to_source.to_s.pluralize +
	  		" to " + relation.source_label.to_s + " Id " + parameters[:source_id].to_s + "." }
	  end
	end
	if relation.source_number == :one || relation.source_number == :one_or_zero
      if has_existing_source(target_start, target_match, relationship_name, parameters)
	  	return { Success: false, Message: "Cannot assign multiple " + relation.name_to_target.to_s.pluralize +
	  		" to " + relation.target_label.to_s + " Id " + parameters[:target_id].to_s + "." }
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
	  RETURN Id(source), Id(target)
	    
	  ", parameters, tx
	)
	if result.length < 1
	  #We couldn't find a matching node to create the relationship.
	  if direction == :outgoing
	    if parameters.has_key?(:target_id)
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " with Id=" + parameters[:target_id].to_s + " not found." }
	    else
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " \"" + parameters[:target_property].to_s + "\" not found." }
	    end
      else
	    if parameters.has_key?(:source_id)
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " with Id=" + parameters[:source_id].to_s + " not found." }
	    else
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: " + other_node_model.label.to_s + " \"" + parameters[:source_property].to_s + "\" not found." }
	    end
	  end
	elsif result.length > 1
	  #Somehow or other we found multiple matching nodes. This shouldn't ever happen, but... *shrug*
	  if direction == :outgoing
	    if parameters.has_key?(:target_id)
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " with Id=" + parameters[:target_id].to_s + " found." }
	    else
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " \"" + parameters[:target_property].to_s + "\" found." }
	    end
      else
	    if parameters.has_key?(:source_id)
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " with Id=" + parameters[:source_id].to_s + " found." }
	    else
	      return { Success: false, Message: "Could not create #{relationship_name} relationship: Multiple " + other_node_model.label.to_s.pluralize + " \"" + parameters[:source_property].to_s + "\" found." }
	    end
	  end
	end
    return { Success: true }
  end
  
  #identifier may be either the numeric id of the node, or the unique property of the term.
  #identifier_is_id indicates which it is.
  def read(params, cas_user)
  	if params.has_key?(:id)
  	  identifier = params[:id]
  	  identifier_is_id = true
  	else
  	  identifier = params[:unique_property]
  	  identifier_is_id = false
  	end

  	LogTime.info("identifier = #{identifier}, identifier_is_id = #{identifier_is_id}")
  	begin
  	  primary_node = read_primary_node(identifier, identifier_is_id, cas_user)
  	rescue Exception => e
  	  if e.to_s == "One of the ids given was invalid."
  	  	return { Message: "#{primary_label} not found.", Success: false }
  	  else
  	  	return { Message: "Error retrieving #{primary_label}: " + e.to_s + " Please review data service logs.", Success: false }
  	  end
  	end
	
	if primary_node == nil
	  LogTime.info "Not found, exiting."
	  return { Message: "#{primary_label} not found.", Success: false }
	end
	
	id = primary_node["Id"]
	
	output = { @primary_label => primary_node, :Success => true }
	
	model = GraphModel.instance.nodes[@primary_label]
	model.outgoing.each do |relation|
	  output[relation.name_to_source] = read_relationship(id, relation, :outgoing)
	end
	model.incoming.each do |relation|
	  output[relation.name_to_target] = read_relationship(id, relation, :incoming)
    end
	
	return output
  end
  
  def read_primary_node(identifier, identifier_is_id, cas_user)
    node_model = GraphModel.instance.nodes[@primary_label]
	output = nil
	if identifier_is_id
	  LogTime.info("Querying with id.")
	  output = CypherTools.execute_query_into_hash_array("
	    START n=node({id})
		MATCH (n:" + node_model.label + ")
		RETURN
		n.CreatedDate,
		n.ModifiedDate,
		" + node_model.property_string("n", cas_user != nil),
		{ :id => identifier.to_i },
		nil)
	else
	  LogTime.info("Querying without id.")
	  output = CypherTools.execute_query_into_hash_array("
		MATCH (n:" + node_model.label + ")
		WHERE n." + node_model.unique_property + " = {unique_property}
		RETURN
		n.CreatedDate,
		n.ModifiedDate,
		" + node_model.property_string("n", cas_user != nil),
		{ :unique_property => identifier },
		nil)
	end
	
	if output.length > 0
	  return output[0]
	end
	return nil
  end
  
  def read_relationship(id, relation, direction)
    LogTime.info("Reading relation: " + relation.to_s)
	relationship_name = relation.relation_name
    if direction == :outgoing
	  other_node_label = relation.target_label
	  match_string = "(primary:#{primary_label})-[r:#{relationship_name}]->(other:#{other_node_label})"
	  return_array = relation.target_number == :many #If this relationship is x-to-many, return an array.
	else
	  other_node_label = relation.source_label
	  match_string = "(other:#{other_node_label})-[r:#{relationship_name}]->(primary:#{primary_label})"
	  return_array = relation.source_number == :many #If this relationship is many-to-x, return an array.
	end
	
	LogTime.info("return_array = " + return_array.to_s)
	
	other_node_model = GraphModel.instance.nodes[other_node_label]
	  
    output = CypherTools.execute_query_into_hash_array("
	  START primary=node({id})
	  MATCH #{match_string}
	  RETURN
	  other.CreatedDate,
	  other.ModifiedDate,
	  " + other_node_model.property_string("other") + relation.property_string("r"),
	  { :id => id },
	  nil)
	  
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
  	  	return { Success: false, Message: "Cannot delete a " + @primary_label.to_s + " that has " +
  	      relation.name_to_source.to_s + "." }
  	  end
  	end
  	model.incoming.each do |relation|
  	  if relations_block_deletion(id, relation, :incoming)
  	  	return { Success: false, Message: "Cannot delete a " + @primary_label.to_s + " that has " +
  	      relation.name_to_target.to_s + "." }
  	  end
  	end
    return { Success: true }
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

    return { Success: true }
  end

  def delete(params, cas_user)
  	if params.has_key?(:id)
  	  identifier = params[:id]
  	  identifier_is_id = true
  	else
  	  identifier = params[:unique_property]
  	  identifier_is_id = false
  	end

    tx = CypherTools.start_transaction

  	#Since we will probably have to delete a bunch of relationships too, we go ahead and
  	#retrieve the node Id first.
  	if identifier_is_id
  	  id = CypherTools.execute_query_returning_scalar("
  	  	START n=node({identifier})
        MATCH (n:#{primary_label})
        RETURN Id(n)
  	  	", { :identifier => identifier.to_i }, tx
  	  )
  	  if id == nil
  	  	return { Success: false, Message: "Could not find #{primary_label} with Id = " + 
  	  	  identifier.to_s + "." }
  	  end
  	else
  	  node_model = GraphModel.instance.nodes[@primary_label]
  	  id = CypherTools.execute_query_returning_scalar("
        MATCH (n:#{primary_label} { " + node_model.unique_property + ": {unique_property} })
        RETURN Id(n)
  	  	", { :unique_property => identifier }, tx
  	  )
  	  if id == nil
  	  	return { Success: false, Message: "Could not find #{primary_label} with " + 
  	  	  node_model.unique_property + " = \"" + identifier + "\"." }
  	  end
  	end

    validate_result = validate_delete(id)
    if !validate_result[:Success]
      return validate_result
    end

	begin
      result = delete_with_transaction(id, tx)
	  if result[:Success]
	    CypherTools.commit_transaction(tx)
	  else
	    CypherTools.rollback_transaction(tx)
	  end
    rescue Exception => e
	  CypherTools.rollback_transaction(tx)
	  raise(e)
	end

	if result[:Success]
	  search_result = ElasticSearchIO.instance.delete_node(@primary_label, id)
	  if !search_result[:Success]
	  	result[:Searchable] = false
	  	result[:SearchableMessage] = search_result[:Message]
	  else
	  	result[:Searchable] = true
	  end
	end
	return result
  end
end
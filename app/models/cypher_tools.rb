require 'neography'

class CypherTools
  @@neo = Neography::Rest.new
  
  def self.start_transaction()
    LogTime.info("Starting transaction.")
    output = @@neo.begin_transaction
	LogTime.info("Started: " + output["commit"].to_s)
	return output
  end
  
  def self.commit_transaction(transaction)
    LogTime.info("Committing transaction: " + transaction["commit"].to_s)
    output = @@neo.commit_transaction(transaction)
	if output["errors"].length > 0
	  LogTime.info("Commit failed. Raising error.")
	  raise output["errors"][0]["message"]
	end
	LogTime.info("Commit successful.")
	return output
  end
  
  def self.rollback_transaction(transaction)
    LogTime.info("Rolling back transaction: " + transaction["commit"].to_s)
    return @@neo.rollback_transaction(transaction)
  end
  
  def self.execute_query(query_string, params, transaction)
    #If we are not given a transaction, we'll create one and close it when we finish.
    tx = transaction
    if transaction == nil
	  tx = start_transaction
	end
	
	LogTime.info("Adding query to transaction: " + query_string)
	LogTime.info("Parameters: " + params.to_s)
	results = @@neo.in_transaction(tx, [query_string, params])
	LogTime.info("Results: " + results.to_s)

	if results.has_key?("errors") && results["errors"].length > 0
	  error = results["errors"][0]
	  if error["code"]=="Neo.ClientError.Statement.EntityNotFound"
	  	raise "One of the ids given was invalid."
	  else
	  	if results["errors"][0].has_key?("message") && results["errors"][0]["message"] != nil
	      raise(results["errors"][0]["message"])
	    else
	      raise("Unknown Neo4j error (no message returned). Please review logs.")
	    end
	  end
	end
	
	if transaction == nil
	  commit_transaction(tx)
	end
	
	return results["results"][0]
  end
  
  # For some reason, neography returns Cypher output in a weird quasi-tabular format.
  # This method converts it into a nice clean array of hashes.
  def self.execute_query_into_hash_array(query_string, params, transaction)
    query_result = execute_query(query_string, params, transaction)
    output = []
	
	query_result["data"].each do |record|
	  this_record = {}
	  query_result["columns"].each_with_index do |column, index|
	    column_name = column.split(".").last
	    this_record[column_name] = record["row"][index]
	  end
	  output << this_record
	end
	
	return output
  end
  
  #And this one just gets a single output value and returns it.
  def self.execute_query_returning_scalar(query_string, params, transaction)
    query_result = execute_query(query_string, params, transaction)
	if query_result.has_key?("data") && query_result["data"].length > 0 &&
	  query_result["data"][0].has_key?("row") && query_result["data"][0]["row"].length > 0
	  return query_result["data"][0]["row"][0]
	else
	  return nil
	end
  end
  
  def self.validate_id_and_label(id, label)
  	LogTime.info("Validating id #{id} for label #{label}.")
    query_result = @@neo.execute_query("
	
	START n=node({id})
	MATCH (n:" + label.to_s + ")
	RETURN Id(n)
	
	", { "id" => id })

	return (query_result["data"].length > 0)
  end
end
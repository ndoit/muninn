require 'neography'

class Terms
  def self.write(package)
	@neo = Neography::Rest.new
	@id = nil
	
	@term = package["Term"]
	
	if package.has_key?("Id")
	  @id = package["Id"]
	  if @term != nil
	    if !@term.has_key?("Name") || @term["Name"] == ""
	      return { message: "Cannot set term name to blank value.", Term: @term, success: false }
		end
		update_term(@id, @term, @neo)
	  end
	else
	  if @term != nil
	    @id = create_term(@term, @neo)
	    if @id == nil
	      return { message: "Term already exists.", TermName: @term["Name"], success: false }
	    end
	  else
	    return { message: "Term object missing from create request.", success: false }
	  end
	end
	
	if package.has_key?("Stakeholders")
	  write_stakeholders(@id, package["Stakeholders"], @neo)
	end
  
	return { Id: @id, success: true }
  end
  
  def self.read(name)
	@neo = Neography::Rest.new
    @term = read_term(name, @neo)
	@id = @term["Id"]
	
	@stakeholders = read_stakeholders(@id, @neo)
	
	return {
	  :Term => @term,
	  :Stakeholders => @stakeholders
	}
  end
  
  end
  
  def self.read_term(name)
    return CypherTools.hashify_cypher_response(neo.execute_query("
	
	MATCH (term:Term)
	WHERE term.Name = {name}
	RETURN
	  term.Name,
	  ID(term) AS Id,
	  term.Definition,
	  term.PossibleValues,
	  term.Notes,
	  term.created_date
	
	", "name" => name))[0]
  end
  
  def self.read_stakeholders(id, neo)
  	return CypherTools.hashify_cypher_response(neo.execute_query("
	
	START term=node({id})
	MATCH (steward:Steward)-[r:HAS_STAKE_IN]->(term)
	RETURN
	  steward.Name,
	  steward.Id,
	  r.Stake
	
	", "id" => id))
  end
 
  def self.create_term(term, neo)
    @now = Time.now.utc
	
	#First, create the actual term node. Note that we do not include any data here.
	#This will be a placeholder until the term is published.
    @create_result = CypherTools.hashify_cypher_response(neo.execute_query("
	
	MERGE (term:Term { Name: {name} })
	ON CREATE SET
	  term.IsPublished = false,
	  term.created_date = {now},
	  term.modified_date = {now}
	RETURN
	  term.created_date = {now} AS CreatedNew,
	  Id(term) AS Id
	
	",
	"name" => term["Name"],
	"now" => @now
	))[0]
	
	if !@create_result["CreatedNew"]
	  #A term with this name already exists.
	  return nil
	end
	
	#Now, create the proposed term.
	neo.execute_query("
	
	START term=node({id})
	MERGE term-[:HAS_PROPOSAL]->(proposedTerm:ProposedTerm)
	ON CREATE SET
	  proposedTerm.Name = {name},
	  proposedTerm.Definition = {definition},
	  proposedTerm.PossibleValues = {possible_values},
	  proposedTerm.Notes = {notes},
	  proposedTerm.created_date = {now},
	  proposedTerm.modified_date = {now}
	
	",
	"id" => @create_result["Id"],
	"name" => term["Name"],
	"definition" => term.has_key?("Definition") ? term["Definition"] : "",
	"possible_values" => term.has_key?("PossibleValues") ? term["PossibleValues"] : "",
	"notes" => term.has_key?("Notes") ? term["Notes"] : "",
	"now" => @now
	)
	
	return @create_result["Id"]
  end
  
  def self.update_term(id, term, neo)
    neo.execute_query("
	
	START term=node({id})
	MERGE term-[:HAS_PROPOSAL]->(proposedTerm:ProposedTerm)
	ON CREATE SET
	  proposedTerm.Name = {name},
	  proposedTerm.Definition = {definition},
	  proposedTerm.PossibleValues = {possible_values},
	  proposedTerm.Notes = {notes},
	  proposedTerm.created_date = {now},
	  proposedTerm.modified_date = {now}
	ON MATCH SET
	  proposedTerm.Name = {name},
	  proposedTerm.Definition = {definition},
	  proposedTerm.PossibleValues = {possible_values},
	  proposedTerm.Notes = {notes},
	  proposedTerm.modified_date = {now}
	  
	  ",
	"id" => id,
	"name" => term["Name"],
	"definition" => term.has_key?("Definition") ? term["Definition"] : "",
	"possible_values" => term.has_key?("PossibleValues") ? term["PossibleValues"] : "",
	"notes" => term.has_key?("Notes") ? term["Notes"] : "",
	"now" => Time.now.utc
	)
  end
  
  def self.write_stakeholders(id, stakeholders, neo)
    @tx = neo.begin_transaction
	neo.in_transaction(@tx, ["
	
	START term=node({id})
	MATCH (steward:Steward)-[r:HAS_STAKE_IN]->(term)
	DELETE r
	
	", { :id => id }
	])
	
	stakeholders.each do |stakeholder|
	  neo.in_transaction(@tx, ["
	  
	  START term=node({id}), steward=node({stakeholder_id})
	  CREATE (steward)-[r:HAS_STAKE_IN {Stake: {stake}}]->(term)
	  
	  ", { :id => id, :stakeholder_id => stakeholder["Id"], :stake => stakeholder["Stake"] }
	  ])
	end
	
	neo.commit_transaction(@tx)
    
  end
end

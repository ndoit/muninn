class TermRepository < ModelRepository
  def initialize
  	super(:term)
  end

  def read(params, cas_user)
    if params.has_key?(:version_number)
      version_number = params[:version_number].to_i
    else
      version_number = 0
    end

    output = super(params, cas_user)
    if version_number==0 || !output[:success]
      return output
    end
    history_result = history(output[:term]["id"])
    if !history_result[:success]
      return history_result
    end
    if version_number > history_result[:OldVersions].length
      return { success: false, message: "Version not found: " + version_number.to_s }
    end
    i = 0
    model = GraphModel.instance.nodes[:term]
    while i < version_number do
      old_version = history_result[:OldVersions][i]
      model.properties.each do |property|
        if old_version.has_key?(property)
          output[:term][property] = old_version[property]
        end
      end
      output[:term]["modified_date"] = old_version["ChangedDate"]
      i = i+1
    end
    return output
  end

  def history(id, cas_user)
    history_list = CypherTools.execute_query_into_hash_array("
      START term=node({id})
      MATCH (term:term)-[*]->(changedFrom:termHistory)
      RETURN changedFrom
      ", { :id => id }, nil)
    output = []
    history_list.each do |history_node|
      output_node = history_node["changedFrom"]
      if(output_node.has_key?("ChangedDate"))
        output_node["ChangedDate"] = Date.parse(output_node["ChangedDate"])
      else
        output_node["ChangedDate"] = Date.parse("1900/1/1")
      end
      output << output_node
    end
    output.sort_by { |x| x["ChangedDate"] }

    return { success: true, OldVersions: output }
  end
end
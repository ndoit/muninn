require "elasticsearch_io.rb"

class BulkLoader
  def wipe
    tx = CypherTools.start_transaction
    result = nil
    begin
      CypherTools.execute_query("
        START n=node(*)
        MATCH (n)-[r]->(m)
        DELETE r 
      ", {}, tx)
      CypherTools.execute_query("
        START n=node(*)
        DELETE n
      ", {}, tx)
      CypherTools.commit_transaction(tx)
    rescue Exception => e
      CypherTools.rollback_transaction(tx)
      raise(e)
    end

    result = { Success: true }

    search_result = ElasticSearchIO.instance.rebuild_search_index
    if !search_result[:Success]
      result[:Searchable] = false
      result[:SearchableMessage] = search_result[:Message]
    else
      result[:Searchable] = true
    end

    return result
  end

  def export
    export_result = []

    GraphModel.instance.nodes.values.each do |node_model|
      all_nodes = CypherTools.execute_query_into_hash_array("
        START n=node(*)
        MATCH (n:#{node_model.label.to_s})
        RETURN
          Id(n) AS Id,
          n.#{node_model.unique_property} AS UniqueProperty
        ",{},nil)
      all_nodes.each do |node|
        exported_node = export_node(node_model, node["Id"])
        if exported_node == nil
          return { Success: false, Message: "Unable to read #{node_model.label.to_s} Id=" + node["Id"].to_s }
        end
        export_result << {
          "target_uri" => node_model.label.to_s.downcase.pluralize + "/" + node["UniqueProperty"],
          "content" => exported_node
        }
      end
    end

    return {
      Success: true,
      ExportResult: export_result
    }
  end

  def export_node(node_model, id)
    repository = ModelRepository.new(node_model.label.to_sym)
    read_result = repository.read({ :id => id}, nil)
    if !read_result[:Success]
      LogTime.info(read_result[:Message])
      return nil
    end

    LogTime.info(read_result.to_s)
    LogTime.info(node_model.label.to_s)

    output = {}

    primary_node = read_result[node_model.label.to_sym].clone
    primary_node.delete("CreatedDate")
    primary_node.delete("ModifiedDate")
    primary_node.delete("Id")

    output[node_model.label.to_sym] = primary_node

    relations = []

    node_model.outgoing.each do |relationship|
      relations << {
        :property_name => relationship.name_to_source,
        :is_array => (relationship.target_number == :many),
        :other_node_model => GraphModel.instance.nodes[relationship.target_label],
        :properties => relationship.properties
      }
    end

    node_model.incoming.each do |relationship|
      relations << {
        :property_name => relationship.name_to_target,
        :is_array => (relationship.source_number == :many),
        :other_node_model => GraphModel.instance.nodes[relationship.source_label],
        :properties => relationship.properties
      }
    end

    relations.each do |relation|
      if relation[:is_array]
        relation_data = []
        read_result[relation[:property_name]].each do |other_node|
          current_item = {
            relation[:other_node_model].unique_property.to_s =>
            other_node[relation[:other_node_model].unique_property.to_s]
          }
          relation[:properties].each do |relation_property|
            current_item[relation_property] = other_node[relation_property]
          end
          relation_data << current_item
        end
      else
        other_node = read_result[relation[:property_name]]
        relation_data = {
            relation[:other_node_model].unique_property.to_s =>
            other_node[relation[:other_node_model].unique_property.to_s]
          }
        relation[:properties].each do |relation_property|
          relation_data[relation_property] = other_node[relation_property]
        end
      end
      output[relation[:property_name]] = relation_data
    end

    return output
  end

  def load(json_body)
    node_states = []

  	json_body.each do |element|
      node_states << DesiredNodeState.new(element)
    end

    duplicate_uris = find_duplicate_uris(node_states)
    if duplicate_uris.length > 0
      joined_duplicates = duplicate_uris.join(", ")
      return { Success: false, Message: "Duplicate target_uris found: #{joined_duplicates}" }
    end

    missing_dependencies = find_missing_dependencies(node_states)
    if missing_dependencies.length > 0
      joined_missing_dependencies = missing_dependencies.join(", ")
      return { Success: false, Message: "Missing dependencies found: #{joined_missing_dependencies}" }
    end

    error_messages = ""

    node_states.each do |node_state|
      output = write_primary_node_content(node_state)
      if !output[:Success]
        error_messages = error_messages + "\n**Failed to write node data for #{node_state.target_uri}: " + output[:Message]
      end
    end

    node_states.each do |node_state|
      output = write_other_content(node_state)
      if !output[:Success]
        error_messages = error_messages + "\n**Failed to write relationships for #{node_state.target_uri}: " + output[:Message]
      end
    end

    if error_messages.length > 0
      result = {
      	Success: false, Message: "Some target_uris were not successfully updated:\n\n#{error_messages}"
      }
    else
      result = {
      	Success: true
      }
    end

    #Unlike standard CRUD operations, bulk load is not guaranteed atomicity, so we may well end up with
    #a partially successful load. The search index should always match what's in the database. Hence, we
    #don't check for success on the bulk load; we rebuild the search index regardless.
    search_result = ElasticSearchIO.instance.rebuild_search_index
    if !search_result[:Success]
      result[:Searchable] = false
      result[:SearchableMessage] = search_result[:Message]
    else
      result[:Searchable] = true
    end

    return result
  end

  def find_duplicate_uris(node_states)
  	target_uris = []
  	duplicate_uris = []
  	node_states.each do |node_state|
  	  if target_uris.include?(node_state.target_uri)
  	    duplicate_uris << node_state.target_uri
  	  else
  	  	target_uris << node_state.target_uri
  	  end
  	end
  	return duplicate_uris
  end

  def find_missing_dependencies(node_states)
    all_uri_dependencies = []
    missing_dependencies = []
    node_states.each do |node_state|
      node_state.uri_dependencies.each do |uri_dependency|
      	if !all_uri_dependencies.include?(uri_dependency)
      	  all_uri_dependencies << uri_dependency
      	end
      end
    end

    all_uri_dependencies.each do |uri_dependency|
      if dependency_is_missing(uri_dependency, node_states)
      	missing_dependencies << uri_dependency
      end
    end

    return missing_dependencies
  end

  def dependency_is_missing(uri_dependency, node_states)
    node_states.each do |node_state|
      if node_state.target_uri == uri_dependency
      	LogTime.info("Dependency matches node state: #{uri_dependency}")
        return (node_state.action == :delete) #If we are deleting this dependency, it's going to be missing!
      end
    end
    split_result = DesiredNodeState.split_uri(uri_dependency)
    repository = ModelRepository.new(split_result[:label].to_sym)
    output = repository.read({ :unique_property => split_result[:unique_property] }, nil)
    return !output[:Success]
  end

  def write_primary_node_content(node_state)
    repository = ModelRepository.new(node_state.primary_label.to_sym)
    read_result = repository.read({ :unique_property => node_state.unique_property }, nil)
    node_exists = read_result[:Success]

  	if node_state.action == :delete
  	  if !node_exists
  	  	#Nothing to do here.
  	  	LogTime.info "Delete requested, node doesn't exist."
  	  	return { Success: true }
  	  end
  	  content = { :unique_property => node_state.unique_property }
  	  	LogTime.info "Attempting delete."
  	  return repository.delete(content, nil)
  	end

  	if node_state.primary_node_content == nil
  	  #No primary node update is required.
  	  return { Success: true }
  	end

    content = node_state.primary_node_content.clone
    content[:unique_property] = node_state.unique_property
  	LogTime.info(node_exists ? "Attempting update: #{node_state.primary_node_content.to_s}." :
  		"Attempting create: #{node_state.primary_node_content.to_s}.")
    return repository.write(content, !node_exists, nil)
  end

  def write_other_content(node_state)
  	if node_state.action == :delete
  	  #If this node has been deleted, we obviously don't have anything to do here.
  	  return { Success: true }
  	end
  	if node_state.other_content == nil
  	  #No relationship updates are required.
  	  return { Success: true }
  	end
    repository = ModelRepository.new(node_state.primary_label.to_sym)
    content = node_state.other_content.clone
    content[:unique_property] = node_state.unique_property
    LogTime.info("Attempting update: #{node_state.other_content.to_s}")
    return repository.write(content, false, nil)
  end
end

class DesiredNodeState
  attr_accessor :target_uri, :primary_label, :unique_property, :primary_node_model
  attr_accessor :action, :primary_node_content, :other_content
  attr_accessor :uri_dependencies

  def self.split_uri(uri)
    first_slash = uri.index('/')
    label = uri[0,first_slash].singularize.capitalize
    unique_property = uri[first_slash+1,uri.length-1]
    return { :label => label, :unique_property => unique_property }
  end

  def initialize(raw_json)
    LogTime.info "Initializing DesiredNodeState from: #{raw_json.to_s}"
    initialize_uri_and_label(raw_json)
    initialize_action_and_content(raw_json)
    initialize_uri_dependencies
  end

  def initialize_uri_and_label(raw_json)
    @target_uri = raw_json["target_uri"]
    split_uri = DesiredNodeState.split_uri(@target_uri)
    @primary_label = split_uri[:label]
    @unique_property = split_uri[:unique_property]
    @primary_node_model = GraphModel.instance.nodes[@primary_label.to_sym]
  end

  #initialize_uri_and_label must be called before this.
  def initialize_action_and_content(raw_json)
    if !(raw_json.has_key?("content"))
  	  @action = :delete
  	  @primary_node_content = nil
  	  @other_content = nil
    else
  	  @action = :upsert
      content = raw_json["content"]
      if content.has_key?(@primary_label)
        @primary_node_content = { @primary_label.to_sym => content[@primary_label].clone }
      else
  	    @primary_node_content = nil
      end
      @other_content = content.clone
      @other_content.delete(@primary_label)
    end
  end

  #initialize_uri_and_label and initialize_action_and_content must both be called before this.
  def initialize_uri_dependencies
    @uri_dependencies = []
    relations = []

    if @other_content == nil
      return
    end

    @primary_node_model.outgoing.each do |relationship|
  	  relations << {
  	    :property_name => relationship.name_to_source,
  	    :is_array => (relationship.target_number == :many),
  	    :other_node_label => relationship.target_label
  	  }
    end

    @primary_node_model.incoming.each do |relationship|
  	  relations << {
  	    :property_name => relationship.name_to_target,
  	    :is_array => (relationship.source_number == :many),
  	    :other_node_label => relationship.source_label
  	  }
    end

    LogTime.info("Other Content: #{other_content.to_s}")
    relations.each do |relation|
      if @other_content.has_key?(relation[:property_name])
        if relation[:is_array]
      	  other_nodes = other_content[relation[:property_name]]
          if other_nodes == nil
            other_nodes = []
          end
        else
      	  other_nodes = [ other_content[relation[:property_name]] ]
        end
        other_node_model = GraphModel.instance.nodes[relation[:other_node_label]]
        other_nodes.each do |other_node|
          @uri_dependencies << relation[:other_node_label].to_s.downcase.pluralize + "/" +
            other_node[other_node_model.unique_property]
        end
      end
    end
  end
end
require "singleton"

class NodeModel
  attr_accessor :label, :properties, :sensitive_properties, :unique_property
  attr_accessor :outgoing, :incoming

  def parameters_contain_property(parameters, property)
    if parameters.has_key?(:properties) && parameters[:properties].include?(property)
      return true
    end
    if parameters.has_key?(:sensitive_properties) && parameters[:sensitive_properties].include?(property)
      return true
    end
    if parameters.has_key?(:unique_property) && parameters[:unique_property] == property
      return true
    end
    return false
  end
  
  def initialize(parameters)
  	#We do not allow properties to be named Id or UniqueProperty, as we use those internally.
  	if parameters_contain_property(parameters, "id")
  	  raise "Invalid property name: \"id\""
  	end
  	if parameters_contain_property(parameters, "unique_property")
  	  raise "Invalid property name: \"unique_property\""
  	end
    @label = parameters[:label]
	@properties = parameters[:properties]
	@sensitive_properties = parameters[:sensitive_properties]
	@unique_property = parameters[:unique_property]
	@outgoing = []
	@incoming = []
  end
  
  def property_string(node_reference, include_sensitive = false)
    output = "ID(#{node_reference}) AS Id"
	@properties.each do |property|
	  output = output + ", #{node_reference}.#{property}"
	end
	if include_sensitive
	  @sensitive_properties.each do |property|
	    output = output + ", #{node_reference}.#{property}"
	  end
	end
	return output
  end
  
  def property_write_string(node_reference, include_sensitive = false)
    output = nil
	if node_reference == nil || node_reference == ""
      node_reference = ""
    else
      node_reference = node_reference + "."
    end
	@properties.each do |property|
	  if output == nil
	    output = "#{node_reference}#{property} = { #{property} }"
	  else
	    output = output + ", #{node_reference}#{property} = { #{property} }"
      end
	end
	if include_sensitive
	  @sensitive_properties.each do |property|
	    output = output + ", #{node_reference}.#{property}"
	  end
	end
	return output
  end
end

class RelationshipModel
  attr_accessor :source_label, :relation_name, :target_label
  attr_accessor :properties, :source_number, :target_number, :name_to_source, :name_to_target, :immutable
  
  def initialize(parameters)
	@source_label = parameters[:source_label]
    @relation_name = parameters[:relation_name]
	@target_label = parameters[:target_label]
	@properties = parameters.has_key?(:properties) ? parameters[:properties] : []
	@source_number = parameters.has_key?(:source_number) ? parameters[:source_number] : :many
	@target_number = parameters.has_key?(:target_number) ? parameters[:target_number] : :many
	if parameters.has_key?(:name_to_source)
	  @name_to_source = parameters[:name_to_source]
	else
	  if @target_number == :many
	    @name_to_source = @target_label.to_s.pluralize
	  else
	    @name_to_source = @target_label
	  end
	end
	if parameters.has_key?(:name_to_target)
	  @name_to_target = parameters[:name_to_target]
	else
	  if @source_number == :many
	    @name_to_target = @source_label.to_s.pluralize
	  else
	    @name_to_target = @source_label
	  end
	end
	@immutable = parameters.has_key?(:immutable) ? parameters[:immutable] : false
  end
  
  def property_string(relationship_reference, show_secure = false)
    output = ""
	@properties.each do |property|
	  output = output + ", #{relationship_reference}.#{property}"
	end
	if show_secure
	  @sensitive_properties.each do |property|
	    output = output + ", #{relationship_reference}.#{property}"
	  end
	end
	return output
  end
  
  def property_write_string(relationship_reference)
    if @properties.length == 0
	  return ""
	end
	if relationship_reference == nil || relationship_reference == ""
      relationship_reference = ""
    else
      relationship_reference = relationship_reference + "."
    end
    output = nil
	@properties.each do |property|
	    if output == nil
	      output = "{ #{relationship_reference}#{property}: { #{property} }"
	    else
	      output = output + ", #{relationship_reference}#{property}: { #{property} }"
        end
	end
	output = output + " }"
	return output
  end
end

class GraphModel
  include Singleton
  attr_accessor :nodes, :relationships

  def initialize
  	LogTime.info("Initializing nodes and relationships.")
    @nodes = {}
	@relationships = []
  	LogTime.info("Defining model.")
	define_model
  	LogTime.info("Determining relations.")
	determine_relations
  end

  def determine_relations
    @relationships.each do |relationship|
      @nodes[relationship.source_label].outgoing << relationship
      @nodes[relationship.target_label].incoming << relationship
    end
  end

  def define_model
    @nodes[:Term] = NodeModel.new({
      :label => "Term",
	  :properties => [ "Name", "Definition", "PossibleValues", "Notes", "DataSensitivity", "DataAvailability" ],
	  :sensitive_properties => [ "Source" ],
	  :unique_property => "Name"
    })
	  
    @nodes[:Office] = NodeModel.new({
	  :label => "Office",
	  :properties => [ "Name" ],
	  :unique_property => "Name"
    })
	  
    @nodes[:Person] = NodeModel.new({
	  :label => "Person",
	  :properties => [ "NetId", "FirstName", "LastName" ],
	  :unique_property => "NetId"
    })
	  
    @nodes[:Report] = NodeModel.new({
	  :label => "Report",
	  :properties => [ "Name", "Uri", "Description" ],
	  :unique_property => "Name"
    })
  
    @relationships << RelationshipModel.new({
	  :source_label => :Office,
	  :relation_name => "HAS_STAKE_IN",
	  :target_label => :Term,
	  :properties => [ "Stake" ],
	  :name_to_source => "Stakes",
	  :name_to_target => "Stakeholders"
    })
	  
    @relationships << RelationshipModel.new({
	  :source_label => :Report,
	  :relation_name => "CONTAINS",
	  :target_label => :Term
    })
	  
    @relationships << RelationshipModel.new({
	  :source_label => :Person,
	  :relation_name => "REPRESENTS_FOR",
	  :target_label => :Office
    })
  end
end
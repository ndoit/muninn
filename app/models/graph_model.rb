require "singleton"

class NodeModel
  attr_accessor :label, :properties, :unique_property
  attr_accessor :outgoing, :incoming

  def has_relation_named?(str)
    outgoing.each do |rel|
      if rel.name_to_source == str
        return true
      end
    end
    incoming.each do |rel|
      if rel.name_to_target == str
        return true
      end
    end
    return false
  end

  def parameters_contain_property(parameters, property)
    if parameters.has_key?(:properties) && parameters[:properties].include?(property)
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
  	@unique_property = parameters[:unique_property]
  	@outgoing = []
  	@incoming = []
    #@is_secured = false
  end

  def property_string(node_reference)
    output = "ID(#{node_reference}) AS id"
  	@properties.each do |property|
  	  output = output + ", #{node_reference}.#{property}"
  	end
  	return output
  end

  def property_write_string(node_reference, node_contents = nil)
    output = nil
  	if node_reference == nil || node_reference == ""
        node_reference = ""
      else
        node_reference = node_reference + "."
      end
  	@properties.each do |property|
      if node_contents == nil || node_contents.has_key?(property)
    	  if output == nil
    	    output = "#{node_reference}#{property} = { #{property} }"
    	  else
    	    output = output + ", #{node_reference}#{property} = { #{property} }"
        end
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
      #if relationship.relation_name == "REQUIRES" && relationship.target_label == :security_role
        # Any node which has a REQUIRES relationship to the security_role node type is
        # considered "secured," meaning we check for access when you try to read it.
        #LogTime.info("REQUIRES relation discovered for " + relationship.source_label.to_s + ", marking node as secured.")
        #@nodes[relationship.source_label].is_secured = true
      #end
    end
  end

  def define_model
  	yaml_data = YAML.load_file("#{Rails.root}/config/schema.yml")
  	node_labels = yaml_data["nodes"].keys
  	node_labels.each do |label|
  	  unique_property = yaml_data["nodes"][label]["unique_property"]
  	  if yaml_data["nodes"][label].has_key?("other_properties")
  	    properties = yaml_data["nodes"][label]["other_properties"]
  	    properties << unique_property
  	  else
  	  	properties = [ unique_property ]
  	  end
  	  @nodes[label.to_sym] = NodeModel.new({
  	    :label => label,
  	    :properties => properties,
  	    :unique_property => unique_property
  	  })
  	end

  	relationship_names = yaml_data["relationships"].keys
  	relationship_names.each do |name|
      if yaml_data["relationships"][name]["source_label"].kind_of?(Array)
        source_labels = yaml_data["relationships"][name]["source_label"]
      else
        source_labels = [ yaml_data["relationships"][name]["source_label"] ]
      end
      if yaml_data["relationships"][name]["target_label"].kind_of?(Array)
        target_labels = yaml_data["relationships"][name]["target_label"]
      else
        target_labels = [ yaml_data["relationships"][name]["target_label"] ]
      end

      source_labels.each do |source_label|
        target_labels.each do |target_label|
      	  parameters = {
      	    :relation_name => name,
      	    :source_label => source_label.to_sym,
      	    :target_label => target_label.to_sym
      	  }
      	  optional_parameters = [
            { :name => "properties", :is_symbol => false },
            { :name => "source_number", :is_symbol => true },
            { :name => "target_number", :is_symbol => true },
            { :name => "name_to_source", :is_symbol => false },
            { :name => "name_to_target", :is_symbol => false }
          ]
      	  optional_parameters.each do |optional_parameter|
            if yaml_data["relationships"][name].has_key?(optional_parameter[:name])
              if optional_parameter[:is_symbol]
                parameters[optional_parameter[:name].to_sym] = yaml_data["relationships"][name][optional_parameter[:name]].to_sym
              else
                parameters[optional_parameter[:name].to_sym] = yaml_data["relationships"][name][optional_parameter[:name]]
              end
            end
          end
          @relationships << RelationshipModel.new(parameters)
        end
      end
  	end
  end
end

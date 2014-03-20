require "singleton"
require "net/http"
require "json"
#require "typhoeus" #recommended in elasticsearch gem docs to improve performance
require "elasticsearch"

#docs: http://rubydoc.info/gems/elasticsearch-api/

class ElasticSearchIO
  include Singleton

  def initialize
  end
  
  def update_nodes_with_data(label, data)
    LogTime.info("Loading data: " + data.to_s)
    data.each do |node|
      id = node["id"]
      LogTime.info("Updating node: " + id.to_s)

      uri = URI.parse("http://localhost:9200/node/#{label}/#{id}")
      request = Net::HTTP::Post.new(uri.path)
      request.content_type = 'application/json'
      request.body = node.to_json

      LogTime.info("Request created.")
      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(request)
      end

      LogTime.info("Response received.")
      if !response.kind_of? Net::HTTPSuccess
        return { success: false, message: response.message }
      end
    end
    return { success: true }
  end

  def rebuild_search_index
    GraphModel.instance.nodes.values.each do |node_model|
      delete_result = delete_all_nodes(node_model.label)
      if !delete_result[:success]
        return delete_result
      end
      update_result = update_all_nodes(node_model.label)
      if !update_result[:success]
        return update_result
      end
    end

    return { success: true }
  end

  def delete_all_nodes(label)
    LogTime.info("Delete all nodes of type: #{label}")

    uri = URI.parse("http://localhost:9200/node/#{label}/")
    request = Net::HTTP::Delete.new(uri.path)

    LogTime.info("Request created: #{uri.path}")
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    LogTime.info("Response received: " + response.to_s)
    if response.kind_of? Net::HTTPSuccess
      return { success: true }
    elsif response.code == "404"
      return { success: true } #If we got a 404, that means there weren't any of these nodes anyway.
    else
      return { success: false, message: response.message }
    end
  end

  def delete_node(label, id)
    LogTime.info("Delete node " + id.to_s + " of type: #{label}")

    uri = URI.parse("http://localhost:9200/node/#{label}/" + id.to_s)
    request = Net::HTTP::Delete.new(uri.path)

    LogTime.info("Request created.")
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    LogTime.info("Response received.")
    if response.kind_of? Net::HTTPSuccess
      return { success: true }
    else
      return { success: false, message: response.message }
    end
  end

  def update_node(label, id)
    LogTime.info("Update node " + id.to_s + " of type: #{label}")

    node_model = GraphModel.instance.nodes[label.to_sym]

    node_data = CypherTools.execute_query_into_hash_array("

    START n=node({id})
    MATCH (n:" + label.to_s + ")
    RETURN
    " + node_model.property_string("n"),
    { :id => id },
    nil)

    LogTime.info("Data retrieved, loading to search engine.")
    return update_nodes_with_data(label, node_data)
  end

  def update_all_nodes(label)
    LogTime.info("Update all nodes of type: #{label}")

    node_model = GraphModel.instance.nodes[label.to_sym]

    node_data = CypherTools.execute_query_into_hash_array("

    MATCH (n:" + label.to_s + ")
    RETURN
    " + node_model.property_string("n"),
    { },
    nil)

    LogTime.info("Data retrieved, loading to search engine.")
    return update_nodes_with_data(label, node_data)
  end

  def advanced_search(query_json, label = nil)
    client = Elasticsearch::Client.new log: true
    if query_json == nil
      return { success: false, message: "You must include a query." }
    end
    if label != nil
      output = client.search index: 'node', type: label, body: query_json
    else
      output = client.search index: 'node', body: query_json
    end
    return { success: true, result: output }
  end

  def search(query_string, label = nil)
    if label == nil
      if query_string == nil
        return { success: false, message: "Specify a result type or a search term." }
      else
        uri_string = "/node/_search?q=#{query_string}"
      end
    else
      if query_string == nil
        uri_string = "/node/#{label}/_search"
      else
        uri_string = "/node/#{label}/_search?q=#{query_string}"
      end
    end
    LogTime.info("Querying: " + uri_string)
    response = Net::HTTP.start("localhost", 9200) do |http|
      http.get(uri_string)
    end

    if response.kind_of? Net::HTTPSuccess
      LogTime.info("Response received: " + response.body)
      return { success: true, results: extract_results(response.body) }
    else
      LogTime.info("Response failed.")
      return { success: false, message: response.message }
    end
  end

  def extract_results(search_response)
    response_hash = JSON.parse(search_response)
    if !response_hash.has_key?("hits")
      LogTime.info("No contents.")
      return []
    end
    output = []
    response_hash["hits"]["hits"].each do |hit|
      node = {
        :id => hit["_id"].to_i,
        :type => hit["_type"],
        :score => hit["_score"],
        :data => hit["_source"]
      }
      output << node
    end
    return output
  end
end
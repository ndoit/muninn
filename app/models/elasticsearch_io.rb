require "singleton"
require "net/http"
require "json"
#require "typhoeus" #recommended in elasticsearch gem docs to improve performance
require "elasticsearch"
require "pathname"
require "httparty"

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

      uri = URI.parse("http://localhost:9200/#{label.to_s.pluralize}/#{label}/#{id}")
      request = Net::HTTP::Put.new(uri.path)
      request.content_type = 'application/json'
      request.body = node.to_json

      LogTime.info("Request created with contents: #{node.to_json}.")
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

  def run_initialization_tasks
    init_files = Dir.glob("config/elasticsearch_init/*")
    LogTime.info("Searching config/elasticsearch_init/, #{init_files.length} files found.")
    responses = []
    init_files.each do |file|
      file_hash = JSON.parse(IO.read(file))
      LogTime.info("File #{file} contents: #{file_hash.to_s}")
      LogTime.info("#{file_hash.length} requests to process.")
      request_count = 0
      file_hash.each do |request_json|
        request_count = request_count + 1

        body = request_json["body"].to_json
        headers = { "Content-Type" => "application/json; charset=utf-8" }

        if request_json["verb"] == "GET"
          LogTime.info("Executing GET with body #{body}.")
          response = HTTParty.get("http://localhost:9200/" + request_json["uri"], { body: body, headers: headers  })
        elsif request_json["verb"] == "POST"
          LogTime.info("Executing POST with body #{body}.")
          response = HTTParty.post("http://localhost:9200/" + request_json["uri"], { body: body, headers: headers  })
        elsif request_json["verb"] == "PUT"
          LogTime.info("Executing PUT with body #{body}.")
          response = HTTParty.put("http://localhost:9200/" + request_json["uri"], { body: body, headers: headers  })
        elsif request_json["verb"] == "DELETE"
          LogTime.info("Executing DELETE with body #{body}.")
          response = HTTParty.delete("http://localhost:9200/" + request_json["uri"], { body: body, headers: headers  })
        else
          return { success: false, message: "Unknown HTTP verb: " + request_json["verb"].to_s }
        end
        if response.code != 200
          return { success: false, message: "Request #{request_count} from file #{file} returned code #{response.code}: #{response.body}" }
        else
          LogTime.info("Received 200, successful.")
          responses << response
        end
      end
    end
    return { success: true, responses: responses }
  end

  def wipe_and_initialize
    LogTime.info("Destroying the world.")
    delete_result = HTTParty.delete("http://localhost:9200/_all")
    if delete_result.code != 200
      return { success: false, message: "Delete command failed with code #{delete_result.code}: #{delete_result.body}" }
    end
    LogTime.info("Running initialization tasks.")
    init_result = run_initialization_tasks
    if !init_result[:success]
      return init_result
    end
    return { success: true }
  end

  def rebuild_search_index
    wipe_result = wipe_and_initialize
    if !wipe_result[:success]
      return wipe_result
    end
    GraphModel.instance.nodes.values.each do |node_model|
      LogTime.info("Re-creating search elements of type: #{node_model}")
      update_result = update_all_nodes(node_model.label)
      if !update_result[:success]
        return update_result
      end
    end

    return { success: true }
  end

  def delete_all_nodes(label)
    LogTime.info("Delete all nodes of type: #{label}")

    uri = URI.parse("http://localhost:9200/#{label.to_s.pluralize}/#{label}/")
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

    uri = URI.parse("http://localhost:9200/#{label.to_s.pluralize}/#{label}/" + id.to_s)
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
      output = client.search index: 'terms', type: label, body: query_json #hard coded terms index needs to be paramater.
    else
      output = client.search index: 'terms', body: query_json #hard coded terms index needs to be paramater. 
    end
    return { success: true, result: output }
  end

  def search(query_string, label = nil)
    if label == nil
      if query_string == nil
        return { success: false, message: "Specify a result type or a search term." }
      else
        uri_string = "/#{label.to_s.pluralize}/_search?q=#{query_string}"
      end
    else
      if query_string == nil
        uri_string  = "/#{label.to_s.pluralize}/#{label}/_search?size=9999" #SMM - added to bypass default sixe
      else
        uri_string = "/#{label.to_s.pluralize}/#{label}/_search?q=#{query_string}"
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

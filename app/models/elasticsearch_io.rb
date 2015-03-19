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

  def user_can_see_node(user_obj, node_name, label, allows_access_with)
    LogTime.info("Checking node access: node_name = #{node_name.to_s}, label = #{label.to_s}, allows_access_with = #{allows_access_with.to_s}")
    if SecurityGoon.check_for_full_read(user_obj, label)
      return true
    end
    if allows_access_with != nil
      allows_access_with.each do |role|
        if user_obj["roles"].has_key?(role["name"])
          return true
        end
      end
    end
    if label == "security_role" && user_obj["roles"].has_key?(node_name)
      return true
    end
    if label == "user" && user_obj["net_id"] == node_name
      return true
    end
    return false
  end

  def convert_hit_to_output(hit, user_obj, general_access, do_cleanup)
    data = hit["_source"]
    output_data = {}
    aggregations = {}
    # We have to apply security filters to related nodes as well as the main node.
    data.keys.each do |key|
      if data[key].kind_of?(Array)
        output_items = []
        data[key].each do |item|
          if item.kind_of?(Hash) && item.has_key?("&label")
            model = GraphModel.instance.nodes[item["&label"].to_sym]
            if user_can_see_node(user_obj, item[model.unique_property], item["&label"], item["&allows_access_with"])
              item.delete("&label")
              item.delete("&allows_access_with")
              output_items << item
            end
          else
            output_items << item
          end
        end
        output_data[key] = output_items
      else
        output_data[key] = data[key]
      end
    end

    if do_cleanup
      return {
        "id" => hit["_id"].to_i,
        "type" => hit["_type"],
        "score" => hit["_score"],
        "sort_name" => hit["_source"]["name"],
        "data" => output_data
      }
    else
      hit["_source"] = output_data
      return hit
    end
  end

  def initialize
  end

  def filter_output_by_access(search_result, user_obj, do_cleanup)
    output = []
    general_access = {}
    counts_by_type = {}
    search_result["hits"]["hits"].each do |hit|
      model = GraphModel.instance.nodes[hit["_type"].to_sym]
      if model == nil
        LogTime.info "No model found for type #{hit["_type"].to_s}."
      else
        if user_can_see_node(user_obj, hit["_source"][model.unique_property], hit["_type"], hit["_source"]["allows_access_with"])
          output << convert_hit_to_output(hit, user_obj, general_access, do_cleanup)
          if !counts_by_type.has_key?(hit["_type"])
            counts_by_type[hit["_type"]] = 1
          else
            counts_by_type[hit["_type"]] += 1
          end
        end
      end
    end
    if do_cleanup
      return output
    else
      search_result["hits"]["hits"] = output
      search_result["hits"]["total"] = output.length
      search_result["aggregations"]["type"]["buckets"] = []
      counts_by_type.keys.each do |key|
        search_result["aggregations"]["type"]["buckets"] << { "key" => key, "doc_count" => counts_by_type[key] }
      end
      return search_result
    end
  end

  def update_nodes_with_data(label, data, update_related_nodes = true)
    LogTime.info("Loading data: " + data.to_s)
    data.each do |node|
      id = node["id"]

      node_model = GraphModel.instance.nodes[label.to_sym]

      LogTime.info("Outgoing relations: " + node_model.outgoing.to_s)
      node_model.outgoing.each do |relation|
        target_model = GraphModel.instance.nodes[relation.target_label]
        related_nodes = CypherTools.execute_query_into_hash_array("
          START n=node({id})
          MATCH (n:" + label.to_s + ")-[r:" + relation.relation_name + "]->(other)
          OPTIONAL MATCH (other)-[:ALLOWS_ACCESS_WITH]->(sr:security_role)
          RETURN id(other) AS id, sr.name AS allows_access_with, other." + target_model.unique_property + relation.property_string("r"),
          { :id => id }, nil)
        node[relation.name_to_source] = process_related_nodes(related_nodes, target_model.label)
        if update_related_nodes
          related_nodes.each do |related_node|
            update_node(target_model.label, related_node["id"], false)
          end
        end
      end

      LogTime.info("Incoming relations: " + node_model.incoming.to_s)
      node_model.incoming.each do |relation|
        source_model = GraphModel.instance.nodes[relation.source_label]
        related_nodes = CypherTools.execute_query_into_hash_array("
          START n=node({id})
          MATCH (n:" + label.to_s + ")<-[r:" + relation.relation_name + "]-(other)
          OPTIONAL MATCH (other)-[:ALLOWS_ACCESS_WITH]->(sr:security_role)
          RETURN id(other) AS id, sr.name AS allows_access_with, other." + source_model.unique_property + relation.property_string("r"),
          { :id => id }, nil)
        node[relation.name_to_target] = process_related_nodes(related_nodes, source_model.label)
        if update_related_nodes
          related_nodes.each do |related_node|
            update_node(source_model.label, related_node["id"], false)
          end
        end
      end

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

  def process_related_nodes(related_nodes, label)
    output = []
    output_nodes = {}
    related_nodes.each do |node|
      if output_nodes.has_key?(node["id"])
        if node["&allows_access_with"] != nil
          output_nodes[node["id"]]["&allows_access_with"] << { "name" => node["allows_access_with"] }
        end
      else
        new_node = { "&label" => label }
        LogTime.info node.to_s
        node.keys.each do |key|
          if key=="allows_access_with"
            if node[key] != nil
              new_node["&allows_access_with"] = [ node[key] ]
            else
              new_node["&allows_access_with"] = []
            end
          else
            new_node[key] = node[key]
          end
        end
        output_nodes[node["id"]] = new_node
      end
    end

    output = []
    output_nodes.keys.each do |key|
      output << output_nodes[key]
    end
    return output
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
      update_result = update_all_nodes(node_model.label, false)
      # We don't bother updating related nodes, because everything's going to get rebuilt anyhow.
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

  def delete_node(label, id, update_related_nodes = true)
    LogTime.info("Delete node " + id.to_s + " of type: #{label}")
    uri = URI.parse("http://localhost:9200/#{label.to_s.pluralize}/#{label}/" + id.to_s)

    if update_related_nodes
      LogTime.info("Searching for related nodes.")
      request = Net::HTTP::Get.new(uri.path)
      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(request)
      end
      if !(response.kind_of? Net::HTTPSuccess)
        return { success: false, message: response.message }
      end
      response = JSON.parse(response.body)
      if !response["found"]
        LogTime.info("Failed to find in response: #{response.to_s}")
        return { success: false, message: "Record not found in ElasticSearch." }
      end
      target_obj = response["_source"]
      ids_to_check = {}
      target_obj.keys.each do |key|
        if target_obj[key].is_a?(Array)
          target_obj[key].each do |possibility|
            if possibility.has_key?("id") && possibility.has_key?("&label")
              ids_to_check[possibility["id"]] = possibility["&label"]
            end
          end
        elsif target_obj[key].is_a?(Hash) && target_obj[key].has_key?("id") && target_obj[key].has_key?("&label")
          ids_to_check[target_obj[key]["id"]] = target_obj[key]["&label"]
        end
      end
      ids_to_check.keys.each do |id|
        update_node(ids_to_check[id], id, false)
      end
    end

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

  def update_node(label, id, update_related_nodes = true)
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
    return update_nodes_with_data(label, node_data, update_related_nodes)
  end

  def update_all_nodes(label, update_related_nodes = true)
    LogTime.info("Update all nodes of type: #{label}")

    node_model = GraphModel.instance.nodes[label.to_sym]

    node_data = CypherTools.execute_query_into_hash_array("

    MATCH (n:" + label.to_s + ")
    RETURN
    " + node_model.property_string("n"),
    { },
    nil)

    LogTime.info("Data retrieved, loading to search engine.")
    return update_nodes_with_data(label, node_data, update_related_nodes)
  end


  def advanced_search(query_json, user_obj, index = nil)
    client = Elasticsearch::Client.new log: true
    if query_json == nil
      return { success: false, message: "You must include a query." }
    end
    if index != nil
      output = client.search index: index, type: label, body: query_json #hard coded terms index needs to be paramater. #SMM added index as the node type
    else
      output = client.search  body: query_json #hard coded terms index needs to be paramater. #SMM removed the index as a parameter for common search
    end
    return { success: true, result: filter_output_by_access(output, user_obj, false) }
  end

  def search(query_string, user_obj, label = nil)
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
      return { success: true, results: extract_results(response.body, user_obj) }
    else
      LogTime.info("Response failed.")
      return { success: false, message: response.message }
    end
  end

  def extract_results(search_response, user_obj)
    response_hash = JSON.parse(search_response)
    if !response_hash.has_key?("hits")
      LogTime.info("No contents.")
      return []
    end
    return filter_output_by_access(response_hash, user_obj, true)
  end
end

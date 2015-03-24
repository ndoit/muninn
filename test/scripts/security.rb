# This script should be run on localhost in a dev env.
# It tests that security works.
# WARNING! Script starts by blowing away the graph. Don't run it if you care about keeping your data.
# NEVER EVER run in prod.

require "httparty"

class TestScript
  include HTTParty
  base_uri "http://localhost:3000"
end

def delete_everything
  response = TestScript.delete("/bulk/NoSeriouslyIMeanIt?admin=true")
  if response.code == 200
    puts "SUCCESS: Bulk delete."
    return 0
  else
    puts "FAILED: Bulk delete. #{JSON.parse(response.body)["message"]}"
    return 1
  end
end

def prepare_environment_with_direct_calls
  data = {
    body: {
      user: {
        net_id: "dick"
      }
    }
  }
  response = TestScript.post("/users?admin=true",data)
  if response.code == 500
    puts "FAILED: Load user dick. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      user: {
        net_id: "jane"
      }
    }
  }
  response = TestScript.post("/users?admin=true",data)
  if response.code == 500
    puts "FAILED: Load user jane. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      security_role: {
        name: "Rockand"
      },
      users: [
        { net_id: "dick" },
        { net_id: "jane" }
      ]
    }
  }
  response = TestScript.post("/security_roles?admin=true",data)
  if response.code == 500
    puts "FAILED: Load security_role Rockand. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      security_role: {
        name: "Ingstone"
      },
      users: [
        { net_id: "jane" }
      ]
    }
  }
  response = TestScript.post("/security_roles?admin=true",data)
  if response.code == 500
    puts "FAILED: Load security_role Ingstone. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      term: {
        name: "Fall"
      },
      allows_access_with: [
        { name: "Rockand", allow_update_and_delete: false }
      ]
    }
  }
  response = TestScript.post("/terms?admin=true",data)
  if response.code == 500
    puts "FAILED: Load term Fall. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      term: {
        name: "Spring"
      },
      allows_access_with: [
        { name: "Ingstone", allow_update_and_delete: false }
      ]
    }
  }
  response = TestScript.post("/terms?admin=true",data)
  if response.code == 500
    puts "FAILED: Load term Spring. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      report: {
        name: "Foo"
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" }
      ],
      allows_access_with: [
        { name: "Rockand", allow_update_and_delete: false },
        { name: "Ingstone", allow_update_and_delete: false }
      ]
    }
  }
  response = TestScript.post("/reports?admin=true",data)
  if response.code == 500
    puts "FAILED: Load report Foo. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      report: {
        name: "Bar"
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" }
      ],
      allows_access_with: [
        { name: "Ingstone", allow_update_and_delete: false }
      ]
    }
  }
  response = TestScript.post("/reports?admin=true",data)
  if response.code == 500
    puts "FAILED: Load report Bar. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  puts "SUCCESS: Load data."
  return 0
end

def compare_items(correct, actual)
  #puts "Comparing #{correct.to_s} to #{actual.to_s}..."
  if correct == nil && actual != nil
    return { :success => false, :message => "Expected nil, got #{actual.to_s}." }
  end
  if correct != nil && actual == nil
    return { :success => false, :message => "Expected #{correct.to_s}, got nil." }
  end
  if correct.is_a?(Hash)
    if actual.is_a?(Hash)
      return compare_hashes(correct,actual)
    else
      return { :success => false, :message => "Expected hash, got #{actual.to_s}." }
    end
  elsif correct.is_a?(Array)
    if actual.is_a?(Array)
      return compare_arrays(correct,actual)
    else
      return { :success => false, :message => "Expected array, got #{actual.to_s}." }
    end
  else
    if correct == actual
      return { :success => true }
    else
      return { :success => false, :message => "Expected #{correct.to_s}, got #{actual.to_s}." }
    end
  end
end

def compare_hashes(correct, actual)
  correct.keys.each do |correct_key|
    result = compare_items(correct[correct_key], actual[correct_key.to_s])
    if !result[:success]
      return result
    end
  end
  # We do not compare all of actual's keys. We are only interested in the specified
  # properties in correct; others (id, created_date, etc) may vary.
  return { :success => true }
end

def filter_hash(correct, actual)
  output = {}
  correct.keys.each do |key|
    if actual.has_key?(key.to_s)
      output[key] = actual[key.to_s]
    end
  end
  return output
end

def compare_arrays(correct, actual)
  correct.each do |correct_item|
    match_found = false
    mismatches = ""
    actual.each do |actual_item|
      comp = compare_items(correct_item, actual_item)
      if comp[:success]
        match_found = true
        break
      else
        mismatches += "\n" + comp[:message]
      end
    end
    if !match_found
      return { :success => false, :message => "Could not match #{correct_item.to_s} in actual output.#{mismatches}" }
    end
  end
  actual.each do |actual_item|
    match_found = false
    mismatches = ""
    correct.each do |correct_item|
      comp = compare_items(correct_item, actual_item)
      if comp[:success]
        match_found = true
        break
      else
        mismatches += "\n" + comp[:message]
      end
    end
    if !match_found
      return { :success => false, :message => "Actual output included unexpected item: #{actual_item.to_s}.#{mismatches}" }
    end
  end
  return { :success => true }
end

def validate_get(url, map)
  response = TestScript.get(url)

  body = JSON.parse(response.body)
  map.keys.each do |map_key|
    correct = map[map_key]
    actual = body[map_key.to_s]
    comparison = compare_items(correct, actual)
    if !comparison[:success]
      puts "FAILED: Query #{url}. Mismatch on #{map_key}: #{comparison[:message]}"
      return 1
    end
  end

  puts "SUCCESS: Query #{url}. All values matched."
  return 0
end

def execute_tests
  my_fails = 0
  my_fails += validate_get(
    "/reports/Foo?cas_user=dick",
    { report: { name: "Foo" }, terms: [ { name: "Fall" } ], allows_access_with: [ { name: "Rockand" } ] }
    )
  my_fails += validate_get(
    "/reports/Bar?cas_user=dick",
    { success: false }
    )
  my_fails += validate_get(
    "/terms/Fall?cas_user=dick",
    { term: { name: "Fall" }, reports: [ { name: "Foo" } ], allows_access_with: [ { name: "Rockand" } ] }
    )
  my_fails += validate_get(
    "/terms/Spring?cas_user=dick",
    { success: false }
    )
  my_fails += validate_get(
    "/users/dick?cas_user=dick",
    { user: { net_id: "dick" }, security_roles: [ { name: "Rockand" } ] }
    )
  my_fails += validate_get(
    "/users/jane?cas_user=dick",
    { success: false }
    )
  my_fails += validate_get(
    "/security_roles/Rockand?cas_user=dick",
    { security_role: { name: "Rockand" }, users: [ { net_id: "dick" } ], reports: [ { name: "Foo" } ], terms: [ { name: "Fall" } ] }
    )
  my_fails += validate_get(
    "/security_roles/Ingstone?cas_user=dick",
    { success: false }
    )

  # Test searches.
  my_fails += validate_get(
    "/reports?cas_user=dick",
    { results: [
      { data: { name: "Foo", terms: [ { name: "Fall" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  my_fails += validate_get(
    "/terms?cas_user=dick",
    { results: [
      { data: { name: "Fall", reports: [ { name: "Foo" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  my_fails += validate_get(
    "/security_roles?cas_user=dick",
    { results: [
      { data: { name: "Rockand", terms: [ { name: "Fall" } ], reports: [ { name: "Foo" } ], users: [ { net_id: "dick" } ] } }
      ] }
    )
  my_fails += validate_get(
    "/users?cas_user=dick",
    { results: [
      { data: { net_id: "dick", security_roles: [ { name: "Rockand" } ] } }
      ] }
    )

  return my_fails
end

def rebuild_search_index
  response = TestScript.post("/search/rebuild?admin=true",{})
  if response.code != 200
    puts "FAILED: Unable to rebuild search index. #{JSON.parse(response.body)["message"]}"
    return 1
  end
  puts "SUCCESS: Rebuild search index."
  sleep(10) # Give Elasticsearch a chance to finish processing.
  return 0
end

def bulk_export_and_import
  response = TestScript.get("/bulk?admin=true")
  if response.code != 200
    puts "FAILED: Unable to bulk export. #{JSON.parse(response.body)["message"]}"
    return 1
  end
  puts "SUCCESS: Bulk export records."

  if delete_everything > 0
    return 1
  end
  
  body = JSON.parse(response.body)
  bulk_data = body["export_result"]
  response = TestScript.post(
    "/bulk?admin=true",
    :headers => { "Content-type" => "application/json" },
    :body => bulk_data.to_json
    )
  if response.code != 200
    puts "FAILED: Unable to bulk import. #{JSON.parse(response.body)["message"]}"
    return 1
  end
  puts "SUCCESS: Bulk import records."
  sleep(10) # Give Elasticsearch a chance to finish processing.
  return 0
end

# ************************** ACTUAL SCRIPT BEGINS HERE **************************

fails = 0

fails += delete_everything
fails += prepare_environment_with_direct_calls

fails += execute_tests

fails += rebuild_search_index

fails += execute_tests

fails += bulk_export_and_import

fails += execute_tests


if fails > 0
  puts "\n************************** #{fails} TESTS FAILED ! ! ! **************************"
else
  puts "\nAll tests passed."
end
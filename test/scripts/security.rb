# This script should be run on localhost in a dev env.
# It tests that security works.
# WARNING! Script starts by blowing away the graph. Don't run it if you care about keeping your data.
# NEVER EVER run in prod.

require "httparty"

class TestScript
  include HTTParty
  base_uri "http://localhost:3000"
end

def prepare_environment
  # Step 1: Blow away the graph.
  response = TestScript.delete("/bulk/NoSeriouslyIMeanIt?admin=true")
  if response.code == 200
    puts "SUCCESS: Bulk delete."
  else
    puts "FAILED: Bulk delete."
    return
  end

  # Step 2: Load data.
  data = {
    body: {
      user: {
        net_id: "dick"
      }
    }
  }
  response = TestScript.post("/users?admin=true",data)
  if response.code == 500
    puts "FAILED: Load user dick."
    return
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
    puts "FAILED: Load user jane."
    return
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
    puts "FAILED: Load security_role Rockand."
    return
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
    puts "FAILED: Load security_role Ingstone."
    return
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
    puts "FAILED: Load term Fall."
    return
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
    puts "FAILED: Load term Spring."
    return
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
    puts "FAILED: Load report Foo."
    return
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
    puts "FAILED: Load report Bar."
    return
  end

  puts "SUCCESS: Load data."
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
      return
    end
  end

  puts "SUCCESS: Query #{url}. All values matched."
end

def execute_tests
  validate_get(
    "/reports/Foo?cas_user=dick",
    { report: { name: "Foo" }, terms: [ { name: "Fall" } ], allows_access_with: [ { name: "Rockand" } ] }
    )
  validate_get(
    "/reports/Bar?cas_user=dick",
    { success: false }
    )
  validate_get(
    "/terms/Fall?cas_user=dick",
    { term: { name: "Fall" }, reports: [ { name: "Foo" } ], allows_access_with: [ { name: "Rockand" } ] }
    )
  validate_get(
    "/terms/Spring?cas_user=dick",
    { success: false }
    )
  validate_get(
    "/users/dick?cas_user=dick",
    { user: { net_id: "dick" }, security_roles: [ { name: "Rockand" } ] }
    )
  validate_get(
    "/users/jane?cas_user=dick",
    { success: false }
    )
  validate_get(
    "/security_roles/Rockand?cas_user=dick",
    { security_role: { name: "Rockand" }, users: [ { net_id: "dick" } ], reports: [ { name: "Foo" } ], terms: [ { name: "Fall" } ] }
    )
  validate_get(
    "/security_roles/Ingstone?cas_user=dick",
    { success: false }
    )

  # Test searches.
  validate_get(
    "/reports?cas_user=dick",
    { results: [
      { data: { name: "Foo", terms: [ { name: "Fall" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  validate_get(
    "/terms?cas_user=dick",
    { results: [
      { data: { name: "Fall", reports: [ { name: "Foo" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  validate_get(
    "/security_roles?cas_user=dick",
    { results: [
      { data: { name: "Rockand", terms: [ { name: "Fall" } ], reports: [ { name: "Foo" } ], users: [ { net_id: "dick" } ] } }
      ] }
    )
  validate_get(
    "/users?cas_user=dick",
    { results: [
      { data: { net_id: "dick", security_roles: [ { name: "Rockand" } ] } }
      ] }
    )

  # Rebuild the search index and try all tests again.
  response = TestScript.post("/search/rebuild?admin=true",{})
  if response.code != 200
    puts "FAILED: Unable to rebuild search index."
  else
    puts "SUCCESS: Rebuild search index."
  end
  sleep(10) # Give Elasticsearch a chance to finish processing.

  validate_get(
    "/reports?cas_user=dick",
    { results: [
      { data: { name: "Foo", terms: [ { name: "Fall" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  validate_get(
    "/terms?cas_user=dick",
    { results: [
      { data: { name: "Fall", reports: [ { name: "Foo" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  validate_get(
    "/security_roles?cas_user=dick",
    { results: [
      { data: { name: "Rockand", terms: [ { name: "Fall" } ], reports: [ { name: "Foo" } ], users: [ { net_id: "dick" } ] } }
      ] }
    )
  validate_get(
    "/users?cas_user=dick",
    { results: [
      { data: { net_id: "dick", security_roles: [ { name: "Rockand" } ] } }
      ] }
    )
end

prepare_environment
execute_tests
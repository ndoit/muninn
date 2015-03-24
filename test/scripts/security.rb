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
        net_id: "cleopatra"
      }
    }
  }
  response = TestScript.post("/users?admin=true",data)
  if response.code == 500
    puts "FAILED: Load user cleopatra. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      user: {
        net_id: "caesar"
      }
    }
  }
  response = TestScript.post("/users?admin=true",data)
  if response.code == 500
    puts "FAILED: Load user caesar. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      user: {
        net_id: "mark_antony"
      }
    }
  }
  response = TestScript.post("/users?admin=true",data)
  if response.code == 500
    puts "FAILED: Load user mark_antony. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      security_role: {
        name: "Rockand"
      },
      users: [
        { net_id: "cleopatra" },
        { net_id: "caesar" }
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
        name: "Ingstone",
        read_access_to: [
          "report"
        ],
        create_access_to: [
          "report"
        ]
      },
      users: [
        { net_id: "caesar" },
        { net_id: "mark_antony" }
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
      term: {
        name: "Summer"
      },
      allows_access_with: [
      ]
    }
  }
  response = TestScript.post("/terms?admin=true",data)
  if response.code == 500
    puts "FAILED: Load term Summer. #{JSON.parse(response.body)["message"]}"
    return 1
  end

  data = {
    body: {
      report: {
        name: "Foo",
        description: "Foo Report."
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" },
        { name: "Summer" }
      ],
      allows_access_with: [
        { name: "Rockand", allow_update_and_delete: false }
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
        name: "Bar",
        description: "Bar Report."
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" }
      ],
      allows_access_with: [
        { name: "Ingstone", allow_update_and_delete: true }
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

  # cleopatra has the Rockand security role.
  # She should be able to see Foo but not Bar; Fall but not Spring or Summer; Rockand but not Ingstone; cleopatra but not caesar or mark_antony.

  # caesar has the Rockand and Ingstone security roles.
  # He should be able to see Foo and Bar; Fall and Spring but not Summer; Rockand and Ingstone; caesar but not cleopatra or mark_antony.

  # mark_antony has the Ingstone security role.
  # He should be able to see Foo (because Ingstone has read access to all reports) and Bar; Spring but not Fall or Summer;
  # Ingstone but not Rockand; mark_antony but not cleopatra or caesar.

  my_fails += validate_get(
    "/reports/Foo?cas_user=cleopatra",
    { report: { name: "Foo", description: "Foo Report." }, terms: [ { name: "Fall" } ], allows_access_with: [ { name: "Rockand", allow_update_and_delete: false } ] }
    )
  my_fails += validate_get(
    "/reports/Foo?cas_user=caesar",
    { report: { name: "Foo" }, terms: [ { name: "Fall" }, { name: "Spring" } ], allows_access_with: [ { name: "Rockand" } ] }
    )
  my_fails += validate_get(
    "/reports/Foo?cas_user=mark_antony",
    { report: { name: "Foo" }, terms: [ { name: "Spring" } ], allows_access_with: [ ] }
    )
  my_fails += validate_get(
    "/reports/Foo?admin=true",
    { report: { name: "Foo" }, terms: [ { name: "Fall" }, { name: "Spring" }, { name: "Summer" } ], allows_access_with: [ { name: "Rockand" } ] }
    )
  my_fails += validate_get(
    "/reports/Bar?cas_user=cleopatra",
    { success: false }
    )
  my_fails += validate_get(
    "/reports/Bar?cas_user=caesar",
    { report: { name: "Bar", description: "Bar Report." }, terms: [ { name: "Fall" }, { name: "Spring" } ], allows_access_with: [ { name: "Ingstone", allow_update_and_delete: true } ] }
    )
  my_fails += validate_get(
    "/terms/Fall?cas_user=cleopatra",
    { term: { name: "Fall" }, reports: [ { name: "Foo" } ], allows_access_with: [ { name: "Rockand" } ] }
    )
  my_fails += validate_get(
    "/terms/Spring?cas_user=cleopatra",
    { success: false }
    )
  my_fails += validate_get(
    "/users/cleopatra?cas_user=cleopatra",
    { user: { net_id: "cleopatra" }, security_roles: [ { name: "Rockand" } ] }
    )
  my_fails += validate_get(
    "/users/caesar?cas_user=cleopatra",
    { success: false }
    )
  my_fails += validate_get(
    "/security_roles/Rockand?cas_user=cleopatra",
    { security_role: { name: "Rockand" }, users: [ { net_id: "cleopatra" } ], reports: [ { name: "Foo" } ], terms: [ { name: "Fall" } ] }
    )
  my_fails += validate_get(
    "/security_roles/Ingstone?cas_user=cleopatra",
    { success: false }
    )

  # Test searches.
  my_fails += validate_get(
    "/reports?cas_user=cleopatra",
    { results: [
      { data: { name: "Foo", terms: [ { name: "Fall" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  my_fails += validate_get(
    "/terms?cas_user=cleopatra",
    { results: [
      { data: { name: "Fall", reports: [ { name: "Foo" } ], allows_access_with: [ { name: "Rockand" } ] } }
      ] }
    )
  my_fails += validate_get(
    "/security_roles?cas_user=cleopatra",
    { results: [
      { data: { name: "Rockand", terms: [ { name: "Fall" } ], reports: [ { name: "Foo" } ], users: [ { net_id: "cleopatra" } ] } }
      ] }
    )
  my_fails += validate_get(
    "/users?cas_user=cleopatra",
    { results: [
      { data: { net_id: "cleopatra", security_roles: [ { name: "Rockand" } ] } }
      ] }
    )

  # Now we play with updating a report...
  data = {
    body: {
      report: {
        name: "Foo",
        description: "A report on dogs, and maybe lions."
      }
    }
  }
  response = TestScript.put("/reports/Foo?cas_user=caesar",data)
  if response.code != 500 # This should fail, Caesar doesn't have access to modify this report.
    puts "FAILED: Update Foo as caesar got response code #{response.code}."
    my_fails += 1
  else
    puts "SUCCESS: Update Foo as caesar was denied."
  end

  my_fails += validate_get(
    "/reports/Foo?cas_user=cleopatra",
    { report: { name: "Foo", description: "Foo Report." } }
    )

  data = {
    body: {
      report: {
        name: "Bar",
        description: "Where Cleopatra goes when she gets thirsty."
      }
    }
  }
  response = TestScript.put("/reports/Bar?cas_user=cleopatra",data)
  if response.code != 500 # This should fail, Cleopatra doesn't have access to modify this report.
    puts "FAILED: Update Bar as cleopatra got response code #{response.code}."
    my_fails += 1
  else
    puts "SUCCESS: Update Bar as cleopatra was denied."
  end

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Bar Report." } }
    )

  data = {
    body: {
      report: {
        name: "Bar",
        description: "Where Caesar goes when he gets thirsty."
      }
    }
  }
  response = TestScript.put("/reports/Bar?cas_user=caesar",data)
  if response.code == 500 # This should succeed, Caesar has the Ingstone role which lets him modify Bar.
    puts "FAILED: Could not update Bar as caesar. #{JSON.parse(response.body)["message"]}."
    my_fails += 1
  else
    puts "SUCCESS: Update Bar as caesar was allowed."
  end

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Where Caesar goes when he gets thirsty." } }
    )

  # And deleting a report...
  response = TestScript.delete("/reports/Foo?cas_user=caesar",data)
  if response.code != 500 # This should fail, Caesar doesn't have access to delete this report.
    puts "FAILED: Delete Foo as caesar got response code #{response.code}."
    my_fails += 1
  else
    puts "SUCCESS: Delete Foo as caesar was denied."
  end

  my_fails += validate_get(
    "/reports/Foo?cas_user=mark_antony",
    { report: { name: "Foo", description: "Foo Report." } }
    )

  response = TestScript.delete("/reports/Bar?cas_user=cleopatra",data)
  if response.code != 500 # This should fail, Cleopatra doesn't have access to delete this report.
    puts "FAILED: Delete Bar as cleopatra got response code #{response.code}."
    my_fails += 1
  else
    puts "SUCCESS: Delete Bar as cleopatra was denied."
  end

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Where Caesar goes when he gets thirsty." } }
    )

  response = TestScript.delete("/reports/Bar?cas_user=caesar",data)
  if response.code == 500 # This should succeed, Caesar has the Ingstone role which lets him delete Bar.
    puts "FAILED: Could not delete Bar as caesar. #{JSON.parse(response.body)["message"]}."
    my_fails += 1
  else
    puts "SUCCESS: Delete Bar as caesar was allowed."
  end

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { success: false }
    )

  # ...and creating a report, which puts the data back like it was.
  # Notice that we do *not* include the Ingstone security role this time. It should be added
  # automatically because that is the role allowing caesar to create Bar.
  data = {
    body: {
      report: {
        name: "Bar",
        description: "Bar Report."
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" }
      ]
    }
  }
  response = TestScript.post("/reports?cas_user=cleopatra",data)
  if response.code != 500 # This should fail, Cleopatra doesn't have access to create reports.
    puts "FAILED: Create Bar as cleopatra got response code #{response.code}."
    my_fails += 1
  else
    puts "SUCCESS: Create Bar as cleopatra was denied."
  end

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { success: false }
    )

  data = {
    body: {
      report: {
        name: "Bar",
        description: "Bar Report."
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" }
      ]
    }
  }
  response = TestScript.post("/reports?cas_user=caesar",data)
  if response.code == 500
    puts "FAILED: Could not create report Bar as caesar. #{JSON.parse(response.body)["message"]}"
    my_fails += 1
  else
    puts "SUCCESS: Create Bar as caesar was allowed."
  end

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Bar Report." } }
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

fails += delete_everything

if fails > 0
  puts "\n************************** #{fails} TESTS FAILED ! ! ! **************************"
else
  puts "\nAll tests passed."
end
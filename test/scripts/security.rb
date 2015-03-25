# This script should be run on localhost in a dev env.
# It tests that security works.
# WARNING! Script starts by blowing away the graph. Don't run it if you care about keeping your data.

require "httparty"
require "active_support/core_ext"

class TestScript
  include HTTParty
  base_uri "http://localhost:3000"
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
      puts "FAILED: Get #{url}. Mismatch on #{map_key}: #{comparison[:message]}"
      return 1
    end
  end

  puts "SUCCESS: Get #{url}. All values matched."
  return 0
end

def load_unique_properties
  if defined?(@unique_properties) == nil
    @unique_properties = {}

    yaml_data = YAML.load_file("config/schema.yml")
    node_labels = yaml_data["nodes"].keys
    node_labels.each do |label|
      @unique_properties[label] = yaml_data["nodes"][label]["unique_property"]
    end
  end
end

def extract_name_and_type_from(url, content)
  # For standard POST requests, a handy feature to identify in the output what you're trying to create.
  load_unique_properties
  target_node = ""
  no_url_params = url.split("?")[0]
  split_url = no_url_params.split("/")
  node_type = ""
  node_name = ""
  split_url.each do |str|
    if str.length > 0
      node_type = str.singularize
      break
    end
  end

  if node_type.length > 0 &&
    content != nil &&
    @unique_properties.has_key?(node_type) &&
    content.has_key?(node_type.to_sym) &&
    content[node_type.to_sym].has_key?(@unique_properties[node_type].to_sym)
    return { :type => node_type, :name => content[node_type.to_sym][@unique_properties[node_type].to_sym] }
  end

  return { :type => nil, :name => nil }
end

def validate_post_put_delete(url, content, expectation, type)
  data = {
    body: content
  }
  if type == :post
    response = TestScript.post(url,data)
  elsif type == :put
    response = TestScript.put(url,data)
  elsif type == :delete
    response = TestScript.delete(url)
  else
    raise "Unknown non-get HTML verb: #{type.to_s}"
  end

  target_node = ""
  if type == :post
    name_and_type = extract_name_and_type_from(url, content)
    if name_and_type[:name] != nil
      target_node = " (creating #{name_and_type[:type]} \"#{name_and_type[:name]}\")"
    end
  end

  correctness = (expectation == :should_succeed) ? (response.code == 200) : (response.code == 500)

  if !correctness
    puts "FAILED: #{type.to_s.capitalize} #{url}#{target_node}. Expected #{(expectation == :should_succeed) ? "200" : "500"}, got: " +
    "#{response.code.to_s + (response.code == 200 ? "" : " - " + response.message)}"
    return 1
  else
    puts "SUCCESS: #{type.to_s.capitalize} #{url}#{target_node} returned #{response.code.to_s} as expected."
    return 0
  end
end

def validate_post(url, content, expectation)
  return validate_post_put_delete(url, content, expectation, :post)
end

def validate_put(url, content, expectation)
  return validate_post_put_delete(url, content, expectation, :put)
end

def validate_delete(url, expectation)
  return validate_post_put_delete(url, nil, expectation, :delete)
end

# ************************** TEST ROUTINES **************************

def delete_everything
  return validate_delete("/bulk/NoSeriouslyIMeanIt?admin=true", :should_succeed)
end

def prepare_environment_with_direct_calls
  my_fails = 0

  my_fails += validate_post(
    "/users?admin=true",
    {
      user: {
        net_id: "cleopatra"
      }
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/users?admin=true",
    {
      user: {
        net_id: "caesar"
      }
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/users?admin=true",
    {
      user: {
        net_id: "mark_antony"
      }
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/security_roles?admin=true",
    {
      security_role: {
        name: "Rockand"
      },
      users: [
        { net_id: "cleopatra" },
        { net_id: "caesar" }
      ]
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/security_roles?admin=true",
    {
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
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/terms?admin=true",
    {
      term: {
        name: "Fall"
      },
      allows_access_with: [
        { name: "Rockand", allow_update_and_delete: false }
      ]
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/terms?admin=true",
    {
      term: {
        name: "Spring"
      },
      allows_access_with: [
        { name: "Ingstone", allow_update_and_delete: false }
      ]
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/terms?admin=true",
    {
      term: {
        name: "Summer"
      },
      allows_access_with: [
      ]
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/reports?admin=true",
    {
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
    },
    :should_succeed
  )

  my_fails += validate_post(
    "/reports?admin=true",
    {
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
    },
    :should_succeed
  )

  return my_fails
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

  # Now we play with updating a report description...
  my_fails += validate_put(
    "/reports/Foo?cas_user=caesar",
    { report: { name: "Foo", description: "A report on dogs, and maybe lions." } },
    :should_fail
    )

  my_fails += validate_get(
    "/reports/Foo?cas_user=cleopatra",
    { report: { name: "Foo", description: "Foo Report." } }
    )

  my_fails += validate_put(
    "/reports/Bar?cas_user=cleopatra",
    { report: { name: "Bar", description: "Where Cleopatra goes when she gets thirsty." } },
    :should_fail
    )

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Bar Report." } }
    )

  my_fails += validate_put(
    "/reports/Bar?cas_user=caesar",
    { report: { name: "Bar", description: "Where Caesar goes when he gets thirsty." } },
    :should_succeed
    )

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Where Caesar goes when he gets thirsty." } }
    )

  # And deleting a report...
  my_fails += validate_delete(
    "/reports/Foo?cas_user=caesar",
    :should_fail
    )

  my_fails += validate_get(
    "/reports/Foo?cas_user=mark_antony",
    { report: { name: "Foo", description: "Foo Report." } }
    )

  my_fails += validate_delete(
    "/reports/Bar?cas_user=cleopatra",
    :should_fail
    )

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Where Caesar goes when he gets thirsty." } }
    )

  my_fails += validate_delete(
    "/reports/Bar?cas_user=caesar",
    :should_succeed
    )

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { success: false }
    )

  # ...and creating a report, which puts the data back like it was.
  # Notice that we do *not* include the Ingstone security role this time. It should be added
  # automatically because that is the role allowing caesar to create Bar.
  my_fails += validate_post(
    "/reports?cas_user=cleopatra",
    {
      report: {
        name: "Bar",
        description: "Bar Report."
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" }
      ]
    },
    :should_fail
    )

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { success: false }
    )

  my_fails += validate_post(
    "/reports?cas_user=caesar",
    {
      report: {
        name: "Bar",
        description: "Bar Report."
      },
      terms: [
        { name: "Fall" },
        { name: "Spring" }
      ]
    },
    :should_succeed
    )

  my_fails += validate_get(
    "/reports/Bar?cas_user=mark_antony",
    { report: { name: "Bar", description: "Bar Report." } }
    )

  return my_fails
end

def rebuild_search_index
  output = validate_post(
    "/search/rebuild?admin=true",
    {},
    :should_succeed
    )
  if output == 0
    sleep(10) # Give Elasticsearch a chance to finish processing.
  end
  return output
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
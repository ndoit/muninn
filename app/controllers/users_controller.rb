require 'rubygems'
require 'json'
require 'net/http'
require 'aws-sdk'

class UsersController < GraphController

  def initialize()
    @primary_label = :user
  end

  def get_model_repository
    return UserRepository.new
  end

  def extract_json_message(rawdata)
    begin
      return JSON.parse(rawdata.body)
    rescue
      return []
    end
  end

  def parse_message(rawdata, role_map)
    LogTime.info "Extracting JSON from AWS message."

    data = extract_json_message(rawdata)

    LogTime.info "Extracted: " + data.to_s

    users = []

    LogTime.info "Parsing users."

    data.each do |user_data|
      user_roles = []
      user_data["entitlement"].each do |entitlement|
        role = entitlement[20..entitlement.length]
        if(role_map[role]!=nil)
          user_roles << { "name" => role_map[role] }
        else
          raise "Role not found in role_map.json: " + role
        end
      end
      user_record = {
        "target_uri" => "users/" + user_data["netId"],
        "content" => {
          "user" => { "net_id" => user_data["netId"] },
          "security_roles" => user_roles
        }
      }

      LogTime.info "User data extracted: " + user_record.to_json

      users << user_record

      LogTime.info "User " + user_data["netId"] + " added."
    end

    LogTime.info "AWS message complete."

    return users
  end

  def get_role_map
    LogTime.info "Loading security roles."
    roles_export = BulkLoader.new.export("security_roles")

    LogTime.info roles_export.to_s

    LogTime.info "Extracting role map."
    role_map = {}
    roles_export[:export_result].each do |role_export|
      role_map[role_export["content"][:security_role]["iam_export_code"]] =
        role_export["content"][:security_role]["name"]
    end

    return role_map
  end

  def get_aws_messages(params)
    LogTime.info "Reading AWS connection params."

    access_key_id = params[:access_key_id]
    secret_access_key = params[:secret_access_key]
    msg_queue = params[:msg_queue]
    msg_queue_owner = params[:msg_queue_owner]

    LogTime.info "Configuring AWS connection to queue " + msg_queue + "."

    Aws.config[:ssl_verify_peer] = false
    creds = Aws::Credentials.new access_key_id, secret_access_key
    sqs = Aws::SQS::Client.new region: 'us-east-1', credentials: creds

    LogTime.info "Retrieving queue url."

    qurl = sqs.get_queue_url queue_name: msg_queue,
                             queue_owner_aws_account_id: msg_queue_owner

    LogTime.info "Retrieving messages."

    messages = sqs.receive_message queue_url: qurl.queue_url

    LogTime.info messages.length.to_s + " messages found."

    return messages
  end

  def load_from_aws    
    role_map = get_role_map
    messages = get_aws_messages(params)

    messages[:messages].each do |rawdata|
      LogTime.info "Raw message: " + rawdata.to_s

      users = parse_message(rawdata, role_map)

      chunkSize = 10
      startIndex = 0

      while startIndex < users.length do
        LogTime.info "Chunking " + startIndex.to_s + ".." + (startIndex + chunkSize - 1).to_s + "..."

        chunk = []
        i = startIndex
        while (i < startIndex + chunkSize) && (i < users.length) do
          chunk << users[i]
          i = i + 1
        end

        LogTime.info "Chunk complete. Loading."
        BulkLoader.new.load(chunk)
      end
    end

    LogTime.info "All messages loaded."

    render :status => 200
  end
end
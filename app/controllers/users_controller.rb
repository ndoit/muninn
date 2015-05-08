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

  def extract_user_values(rawdata)
    begin
      data = JSON.parse(rawdata)
      return data["entitlements"]
    rescue Exception => e  
      LogTime.info "Extract failed with error: " + e.message
      return []
    end
  end

  # def user_roles
  #   begin
  #     role_hash = {}
  #     role_hash["roles"] = []
  #     # with this line, EVERYONE can publish a report!
  #     role_hash["roles"] << "Report Publisher"

  #     if ( params[:netid] == 'afreda' or 'rsnodgra' )
  #       role_hash["roles"] << "Term Editor"
  #     end 

  #     render json: role_hash.to_json
  #   rescue (Exception e)
  #     render json: {}
  #   end
  # end

  def my_access
    output = SecurityGoon.who_is_this(params)
    render :status => (output[:success] ? 200 : 500), :json => output.to_json
  end

  def parse_message(rawdata, role_map)
    LogTime.info "Extracting JSON user values from AWS message."

    data = extract_user_values(rawdata)

    LogTime.info "Extracted: " + data.to_s

    users = []

    LogTime.info "Parsing users."

    data.each do |user_data|
      LogTime.info("Parsing" + user_data.to_s + "...")
      user_roles = []
      missing_roles = ""
      user_data["entitlement"].each do |entitlement|
        role = entitlement[20..entitlement.length]
        if(role_map[role]!=nil)
          user_roles << { "name" => role_map[role] }
        else
          missing_roles += role + ";"
        end
      end
      if missing_roles.length > 0
        raise "Role not found in role_map.json: " + missing_roles
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

  def get_role_map(user_obj)
    LogTime.info "Loading security roles."
    roles_export = BulkLoader.new.export("security_roles",user_obj)

    LogTime.info roles_export.to_s

    LogTime.info "Extracting role map."
    role_map = {}
    roles_export[:export_result].each do |role_export|
      role_map[role_export["content"][:security_role]["iam_export_code"]] =
        role_export["content"][:security_role]["name"]
    end

    return role_map
  end

  def pull_aws_queue
    LogTime.info "Loading AWS connection info."

    access_key_id = ENV["security_load_access_key_id"]
    secret_access_key = ENV["security_load_secret_access_key"]
    msg_queue = ENV["security_load_msg_queue"]
    msg_queue_owner = ENV["security_load_msg_queue_owner"]

    LogTime.info "Configuring AWS connection to queue " + msg_queue + "."

    Aws.config[:ssl_verify_peer] = false
    creds = Aws::Credentials.new access_key_id, secret_access_key
    sqs = Aws::SQS::Client.new region: 'us-east-1', credentials: creds

    LogTime.info "Retrieving queue url."

    qurl = sqs.get_queue_url queue_name: msg_queue,
                             queue_owner_aws_account_id: msg_queue_owner

    LogTime.info "Retrieving messages."

    messages = sqs.receive_message queue_url: qurl.queue_url

    LogTime.info "Retrieved: #{messages.to_s}"

    LogTime.info messages[:messages].length.to_s + " messages found."

    return {
      :messages => messages[:messages],
      :sqs => sqs,
      :queue_url => qurl.queue_url
    }
  end

  def load_from_aws    
    # VERY IMPORTANT!

    # This method does not accept user input in any way, shape, or form.

    # This is crucial, because it bypasses regular authentication and runs with admin privs.

    # If you change it to accept any kind of user input, you MUST remove the following line
    # and replace it with the regular SecurityGoon process for authenticating a user. 

    # And then you need to modify the cron job that calls this process nightly, since
    # that job doesn't do anything to authenticate itself.
    user_obj = SecurityGoon.generic_admin

    aws_queue = pull_aws_queue

    if(aws_queue[:messages].length==0)
      render :status => 200, :json => { :success => true, :message => "Queue empty." }
      return
    end

    sqs = aws_queue[:sqs]
    queue_url = aws_queue[:queue_url]

    begin
      role_map = get_role_map(user_obj)
    rescue Exception => e
      return { message: "Failed to generate role map due to error: #{e.message}", success: false }
    end

    processed = 0
    success = false

    aws_queue[:messages].each do |rawdata|
      LogTime.info "Raw message: " + rawdata.to_s

      users = parse_message(rawdata.body, role_map)
      processed = processed + 1

      if users.length > 0
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
          BulkLoader.new.load(chunk,user_obj)
          LogTime.info "*** CHUNK LOADED ***"

          startIndex += chunkSize
        end

        LogTime.info "Message loaded."
        success = true
      end

      if Rails.application.config.delete_security_role_updates
        LogTime.info "Deleting queue_url " + queue_url.to_s + ", receipt_handle: " + rawdata[:receipt_handle].to_s
        delete_output = sqs.delete_message queue_url: queue_url, receipt_handle: rawdata[:receipt_handle]
        LogTime.info "Delete output: " + delete_output.to_s
      end
    end

    if success
      render :status => 200, :json => { :success => true, :message => processed.to_s + " messages processed. Users updated." }
    else
      render :status => 500, :json => { :success => false, :message => processed.to_s + " messages processed. All had errors." }
    end
  end
end

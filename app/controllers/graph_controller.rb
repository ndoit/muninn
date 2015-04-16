require "elasticsearch_io.rb"
require "net/http"
require "json"
require "open-uri"

class GraphController < ApplicationController
  #We don't need to worry about cross-site request forgery.
  skip_before_action :verify_authenticity_token
  #before_filter CASClient::Frameworks::Rails::GatewayFilter, :only => :authenticated_show
  #before_filter CASClient::Frameworks::Rails::Filter, :except => [ :show, :search ]
  #before_filter :authenticate!, :only => :authenticated_show

  attr_accessor :primary_label

  def get_model_repository
    return ModelRepository.new(@primary_label)
  end

  
  def create
    LogTime.info "****************************************** COMMENCE CREATE ******************************************"
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end

    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository
    
    LogTime.info "Writing to database creating node."
    output = repository.write(params, true, user_result[:user])
    if output[:success]
      SecurityGoon.clear_cache
      render :status => 200, :json => output
    else
      render :status => 500, :json => output
    end
  end
  
  def update
    LogTime.info "****************************************** COMMENCE UPDATE ******************************************"
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end

    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository
    
    LogTime.info "Writing to database."
    output = repository.write(params, false, user_result[:user])
    if output[:success]
      SecurityGoon.clear_cache
      render :status => 200, :json => output
    else
        render :status => 500, :json => output
    end
  end
  
  def show
    LogTime.info "****************************************** COMMENCE SHOW ******************************************"
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    
    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository
  
    LogTime.debug "Processing read request."
    output = repository.read(params, user_result[:user])

    output[:validated_user] = user_result[:user]["net_id"]
  
    LogTime.debug "Rendering output."
    if output[:success]
      render :status => 200, :json => output
    else
      render :status => 500, :json => output
    end
  end
  
  def destroy
    LogTime.info "****************************************** COMMENCE DESTROY ******************************************"
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    
    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository
  
    LogTime.debug "Processing delete request."
    output = repository.delete(params, user_result[:user])
  
    LogTime.debug "Rendering output."
    if output[:success]
      SecurityGoon.clear_cache
      render :status => 200 ,:json => output
    else
        render :status => 500 ,:json => output
    end
  end

  def search
    LogTime.info "****************************************** COMMENCE SEARCH ******************************************"
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    
    if params.has_key?(:query_string)
      query_string = params[:query_string]
    else
      render :status => 500, :json => { success: false, message: "Enter a query string." }
      return
    end

    output = ElasticSearchIO.instance.search(URI.escape(query_string), @primary_label)
    if output[:success]
      render :status => 200, :json => output
    else
        render :status => 500, :json => output
    end
  end

  def index
    LogTime.info "****************************************** COMMENCE INDEX ******************************************"
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    user_obj = user_result[:user]
    
    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository
  
    LogTime.debug "Processing index request."
    output = ElasticSearchIO.instance.search(nil, user_obj, @primary_label)
  
    LogTime.debug "Rendering output."
    if output[:success]
        render :status => 200, :json => output
    else
        render :status => 500, :json => output
    end
  end
  
end
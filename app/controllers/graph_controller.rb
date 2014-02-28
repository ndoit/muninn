require "elasticsearch_io.rb"

class GraphController < ApplicationController
  #We don't maintain sessions, so we don't need to worry about cross-site request forgery.
  skip_before_action :verify_authenticity_token
  #before_filter CASClient::Frameworks::Rails::GatewayFilter, :only => :show
  #before_filter CASClient::Frameworks::Rails::Filter, :except => [ :show, :search ]

  attr_accessor :primary_label

  def get_model_repository
    return ModelRepository.new(@primary_label)
  end
  
  def create
  	LogTime.info "Instantiating ModelRepository."
  	repository = get_model_repository
  	
  	LogTime.info "Writing to database."
    output = repository.write(params, true, session[:cas_user])
  	if output[:success]
  	  render :status => 200, :json => output
  	else
      render :status => 500, :json => output
  	end
  end
  
  def update
    LogTime.info "Instantiating ModelRepository."
  	repository = get_model_repository
  	
  	LogTime.info "Writing to database."
    output = repository.write(params, false, session[:cas_user])
  	if output[:success]
  	  render :status => 200, :json => output
  	else
        render :status => 500, :json => output
  	end
  end
  
  def show
  	LogTime.info "Instantiating ModelRepository."
	  repository = get_model_repository
	
    LogTime.debug "Processing read request."
    output = repository.read(params, session[:cas_user])
	
    LogTime.debug "Rendering output."
	  if output[:success]
      render :status => 200, :json => output
	  else
      render :status => 500, :json => output
	  end
  end
  
  def destroy
  	LogTime.info "Instantiating ModelRepository."
	  repository = get_model_repository
	
    LogTime.debug "Processing delete request."
    output = repository.delete(params, session[:cas_user])
	
    LogTime.debug "Rendering output."
  	if output[:success]
        render :status => 200, :json => output
  	else
        render :status => 500, :json => output
  	end
  end

  def search
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
    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository
  
    LogTime.debug "Processing index request."
    output = ElasticSearchIO.instance.search(nil, @primary_label)
  
    LogTime.debug "Rendering output."
    if output[:success]
        render :status => 200, :json => output
    else
        render :status => 500, :json => output
    end
  end
  
end
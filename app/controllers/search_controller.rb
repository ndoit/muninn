require "elasticsearch_io.rb"

class SearchController < ApplicationController
  #We don't maintain sessions, so we don't need to worry about cross-site request forgery.
  skip_before_action :verify_authenticity_token

  def rebuild
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    user_obj = user_result[:user]
    if !user_obj["is_admin"]
      render :status => 500, :json => { success: false, message: "Access denied." }
      return
    end

  	output = ElasticSearchIO.instance.rebuild_search_index
	  if output[:success]
	    render :status => 200, :json => output
	  else
      render :status => 500, :json => output
	  end
  end

  def reinitialize
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    user_obj = user_result[:user]
    if !user_obj["is_admin"]
      render :status => 500, :json => { success: false, message: "Access denied." }
      return
    end

    output = ElasticSearchIO.instance.wipe_and_initialize
    if output[:success]
      render :status => 200, :json => output
    else
      render :status => 500, :json => output
    end
  end
  
  def search
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

    output = ElasticSearchIO.instance.search(URI.escape(query_string), user_result[:user], nil)
	  if output[:success]
	    render :status => 200, :json => output
	  else
      render :status => 500, :json => output
	  end
  end
  
  def advanced_search
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end

    LogTime.info params.to_s
    if params.has_key?("search")
      query_body = params["search"]
    else
      render :status => 500, :json => { success: false, message: "You must include a query body." }
      return
    end

    output = ElasticSearchIO.instance.advanced_search(query_body, user_result[:user], nil)
    if output[:success]
      render :status => 200, :json => output
    else
      render :status => 500, :json => output
    end
  end
  
end
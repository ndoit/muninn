require "elasticsearch_io.rb"

class SearchController < ApplicationController
  #We don't maintain sessions, so we don't need to worry about cross-site request forgery.
  skip_before_action :verify_authenticity_token

  def rebuild
  	output = ElasticSearchIO.instance.rebuild_search_index
	  if output[:success]
	    render :status => 200, :json => output
	  else
      render :status => 500, :json => output
	  end
  end

  def reinitialize
    output = ElasticSearchIO.instance.wipe_and_initialize
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

    output = ElasticSearchIO.instance.search(URI.escape(query_string), nil)
	  if output[:success]
	    render :status => 200, :json => output
	  else
      render :status => 500, :json => output
	  end
  end
  
  def advanced_search
    LogTime.info params.to_s
    if params.has_key?("search")
      query_body = params["search"]
    else
      render :status => 500, :json => { success: false, message: "You must include a query body." }
      return
    end

    output = ElasticSearchIO.instance.advanced_search(query_body, nil)
    if output[:success]
      render :status => 200, :json => output
    else
      render :status => 500, :json => output
    end
  end
  
end
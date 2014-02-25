require "elasticsearch_io.rb"

class SearchController < ApplicationController
  #We don't maintain sessions, so we don't need to worry about cross-site request forgery.
  skip_before_action :verify_authenticity_token

  def rebuild
  	output = ElasticSearchIO.instance.rebuild_search_index
	if output[:Success]
	  render :status => 200, :json => output
	else
      render :status => 500, :json => output
	end
  end
  
  def search
  	if params.has_key?(:query_string)
  	  query_string = params[:query_string]
  	else
      render :status => 500, :json => { Success: false, Message: "Enter a query string." }
      return
    end

    output = ElasticSearchIO.instance.search(URI.escape(query_string), nil)
	if output[:Success]
	  render :status => 200, :json => output
	else
      render :status => 500, :json => output
	end
  end
  
end
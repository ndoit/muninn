class BulkController < ApplicationController
  #We don't maintain sessions, so we don't need to worry about cross-site request forgery.
  skip_before_action :verify_authenticity_token
  #before_filter CASClient::Frameworks::Rails::GatewayFilter, :only => :show
  #before_filter CASClient::Frameworks::Rails::Filter, :except => [ :show, :search ]

  def wipe
    if params[:confirmation] != "NoSeriouslyIMeanIt"
      render :status => 500, :json => { Success: false,
        Message: "Confirmation is required. To irreversibly wipe the entire database, " +
        "send a delete request to the URL: bulk/wipe/NoSeriouslyIMeanIt"}
      return
    end
    result = BulkLoader.new.wipe
    if result[:Success]
      render :status => 200, :json => result
    else
      render :status => 500, :json => result
    end
  end

  def load
  	json_body = params["_json"]
    result = BulkLoader.new.load(json_body)
    if result[:Success]
      render :status => 200, :json => result
    else
      render :status => 500, :json => result
    end
  end

  def export
    result = BulkLoader.new.export
    if result[:Success]
      render :status => 200, :json => result
    else
      render :status => 500, :json => result
    end
  end
end
class BulkController < ApplicationController
  #We don't maintain sessions, so we don't need to worry about cross-site request forgery.
  skip_before_action :verify_authenticity_token

  def wipe
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    user_obj = user_result[:user]
    if request.remote_ip != "127.0.0.1"
      if !user_obj["is_admin"]
        render :status => 500, :json => { success: false, message: "Access denied." }
        return
      end
    else
      user_obj["net_id"] = "&localhost"
      user_obj["is_admin"] = true
    end

    if params[:confirmation] != "NoSeriouslyIMeanIt"
      render :status => 500, :json => { success: false,
        message: "Confirmation is required. To irreversibly wipe the entire database, " +
        "send a delete request to the URL: bulk/NoSeriouslyIMeanIt"}
      return
    end
    result = BulkLoader.new.wipe(user_obj)
    if result[:success]
      SecurityGoon.clear_cache
      render :status => 200, :json => result
    else
      SecurityGoon.clear_cache
      render :status => 500, :json => result
    end
  end

  def load
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    user_obj = user_result[:user]
    if request.remote_ip != "127.0.0.1"
      if !user_obj["is_admin"]
        render :status => 500, :json => { success: false, message: "Access denied." }
        return
      end
    else
      user_obj["net_id"] = "&localhost"
      user_obj["is_admin"] = true
    end

  	json_body = params["_json"]
    result = BulkLoader.new.load(json_body, user_obj)
    if result[:success]
      SecurityGoon.clear_cache
      render :status => 200, :json => result
    else
      SecurityGoon.clear_cache
      render :status => 500, :json => result
    end
  end

  def export
    LogTime.info "Identifying user."
    user_result = SecurityGoon.who_is_this(params)
    if !user_result[:success]
      render :status => 500, :json => user_result
      return
    end
    user_obj = user_result[:user]
    if request.remote_ip != "127.0.0.1"
      if !user_obj["is_admin"]
        render :status => 500, :json => { success: false, message: "Access denied." }
        return
      end
    else
      user_obj["net_id"] = "&localhost"
      user_obj["is_admin"] = true
    end

    result = BulkLoader.new.export(params[:target], user_obj)
    if result[:success]
      SecurityGoon.clear_cache
      render :status => 200, :json => result
    else
      SecurityGoon.clear_cache
      render :status => 500, :json => result
    end
  end
end
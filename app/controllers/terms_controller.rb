class TermsController < GraphController

  def initialize()
    @primary_label = :Term
  end

  def get_model_repository
    return TermRepository.new
  end

  def history
    if !Packager.is_integer(params[:id])
      render :status => 500, :json => { Message: "Invalid id.", Success: false }
    end

    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository
  
    LogTime.debug "Processing publish request."
    output = repository.history(params[:id].to_i, session[:cas_user])

    LogTime.debug "Rendering output."
    if output[:Success]
      render :status => 200, :json => output
    else
      render :status => 500, :json => output
    end
  end
end
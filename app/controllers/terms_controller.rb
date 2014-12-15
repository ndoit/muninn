require 'neography'

class TermsController < GraphController

  def initialize()
    @primary_label = :term
    @neo = Neography::Rest.new
  end

  def get_model_repository
    return TermRepository.new
  end

  def history
    if !Packager.is_integer(params[:id])
      render :status => 500, :json => { message: "Invalid id.", success: false }
      return
    end

    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository

    LogTime.debug "Processing publish request."
    output = repository.history(params[:id].to_i, session[:cas_user])

    LogTime.debug "Rendering output."
    if output[:success]
      render :status => 200, :json => output
    else
      render :status => 500, :json => output
    end
  end
end

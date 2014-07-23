require 'neography'

class TermsController < GraphController

  def initialize()
    @primary_label = :term
    @neo = Neography::Rest.new
  end

  def get_model_repository
    return TermRepository.new
  end

  def show
    LogTime.info "Instantiating ModelRepository."
    repository = get_model_repository

    LogTime.debug "Processing read request."
    output = repository.read(params, session[:cas_user])
    #output[:cas_user] = session[:cas_user]

    output[:validated_user] = SecurityGoon.who_is_this(params)
    output[:raci_matrix] = raci_matrix(params[:unique_property])

    render json: output, status: 200
  end

  def raci_matrix( term_name )
    @result = @neo.execute_query( "match (n:term)<-[r:HAS_STAKE_IN]-(o) where n.name ='#{term_name}' return r.stake, o.name order by r.stake")

    # aggregate raci groups into hash of arrays
    raci = {}
    @result["data"].each do |row|
      raci[row[0]] ||= []
      raci[row[0]] << row[1]
    end
    raci
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

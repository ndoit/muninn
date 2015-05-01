class TermRepository < ModelRepository
  def initialize
  	super(:term)
  end

  def read(params, user_obj)

    output = super(params, user_obj)
    add_raci_matrix(output)
    return output
  end

  def add_raci_matrix(output)
    output[:raci_matrix] = {}
    if(output.has_key?("stakeholders"))
      output["stakeholders"].each do |stakeholder|
        if !output[:raci_matrix].has_key?(stakeholder["stake"])
          output[:raci_matrix][stakeholder["stake"]] = []
        end
        output[:raci_matrix][stakeholder["stake"]] << stakeholder["name"]
      end
    end
  end
end

#  def show
#    LogTime.info "Instantiating ModelRepository."
#    repository = get_model_repository
#
#    LogTime.debug "Processing read request."
#    output = repository.read(params, session[:cas_user])
#    #output[:cas_user] = session[:cas_user]
#
#    output[:validated_user] = SecurityGoon.who_is_this(params)
#    output[:raci_matrix] = raci_matrix(params[:unique_property])
#
#    render json: output, status: 200
#  end
# 
#  def raci_matrix( term_name )
#    @result = @neo.execute_query( "match (n:term)<-[r:HAS_STAKE_IN]-(o) where n.name ='#{term_name}' return r.stake, o.name order by r.stake")
#
    # aggregate raci groups into hash of arrays
#    raci = {}
#    @result["data"].each do |row|
#      raci[row[0]] ||= []
#      raci[row[0]] << row[1]
#    end
#    raci
#  end
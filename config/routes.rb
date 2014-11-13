BIPortalDataService::Application.routes.draw do

  def create_resources nodes
    #It would be nice to be able to do all this with a simple resources command, but
    #I'm not seeing how you get the /id routes in there. So, we just define it all
    #explicitly.
    get nodes + '/:unique_property', to: nodes + '#show'
    get nodes + '/id/:id', to: nodes + '#show'

    post nodes, to: nodes + '#create'

    put nodes + '/:unique_property', to: nodes + '#update'
    put nodes + '/id/:id', to: nodes + '#update'  # NOT WORKING?

    delete nodes + '/:unique_property', to: nodes + '#destroy'
    delete nodes + '/id/:id', to: nodes + '#destroy'

    get nodes + '/search/:query_string', to: nodes + '#search'

    get nodes, to: nodes + '#index'
  end

  get '/bulk', to: 'bulk#export'
  post '/bulk', to: 'bulk#load'
  delete '/bulk/:confirmation', to: 'bulk#wipe'

  create_resources 'terms'
  get '/terms/history/id/:id', to: 'terms#history'
  get '/terms/id/:id/:version_number', to: 'terms#show'
  get '/terms/:unique_property/:version_number', to: 'terms#show'

  get '/users/:netid/roles', to: 'users#user_roles'

  create_resources 'users'

  #create_resources 'proposed_terms'
  #put '/proposed_terms/publish/:id', to: 'proposed_terms#publish'

  create_resources 'offices'

  create_resources 'reports'

  create_resources 'domain_tags'

  create_resources 'bus_process_tags'

  create_resources 'security_roles'

  get 'search/:query_string', to: 'search#search'
  get 'search/custom/query/:index', to: 'search#advanced_search'
  get 'search/custom/query', to: 'search#advanced_search'
  post 'search/rebuild', to: 'search#rebuild'
  post 'search/reinitialize', to: 'search#reinitialize'

end

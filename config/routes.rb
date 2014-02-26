BIPortalDataService::Application.routes.draw do

  def create_resources nodes
    #It would be nice to be able to do all this with a simple resources command, but
    #I'm not seeing how you get the /id routes in there. So, we just define it all
    #explicitly.
    get nodes + '/:unique_property', to: nodes + '#show'
    get nodes + '/id/:id', to: nodes + '#show'

    post nodes, to: nodes + '#create'

    put nodes + '/:unique_property', to: nodes + '#update'
    put nodes + '/id/:id', to: nodes + '#update'

    delete nodes + '/:unique_property', to: nodes + '#destroy'
    delete nodes + '/id/:id', to: nodes + '#destroy'

    get nodes + '/search/:query_string', to: nodes + '#search'

    get nodes, to: nodes + '#index'
  end

  post '/bulk_load', to: 'bulk_load#load'
  
  create_resources 'terms'
  get '/terms/history/id/:id', to: 'terms#history'
  get '/terms/:unique_property/:version_number', to: 'terms#show'
  get '/terms/id/:id/:version_number', to: 'terms#show'

  #create_resources 'proposed_terms'
  #put '/proposed_terms/publish/:id', to: 'proposed_terms#publish'
  
  create_resources 'offices'
  
  create_resources 'people'

  create_resources 'reports'

  get 'search/:query_string', to: 'search#search'
  post 'search/rebuild', to: 'search#rebuild'
  
end

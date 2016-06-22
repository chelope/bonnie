class Thorax.Models.ArchivedMeasure extends Thorax.Models.Measure
  idAttribute: '_id'
  initialize: ->
    # Becasue we bootstrap patients we mark them as _fetched, so isEmpty() will be sensible
    @set 'patients', new Thorax.Collections.Patients [], _fetched: true
  
  fetchDeferred: ->
    fetchDef = $.Deferred()
    @fetch(
      success: (model) -> fetchDef.resolve(model)
      error: (model) -> fetchDef.reject(model)
    )
    return fetchDef

class Thorax.Collections.ArchivedMeasures extends Thorax.Collection
  initialize: (models, options) ->
    @measure_id = options.measure_id
    
  url: -> "/measures/#{@measure_id}/archived_measures"
    
  model: Thorax.Models.ArchivedMeasure
  
  parse: (response, options) ->
    return _(response).map (arch_measure) ->
       new Thorax.Models.ArchivedMeasure {_id: arch_measure.measure_db_id}, _fetched: false
       
  fetchDeferred: ->
    fetchDef = $.Deferred()
    @fetch(
      success: (collection) -> fetchDef.resolve(collection)
      error: (collection) -> fetchDef.reject(collection)
    )
    return fetchDef
    
  fetchAll: ->
    fetchAllDef = $.Deferred()
    @fetchDeferred().then((collection) -> 
      $.when.apply(@, collection.map((model) -> model.fetchDeferred()))
        .done( ->
          fetchAllDef.resolve(collection))
        .fail( ->
          fetchAllDef.reject(collection))
      )
    return fetchAllDef
    
## All filter implementations should have an #apply(patient) method that returns true/false.

class Thorax.Models.MeasureAuthorFilter extends Thorax.Model
  additionalRequirements: {name: 'email', text: 'E-mail address', type: 'email'}
  initialize: (@email) -> @regexp = new RegExp(@email, "i")
  apply: (patient) -> !!patient.get('user_email').match(@regexp)
  label: -> "User #{@email}"

class Thorax.Models.MeasureFilter extends Thorax.Model
  additionalRequirements: {name: 'cms_id', text: 'CMS ID', type: 'text'}
  initialize: (@cmsId) -> @regexp = new RegExp(@cmsId, "i")
  apply: (patient) ->
    cms_ids = patient.get('cms_ids')
    _.some cms_ids, (cms_id) => cms_id.match(@regexp)
  label: -> "Measure #{@cmsId}"

class Thorax.Models.PopulationsFilter extends Thorax.Model
  # TODO determine if this needs tweaking for CV measures
  initialize: (@criteria, @population) ->

  apply: (patient) ->
    calculation = @population.calculate(patient)
    result = calculation.get @criteria
    if result? then result # if it calculates true, return the patient

  label: -> @criteria
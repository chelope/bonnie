class Thorax.Views.CqlLogic extends Thorax.Views.BonnieView

  template: JST['logic/cql_logic']

  initialize: ->

  events:
    "ready": ->
      @editor = ace.edit("editor")
      @editor.setTheme("ace/theme/chrome")
      @editor.session.setMode("ace/mode/cql")
      @editor.setReadOnly(true)
      @editor.setShowPrintMargin(false)
      @editor.setOptions(maxLines: Infinity)
      @editor.renderer.setShowGutter(false);
      @editor.setValue(@model.get('cql'), -1)

  context: -> _(super).extend cqlLines: @model.get('cql').split("\n")

  showCoverage: ->

  clearCoverage: ->

  showRationale: ->

  clearRationale: ->

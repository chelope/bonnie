import DS from 'ember-data';

export default DS.Model.extend({
  IPP: DS.attr('string'),
  STRAT: DS.attr('string'),
  DENOM: DS.attr('string'),
  NUMER: DS.attr('string'),
  DENEXCEP: DS.attr('string'),
  DENEX: DS.attr('string'),
  MSRPOPL: DS.attr('string'),
  OBSERV: DS.attr('string'),
  sub_id: DS.attr('string'),
  measure: DS.belongsTo('measure', { async: false, inverse: 'populations' })
});

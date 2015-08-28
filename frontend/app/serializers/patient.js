import DS from 'ember-data';

export default DS.RESTSerializer.extend(DS.EmbeddedRecordsMixin, {
  isNewSerializerAPI: true,
  primaryKey: '_id',
  attrs: {
    measureId: {
      embedded : 'always'
    },
    measureIds: {
      embedded : 'always'
    },
    expectedValues: {
      embedded : 'always'
    }
  }
});

class MeasuresController < ApplicationController

  skip_before_action :verify_authenticity_token, only: [:show, :value_sets]

  respond_to :json, :js, :html

  def show
    skippable_fields = [:map_fns, :record_ids, :measure_attributes]
    @measure = Measure.by_user(current_user).without(*skippable_fields).find(params[:id])
    if stale? last_modified: @measure.updated_at.try(:utc), etag: @measure.cache_key
      @measure_json = MultiJson.encode(@measure.as_json(except: skippable_fields))
      respond_with @measure do |format|
        format.json { render json: @measure_json }
      end
    end
  end

  def value_sets
    if stale? last_modified: Measure.by_user(current_user).max(:updated_at).try(:utc)
      value_set_oids = Measure.by_user(current_user).only(:value_set_oids).pluck(:value_set_oids).flatten.uniq

      # Not the cleanest code, but we get a many second performance improvement by going directly to Moped
      # (The two commented lines are functionally equivalent to the following three uncommented lines, if slower)
      # value_sets_by_oid = HealthDataStandards::SVS::ValueSet.in(oid: value_set_oids).index_by(&:oid)
      # @value_sets_by_oid_json = MultiJson.encode(value_sets_by_oid.as_json(except: [:_id, :code_system, :code_system_version]))
      value_sets = Mongoid::Sessions.default[HealthDataStandards::SVS::ValueSet.collection_name].find(oid: { '$in' => value_set_oids }, user_id: current_user.id)
      value_sets = value_sets.select('concepts.code_system' => 0, 'concepts.code_system_version' => 0)
      @value_sets_by_oid_json = MultiJson.encode value_sets.index_by { |vs| vs['oid'] }

      respond_with @value_sets_by_oid_json do |format|
        format.json { render json: @value_sets_by_oid_json }
      end
    end
  end

  def create
    if params[:measure_file].present?
      uploaded_measure = process_measure_file(params)
      measure = write_measure(uploaded_measure, params) if uploaded_measure
    else
      flash[:error] = show_error('loading', 'missingfile')
      redirect_to "#{root_path}##{params[:redirect_route]}"
      return false
    end

    current_user.measures << measure
    current_user.save!

    redirect_to "#{root_path}##{params[:redirect_route]}"
  end

  def update
    existing = Measure.by_user(current_user).where(hqmf_set_id: params[:hqmf_set_id], hqmf_id: params[:hqmf_id]).first

    if params[:measure_file].present?
      uploaded_measure = process_measure_file(params, existing)
      measure = write_measure(uploaded_measure, params) if uploaded_measure
    else
      measure = write_measure(existing, params)
    end

    # rebuild the users patients if set to do so
    if params[:rebuild_patients] == "true"
      Record.by_user(current_user).each do |r|
        Measures::PatientBuilder.rebuild_patient(r)
        r.save!
      end
    end

    redirect_to "#{root_path}##{params[:redirect_route]}"
  end

  def destroy
    measure = Measure.by_user(current_user).find(params[:id])
    Measure.by_user(current_user).find(params[:id]).destroy
    render :json => measure
  end

  def finalize
    measure_finalize_data = params.values.select {|p| p['hqmf_id']}.uniq
    measure_finalize_data.each do |data|
      measure = Measure.by_user(current_user).where(hqmf_id: data['hqmf_id']).first
      measure.update_attributes({needs_finalize: false, episode_ids: data['episode_ids']})
      measure.populations.each_with_index do |population, population_index|
        population['title'] = data['titles']["#{population_index}"] if (data['titles'])
      end
      measure.generate_js(clear_db_cache: true)
      measure.save!
    end
    redirect_to "#{root_path}##{params[:redirect_route]}"
  end

  def debug
    @measure = Measure.by_user(current_user).without(:map_fns, :record_ids).find(params[:id])
    @patients = Record.by_user(current_user).asc(:last, :first)
    render layout: 'debug'
  end

  def clear_cached_javascript
    measure = Measure.by_user(current_user).find(params[:id])
    measure.generate_js clear_db_cache: true
    redirect_to :back
  end

  private
  def show_error(category, type, missing_value_sets=[])
    available_messages = {
      "match" => {
        "format" => {:title => "Error Loading Measure", :summary => "Incorrect Upload Format.", :body => "The file you have uploaded does not appear to be a Measure Authoring Tool zip export of a measure or HQMF XML measure file. Please re-export your measure from the MAT and select the 'eMeasure Package' option, or select the correct HQMF XML file."},
        "zip" => {:title => "Error Uploading Measure", :summary => "The uploaded zip file is not a Measure Authoring Tool export.", :body => "You have uploaded a zip file that does not appear to be a Measure Authoring Tool zip file. If the zip file contains HQMF XML, please unzip the file and upload the HQMF XML file instead of the zip file. Otherwise, please re-export your measure from the MAT and select the 'eMeasure Package' option"},
        "already_loaded" => {:title => "Error Loading Measure", :summary => "A version of this measure is already loaded.", :body => "You have a version of this measure loaded already.  Either update that measure with the update button, or delete that measure and re-upload it."},
        "update_file" => {:title => "Error Updating Measure", :summary => "The update file does not match the measure.", :body => "You have attempted to update a measure with a file that represents a different measure.  Please update the correct measure or upload the file as a new measure."},
        "eoc" => {:title => "Error Loading Measure", :summary => "An episode of care measure requires at least one specific occurrence for the episode of care.", :body => "You have loaded the measure as an episode of care measure.  Episode of care measures require at lease one data element that is a specific occurrence.  Please add a specific occurrence data element to the measure logic."},
        "value_sets" => {:title => "Measure is missing value sets", :summary => "The measure you have tried to load is missing value sets.", :body => "The measure you are trying to load is missing value sets.  Try re-packaging and re-exporting the measure from the Measure Authoring Tool.  The following value sets are missing: [#{missing_value_sets.join(', ')}]"}
      },
      "loading" => {
        "valuesets" => {:title => "Error Loading Measure", :summary => "The measure value sets could not be found.", :body => "Please re-package the measure in the MAT and make sure &quot;VSAC Value Sets&quot; are included in the package, then re-export the MAT Measure bundle."},
        "other" => {:title => "Error Loading Measure", :summary => "The measure could not be loaded.", :body => "Please re-package the measure in the MAT, then re-download the MAT Measure Export.  If the measure has QDM elements without a VSAC Value Set defined the measure will not load."},
        "missingfile" => {:title => "Error Loading Measure", :body => "You must specify a Measure Authoring tool measure export to use."}
      }
    }
    return available_messages[category][type]
  end

  def show_error_with_message(type, e)
    available_messages = {
      "hqmf" => {:title => "Error Loading Measure", :summary => "Error loading XML file.", :body => "There was an error loading the XML file you selected.  Please verify that the file you are uploading is an HQMF XML or SimpleXML file.  Message: #{e.message}"},
      "vsac" => {:title => "Error Loading VSAC Value Sets", :summary => "VSAC value sets could not be loaded.", :body => "Please verify that you are using the correct VSAC username and password. #{e.message}"}
    }
    return available_messages[type]
  end

  def process_measure_file(params, existing=nil)

    measure_file = params[:measure_file]
    extension = File.extname(measure_file.original_filename).downcase
    if extension && !['.zip', '.xml'].include?(extension)
      flash[:error] = show_error('match', 'format')
      redirect_to "#{root_path}##{params[:redirect_route]}"
      return false
    elsif extension == '.zip'
      if !Measures::MATLoader.mat_export?(measure_file)
        flash[:error] = show_error('match', 'zip')
        return false
      end
    end

    begin
      if extension == '.xml'
        includeDraft = params[:include_draft] == 'true'
        effectiveDate = nil
        unless includeDraft
          effectiveDate = Date.strptime(params[:vsac_date],'%m/%d/%Y').strftime('%Y%m%d')
        end
        measure = Measures::SourcesLoader.load_measure_xml(measure_file.tempfile.path, current_user, params[:vsac_username], params[:vsac_password], {}, true, false, effectiveDate, includeDraft) # overwrite_valuesets=true, cache=false, includeDraft=true
      else
        measure = Measures::MATLoader.load(measure_file, current_user, {})
      end

      # throw error if this is not actually an episode of care measure
      if (params[:calculation_type] == 'episode') && measure.data_criteria.values.select {|d| d['specific_occurrence']}.empty?
        measure.delete
        flash[:error] = show_error('match', 'eoc')
        return false
      end

      # exclude patient birthdate and expired OIDs used by SimpleXML parser for AGE_AT handling and bad oid protection in missing VS check
      missing_value_sets = (measure.as_hqmf_model.all_code_set_oids - measure.value_set_oids - ['2.16.840.1.113883.3.117.1.7.1.70', '2.16.840.1.113883.3.117.1.7.1.309'])
      if missing_value_sets.length > 0
        measure.delete
        flash[:error] = show_error('match', 'value_sets', missing_value_sets)
        return false
      end

      # has this measure already been uploaded? or might it be uploaded to the wrong update?
      if !existing
        existing = Measure.by_user(current_user).where(hqmf_set_id: measure.hqmf_set_id)
        if existing.count > 1
          measure.delete
          flash[:error] = show_error('match', 'already_loaded')
          return false
        end
      elsif existing.hqmf_set_id != measure.hqmf_set_id # update, doesn't match
        measure.delete
        flash[:error] = show_error('match', 'update_file')
        return false
      end

    rescue Exception => e
      errors_dir = Rails.root.join('log', 'load_errors')
      FileUtils.mkdir_p(errors_dir)
      clean_email = File.basename(current_user.email) # Prevent path traversal
      filename = "#{clean_email}_#{Time.now.strftime('%Y-%m-%dT%H%M%S')}#{extension}"

      operator_error = false # certain types of errors are operator errors and do not need to be emailed out.

      FileUtils.cp(measure_file.tempfile, File.join(errors_dir, filename))
      File.chmod(0644, File.join(errors_dir, filename))
      File.open(File.join(errors_dir, "#{clean_email}_#{Time.now.strftime('%Y-%m-%dT%H%M%S')}.error"), 'w') {|f| f.write(e.to_s + "\n" + e.backtrace.join("\n")) }
      if e.is_a? Measures::ValueSetException
        flash[:error] = show_error('loading', 'valuesets')
      elsif e.is_a? Measures::HQMFException
        operator_error = true
        flash[:error] = show_error_with_message('hqmf', e)
      elsif e.is_a? Measures::VSACException
        operator_error = true
        flash[:error] = show_error_with_message('vsac', e)
      else
        flash[:error] = show_error('loading', 'other')
      end

      # email the error
      if !operator_error && defined? ExceptionNotifier::Notifier
        params[:error_file] = filename
        ExceptionNotifier::Notifier.exception_notification(env, e).deliver
      end

      return false
    end

    if measure.populations.size > 1
      strat_index = 1
      measure.populations.each do |population|
        if (population[HQMF::PopulationCriteria::STRAT])
          population['title'] = "Stratification #{strat_index}"
          strat_index += 1
        end
      end
    end

    measure
  end

  def write_measure(measure, params)

    measure_details = {
      'type' => params[:measure_type],
      'episode_of_care' => params[:calculation_type] == 'episode',
      'needs_finalize' => ((params[:calculation_type] == 'episode') || measure.populations.size > 1)
    }

    if measure_details['episode_of_care']
      episodes = params["eoc_#{params[:hqmf_set_id]}"]
      if episodes && episodes['episode_ids'] && !episodes['episode_ids'].empty?
        measure_details['episode_ids'] = episodes['episode_ids']
      end
    end

    if measure.populations
      measure_details['population_titles'] = measure.populations.map {|p| p['title']} if measure.populations.length > 1
      measure.populations.each_with_index do |population, population_index|
        population['title'] = measure_details['population_titles'][population_index] if (measure_details['population_titles'])
      end
    end

    measure.update_attributes(measure_details)

    Measures::ADEHelper.update_if_ade(measure)
    measure.generate_js
    measure.save!
    measure
  end


end

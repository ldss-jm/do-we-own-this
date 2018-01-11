require 'numbers_in_words'

class KnownRecord
  attr_reader :hsh, :cands,
              :candidate_ids, :text_title,  :candidates, :search_candidates,
              :split_authors, :terms_searched, :o, :my, :output

  @@seen = $candidates
  @@matcher = $matcher

  def initialize(hsh, options)
    @o = options
    oo = @o[:options]
    @candidates = CandidateSet.new(@o)
    @hsh = hsh
    @terms_searched = {}
    @my = {alt_title: [], alt_author: []}
    
    # read input from source file and map fields to standard terms
    @o[:input_mappings].each do |our_label, source_labels|
      source_labels = [source_labels] if !source_labels.is_a?(Array)
      @my[our_label] = []
      source_labels.each do |source_label|
        @my[our_label] << hsh[source_label].to_s.strip
      end
      @my[our_label].uniq!
      @my[our_label].delete("")
    end
    
    # transform each/any fields according to field specs
    @o[:input_transforms].each { |k, v| xform(k, v) }
    
    # get alt_titles
    @number_title = text_to_num(my[:title]) if oo[:number_title]
    @text_title = num_to_text(my[:title]) if oo[:text_title]
    my[:alt_title] += (@number_title + @text_title).flatten
    my[:alt_title].delete("")
    vol_detect if oo[:vol_detect]
    split_titles if oo[:split_titles]
    @my[:alt_title].map! { |x| trim_punct(x) }
    @my[:alt_title].uniq!

    # get alt_authors
    @surnamed_authors = my[:author].map { |x| surname_parse(x) } if oo[:surname_parse]
    if oo[:split_authors]
      @split_authors = split_names(my[:author])
      @split_authors.map! { |x| [x, surname_parse(x)] }.flatten if oo[:surname_parse]
    end
    my[:alt_author] = [@split_authors.to_a + @surnamed_authors.to_a].flatten.compact.uniq
    @number_author = text_to_num(my[:author] + my[:alt_author]) if oo[:number_author]
    @text_author = num_to_text(my[:author] + my[:alt_author]) if oo[:text_author]
    my[:alt_author] += (@number_author.to_a + @text_author.to_a)
    if my[:alt_author].any? { |x| x=~ /Various/i } && oo[:plain_various]
      my[:alt_author] << 'Various'
    end
    my[:alt_author].uniq!

    # trim punct, remove 
    # notes:
    # format for sing_out can have multiple values
  end
  
  def inspect
    my
  end


  def vol_detect
    words = ['vol', 'part', 'volume', 'pt', 'v.', 'no.', 'number']
    #todo: move words to options
    #todo: maybe sometime try to split out a vol subtitle and write
    # that to alt_title, but for now no need to write things starting with
    # "vol x" to alt_title
    @my[:alt_title] ||= []
    titles = @my[:title] + @my[:alt_title]
    titles.each do |title|
      m = title.match(/(.*?)(\b(#{words.join('|')})s?\b.*)/i)
      return nil if !m
      @my[:vol] ||= []
      @my[:alt_title] += [m[1]]
      @my[:vol] += [m[2]]
      @candidates.knownrecord_iffiness *= 0.85
    end

  end



  


  def xform(k, v)
    orig = @my[k]
    v.each do |funct, params|
      case
      #todo: make this strip from end only?
      when funct == :strip_text
        @my[k] = orig.map { |x| strip_text(x, params) }
      when funct == :normalize_isbn
        @my[k] = orig.map { |x| normalize_isbn(x, params) }
      when funct == :split_camelcase
        @my[k] = orig.map { |x| split_camelcase(x, params) }
      end
    end
    @my[k].uniq!
  end

  def strip_text(orig, phrases_to_remove)
    phrases_to_remove.each do |phrase|
      orig.gsub!(/ ?\b#{phrase}\b/i, '')
    end
    return orig
  end

  def trim_punct(term)
    term.sub!(/[.,;: \/]*$/, '')
  end

  # PatHarris -> Pat Harris
  def split_camelcase(orig, nothing)
    new = orig.gsub(/([a-z])([A-Z])/, '\1 \2')
  end

  def normalize_isbn(orig, nothing)
    orig.gsub!(/[[:punct:]]/, '')
    return orig.upcase
  end

  def search_phrase(tag: index_tag, phrase: query_phrase,
                    source: phrase_source)
    limit = @o[:options][:cand_search_limit] || 10000
    osql = @o[:candidate_sql]
    results = {}
    phrase = index_normalize(phrase)
    $c.index_query(tag, phrase, osql)
    if $c.results.entries.length > limit
      $c.index_query(tag, phrase, osql, whole_word_match: true)
    end
    log_search_term(tag, phrase)
    $c.results.entries.map { |x| x['record_id']}.each do |entry|
      results[entry] = {source: [source]}
    end
    if results.length > limit
      begin
      whitelist = @o[:whitelisted_terms][tag.to_sym]
      rescue NoMethodError
      end
      unless whitelist && whitelist.include?(phrase)
        log_too_many(tag, phrase, results)
        return nil
      end
    end
    return results
  end

  def log_too_many(tag, phrase, results)
    puts 'too many!!'
    count = results.length
    orig =
      if tag == 'a'
        @my[:author].first
      elsif tag == 't'
        @my[:title].first
      else
        ''
      end
    File.open('many_results.log', 'a') { |of| of << "#{tag}\t#{count}\t#{phrase}\t#{orig}\n" }
  end


  def search_each_phrase(tag: index_tag, phrases: query_phrases, source: phrase_source)
    results = {}
    phrases.each do |query_phrase|
      res = search_phrase(tag: tag, phrase: query_phrase, source: source)
      results.update(res.to_h)
    end
    return results
  end

  def log_search_term(tag, term)
    if @terms_searched[tag]
      @terms_searched[tag] << term
    else
      @terms_searched[tag] = [term]
    end
    @terms_searched[tag].uniq!
  end

  def find_helper(index_tag, query_phrase, phrase_source)
    return nil if !query_phrase || query_phrase.empty?
    index_tag = index_tag.to_s
    results =
      if query_phrase.is_a?(Array)
        search_each_phrase(tag: index_tag, phrases: query_phrase, source: phrase_source)
      else
        search_phrase(tag: index_tag, phrase: query_phrase, source: phrase_source)
      end
    @candidates.update_ids(results)
  end



  def find_candidates(verbose: false)
    @o[:candidate_sql][:queries].each do |tag, fields|
      fields.each do |field|
        find_helper(tag, my[field], field)
      end
    end
  end

  def link_candidates
    @candidates.data.each do |rec_id, v|
      @@seen[rec_id] = Candidate.new(rec_id, @o) unless @@seen.include?(rec_id)
      v[:obj] = @@seen[rec_id]
      v[:comp_score] = {}
    end
  end

  def score_candidates()
    @candidates.data.each do |rec_id, v|
      cand = @candidates.data[rec_id]
      cand_details = v[:obj].details
      cand[:scores] = []
      @o[:matching].each do |name, params|
        needle, haystack, weight, *exact = params
        needle = @my[needle]
        haystack = cand_details[haystack]
        if exact.empty?
          cand[:scores] << score_term(needle, haystack, name, weight: weight)
        else
          cand[:scores] << score_exact(needle, haystack, name, weight: weight)
        end
      cand[:scores].flatten!
      end
    end
  end

  def score_exact(needle, haystack, name, weight: 1)
    return nil unless needle && haystack
    if needle.is_a?(Array)
      collector = []
      needle.each do |item|
        collector << score_exact(item, haystack, name, weight: weight)
      end
      return collector
    end
    exact_match = haystack.include?(needle) ? 1 : 0
    return MatchScore.new(
      {score: exact_match, weight: 1, name: name,
      term: needle, match: needle}
    )
  end

  def score_term(needle, haystack, name, weight: 1)
    return nil unless needle && haystack
    if needle.is_a?(Array)
      collector = []
      needle.each do |item|
        collector << score_term(item, haystack, name, weight: weight)
      end
      return collector
    end
    match_result = bmatch(needle, haystack)
    score = match_result ? match_result[1] : 0
    match = match_result ? match_result[0] : nil
    score = 0 if score.to_f.nan?
    return MatchScore.new(
      {score: score, weight: weight, name: name,
      term: needle, match: match}
    )
  end

  def score_detail(needle, haystack)
    return nil unless needle && haystack
    return bmatch(needle, haystack)
  end


  def search
    find_candidates
    link_candidates
    score_candidates
  end

  def explode_artists(artist)
    artists = {}
    artist = artist.strip
    artists[:as_is] = artist
    artists[:exploded] = split_names(artist)
    return artists
  end
  
  def split_names(lst)
    split_list_new = [lst].flatten
    split_list_prev = []
    while split_list_prev != split_list_new
      split_list_prev = split_list_new
      work_list = []
      split_list_prev.each do |artist|
        next if !artist
        work_list << artist.gsub(/\band\b/i, "&")
        work_list << artist.split('&')
        work_list << artist.split(/\b(with|feat|featuring|by)\b/i)
        work_list << artist.split('/')
        work_list << artist.split(',') if @o[:options][:commas_split]
        if artist.include?('&')
          work_list << artist.gsub(/^(.*)&(.*)\s([^\s]*)/, '\1 \3')
          # do mel & pat smith benatar => mel smith benatar
          work_list << artist.gsub(/^(.*)&\s([^\s]*)\s(.*)/, '\1 \3')
        # mel & Pat Middle de la Something => mel de la Something
          work_list << artist.gsub(/^(.*)&(.*[A-Z][^\s]*)\s([^A-Z]*[^\s]*)/, '\1 \3')
        end
      end
      split_list_new = Set.new(work_list.flatten.map { |x| x.strip })
    end
    split_list_new -= my[:author]
    split_list_new.delete(nil)
    return split_list_new
  end

  def split_titles
    titles = [my[:title] + my[:alt_title]].flatten
    return '' if titles.empty?
    trunc = []
    titles.each do |title|
      # require at least one character before the Vol/Part text
      m = title.match(/^(.+)\b(Vol|Volume|Part|Pt)\b.*$/i)
      trunc << m[1].strip if m
    end
    trunc += titles
    trunc.uniq!
    split = []
    trunc.each do |title|
      split += [title].map { |x| x.split('/') }.flatten.
                      map { |x| x.split(';') }.flatten.
                      map { |x| x.split(': ') }.flatten.
                      map { |x| x.split(' - ') }.flatten
    end
    split += trunc
    split.flatten!
    split.uniq!
    # get alt titles for things in begin or end parentheses, and the things
    # not in those parentheses. Also gets all content not in parentheses.
    # Could also probably be done better.
    collect = []
    split.each do |title|
      # for (get_this) excluded
      collect << title.partition(')')[0]
      # for (excluded) get_this
      collect << title.partition(')')[2]
      # for excluded (get_this)
      collect << title.rpartition('(')[-1]
      # for get_this (excluded)
      collect << title.rpartition('(')[0]
      # for (excluded) get_this (excluded)
      collect << title.partition(')')[2].partition('(')[0]
      # for all content non in parentheses
      collect << title.gsub(/\([^\)]*\)/, '')
      collect.map! { |title| title.gsub(/(\(|\))/, '').strip }
      collect.uniq!
      collect.delete("")
    end
    split += collect
    my[:alt_title] += (split.uniq - titles)
  end

  def vary_initials(name)
    names = [name]
    # drop all intials
    names = name.gsub(/\b\w\b/, '')
    # drop intials but don't drop first word
    if name.match(/^[^\w]*\w\b/)
      names << name.match(/^[^\w]*\w\b/)[0] + name.gsub(/\b\w\b/, '')
    end
    return names
  end
  
  def surname_parse(name)
    return nil if !name or name.empty?
    # names with the/and etc. are either not atomic names or don't need surname parsing
    return nil if name.match(/\b(with|the|and|&|\/|,|feat|featuring|by)\b/i)
    names = []
    # surname = the last word
    # Mary Something de la Lastname => lastname, mary something de la
    names << name.gsub(/^(.*)\s([^\s]*)/, '\2, \1')
    # surname = everything but the first word
    # Mary Something de la Lastname => something de la lastname, mary
    names << name.gsub(/^([^\s]*)\s(.*)/, '\2, \1')
    # surname = everything thing after the penultimate capitalized name as
    # Mary Something de la Lastname => de la lastname, mary something
    names << name.gsub(/^(.*[A-Z][^\s]*)\s([^A-Z]*[^\s]*)/, '\2, \1')
    names.delete(name)
    return names.uniq!
  end

  def text_to_num(input_arry) #aka num_title
    num_output = []
    input_arry.each do |term|
      next if NumbersInWords.in_numbers(term) == 0 and !term.match(/zero/)
      orig_term = term
      all_sep = term.split(" ").map { |x|
        if NumbersInWords.in_numbers(x) == 0 and x != 0
          "|" + x + "|"  # flag text
        else
          x             # leave number-words alone 
        end
      } # e.g. ["twenty", "|Requested|", "|Ballads|", "|of|", "|Ireland|", "|(Volume|", "Three)"]
      nums_sep = all_sep.join("").gsub("||", " ").split("|")
        # e.g. ["twenty", "Requested Ballads of Ireland (Volume", "Three)"]
      num_term = nums_sep.map { |x|
        if (NumbersInWords.in_numbers(x) == 0 and x != 0) || x =~ /^[0-9]*$/
          x                            # leave text clumps alone
        else
          NumbersInWords.in_numbers(x) # convert number-word clumps alone
        end
      }.join(" ") # "20 Requested Ballads of Ireland (Volume 3"
      num_output << num_term unless input_arry.include?(num_term)
    end
    return num_output
  end

  def num_to_text(input_arry)  #aka text_title
    text_output = []
    input_arry.each do |term|
      next if !term.match(/[0-9]/)
      text_output << term.gsub(/([0-9]+)/) { |x|
        NumbersInWords.in_words(x.to_i).
        gsub("ten one", "eleven").
        gsub("ten two", "twelve").
        gsub("ten three", "thirteen").
        gsub("ten five", "fifteen").
        gsub("ten eight", "eighteen").
        gsub(/ten (four|six|seven|nine)/, '\1' + 'teen')
      }
    end
    return text_output
  end

  def output
    output = []
    @o[:output_known].each do |k|
      if !k || k.empty?
        output << ''
      else @o[:input_mappings].include?(k)
        k = @o[:input_mappings][k].dup unless @hsh.include?(k)
        k = [k] unless k.is_a?(Array)
        k.map! { |x| @hsh[x].to_s }
        k.delete("")
        output << k.join('; ')
      end
    end
    return output
  end

end
class Connect
  
    #use this to extend $c
  
    # whole_word_match insists on 'pat smith' matching 'pat smith more' but not
    # 'pat smithfield'
    def index_query(index_tag, phrase, options, verbose: false,
                    whole_word_match: false)
      return {} if phrase.empty?
      if options[:mattype_is]
        mattype = options[:mattype_is]
        mattype_base = 'inner join sierra_view.bib_record_property brp on
                          brp.bib_record_id = b.id and brp.material_code '
        mattype_phrase = (mattype_base + mattype.to_s)
      end
      wholeword = '( |$)' if whole_word_match
      base_query = <<-SQL
        select distinct phe.record_id, phe.index_entry
        from sierra_view.phrase_entry phe
        inner join sierra_view.bib_record b on b.id = phe.record_id
        and b.bcode3 not in ('d', 'n', 'c', 'x')
        {MATTYPE_RESTRICTIONS}
        where
        (phe.index_tag || phe.index_entry) ~ '^{INDEXTAG}{FIELDSTRING}{wholeword}'
       --limit 500;
      SQL
      myquery = base_query.
      gsub('{INDEXTAG}', index_tag).
      gsub('{FIELDSTRING}', phrase).
      gsub('{MATTYPE_RESTRICTIONS}', mattype_phrase.to_s).
      gsub('{wholeword}', wholeword.to_s)
      $c.make_query(myquery)
      puts $c.results.entries if verbose
      return $c.results
    end

    # pummel_query helper
    def form_pummel_query(primary_tag, primary, secondary)
      secondary_tag = 'a'
      secondary_tag = 't' if primary_tag == 'a'
      base = <<-SQL
        select distinct phe.record_id
                    --, phe.index_entry as main_entry
                    --, 'b' || rm.record_num || 'a' as bnum
                    --, phe_alt.index_entry as sub_entry
        from sierra_view.phrase_entry phe
        inner join sierra_view.bib_record b on b.id = phe.record_id
        inner join sierra_view.record_metadata rm on rm.id = b.id
        and b.bcode3 not in ('d', 'n', 'c', 'x')
        inner join sierra_view.phrase_entry phe_alt on phe_alt.record_id = b.id
        inner join sierra_view.bib_record_property brp on
                          brp.bib_record_id = b.id and brp.material_code in ('i', 'j', '4', '5', '6')
        where
        (({PRIMARYPHRASE}
        ))
        and (phe_alt.index_tag || phe_alt.index_entry) ~ '{SECONDARYPHRASE}'
      SQL
      query =
        base.gsub('{PRIMARYPHRASE}',
                  primary.map { |word|
                    "(phe.index_tag || phe.index_entry) ~ '^#{primary_tag}#{index_normalize(word)}( |$)'"
                  }.join('or ')
           ).gsub('{SECONDARYPHRASE}',
                  "^#{secondary_tag}.*(#{secondary.join('|')})"
           )
      return query
    end

    # todo: fix material_code fixity in helper
    # Accepting arrays of each of the non-stop words in author and title
    # composes a query that returns records:
    # 1) with an indexed author entry that _begins_ with an author-word and
    #      _contains_ a title-word in an indexed title entry
    # 2) index title entry begins title word and contains author word in author entry
    #
    #
    def pummel_query(author, title)
      q1 = form_pummel_query('a', author, title)
      q2 = form_pummel_query('t', title, author)
      combined = "(#{q1}\nUNION\n#{q2}"
    end


    # returns a hash of the query results, with an added extracted content
    # field
    #
    # 'tags' contains marc fields and associated subfields to be retrieved
    # it can be a string of a single tag (e.g '130' or '210abnp')
    # or an array of tags (e.g. ['130', '210abnp'])
    # if no subfields are listed, all subfields are retrieved
    # tag should consist of three characters, so '020' and never '20'
    def get_varfields(record_id, tags)
      tags = [tags] unless tags.is_a?(Array)
      makedict = {}
      tags.each do |entry|
        m = entry.match(/^(?<tag>[0-9]{3})(?<subfields>.*)$/)
        marc_tag = m['tag']
        subfields = m['subfields'] unless m['subfields'].empty?
        if makedict.include?(marc_tag)
          makedict[marc_tag] << subfields
        else
          makedict[marc_tag] = [subfields]
        end
      end
      tags = makedict
      tag_phrase = tags.map { |x| "'" + x[0].to_s + "'"}.join(', ')
      query = <<-SQL
      select * from sierra_view.varfield v
      where v.record_id = #{record_id}
      and v.marc_tag in (#{tag_phrase})
      order by marc_tag, occ_num
      SQL
      $c.make_query(query)
      return nil if $c.results.entries.empty?
      varfields = $c.results.entries
      varfields.each do |varfield|
        varfield['extracted_content'] = []
        subfields = tags[varfield['marc_tag']]
        subfields.each do |subfield|
          varfield['extracted_content'] << $c.extract_subfields(varfield['field_content'], subfield, trim_punct: true)
        end
      end
      return varfields
    end

    # returns an array of the field_contents of the requested
    # tags/subfields
    def compile_varfields(record_id, tags)
      varfields = get_varfields(record_id, tags)
      return nil if !varfields
      compiled = varfields.map { |x| x['extracted_content']}
      compiled.flatten!
      compiled.delete("")
      return compiled
    end

    def compile_titles(record_id)
      tags = ['130abnp', '210abnp', '240abnp', '242abnp',
              '245abnp', '246abnp', '247abnp', '730abnp']
      titles = compile_varfields(record_id, tags)
    end
    
    def compile_authors(record_id)
      tags = ['100ac', '110a', '111a', '511a', '700ac',
              '710a', '711a', '245c']
      authors = compile_varfields(record_id, tags)
    end
    
    def extract_subfields(whole_field, desired_subfields, trim_punct: false)
      field = whole_field.dup
      desired_subfields = '' if !desired_subfields
      desired_subfields = desired_subfields.join() if desired_subfields.is_a?(Array)
      # we don't assume anything before a valid subfield delimiter is |a, so remove
      # all from beginning to first pipe
      field.gsub!(/^[^|]*/, '')
      field.gsub!(/\|[^#{desired_subfields}][^|]*/, '') unless desired_subfields.empty?
      extraction = field.gsub(/\|./, ' ').lstrip
      extraction.sub!(/[.,;: \/]*$/, '') if trim_punct
      return extraction
    end
  
    def get_008(record_id)
      query = "select * from sierra_view.control_field where control_num = '8' and record_id = #{record_id} limit 1;"
      $c.make_query(query)
      return '' if $c.results.values.empty?
      m008 = $c.results.values.first[4..43].map{ |x| x.to_s }.join
      return m008
    end

    def get_007s(record_id)
      query = "select * from sierra_view.control_field where control_num = '7' and record_id = #{record_id};"
      $c.make_query(query)
      return [] if $c.results.values.empty?
      m007s = $c.results.values.map { |field| field[4..28].map{ |x| x.to_s }.join }
      return m007s
    end
  
  end
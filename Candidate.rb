

class Candidate
attr_reader :om, :output, :output2, :out

  def initialize(rec_id, options)
    @rec_id = rec_id
    @o = options
    @om = options[:marc_mappings]
    @op = options[:marc_processing]
    @out = options[:output]

  end

  def inspect
    puts output
    rescue ''
  end

  def details
    @details ||= query_details
  end

  def query_details
    @details = []
    detail_query = <<-SQL
      select b.id, brp.material_code, brp.best_title, brp.best_author,
            brp.publish_year, brp.bib_level_code,
            (select STRING_AGG(brl.location_code, '; ')
            from sierra_view.bib_record_location brl
            where brl.bib_record_id = rm.id
            and brl.location_code != 'multi') as locs,
            'b' || rm.record_num || 'a' as bnum
      from sierra_view.bib_record b
      inner join sierra_view.bib_record_property brp on brp.bib_record_id = b.id
      inner join sierra_view.record_metadata rm on rm.id = b.id
      --inner join sierra_view.varfield v on v.record_id = b.id
      --inner join sierra_view.control_field cf on cf.record_id = b.id and cf.control_num = '8'
      where b.id = #{@rec_id}
      and b.bcode3 not in ('d', 'n', 'c')
    SQL
    $c.make_query(detail_query)
    #puts $c.results.entries
    @details = {}
    results = $c.results.entries.first
    results.keys.each { |k| @details[k.to_sym] = results[k].to_s }
    @om.each do |element, fields|
      @details[element] = $c.compile_varfields(@rec_id, fields)
      @details[element] = [] if !@details[element]
    end
    @op.each { |k, v| xform(k, v) }
    #@details[:locs] = sort_locs(prefered_locs: @op[:prefered_locs])
    #process_catalog_number if @details[:catalog_number]
    #extract_isbn if @details[:isbn]
    # todo 260|c date vs 008/brp publish year
    @details[:format] = determine_format
    @details[:publish_year] = get_date
    @details[:author] = process_all_authors
    # pretty author = 245c > 1XXa > b-tag 7XX > a-tag 7XX > a-tag non-marc > [all]author
    @details[:pretty_author] = $c.compile_varfields(@rec_id, '245c').first.to_s
    @details[:pretty_author] = @details[:best_author] if @details[:pretty_author].to_s.empty?
    @details[:pretty_author] = @details[:author].to_s if @details[:pretty_author].to_s.empty?
    # pretty_title = 245abnp > 245abghnp > t non-marc field > t marc field
    @details[:pretty_title] = $c.compile_varfields(@rec_id, '245abnp').first.to_s
    @details[:pretty_title] = @details[:best_title] if @details[:pretty_title].to_s.empty?
    return @details
  end

  def process_catalog_number(orig, nothing)
    m = orig.match(/[^0-9]*([0-9]+)[^0-9]*$/)
    orig = m ? m[1] : ''
    return orig
  end

  def extract_isbn(orig, nothing)
    m = orig.upcase.match(/^[- 0-9X]*/)
    orig = m ? m[0].strip : ''
    return orig
  end

  def xform(k, v)
    orig = @details[k]
    v.each do |funct, params|
      case
      when funct == :strip_text
        @details[k] = orig.map { |x| strip_text(x, params) }
      when funct == :strip_from_tail
        @details[k] = orig.map { |x| strip_from_tail(x, params) }
      when funct == :normalize_isbn
        @details[k] = orig.map { |x| normalize_isbn(x, params) }
      when funct == :extract_isbn
        @details[k] = orig.map { |x| extract_isbn(x, params) }
      when funct == :process_catalog_number
        @details[k] = orig.map { |x| process_catalog_number(x, params) }
      when funct == :sort_locs
        @details[k] = sort_locs(orig, params)
      end 
    end
    @details[k].uniq!
  end

=begin
  def roman(title)
    /c?m{,3}?d?   /
    /(cm|m{,3})?d?(xc|c{,3})?l?(ix|x{,3})v?/

    if (r == 'I')
      return 1;
  if (r == 'V')
      return 5;
  if (r == 'X')
      return 10;
  if (r == 'L')
      return 50;
  if (r == 'C')
      return 100;
  if (r == 'D')
      return 500;
  if (r == 'M')
      return 1000;
  end
=end


  def strip_text(orig, phrases_to_remove)
    phrases_to_remove.each do |phrase|
      orig.gsub!(/ ?\b#{phrase}\b/i, '')
    end
    return orig
  end

  def strip_from_tail(orig, phrases_to_remove)
    old = ''
    new = orig
    until new == old
      old = new.dup
      phrases_to_remove.each do |phrase|
        new.gsub!(/ ?\b#{phrase}\b[^\w]*$/i, '')
      end
    end
    return new
  end

  def normalize_isbn(orig, nothing)
    orig.gsub!(/[[:punct:]]/, '')
    return orig.upcase
  end

  def process_all_authors
    return [] if @details[:author].empty?
    processed = []
    @details[:author].each do |author|
      author.gsub!(/Performed by ?/i, '')
      author.gsub!(/\((Male |Female )?Musical group\)/i, '')
      processed << author
    end
    if @details[:author].any? { |x| x=~ /Various/i } && @o[:options][:plain_various]
      processed << 'Various'
    end
    return processed.uniq
  end


  def sort_locs(locs, prefered_locs: [])
    prefered_locs = [] if !prefered_locs
    locs = locs.split('; ').sort!
    return locs.join('; ') if prefered_locs.empty?
    pref_first_locs = locs.select { |loc| prefered_locs.include?(loc) }
    pref_first_locs << locs.reject { |loc| prefered_locs.include?(loc) }
    return pref_first_locs.flatten
  end

  def parse_format(arry)
    return '' if arry.empty?
    return arry.join('; ') if arry.length > 1
    str = arry.first
    case
    when str.match(/score/)
      return "score"
    when str.match(/compact disc/)
      return "audio cd"
    when str.match(/(online|electronic) resource/)
      return "online"
    when str.match(/(audio|sound) disc.*analog/)
      return "audio lp"
    #TODO: care about 78, 33.1/3?
    when str.match(/(audio|sound) disc.*digital/)
      return "audio cd"
    when str.match(/33.*rpm/)
      return "audio lp"
    when str.match(/78.*rpm/)
      return "audio lp"
    when str.match(/4 3\/4 in\./)
      if str.match(/video ?disc|DVD/)
        return "dvd"
      elsif str.match(/audio ?disc|CD/)
        return "audio cd"
      else
        return "cd/dvd"
      end
    when str.match(/music/)
      return "music"
    when str.match(/microfilm/)
      return "microfilm"
    end
    return str
  end


  def output
    output = []
    @out.each { |k, v| output << output_value(k, v) }
    return output
  end

  def output_value(k, v)
    return '' if ( !@details[k] || @details[k].empty?)
    value = @details[k].dup
    value = value.uniq.join('; ') if v == :join
    return value
  end

  def get_date
    sierra_pub_year = @details[:publish_year]
    @details[:m008] ||= $c.get_008(@details[:id])
    date1_008 = @details[:m008][7..10] if @details[:m008]
    date1_008 || sierra_pub_year
  end

  # mappings [mostly] stolen from args_extract.pl
  def determine_format
    blvl = @details[:bib_level_code]
    mat_type = @details[:material_code]
    @details[:m008] ||= $c.get_008(@details[:id])
    @details[:m007s] = $c.get_007s(@details[:id])
    m008 = @details[:m008]
    m007s = @details[:m007s]
    # format is initially set based on III Material Type
    bcodes = {
              "0" => "Motion Picture Reel",         
              "1" => "Microfiche",       
              "3" => "Slide Set",         
              "7" => "Geospatial Data",     
              "8" => "Statistical Dataset",     
              "9" => "Electronic Audio Book",       
              "a" => "a",
              "b" => "Archival Material",      
              "c" => "Printed Music",       
              "d" => "Printed Music",        
              "e" => "Map",      
              "f" => "Map",       
              "g" => "Videos and DVDs",      
              "h" => "Microfilm",       
              "i" => "Audio",      
              "j" => "Music",    
              "k" => "Art",     
              "m" => "Software",        
              "o" => "Kit",      
              "p" => "Archival Material",    
              "r" => "Realia",      
              "s" => "Electronic Journal",
              "t" => "Thesis",        
              "w" => "Internet Resource",        
              "z" => "eBook"
    }
    format = bcodes[mat_type]

    m007_00s = []
    m007_01s = []
    m007_03s = []
    m007_04s = []
    m007s.each do |m007|
      m007_00s << m007[0]
      m007_01s << m007[0] + m007[1]
      m007_03s << m007[0] + m007[3]
      m007_04s << m007[0] + m007[4]
    end

    # Further format mappings when III material type = a (printed material)
    if format == "a"
      if m008[21] == "p"
        format = "Journal"
      elsif m008[21] == "n"
        format = "Newspaper"
      elsif (blvl == "s" || blvl == "b") && m007_01s.any? { |x| x == 'cr' }
        #TODO:multiple m007s
        format = "Electronic Journal"
      elsif blvl == "s" || blvl == "b"
        format = "Serial"
      elsif m008[23] == "c"
        format = "Micro-opaque"
      elsif m008[23] == "b"
        format = "Microfiche"
      elsif m008[23] == "a"
        format = "Microfilm"
      elsif m007_00s.any? { |x| x == 'h' }
        format = "Microform"
      else
        format = "Book"
      end
    
    elsif format == "Audio" || format == "Music"
      if m007_01s.any? { |x| x == 'ss' }
        format += " cassette"
      elsif m007_03s.any? { |x| x == 'sf' }
        format += " CD"
      elsif m007_03s.any? { |x| x =~ /s[abcde]/ }
        format += " vinyl record"
      elsif m007_01s.any? { |x| x == 'st' }
        format += " reel to reel tape"
      elsif m007_01s.any? { |x| x == 'cr' }   #not in args extract
        format = 'Online Music'
      end
    
    elsif format == "Videos and DVDs"
      if mat_type == 'g' && m008[33] == 'f'
        format = 'Filmstrip'
      elsif mat_type == 'g' && m008[33] == 's'
        format = 'Slides'
      elsif m007_04s.any? { |x| x == 'vg' }
        format = 'Laserdisc' 
      elsif m007_04s.any? { |x| x ~ /v[hbn]/ }
        format = 'Video cassette'
      elsif m007_04s.any? { |x| x == 'vv' }
        format = 'Video DVD'
      elsif m007_04s.any? { |x| x == 'vg' } || m007_01s.any? { |x| x == 'cr' }
        format = 'Online Video'
      elsif m007_04s.any? { |x| x == 'vs' }
        format = 'Blu-ray Disc'
      elsif m007_01s.any? { |x| x == 'mr' }
        format = 'Motion Picture Reel'
      end

    elsif format == "Microfilm"
      if blvl == "s" && m008[21] == "n"
        format = "Newspaper"
      end
    end
    suppl = parse_format(@details[:suppl_material]) if @details[:suppl_material]
    return "#{format} with suppl. #{suppl}".strip if suppl && !suppl.empty?
    return format
  end

end
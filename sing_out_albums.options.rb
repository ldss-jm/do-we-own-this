
work_comp =
  Proc.new do |scores|
    a_score = [scores[:author], scores[:alt_author]].max
    t_score = [scores[:title], scores[:alt_title]].max
    p_score = scores[:publisher]
    stdnum_score = scores[:catalog_number]
    composite = (
      a_score**2 +
      t_score**2 +
      [a_score, t_score].min**1.5 +
      p_score/5 +
      ([p_score, 0.1].max * stdnum_score * 3)
    )/3.2
    # return:
    composite
  end

ed_comp = 
  Proc.new do |scores|
    p_score = scores[:publisher]
    stdnum_score = scores[:catalog_number]
    composite = (
      (p_score**2 +
      stdnum_score*1.5
      )/1.5
    )*work_comp.call(scores)
    # return
    composite
  end

format_comp =
  Proc.new do |scores|
    #format
    stdnum_score = scores[:catalog_number]
    composite = (
      [stdnum_score, 0.3].max
    )*ed_comp.call(scores)/1
    # return
    composite
  end

  #soft-strip: ["Collector's Edition", 'Album', 'Live']
OPTIONS = {
  input_mappings: {
    id: 'ALBUMID',
    title: 'ALBUM',
    author: 'ARTIST',
    #todo: make this work with an array - it should now
    publisher: ['RLBL', 'Alt Label'],
    catalog_number: 'CATALOG'
  },
  input_transforms: {
    :title => {strip_text: ['-0-']},
    :author => {strip_text: ['N/A'], split_camelcase: ''},
    #todo: make strip_text strip from end only, check sierra counterparts to see if should strip music.
    :publisher => {strip_from_tail: ['Records', 'Recording', 'Recordings']},
  },
  candidate_sql: {
    mattype_is: "in ('i', 'j', '4', '5', '6')",
    #bib_loc_is: #for future, not for this
    queries: {
      a: [:author, :alt_author],
      t: [:title, :alt_title],
      # sierra tends to have the cat numbers in as ck47307ck47308columbialegacy
      # and lacking the initial pub code, we probably don't want to search them
    }


  },
  whitelisted_terms: {
    a: ['brahms johannes', 'brahms', 'schumann', 'brown', 'johnson', 'lewis',
       'rose', 'armstrong', 'jackson', 'wilson', 'scott', 'anderson', 'james',
        'verdi giuseppe', 'ellington duke', 'martin', 'young', 'bartok bela',
        'williams', 'london symphony orchestra', 'stravinsky igor', 'bernstein leonard',
        'london philharmonic orchestra', 'mozart wolfgang amadeus'
    ],
    t: ['live', 'blues', 'songs', 'music', 'jazz', 'piano', 'best of',
        'american music', 'best'
    ]
  },
  marc_mappings: {
    title: ['130abnp', '210abnp', '240abnp', '242abnp',
                '245a', '245abnp', '246abnp', '247abnp', '730abnp', '130a'],
    author: ['100ac', '110a', '111a', '511a', '700ac',
              '710a', '711a', '245c', '100a', '700a'],
    publisher: ['260b', '028b'],
    catalog_number: ['028a'],
    m300: ['300'],
    suppl_material: ['300e'],
    sn: ['028']
    #isbn: ['020a']

  },
  marc_processing: {
    publisher: {strip_from_tail: ['Records', 'Inc', 'Recordings', 'Music']},
    catalog_number: {process_catalog_number: ''},
    #isbn: {extract_isbn: ''},
    locs: {sort_locs: {prefered_locs: ['wa']}}
  },
  options: {
    number_title: true,  # try convert text to numerals?
    text_title: true,     # try convert numerals to text?
    number_author: true,
    text_author: true,
    plain_various: true, #any "Various X" authors, add "Various"
    surname_parse: true,
    split_authors: true,
    commas_split: true,
    split_titles: true,
    best_threshold: 0.4,
    vol_detect: true,
    cand_search_limit: 500,
  },
  matching: {
    # name: [known's field, cand's field, weight ]
    author: [:author, :author, 1.0],
    title: [:title, :title, 1.0],
    publisher: [:publisher, :publisher, 1.0],
    catalog_number: [:catalog_number, :catalog_number, 1.0, :exact],
    alt_author: [:alt_author, :author, 0.9],
    alt_title: [:alt_title, :title, 0.8]
  },
  composite_formula: {
    work: work_comp,
    #edition: ed_comp,
    #format: format_comp
  },
  output: {
    locs: :join,
    bnum: '',
    pretty_title: '',
    pretty_author: '',
    publisher: :join,
    catalog_number: :join,
    #inum,
    format: '',
    publish_year: '',
    sn: :join,
    title: :join,
    author: :join,
    #todo what matched, where's it from
  },
  output_known: [:id, '', '', '', :id, :title, :author, :publisher, :catalog_number, 'LP', 'COMD', 'CASS'],
  headers: ['id', 'locs', 'bnum', 'wk_score', 'id.', 'title', 'author', 'label', 'catalog_number',  'LP / format', 'CD / date', 'CASS / m028', 'all_titles', 'all_authors', 'matches_reported', "known's_best"]
  
}



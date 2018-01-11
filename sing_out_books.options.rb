
work_comp =
  Proc.new do |scores|
    a_score = [scores[:author], scores[:alt_author]].max
    t_score = [scores[:title], scores[:alt_title]].max
    p_score = scores[:publisher]
    isbn_score = scores[:isbn]
    lccn_score = scores[:lccn]
    composite = (
      a_score +
      t_score**2 +
      [a_score, t_score].min**2 +
      isbn_score +
      lccn_score +
      p_score/3
    )/2.5
    # return:
    composite
  end

  ed_comp = ''
  format_comp = ''
OPTIONS = {
  input_mappings: {
    :id => 'BOOKID',
    :title => 'TITLE',
    :author => 'AUTHORS',
    :publisher => 'PUBLISHR',
    :isbn => 'ISBN',
    :lccn => 'LCCN',
    :date => 'YEAR'
  },
  input_transforms: {
    :author => {strip_text: ['N/A']},
    :publisher => {strip_text: ['N/A'],
                  strip_from_tail: ['Press', 'Publishing', 'Inc', 'Company', 'Publications', 'Ltd', 'Co']
                },
    :isbn => {strip_text: ['N/A'], normalize_isbn: '', both_10_and_13: ''},
    :lccn => {strip_text: ['N/A'], normalize_isbn: ''}
  },
  candidate_sql: {
    mattype_is: "in ('a', 'b', 'c', 'd', 'z')",
    queries: {
      a: [:author, :alt_author],
      t: [:title, :alt_title],
      i: [:isbn, :lccn]


    }

  },
  whitelisted_terms: {
    a: ['adams john', 'arthur', 'bell', 'harper'],
    t: ['heritage', 'reflections', 'village']
  },
  marc_mappings: {
    title: ['130abnp', '210abnp', '240abnp', '242abnp',
                '245abnp', '245a', '246abnp', '247abnp', '730abnp', '130a'],
    author: ['100ac', '110a', '111a', '511a', '700ac',
              '710a', '711a', '245c', '100a', '700a'],
    publisher: ['260b'],
    m300: ['300'],
    suppl_material: ['300e'],
    isbn: ['020a'],
    lccn: ['010a'],
    place: ['260a']

  },
  marc_processing: {
    lccn: {normalize_isbn: ''},
    :publisher => {strip_from_tail: ['Press', 'Publishing', 'Inc', 'Company', 'Publications', 'Ltd', 'Co']},
    # isbn?
    # pub? 
    locs: {sort_locs: {prefered_locs: ['wa']}}
  },
  options: {
    number_title: true,  # try convert text to numerals?
    text_title: true,     # try convert numerals to text?
    surname_parse: false,
    split_authors: true,
    commas_split: false,
    split_titles: true,
    best_threshold: 0.4,
    vol_detect: true,
    cand_search_limit: 1000,
  },
  matching: {
    # name: [known's field, cand's field, weight ]
    author: [:author, :author, 1.0],
    title: [:title, :title, 1.0],
    publisher: [:publisher, :publisher, 1.0],
    isbn: [:isbn, :isbn, 1.0, :exact],
    lccn: [:lccn, :lccn, 1.0, :exact],
    alt_author: [:alt_author, :author, 0.8],
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
    publish_year: '',
    #inum,
    isbn: :join,
    lccn: :join,
    place: :join,
    format: '',
    m300: :join,
    spacer: '',
    title: :join,
    author: :join,
    #todo what matched, where's it from
  },
  output_known: [:id, '', '', '', :id, :title, :author, :publisher, :date, :isbn, :lccn, 'PLACE', 'CONTENTS', 'REMARKS', 'MUSICFLAG'],
  headers: ['id', 'locs', 'bnum', 'wk_score', 'id.', 'title', 'author', 'publisher', 'date', 'isbn', 'lccn', 'place', 'contents/format', 'remarks/m300', 'musicflag', 'all_titles', 'all_authors', 'matches_reported', "known's_best"]
}



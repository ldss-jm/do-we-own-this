
Introduction
------------
Takes a title list containing "known records," finds possible "candidate matches" in iii's Sierra ILS, scores the candidate matches for the likelihood they are a match, and returns a list of the known records and their candidate matches (if any) above a specified threshold.

Only matching at the work level was implemented decently, but ability to match at the edition or format level is intended as well.

Is dependent on https://github.com/ldss-jm/postgres_connect and most of the content of this Connect.rb is being pushed into postgres_connect.

This was written to work and never sufficiently cleaned up or improved. Cleanup and improvement should slowly happen; or happen abruptly if another use case pops up for us.


options/config file
-------------------
The options file gives the script instructions on how to interpret and clean fields in an incoming title list, which marc fields to look at for comparison and how to clean them, scoring options/weights/formulas, and output. See sing_out_albums.options.rb or sing_out_books.options.rb for examples.

The options are stored as a hash in an .rb file in order to be able to specify/store scoring procs.

- input_mappings
  - maps fields from the known record title list (e.g. 'ALBUM') onto standard fields (e.g. :title)
- input_transforms
  - gives instructions on how to clean standard fields from the known records
- candidate_sql
  - defines restrictions (e.g. mat_type, bib_loc) for sql candidate queries and defines which sierra index to search for terms from a given standard field
- whitelisted_terms
  - terms listed here are allowed to exceed the cand_search_limit
- marc_mappings
  - maps Sierra marc fields/subfields into standard fields for candidate records
- marc_processing
  - gives instructions on how to clean standard fields from the candidate records
- options
  - number_title: true,   # try convert text to numerals?
  - text_title: true,     # try convert numerals to text?
  - number_author: true,
  - text_author: true,
  - plain_various: true,  # any "Various X" authors, add "Various"
  - surname_parse: true,  # Pat Smith -> Smith, Pat
  - split_authors: true,  # try Pat Smith and Pat Jones -> [Pat Smith, Pat Jones]
  - commas_split: true,   # if split_authors: Pat Smith, Pat Jones -> [Pat Smith, Pat Jones]
  - split_titles: true,   # things like 'Book: the novel' -> ['Book', 'the novel']
  - best_threshold: 0.4,  # candidates below this threshold will not be reported
  - vol_detect: true,     # ?
  - cand_search_limit: 500, # if not specified 10,000
- matching
  - defines a known record field and a candidate field to compare/score and the
  weight for that score
  - comparison is normally a fuzzy match score, but the :exact option requires an exact match
- composite_formula
  - specifies which proc to use for composite work (or edition or format) score
- output
  - output fields/options for candidate records
- output_known
  - output fields for known records
- headers
  - output headers

### input_transforms, marc_processing
At the moment these have separate pools of transform functions (including duplicate copies of the same function) and eventually those would be united into a common pool.

known records:
- strip_text
  - e.g. Apple Publishing -> Apple
  - and: Publishing is Great Company -> is Great Company
- strip_from_tail
  - e.g. Apple Publishing -> Apple
  - but: Publishing is Great Company -> Publishing is Great Company
- normalize_isbn
  - remove spaces/dashes/text?
- both_10_and_13 -- not implemented afaik
  - derive other form of isbn from given form
- split_camelcase
  - PatSmith -> Pat Smith


candidate records:
- strip_from_tail
  - see above
- normalize_isbn
  - see above
- sort_locs / prefered_locs
  - sorts bib locations (alphabetically) and allows prefered locations to come first
- process_catalog_number
  - maybe: SH-CD-9102 -> 9102


Scoring procs

work_comp - formula to calculate a composite match score (at the work level) using the scores from various field comparisons. Higher is better.

ed_comp, format_comp - intended to score likelihood of edition/format match

require 'csv'
load '../postgres_connect/connect.rb'
require 'i18n'
require 'fuzzy_match'
load 'Connect.rb'
I18n.available_locales = [:en]



def remove_punct(str)
  str = str.gsub('&', ' and ') # we need the spaces around and; dupe spaces will be removed
  # manually define punctuation to be removed, since some needs to be kept
  # keep:
  #   +%$#@
  # remove:
  str = str.gsub(/["']/, '')
  # replace with spaces:
  str = str.gsub(/[!\&'()*,\-.\/:;<=>?\[\\\]^_`{|}~]/, ' ').rstrip
  str.gsub(/  +/, ' ').lstrip
end

def pad_numbers(str)
  # return a str padded on the left with spaces, to eight chars
  # return str if longer than 8 chars
  # matches sierra number indexing
  regexp = /
    (?<![\+#$])             # not when preceded by these chars
    \b
    ([0-9]+)                # main number block, which gets justified
    ([^ [:digit:]][^ ]*)?   # subsequent attached chars, which we dont justify
  /x
  str.gsub(regexp) do |match|
    $2 ? $1.rjust(8, ' ') + $2 : $1.rjust(8, ' ')
  end
end

def trunc_str(str)
  # truncate str so it's less than 124 chars, and don't let it break any
  #   words (i.e. drop any resulting word fragments)
  # strings with many multibyte chars get more heavily truncated
  #   elsewhere. 123 seems fine for general records. e.g. where 123
  #   doesn't work 4954879 (but elsewhere-truncation does)
  return str if str.length < 124
  str = str[0..123].
    split(/\b/)[0..-2].
    join('').
    rstrip
end

def index_normalize(str)
  # moved the a/an/the gsub up; it seems like "a' go go" should prp be indexed as
  # "a go go." So, remove /(a|an|the) /, then remove punct
  str = str.dup.downcase.
    gsub(/\u02B9|\u02BB|\uFE20|\uFE21/, '') # remove select punct
  str = I18n.transliterate(str)
  str = str.gsub(/^(a|an|the) /i, '')
  str = pad_numbers(remove_punct(str.downcase))
  trunc_str(str)
  #TODO: fail if not confident of normalizing
end

def match_normalize(str)
  str = str.dup.downcase.strip
  str = I18n.transliterate(str)
  str = str.gsub(/^(a|an|the) /, '')
  str = remove_punct(str.downcase)
  return str
  #TODO: fail if not confident of normalizing
end

def bmatch(needle, haystack, normalize: true)
  if normalize
    needle = match_normalize(needle)
    haystack.map! { |x| match_normalize(x)}
  end
  matcher = FuzzyMatch.new(haystack, find_with_score: true)
  return matcher.find(needle)
end

def print_comp(score)
  return '' if !score
  return sprintf("%#.3f", score)
end

def best_string(best)
  begin
  best_score = best[0][1][:comp_score][:work]
  rescue
  end
  best_string =
  case
  when !best_score
    "4 - has nothing"
  when best_score >= 0.9
    "1 - has likely"
  when best_score < 0.6
    "3 - has unlikely"
  else
    "2 - has maybe"
  end
  best_string
end

def best_is(best)
  text = "#{best_string(best)[0]}'s best"
  text.gsub("4's", "no")
end
#################
#################
#################
#################
#################
#################
#################
#################
#################
#################

$c.close if $c
$c = Connect.new
$candidates = {}
load 'Connect.rb'
load 'KnownRecord.rb'
load 'Candidate.rb'
load 'MatchScore.rb'
load 'CandidateSet.rb'




$candidates = {}
class KnownRecord
  @@seen = $candidates
end

load 'sing_out_albums.options.rb'
filename = 'albums.source.txt'

#load 'sing_out_books.options.rb'
#filename = 'books.txt'


options = OPTIONS
recs = CSV.read(filename, headers: true, col_sep: "\t",
        encoding: 'windows-1251:utf-8').map {|x| KnownRecord.new(x, options)}

i=0
CSV.open(filename + '.out', 'w') do |csv|
  csv << options[:headers] if options[:headers]
  recs.each do |rec|
    puts [i, rec.my[:id], rec.my[:author], rec.my[:title]]
    rec.search
    best = rec.candidates.best_candidates
    csv << rec.output + [
           rec.terms_searched['t'].to_a.join('; '),
           rec.terms_searched['a'].to_a.join('; '),
           best.to_a.length,
           #best_string(best),
           best_is(best)
          ].flatten
    
    if best
      best.each do |k, v|
        scores = v[:comp_score]
        csv << [rec.my[:id], v[:obj].output[0..1], print_comp(scores[:work]),
                #print_comp(scores[:edition]), print_comp(scores[:format]),
                '', v[:obj].output[2..-1], '',
                #'0 - candidate',
                best_is(best)
              ].flatten
      end
    end
    i += 1
  end
end


=begin

#todo before results
>500 results
report locations w/unsupp copies ??
scoring tweaks
scoring options, partial ratio etc.



#change it so procs can be done on indl marc fields
# convert lastname, firstnames 700a -> firstname lastname


title
# so something to improve volume matching or unmatching
#need to remove la le etc?
# how do roman numerals get indexed?
# try also with removing roman numerals
#conver troman numerals to numbers; let text-title also convert to text
# try alt title if title still begins with a?
#soft-stripping to get title minus text into alt-title before cand search
# if we isolate the volume in:
#  Sounds of Alaska Vol II  The Story of Pat O'Donnell
# also split title into alt_titles:
#     Sounds of Alaska
#    The Story of Pat O'Donnell
# do some kind of vol matching?
  #split on presents?
  #try dropping final numbers/punct: Live at Harvard Crimson Network, 2/27/47

#artist
# drop a/an/the la?
# if title list has various, count artist match less?
=end


#input lccns, dash -> 0 ?


#do something with > 500 entries
# check term$ or term[space]
# check term$
# (phe.index_tag || phe.index_entry) ~ '^al ' or (phe.index_tag || phe.index_entry) = 'al'
# cross search

#look for name see froms etc?



#work/edition/format scoring
#other source when fail

#anything re: # see also format from 347-ish. e.g.b30973168

#report locations with unsuppressed copies rather than any loc

#todo why just music format
#4064	er; es; ul	b6621945a	0.431	0	0		Where have all the flowers gone the songs of Pete Seeger	Seeger, Pete, 1919-2014.	appleseed recordings		Music

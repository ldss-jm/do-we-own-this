require 'set'


class CandidateSet
attr_accessor :data, :o, :thing, :knownrecord_iffiness


  def initialize(options)
    #
    @o = options
    @data = {}
    # for uncertainty resulting from traits of the known record, for all
    # candidates in this set, comp_score == comp_score times the below
    @knownrecord_iffiness = 1.0
  end

  def ids
    @data.keys
  end

  def inspect
    ids
  end

  def list
    lst = []
    @data.each do |k, v|
      v[:id] = k
      lst << v
    end
    return lst
  end

  def update_ids(incoming_hash)
    @data.update(incoming_hash) do |key, old, new|
      old.update(new) { |k, o, n| (o += n).flatten.uniq }
    end
  end


  def cand_best_scores(candidate)
    mybest = {}
    @o[:matching].keys.each do |name|
      mybest[name] = candidate[:scores].select { |x| x && x.name == name }.
                    max_by { |x| x.weighted}
    end
  return mybest
  end
    

  def composite_score(scores_only, name)
    base_comp = @o[:composite_formula][name].call(scores_only)
    return base_comp * @knownrecord_iffiness if base_comp
  end

  def best_candidates #
    o = @o[:options]
    first_n = o.include?(:first_n) ? o[:best_first_n] : 0
    threshold = o.include?(:best_threshold) ? o[:best_threshold] : 0.4
    @data.each do |k, v|
      v[:best_scores] = cand_best_scores(v)
      scores_only = {}
      scores_only.default=0
      v[:best_scores].each do |k, v|
        scores_only[k] = v.weighted if v
      end
      @o[:composite_formula].keys.each do |name|
        v[:comp_score][name] = composite_score(scores_only, name)
      end
    end
    sorted = @data.sort_by { |k,v| -v[:comp_score][:work] }
    return nil if sorted.empty?
    if first_n == 0
      results = sorted.select { |x| x[1][:comp_score][:work] > threshold }
    else
    results = sorted[0..first_n - 1] +
              sorted[first_n..-1].select { |x| x[1][:comp_score][:work] > threshold }
    end
    return results
   end


end





=begin
  def best_scores(a)
    @thing = {}
    @o[:matching].keys.each do |name|
      @thing[name] = a[:scores].select { |x| x && x.name == name }.
                    max_by { |x| x.weighted}
    end

    best = {}
    best[:author] = a[:scores].select { |x| x && x.term_source == 'author' }.
                               max_by { |x| x.weighted}
    best[:title] = a[:scores].select { |x| x && x.term_source == 'title' }.
                               max_by { |x| x.weighted}
    best[:publisher] =
      a[:scores].select { |x|x &&  x.term_source == 'publisher' }.
                 max_by { |x| x.weighted}
    best[:stdnum_catalog] =
      a[:scores].select { |x| x && x.term_source == 'stdnum_catalog' }.
                 max_by { |x| x.weighted}
    best[:alt_author] =
      a[:scores].select { |x| x && x.term_source == 'alt_author' }.
                 max_by { |x| x.weighted}
    best[:alt_title] =
      a[:scores].select { |x| x && x.term_source == 'alt_title' }.
                 max_by { |x| x.weighted}

scores_only = {}
scores_only.default=0
#best.each do |k, v|
thing.each do |k, v|
  scores_only[k] = v.weighted if v
end
#return best, scores_only
return thing, scores_only
end


def composite_score(best, scores_only)
scores = scores_only
a_score = [scores[:author], scores[:alt_author]].max
t_score = [scores[:title], scores[:alt_title]].max
p_score = scores[:publisher]
stdnum_score = scores[:stdnum_catalog]
composite = (
  a_score**2 +
  t_score**2 +
  [a_score, t_score].min**2 +
  p_score/5 +
  (p_score * stdnum_score * 3)
)/3.2
  # todo if pub score is 0 still give stdnum_score
return composite
end

def best(first_n: 0, threshold: 0.4)
@data.each do |k, v|
  best, scores_only = best_scores(v)
  v[:comp_score] = composite_score(best, scores_only)
end
sorted = @data.sort_by { |k,v| -v[:comp_score] }
return nil if sorted.empty?
if first_n == 0
  results = sorted.select { |x| x[1][:comp_score] > threshold }
else
results = sorted[0..first_n - 1] +
          sorted[first_n..-1].select { |x| x[1][:comp_score] > threshold }
end
return results
end

=end
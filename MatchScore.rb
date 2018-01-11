

class MatchScore
attr_reader :score, :weight, :name,
            :term, :match, :weighted

  def initialize(hsh)
    @score = hsh[:score]
    @weight = hsh[:weight]
    @name = hsh[:name]
    @term = hsh[:term]
    @match = hsh[:match]
    @weighted = @score * @weight
  end

end

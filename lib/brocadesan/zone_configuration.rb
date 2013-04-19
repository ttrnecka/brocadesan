# Zone Configuration model
class ZoneConfiguration
  # returns name of the zone configuration
  attr_reader :name
  
  # init method
  def initialize(name,opts={})
      @name=name
      @opts=opts
  end
end
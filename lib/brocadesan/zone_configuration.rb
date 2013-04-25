# Zone Configuration model
class ZoneConfiguration
  # returns name of the zone configuration
  attr_reader :name
  
  # true if configuration is effective, false if defined
  attr_reader :effective
  
  # array of all zones members
  
  attr_reader :members
  
  # init method
  def initialize(name,opts={})
    @name=name
    @members=[]
    @effective=opts[:effective].nil? ? false : opts[:effective] 
  end
end
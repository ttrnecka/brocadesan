# Zone Configuration model
class ZoneConfiguration
  # returns name of the zone configuration
  attr_reader :name
  
  # true if configuration is effective, false if defined
  attr_reader :effective
  
  # init method
  def initialize(name,opts={})
      @name=name
      @effective=opts[:effective].nil? ? false : opts[:effective] 
  end
end
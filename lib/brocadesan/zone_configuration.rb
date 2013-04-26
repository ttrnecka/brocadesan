module Brocade module SAN
  
# Zone Configuration model
class ZoneConfiguration
  # returns name of the zone configuration
  attr_reader :name
  
  # true if configuration is effective, false if defined
  attr_reader :effective
  
  # init method
  def initialize(name,switch,opts={}) # :nodoc:
    if switch.class==Switch
      @switch=switch
    else
      raise Switch::Error.new("#{switch} is not instance of SanSwitch!!!")
    end
    @switch=switch if switch.class==Switch
    @name=name
    @effective=opts[:effective].nil? ? false : opts[:effective] 
  end
  
  # returns array of members
  
  def members
    @switch.zone_configurations(true) if @switch.configuration[:defined_configuration][:cfg][self.name].empty?
    @switch.configuration[:defined_configuration][:cfg][self.name]
  end
end

end; end
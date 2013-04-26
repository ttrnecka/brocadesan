module Brocade module SAN
  
# Zone model
class Zone
  # returns name of the zone
  attr_reader :name
  
  # true if zone is active / member of effective ZoneConfiguration
  attr_reader :active
   
  # init method
  def initialize(name,switch,opts={}) # :nodoc:
    if switch.class==Switch
      @switch=switch
    else
      raise Switch::Error.new("#{switch} is not instance of Switch!!!")
    end
    @switch=switch if switch.class==Switch
    @name=name
    @active=opts[:active].nil? ? false : opts[:active] 
  end
  
  # returns array of members
  
  def members
    switch.zones if @switch.configuration[:defined_configuration][:zone][self.name].empty?
    @switch.configuration[:defined_configuration][:zone][self.name]
  end
end

end; end
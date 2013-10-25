module Brocade module SAN
  
# Zone Configuration model
class ZoneConfiguration
  # returns name of the zone configuration
  attr_reader :name
  
  # true if configuration is effective, false if defined
  attr_reader :effective
  
  # init method
  def initialize(name,opts={}) # :nodoc:
    Switch::verify_name(name)
    @name=name
    @effective=opts[:effective].nil? ? false : true
    @members=[] 
  end
  
  # returns array of members
  
  def members
    @members
  end
  
  # add member to the object
  # members of zone configurations are zones
  # +member+ is name of the zone
  def add_member(member)
    Switch::verify_name(member)
    @members<<member
  end
  
end

end; end
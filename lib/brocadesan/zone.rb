module Brocade module SAN
  
# Zone model
class Zone
  # returns name of the zone
  attr_reader :name
  
  # true if zone is active / member of effective ZoneConfiguration
  attr_reader :active
  
  # member naming rule
  # member can be anything that match Switch::NAME_RULE
  # or WWN or Domain,Index port notation
  # allowed examples:
  #
  # 50:00:10:20:30:40:50:60
  #
  # 2,61
  #
  # alias_test_3
  
  MEMBER_RULE='([\da-f]{2}:){7}[\da-f]{2}|\d{1,3},\d{1,3}|' << Switch::NAME_RULE
   
  # verifies if +str+ matches convetion defined in Zone::MEMBER_RULE
  # raises Switch::Error: Incorrect name format if not
  # this method is used internally mostly
    
  def self.verify_member_name(str)
    raise Switch::Error.incorrect("#{str}") if !str.match(/#{MEMBER_RULE}/i)
  end
  
  # init method
  def initialize(name,opts={}) # :nodoc:
    Switch::verify_name(name)
    @name=name
    @active=opts[:active].nil? ? false : opts[:active]
    @members=[] 
  end
  
  # returns array of members
  
  def members
    @members
  end
  
  # add member to the object
  # members of zones are aliases, wwns or D,I notation
  # +member+ is name of the member  
  def add_member(member)
    Zone::verify_member_name(member)
    @members<<member
  end
  
  def to_s
    @name
  end
  
end

end; end
module Brocade module SAN
  
# Alias model
class Alias
  # returns name of the alias
  attr_reader :name
  
  # member naming rule
  # member ca be WWN or Domain,Index port notation
  # allowed examples:
  #
  # 50:00:10:20:30:40:50:60
  #
  # 2,61
  
  MEMBER_RULE='([\da-f]{2}:){7}[\da-f]{2}|\d{1,3},\d{1,3}'
  
  # verifies if +str+ matches convetion defined in Alias::MEMBER_RULE
  # raises Switch::Error: Incorrect name format if not
  # this method is used internally mostly
    
  def self.verify_name(str)
    raise Switch::Error.new("Incorrect name format \"#{str}\"") if !str.match(/#{MEMBER_RULE}/i)
  end
   
  # init method
  def initialize(name,opts={}) # :nodoc:
    Switch::verify_name(name)
    @name=name 
    @members=[]
  end
  
  # returns array of members  
  
  def members
    @members
  end
  
  # add member to the object
  # members of aliasese are WWNs or Domain,Index port notation
  # +member+ is name of the zone
  # return all memebers, otherwises raises error
  
  def add_member(member)
    Alias::verify_name(member)
    @members<<member
  end
  
end

end; end
module Brocade module SAN
  
# Alias model
class Alias
  # returns name of the alias
  attr_reader :name
  
  # alias member naming rule (regular expresion)
  #
  # member can be WWN or Domain,Index port notation
  #
  # allowed examples:
  #
  # 50:00:10:20:30:40:50:60
  #
  # 2,61
  
  MEMBER_RULE='([\da-f]{2}:){7}[\da-f]{2}|\d{1,3},\d{1,3}'
  
  # inititialize new alias with +name+
  #
  # +opts+ reserved for future use
  def initialize(name,opts={})
    # checked against alias name rule - not alias member
    Switch::verify_name(name)
    @name=name 
    @members=[]
  end
  
  # returns array of members  
  
  def members
    @members
  end
  
  # add new member to the alias
  #
  # members of aliases are WWNs or Domain,Index port notation
  #
  # +member+ is name of the zone
  #
  # return all members, otherwises raises error
  
  def add_member(member)
    Alias::verify_member_name(member)
    @members<<member
  end
  
  # verifies if +str+ matches convetion defined in Alias::MEMBER_RULE
  #
  # raises Switch::Error: Incorrect name format "+str+" if not
  #
  # this method is used mostly internally
    
  def self.verify_member_name(str)
    raise Switch::Error.incorrect(str) if !str.match(/#{MEMBER_RULE}/i)
  end
end

end; end
module Brocade module SAN
  
# Wwn model
class Wwn
  # returns value of the WWN
  attr_reader :value
  
  # description of WWN is provided by device itself
  
  attr_reader :symbol
  
  # device type - usualy target or initiator
  
  attr_reader :dev_type
  
  # port index where wwn is located
  
  attr_reader :port_index
  
  # domain of switch where wwn is online
  #
  # domain of 0 means the switch does not have any domain id
  
  attr_reader :domain_id
  
  # value naming rule
  # value ca be only WWN
  #
  # 50:00:10:20:30:40:50:60
  
  VALUE_RULE='([\da-f]{2}:){7}[\da-f]{2}'
  
  # verifies if +str+ matches convetion defined in Wwn::VALUE_RULE
  # raises Switch::Error: Incorrect value format if not
  # this method is used internally mostly
    
  def self.verify_value(str)
    raise Switch::Error.new("Incorrect value format \"#{str}\"") if !str.match(/#{VALUE_RULE}/i)
  end
  
  # shadows value
  def name
    @value
  end
   
  # init method
  #
  # opts => :symbol => "text" - device description
  def initialize(value,dev_type,domain_id,port_index,opts={}) # :nodoc:
    Wwn::verify_value(value)
    @value=value 
    @dev_type=dev_type
    @domain_id=domain_id.to_i
    @port_index=port_index.to_i
    @symbol= !opts[:symbol].nil? ? opts[:symbol] : ""
  end  
  
  def to_s
    @value
  end
end

end; end
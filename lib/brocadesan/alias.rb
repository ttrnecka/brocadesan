module Brocade module SAN
  
# Alias model
class Alias
  # returns name of the alias
  attr_reader :name
   
  # init method
  def initialize(name,switch,opts={}) # :nodoc:
    if switch.class==Switch
      @switch=switch
    else
      raise Switch::Error.new("#{switch} is not instance of Switch!!!")
    end
    @switch=switch if switch.class==Switch
    @name=name 
  end
  
  # returns array of members
  
  def members
    switch.aliases if @switch.configuration[:defined_configuration][:alias][self.name].empty?
    @switch.configuration[:defined_configuration][:alias][self.name]
  end
end

end; end
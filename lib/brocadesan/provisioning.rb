# Brocade namespace
module  Brocade 
# SAN namespace  
module SAN
  
# Provisioning namespace
module Provisioning
  class Agent < Brocade::SAN::Switch
    
    # Creates a Brocade::SAN::Provisioning::Agent instance and tests a connection.
    #
    # Checks as well if the switch is virtual fabric enabled since that defines the way it will be queried further.
    def self.create(*params)
      agent=self.new(*params)
    end
    
    # Adds alias to config and saves it
    #
    # +al+ must be of class Alias. It will be created as it is with all the members
    #
    # raises error if alias exists or transaction is running or response is unexpected
    
    def alias_add(al)
      raise Agent::Error.new(Agent::Error::ALIAS_BAD) if !al.kind_of? Alias
      self.session do 
        raise Agent::Error.new(Agent::Error::ALIAS_EXISTS) if !find_alias(al.name).empty?
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        response=query("alicreate \"#{al.name}\",\"#{al.members.join("; ")}\"")

        #empty response is ok
        if response.data.split("\n").size==1
          cfg_save
        else
          error = response.data.split("\n").delete_if {|item| item.match(/^#{Agent::QUERY_PROMPT}/)}.join("\n")
          raise Agent::Error.new(error)
        end
      end
      true
    end
    
    # Saves config
    # Raises erros if cancelled, nothing saved or unexpected result, otherwise returns true
    def cfg_save
      set_mode("interactive")
      
      response = query("cfgsave","y")
      case
      when response.data.match(/Operation cancelled/)
        raise Agent::Error.new(Agent::Error::CFGSAVE_CANC)
      when response.data.match(/Nothing changed: nothing to save, returning/)
        raise Agent::Error.new(Agent::Error::CFGSAVE_NOCHANGE)
      when response.data.match(/Updating flash/)    
        return true
      else
        raise Agent::Error.new(response.data)
      end
    ensure
      set_mode("script")
    end    
    
    # Check if there is zoning transaction in progress
    #
    # Returns +true+ or +false+
    def check_for_running_transaction
      response=query("cfgtransshow")
      response.data.match(/There is no outstanding zoning transactions/) ? false : true
    end
    
    private
    
    def initialize(*params)
      super(*params)
    end
    
    # verifies if the specified user can change zoning configuration
    #
    # returns true if yes, raises error if not
    def verify
      response=query("configshow | grep RBAC")     
      raise Agent::Error.new(Agent::Error::BAD_USER) if response.data.match(/RBAC permission denied/)
      true
    end
  end
    
  class Agent   
     class Error < self::Error
       BAD_USER = "User has insufficient rights to do provisioning"
       TRNS_IPRG = "Another zoning transaction is already in progress"
       ALIAS_BAD = "Parameter should be of Alias class"
       ALIAS_EXISTS = "Cannot create alias because it already exists"
       CFGSAVE_CANC = "cfgsave was cancelled"
       CFGSAVE_NOCHANGE = "cfgsave: nothing changed, nothing to save"
     end
  end
end; end; end

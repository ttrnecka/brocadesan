# Brocade namespace
module  Brocade 
# SAN namespace  
module SAN
  
# Provisioning namespace
module Provisioning
  # Agent class, used for provisioning tasks
  class Agent < Brocade::SAN::Switch
    
    # Creates a Brocade::SAN::Provisioning::Agent instance and tests a connection.
    #
    # Checks as well if the switch is virtual fabric enabled since that defines the way it will be queried further.
    def self.create(*params)
      agent=self.new(*params)
    end
    
    # creates a transaction
    #
    # transaction runs in 1 session
    #
    # cfg_save will be run a the end if the transaction is ok
    
    def transaction
      raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
      @transaction = true
      session do
        begin
          yield
          cfg_save
        rescue => e
          abort_transaction
          raise e
        end  
      end
    ensure
      @transaction = nil
    end
    
    # Creates alias and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +al+ must be of class Alias. It will be created as it is with all the members
    #
    # raises error if alias exists or transaction is running or response is unexpected
    
    def alias_create(al)
      raise Agent::Error.new(Agent::Error::ALIAS_BAD) if !al.kind_of? Alias
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        response=query("alicreate \"#{al.name}\",\"#{al.members.join("; ")}\"")

        validate_and_save(response)
      end
      true
    end
    
    
    # Removes alias and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +al+ must be of class Alias. It will be created as it is with all the members
    #
    # raises error if alias does not exist or transaction is running or response is unexpected
    
    def alias_delete(al)
      raise Agent::Error.new(Agent::Error::ALIAS_BAD) if !al.kind_of? Alias
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        response=query("alidelete \"#{al.name}\"")

        validate_and_save(response)
      end
      true
    end
    
    # Changes alias and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +al+ must be of class Alias. alias with the name will be removed and it will be created anew as it is with all the members
    #
    # raises error if alias does not exist or transaction is running or response is unexpected
    
    def alias_change(al)
      raise Agent::Error.new(Agent::Error::ALIAS_BAD) if !al.kind_of? Alias
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        alias_delete(al)
        alias_create(al)
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
    
    
    # Creates zone and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +zone+ must be of class Zone. It will be created as it is with all the members
    #
    # raises error if zone exists or transaction is running or response is unexpected
    
    def zone_create(zone)
      raise Agent::Error.new(Agent::Error::ZONE_BAD) if !zone.kind_of? Zone
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        response=query("zonecreate \"#{zone.name}\",\"#{zone.members.join("; ")}\"")

        validate_and_save(response)
      end
      true
    end
    
    # Removes zone and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +zone+ must be of class Zone. It will be created as it is with all the members
    #
    # raises error if alias does not exist or transaction is running or response is unexpected
    
    def zone_delete(zone)
      raise Agent::Error.new(Agent::Error::ZONE_BAD) if !zone.kind_of? Zone
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        response=query("zonedelete \"#{zone.name}\"")

        validate_and_save(response)
      end
      true
    end
    
    # Changes zone and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +zone+ must be of class Zone. +zone+ with the name will be removed and it will be created anew as it is with all the members
    #
    # raises error if alias does not exist or transaction is running or response is unexpected
    
    def zone_change(zone)
      raise Agent::Error.new(Agent::Error::ZONE_BAD) if !zone.kind_of? Zone
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        zone_delete(zone)
        zone_create(zone)
      end
      true
    end
    
    # Check if there is zoning transaction in progress
    #
    # Returns +true+ or +false+
    def check_for_running_transaction
      # ignore thi command when within transaction block
      # as this command is started at the beginign of transaction
      return false if @transaction
      
      response=query("cfgtransshow")
      response.data.match(/There is no outstanding zoning transactions/) ? false : true
    end
    
    # aborts transaction
    # returns
    # +true+ if transaction was aborted and
    # +false+ if there was no transaction to abort and
    # raises error if not owner of the transaction
    def abort_transaction
      response=query("cfgtransabort")
      #empty response is ok
      case
      when  response.data.split("\n").size==1
        return true
      when  response.data.match(/There is no outstanding transaction/)
        return false
      when response.data.match(/trans_abort: there is an outstanding  transaction/)
        raise Agent::Error.new(Agent::Error::TRANS_NOTOWNER)
      else
        error = response.data.split("\n").delete_if {|item| item.match(/^#{Agent::QUERY_PROMPT}/)}.join("\n")
        raise Agent::Error.new(error)
      end
    end
    
    private
    
    def initialize(*params)
      super(*params)
      @transaction=nil
    end
    
    # verifies if the specified user can change zoning configuration
    #
    # returns true if yes, raises error if not
    def verify
      response=query("configshow | grep RBAC")     
      raise Agent::Error.new(Agent::Error::BAD_USER) if response.data.match(/RBAC permission denied/)
      true
    end
    
    # saves if th response if empty and if so it save config, otherwise raises error
    def validate_and_save(response)
      #empty response is ok
      if response.data.split("\n").size==1
        cfg_save if @transaction.nil?
      else
        error = response.data.split("\n").delete_if {|item| item.match(/^#{Agent::QUERY_PROMPT}/)}.join("\n")
        raise Agent::Error.new(error)
      end
    end
    
  end
    
  class Agent   
     # Class that holds Agent::Error messages
     class Error < self::Error
       BAD_USER = "User has insufficient rights to do provisioning"
       TRNS_IPRG = "Another zoning transaction is already in progress"
       ALIAS_BAD = "Parameter should be of Alias class"
       ZONE_BAD = "Parameter should be of Zone class"
       CFGSAVE_CANC = "cfgsave was cancelled"
       CFGSAVE_NOCHANGE = "cfgsave: nothing changed, nothing to save"
       TRANS_NOTOWNER = "Cannot abort transaction you are not owner of"
     end
  end
end; end; end

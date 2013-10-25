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
    # Command allows transaction within transaction
    #
    # cfg_save will be run a the end if the transaction is ok
    
    def transaction
      @transaction_level+=1
      raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
      @transaction = true
      session do
        begin
          yield
          cfg_save if @transaction_level==1
        rescue => e
          abort_transaction
          raise e
        end  
      end
    ensure
      @transaction_level-=1
      @transaction = nil if @transaction_level==0
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
        self.transaction do
          alias_delete(al)
          alias_create(al)
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
    
    # enables config
    # Raises erros if cancelled, nothing saved or unexpected result, otherwise returns true
    def cfg_enable(cfg)
      raise Agent::Error.new(Agent::Error::CFG_BAD) if !cfg.kind_of? ZoneConfiguration
      
      set_mode("interactive")
      
      response = query("cfgenable #{cfg.name}","y")
      case
      when response.data.match(/Operation cancelled/)
        raise Agent::Error.new(Agent::Error::CFGSAVE_CANC)
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
    # Alias members must exist 
    #
    # raises error if zone exists or transaction is running or response is unexpected
    
    def zone_create(zone)
      raise Agent::Error.new(Agent::Error::ZONE_BAD) if !zone.kind_of? Zone
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        zone.members.each do |member|
          # do not check if WWNs exist
          next if member.match(/#{Alias::MEMBER_RULE}/i)
          raise Agent::Error.new(Agent::Error.does_not_exist("Alias #{member}")) if !exist?(member,:object => :alias)
        end
           
        response=query("zonecreate \"#{zone.name}\",\"#{zone.members.join("; ")}\"")
        validate_and_save(response)
      end
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
        self.transaction do
          zone_delete(zone)
          zone_create(zone)
        end
      end
      true
    end
    
    # Creates zone configuration and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +cfg+ must be of class ZoneConfiguration. It will be created as it is with all the members
    #
    # Zone members must exist 
    #
    # raises error if zone configuration exists or transaction is running or response is unexpected
    
    def cfg_create(cfg)
      raise Agent::Error.new(Agent::Error::CFG_BAD) if !cfg.kind_of? ZoneConfiguration
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        cfg.members.each do |member|
          raise Agent::Error.new(Agent::Error.does_not_exist("Zone #{member}")) if !exist?(member,:object => :zone)
        end
        
        response=query("cfgcreate \"#{cfg.name}\",\"#{cfg.members.join("; ")}\"")
        validate_and_save(response)
      end
    end
    
    
    # Removes zone configuration and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +cfg+ must be of class ZoneConfiguration. It will be created as it is with all the members
    #
    # raises error if zone configuration does not exist or transaction is running or response is unexpected
    
    def cfg_delete(cfg)
      raise Agent::Error.new(Agent::Error::CFG_BAD) if !cfg.kind_of? ZoneConfiguration
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        
        response=query("cfgdelete \"#{cfg.name}\"")
        validate_and_save(response)
      end
    end
    
    
    # Adds zone to configuration
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +zone+ must be of class Zone and +cfg+ of class ZoneConfiguration. It will be created as it is with all the members
    #
    # Zone members and zone configuration must exist
    #
    # raises error if zone configuration does not exist or transaction is running or response is unexpected
    
    def cfg_add(cfg,zone)
      raise Agent::Error.new(Agent::Error::CFG_BAD) if !cfg.kind_of? ZoneConfiguration
      raise Agent::Error.new(Agent::Error::ZONE_BAD) if !zone.kind_of? Zone
      self.session do
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        raise Agent::Error.new(Agent::Error.does_not_exist("Config #{cfg.name}")) if !exist?(cfg.name,:object => :cfg)
        raise Agent::Error.new(Agent::Error.does_not_exist("Zone #{zone.name}")) if !exist?(zone.name,:object => :zone)
        
        response=query("cfgadd \"#{cfg.name}\", \"#{zone.name}\"")
        validate_and_save(response)
      end
    end
    
    # Remove zone to configuration
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the commqnd returns
    #
    # +zone+ must be of class Zone and +cfg+ of class ZoneConfiguration.
    #
    # raises error if zone configuration does not exist or transaction is running or response is unexpected
    
    def cfg_remove(cfg,zone)
      raise Agent::Error.new(Agent::Error::CFG_BAD) if !cfg.kind_of? ZoneConfiguration
      raise Agent::Error.new(Agent::Error::ZONE_BAD) if !zone.kind_of? Zone
      self.session do 
        raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
        raise Agent::Error.new(Agent::Error.does_not_exist("Config #{cfg.name}")) if !exist?(cfg.name,:object => :cfg)
        
        response=query("cfgremove \"#{cfg.name}\", \"#{zone.name}\"")
        validate_and_save(response)
      end
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
    
    # Check if object exists. Finds even objects not stored in memory
    #
    # +str+ is name of the object
    #
    # +opts+
    # :object => :zone, :alias, :cfg
    #
    # if no :object is pecified :zone is used by default
    def exist?(str,opts={})
      obj = !opts[:object].nil? && [:zone,:alias,:cfg].include?(opts[:object]) ? opts[:object] : :zone
      cmd = case obj
      when :zone
        "zoneshow"
      when :alias
        "alishow"
      when :cfg
        "cfgshow"
      end  
      
      response=query("#{cmd} \"#{str}\"")
      return response.data.match(/does not exist/) ? false : true
    end
    
    private
    
    def initialize(*params)
      super(*params)
      @transaction=nil
      @transaction_level=0
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
      #true response is ok
      if response.data.split("\n").size==1
        cfg_save if @transaction.nil?
      else
        error = response.data.split("\n").delete_if {|item| item.match(/^#{Agent::QUERY_PROMPT}/)}.join("\n")
        raise Agent::Error.new(error)
      end
      true
    end
    
  end
    
  class Agent   
     # Class that holds Agent::Error messages
     class Error < self::Error
       BAD_USER = "User has insufficient rights to do provisioning"
       TRNS_IPRG = "Another zoning transaction is already in progress"
       ALIAS_BAD = "Parameter should be of Alias class"
       ZONE_BAD = "Parameter should be of Zone class"
       CFG_BAD = "Parameter should be of ZoneConfiguration class"
       CFGSAVE_CANC = "cfgsave was cancelled"
       CFGSAVE_NOCHANGE = "cfgsave: nothing changed, nothing to save"
       TRANS_NOTOWNER = "Cannot abort transaction you are not owner of"
       OBJ_NOTEXIST = "does not exist"
       
       # used to raise modifyable "does not exist message" 
       def self.does_not_exist(str)
         "#{str} #{OBJ_NOTEXIST}"
       end
     end
  end
end; end; end

# Brocade namespace
module  Brocade 
# SAN namespace  
module SAN
  
# Provisioning namespace
module Provisioning
  # holds replies strings as constants
  module Replies
    # from cfgtransshow
    NO_ZONING_TRANSACTION = "There is no outstanding zoning transaction"
    # from cfgtransabort
    NO_TRANSACTION = "There is no outstanding transaction"
    OUTSTANDING_TRANSACTION = "trans_abort: there is an outstanding  transaction"
    OPERATION_CANCELLED = "Operation cancelled"
    NO_CHANGE="Nothing changed: nothing to save, returning"
    FLASH_UPDT="Updating flash"
    DOES_NOT_EXIST="does not exist"
    RBAC_DENIED="RBAC permission denied"
    CURRENT_TRANSACTION = "Current transaction token is"
    
  end
  # Agent class, used for provisioning tasks
  # 
  # Under development - do not use
  #
  # TODO: need to properly test it live (partialy done)

  class Agent < Brocade::SAN::Switch
    
    # Creates a Brocade::SAN::Provisioning::Agent instance, tests a connection and test if user has enough rights for provisioning. 
    # Raises Error otherwise
    #
    # Checks as well if the switch is virtual fabric enabled since that defines the way it will be queried further.
    def self.create(*params)
      agent=new(*params)
      #TODO revisit this once the v7.3 is installed
      agent.override_vf
      agent
    end
    
    # Queries the agent for ongoing transaction.
    #
    # Retruns Transaction instance or false if there is no transaction.
    #
    # Raises Error when transaction details could not be obtained
    def get_transaction
      trans=Transaction.new(cfg_transaction(true))
      return false if trans.id==-1
      raise Error.new(Error::TRANS_UNEXPECTED) if trans.id.nil?
      trans
    end
    
    # Opens a provisioning transaction. 
    #
    # Transaction runs in 1 session.
    #
    # Command allows transaction within transaction.
    #
    # cfg_save will be run at the end of the transaction is there was no error raised and this is the top-most transaction block.
    #
    # cfg_save wil not run as result of the transaction, you can however run it as last command in transaction
    
    def transaction(opts={:auto_enable => false})
      @transaction_level||=0
      @transaction_level+=1
      session do
        raise_if_transaction_running
        @transaction ||= true
        raise Error.cannot_obtain_transaction_lock if not lock_transaction
        begin
          yield
          # get_transaction in case cfgsave or cfgenable was run in transaction block
          # if there is no transaction we do not need to run it
          # if there is transaction but opend by someone else then t
          cfg_save if @transaction_level==1 && get_transaction
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
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns
    #
    # +al+ must be of class Alias. It will be created as it is with all the members of +al+ instance
    #
    # raises error if alias exists or different transaction is running or response is unexpected
    #
    # Returns Alias 
    
    def alias_create(al)
      obj_create al, Alias
    end
    
    # Creates +zone+ and saves config.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +zone+ must be of class Zone. It will be created as it is with all the +zone+ members.
    #
    # +members+ must exist. Exaception is members matching WWN and D,P notation. 
    #
    # Raises error if +zone+ exists already or different transaction is running or response is unexpected.
    #
    # Returns Zone
    
    def zone_create(zone)
      obj_create zone, Zone
    end
    
    # Creates zone configuration and saves fabric configuration.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +cfg+ must be of class ZoneConfiguration. It will be created as it is with all the members of +cfg+.
    #
    # Members must exist on the switch as zones.
    #
    # Raises error if +cfg already exists or some of the members do not exist or different transaction is running or response is unexpected.
    #
    # Returns ZoneConfiguration
    
    def cfg_create(cfg)
      obj_create cfg, ZoneConfiguration
    end
    
    # Deletes alias and saves config
    #
    # NOTE: This command checks if every member exists before creating the cfg, if the cfg has many members it will take lot of time, however cfg creation is on daily task.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns
    #
    # +al+ must be of class Alias.
    #
    # raises error if alias does not exist or transaction is running or response is unexpected
    #
    # this is low level command and it only removes the alias
    #
    # it will not remove alias reference from zones, see Agent::#alias_purge that removes all
    #
    # Returns nil if deletion is successful
    
    def alias_delete(al)
      obj_delete al, Alias
    end
    
    
    # Removes +zone+ and saves config.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +zone+ must be of class Zone. 
    #
    # Raises error if +zone+ does not exist or different transaction is running or response is unexpected.
    #
    # This is low level command, it will remove the +zone+ record but not zone references from zone configurations, use #zone_purge for this purpose.
    #
    # Returns nil if deletion is successful
    
    def zone_delete(zone)
      obj_delete zone, Zone
    end
    
    # Removes zone configuration and saves fabric configuration.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +cfg+ must be of class ZoneConfiguration. It will delete only zone config, keep the members intact.
    #
    # Raises error if zone configuration does not exist or different transaction is running or response is unexpected.
    #
    # Returns nil if deletion is successful
    
    def cfg_delete(cfg)
      obj_delete cfg, ZoneConfiguration
    end
    
    # Changes alias and saves config
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns
    #
    # +al+ must be of class Alias. alias with the Alias#name will be removed and it will be created anew as it is with all the members defined in +al+ instance
    #
    # raises error if alias does not exist or different transaction is running or response is unexpected
    #
    # this is shorthand method that instead of modifiyng the alias removes the alias and recreates it
    # 
    # use alias_remove and alias_add if the above is not an option
    #
    # Returns Alias
    
    def alias_change(al)
      obj_change al, Alias
    end
    
        
    # Changes +zone+ and saves config.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +zone+ must be of class Zone. +zone+ with the name will be removed and it will be created anew as it is with all the +zone+ members.
    #
    # Raises error if +member+ does not exist (WWN and D,P members are exception) or different transaction is running or response is unexpected.
    #
    # This is shorthand method that instead of modifiyng the zone removes the zone and then recreates it.
    #
    # Returns Zone
    
    def zone_change(zone)
      obj_change zone, Zone
    end
    
    # Removes member from alias +al+
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns
    #
    # +al+ must be instance of Alias and +member+ must minstance of Wwn or String matching Alias::MEMBER_RULE
    #
    # raises error if alias does not exist, +member+ does not match the rule or different transaction is running or response is unexpected
    #
    # Returns Alias or nil if the removed member was last one (it removes the Alias as well)
    
    def alias_remove(al,member)
      obj_remove(al,Alias,member)
    end
    
    # Remove +member+ from +zone+.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +zone+ must be of class Zone and +member+ of class Alias or Wwn or String matching Alias::MEMBER_RULE
    #
    # Raises error if zone does not exist or different transaction is running or response is unexpected.
    #
    # Returns Zone or nil if the removed member was last one (it removes the Zone as well)
    
    def zone_remove(zone,member)
      obj_remove(zone,Zone,member)
    end
    
    # Remove zone +member+ from configuration +cfg+.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +member+ must be of class Zone and +cfg+ of class ZoneConfiguration.
    #
    # Raises error if +cfg+ does not exist or different transaction is running or response is unexpected.
    #
    # Returns ZoneConfiguration or nil if the removed member was last one (it removes the ZoneConfiguration as well)
    
    def cfg_remove(cfg,member)
      obj_remove(cfg,ZoneConfiguration,member)
    end
    
    # Purges the Zone +zone+ completely, along with all references.
    #
    # +zone+ must me instance of Zone.
    # The method first removes the zone from all zone configurations it is member of.
    # Then deletes the zone and saves configuration.
    #
    # Should return nil if the +zone+ was purged.
    
    def zone_purge(zone)
      obj_purge(zone,Zone)
    end
    
    # Purges the Alias +al+ completely, along with all references.
    #
    # +al+ must be instance of Alias.
    #
    # The method first removes the alias from all zones it is member of.
    # Then deletes the alias and saves configuration.
    #
    # Should return nil if the +al+ was purged.
    def alias_purge(al)
       obj_purge(al,Alias)
    end
    
    # Adds zone cofiguration member to zone configuration.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns.
    #
    # +member+ must be instance of Zone and +cfg+ instance of class ZoneConfiguration. 
    #
    # Zone and zone configuration must both exist.
    #
    # Raises error if +cfg+ or +member+ do not exist or different transaction is running or response is unexpected.
    #
    # Returns ZoneConfiguration
    
    def cfg_add(cfg,member)
      obj_add(cfg,ZoneConfiguration,member)
    end
    
    # Adds zone +member+ to +zone+.
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns
    #
    # +member+ must be of class Alias or Wwn or Strign matching Alias::MEMBER_RULE and +zone+ of class Zone. 
    #
    # Zone and member must exist. Exception is if +member+ is Wwn.
    #
    # Raises error if zone or member does not exist or transaction is running or response is unexpected.
    #
    # Returns Zone
    
    def zone_add(zone,member)
      obj_add(zone,Zone,member)
    end
    
    # Adds alias member to alias
    #
    # If started outside transaction block it runs as single command transaction, otherwise it is not commited when the command returns
    #
    # +member+ must be instance of Wwn or String matching Alias::MEMBER_RULE (WWN or D,P) 
    #
    # +al+ must be Alias and must exist in switch configuration, the +member+ does not need to, it has only to match the rule 
    #
    # raises error if +al+ does not exist, member does not match the rule, dirrefent transaction is running or response is unexpected
    #
    # Returns Alias
    
    def alias_add(al,member)
      obj_add(al,Alias,member)
    end
   
    # Renames the +object+ to +newname+
    #
    # +object+ and +newname can be instance of Alias, Zone, ZoneConfiguration or String
    #
    # Returns renamed object or raises error
    def rename_object(object,newname)
      session do
        response = script_mode do
          query("zoneobjectrename \"#{object}\", \"#{newname}\"")
        end
        
        validate_and_save(response)
        pull newname.to_s, :object => get_obj_type(object)
      end
    end
    
    # Enables zoning configuration +cfg+.
    #
    # +cfg+ must be ZoneConfiguration instance, will only use it's name and ignore its members.
    #
    # Raises erros if cancelled, nothing saved or unexpected result, otherwise returns true.
    def cfg_enable(cfg)
      raise Agent::Error.new(Agent::Error::CFG_BAD) if !cfg.kind_of? ZoneConfiguration
      
      response = interactive_mode do 
        query("cfgenable \"#{cfg}\"","y")
      end
      
      case
      when response.data.match(/#{Replies::OPERATION_CANCELLED}/)
        raise Agent::Error.new(Agent::Error::CFGSAVE_CANC)
      when response.data.match(/#{Replies::FLASH_UPDT}/)
        # if any transaction was in progres it is closed now
        @transaction=nil
        return true
      else
        raise Agent::Error.new(response.data)
      end
    end
    
    # Check if there is different zoning transaction in progress.
    #
    # Returns +true+ or +false+.
    #
    # if started in within transactino block it will simply return false.
    def check_for_running_transaction
      # ignore this command when within transaction block
      # as this command is started at the begining of transaction
      return false if @transaction
      response = script_mode do
        query("cfgtransshow")
      end
      response.data.match(/#{Replies::NO_ZONING_TRANSACTION}/) ? false : true
    end
    
    # Aborts transaction
    
    # returns
    # +true+ if transaction was aborted and
    # +false+ if there was no transaction to abort and
    # raises error if it is not owner of the transaction
    def abort_transaction
      response = script_mode do
        query("cfgtransabort")
      end
      #empty response is ok
      case
      when  response.data.split("\n").size==1
        return true
      when  response.data.match(/#{Replies::NO_TRANSACTION}/)
        return false
      when response.data.match(/#{Replies::OUTSTANDING_TRANSACTION}/)
        raise Agent::Error.new(Agent::Error::TRANS_NOTOWNER)
      else
        error = response.data.split("\n").delete_if {|item| item.match(/^#{@prompt}/)}.join("\n")
        raise Agent::Error.new(error)
      end
    end
    
    # Checks if object exists in fabric. Finds even objects not stored in memory but as well object created in open transaction.
    #
    # +str+ is name of the object
    #
    # +opts+
    # :object => :zone, :alias, :cfg
    #
    # if no :object is specified :zone is used by default
    def exist?(str,opts={})
      obj = !opts[:object].nil? && [:zone,:alias,:cfg].include?(opts[:object]) ? opts[:object] : :zone
      
      response = script_mode do 
        query("#{show_cmd(obj)} \"#{str}\"")
      end
      return response.data.match(/#{Replies::DOES_NOT_EXIST}/) ? false : true
    end
    
    # Pulls object matching +str+ from switch configuration, even objects not yet saved
    # 
    # Returns the object or nil
    #
    # options
    # [:object]   :zone (default)
    #             :alias
    #             :cfg
    #             :all
    def pull(str,opts={})
      obj = !opts[:object].nil? && [:zone,:alias,:cfg, :all].include?(opts[:object]) ? opts[:object] : :zone
      
      response=nil
      
      session do
        if obj == :all
          [:cfg, :zone, :alias].each do |type|
            obj = type
            response = script_mode do 
              query("#{show_cmd(type)} \"#{str}\"")
            end
            response.parse
            break if !response.parsed[:base].nil?
          end
        else
          response = script_mode do 
            query("#{show_cmd(obj)} \"#{str}\"")
          end
          response.parse
        end 
      end
      return nil if response.parsed[:base].nil?
      
      object = response.parsed[:base][obj] #hash with single key
      name = object.keys[0]
      case obj
      when :zone
        item = Zone.new(name)
      when :alias
        item = Alias.new(name)
      when :cfg 
        item = ZoneConfiguration.new(name)
      end
      object[name].each do |member|
        item.add_member(member)
      end
         
      return response.data.match(/#{Replies::DOES_NOT_EXIST}/) ? nil : item
    end
    
    private_class_method :new
    
    private
    
    def initialize(*params) #:nodoc:
      super(*params)
      raise Error.new(Error::BAD_USER) if not verify
    end
    
    def show_cmd(obj_sym)
      cmd = case obj_sym
      when :zone
        "zoneshow"
      when :alias
        "alishow"
      when :cfg
        "cfgshow"
      end  
    end
    # verifies if the specified user can change zoning configuration
    #
    # returns true if yes, false if no
    def verify
      response = script_mode do 
        query("configshow | grep RBAC")
      end     
      response.data.match(/#{Replies::RBAC_DENIED}/) ? false : true
    end
    
    # saves if the response if empty and if so it save config, otherwise raises error
    def validate_and_save(response)
      #true response is ok
      if response.data.split("\n").size==1
        # will not save if part of transaction
        cfg_save if @transaction.nil?
      else
        error = response.data.split("\n").delete_if {|item| item.match(/^#{@prompt}/)}.join("\n")
        raise Agent::Error.new(error)
      end
      true
    end
    
    # Obtains transaction lock and stores that transaction in @transaction
    #
    # Returns +false+ otherwise
    def lock_transaction
      begin
        return true if @transaction.kind_of? Transaction
         if get_transaction==false
           lock_alias=Alias.new("brocade_san_lock")
           lock_alias.add_member("50:00:00:00:00:00:00:00")
           alias_create lock_alias
           alias_delete lock_alias
           @transaction = get_transaction
           true
         else
           false
         end
      rescue
        return false
      end
    end
    
    # Saves config
    # Raises erros if cancelled, nothing saved or unexpected result, otherwise returns true
    # this method will be called by adhoc methods or by finishing transaction, should not be called directly
    # because it does not check for running transaction, it expect the caller to take care of that
    def cfg_save
      response = interactive_mode do
        query("cfgsave","y")
      end
      
      case
      when response.data.match(/#{Replies::OPERATION_CANCELLED}/)
        raise Agent::Error.new(Agent::Error::CFGSAVE_CANC)
      when response.data.match(/#{Replies::NO_CHANGE}/)
        raise Agent::Error.new(Agent::Error::CFGSAVE_NOCHANGE)
      when response.data.match(/#{Replies::FLASH_UPDT}/)    
        @transaction=nil
        return true
      else
        raise Agent::Error.new(response.data)
      end
    end
    
    # pulls given object from switch 
    def obj_pull(obj,klass)
      pull obj.to_s, :object=> get_obj_type(obj)
    end
    
    # creates the appropriate object
    def obj_create(obj,klass)
      obj_manipulate obj,klass do |man| 
        man.in_session do 
          raise_if_members_do_not_exist obj       
          get_response_and_validate_for(obj,klass,"create",nil)
        end
      end
    end
    
    
    # deletes the appropriate object
    def obj_delete(obj,klass)
      obj_manipulate obj,klass do |man| 
        man.in_session do        
          get_response_and_validate_for(obj,klass,"delete",nil)
        end
      end
    end
    
    # changes the appropriate object
    def obj_change(obj,klass)
      #raise_if_obj_is_not obj , klass
      session do 
      #  raise_if_transaction_running
        cmd = klass.to_s.split("::").last.downcase
        transaction do
          self.send("#{cmd}_delete", obj)
          self.send("#{cmd}_create", obj)
        end
        obj_pull obj, klass
      end
    end
    
    # removes member from object
    def obj_remove(obj,klass,member)
      obj_manipulate obj,klass do |man|
        man.checks do 
          raise_if_member_is_not_valid_for klass, member
        end 
        man.in_session do 
          raise_if_obj_do_not_exist obj       
          get_response_and_validate_for(obj,klass,"remove",member)
        end
      end
    end
    
    # adds member to object
    def obj_add(obj,klass,member)
      obj_manipulate obj,klass do |man|
        man.checks do 
          raise_if_member_is_not_valid_for klass, member
        end 
        man.in_session do 
          raise_if_obj_do_not_exist obj
          raise_if_obj_do_not_exist member      
          get_response_and_validate_for(obj,klass,"add",member)
        end
      end
    end
    
    
    # purges given object compltely
    
    def obj_purge(obj,klass)
      obj_manipulate obj,klass do |man|
        man.in_session do 
          parents = find_by_member(obj.name, :find_mode => :exact, :transaction => true)
          transaction do
            parents.each do |par|
              obj_remove par, par.class, obj
            end
            obj_delete obj, obj.class
          end
        end
      end
    end
    
    # raises error if member is not valid for given class
    
    def raise_if_member_is_not_valid_for(klass,member)
      case klass.to_s
      when "Brocade::SAN::ZoneConfiguration"
        raise Agent::Error.new(Agent::Error::ZONE_BAD) if !member.kind_of? Zone
      when "Brocade::SAN::Zone"
        raise Agent::Error.new(Agent::Error::MEMBER_BAD) if !member.kind_of?(Alias) && !member.kind_of?(Wwn) && !member.match(/^#{Alias::MEMBER_RULE}$/)
      when "Brocade::SAN::Alias"
        case member.class.to_s
        when "Brocade::SAN::Wwn"
        when "String"
          raise Agent::Error.new(Agent::Error::ALIAS_MEMBER_BAD) if !member.match(/^#{Alias::MEMBER_RULE}$/)
        else
          raise Agent::Error.new(Agent::Error::ALIAS_MEMBER_BAD)
        end
      end
    end
    
    # raises proper error if obj is not of class klass
    def raise_if_obj_is_not(obj,klass)     
      case klass.to_s
      when "Brocade::SAN::ZoneConfiguration"
        raise Agent::Error.new(Agent::Error::CFG_BAD) if !obj.kind_of? klass
      when "Brocade::SAN::Zone"
        raise Agent::Error.new(Agent::Error::ZONE_BAD) if !obj.kind_of? klass
      when "Brocade::SAN::Alias"
        raise Agent::Error.new(Agent::Error::ALIAS_BAD) if !obj.kind_of? klass
      end
    end
    
    # raises error if another transcation is already running
    def raise_if_transaction_running
      raise Agent::Error.new(Agent::Error::TRNS_IPRG) if check_for_running_transaction
    end
    
    # raise error if object does not actually exist in configuration
    def raise_if_obj_do_not_exist(obj)
      klass = obj.class.to_s
      case klass
      when "Brocade::SAN::ZoneConfiguration"
        raise Agent::Error.does_not_exist("Config #{obj.name}") if !exist?(obj.name,:object => :cfg)
      when "Brocade::SAN::Zone"
        raise Agent::Error.does_not_exist("Zone #{obj.name}") if !exist?(obj.name,:object => :zone)
      when "Brocade::SAN::Alias"
        raise Agent::Error.does_not_exist("Alias #{obj.name}") if !exist?(obj.name,:object => :alias)
      when "String" # Wwn and D,P notation for zone and alias members
       raise Agent::Error.new(Agent::Error::MEMBER_BAD_2) if !obj.match(/^#{Alias::MEMBER_RULE}$/)
      end
    end
    
    # raise error if members of obj do not actually exists in configuration
    def raise_if_members_do_not_exist(obj)
      klass = obj.class.to_s
      raise Agent::Error.members_empty if obj.members.empty?
      # pull all zones
      if klass == "Brocade::SAN::ZoneConfiguration"
        zones(true)
      end
      obj.members.each do |member|
        case klass
        when "Brocade::SAN::ZoneConfiguration"
          # exist? is slow for for big configurations
          #raise Agent::Error.does_not_exist("Zone #{member}") if !exist?(member,:object => :zone)
          raise Agent::Error.does_not_exist("Zone #{member}") if zones.select {|z|z.name==member}.empty?
        when "Brocade::SAN::Zone"
          # no need to  check if WWNs exist
          next if member.match(/#{Alias::MEMBER_RULE}/i)
          # check if other members => only aliases exist
          raise Agent::Error.does_not_exist("Alias #{member}") if !exist?(member,:object => :alias)
          # no checks for Alias required - the members do not need to exists for Alias
        end
      end
    end
    
    #return proper cmd to use
    def get_cmd(klass,task)
      cmd = case klass.to_s
        when "Brocade::SAN::ZoneConfiguration"
          "cfg#{task}"
        when "Brocade::SAN::Zone"
          "zone#{task}"
        when "Brocade::SAN::Alias"
          "ali#{task}"
      end  
    end
    
    #return proper cmd to use
    def get_obj_type(obj)
      type = case obj.class.to_s
        when "Brocade::SAN::ZoneConfiguration"
          :cfg
        when "Brocade::SAN::Zone"
          :zone
        when "Brocade::SAN::Alias"
          :alias
        when "String"
          :all
      end  
    end
    
    #return proper member part of provisioning query command for given word, obj and member
    def get_member_part(obj, word, member=nil)
      case word
      when "delete"
        ""
      when "create"
        ", \'#{obj.members.join(";")}\'"
      when "remove","add"
        ", \'#{member}\'"
      else
        ""
      end
    end
    
    # manipulates object
    # this is private method that is for use only in another private methods
    # follows this template for given obj,klass and member arguments
    # raise_if_obj_is_not obj , klass
    # checks
    # session do
    #   raise_if_transaction_running
    #   in_sesssion
    # end
    # the checks and in_session blocks can be defined on the manipulator object yielded to the block
    # Example:
    # obj_manipulate obj,klass,member do |man|
    #   man.checks do
    #     #puts checks here
    #   end
    #   man.in_session do
    #    #puts session block here
    #   end
    # end
    
    def obj_manipulate(*args,&block)
      obj,klass,member = args
      manipulator = Brocade::SAN::Provisioning::ObjectManipulator.new
      # block can define checks and in_session handlers
      yield manipulator
      # standard template follows
      # check if class is proper
      raise_if_obj_is_not obj , klass
      # run run check block - should contain checks not requiring session -> switch access
      manipulator.run_checks
      # starting session
      session do
        # standard transaction check
        raise_if_transaction_running
        # run block defined in in_session block
        manipulator.run_session
        # returns the fresh object
        obj_pull(obj,klass)
      end
    end
    
    # gets response and validates
    def get_response_and_validate_for(obj,klass,word,member=nil)
      # gets proper command for given word and klass
      cmd_part = get_cmd klass, word
      object_member_part = get_member_part obj, word, member
      response = script_mode do
        query("#{cmd_part} \'#{obj}\'#{object_member_part}")
      end
      validate_and_save(response)
    end
    
  end
    
  class Agent   
     # Class that holds Agent::Error messages
     class Error < self::Error
       BAD_USER = "User has insufficient rights to do provisioning"
       TRNS_IPRG = "Another zoning transaction is already in progress"
       ALIAS_BAD = "Parameter should be of Alias class"
       MEMBER_BAD = "Parameter should be of Alias or Wwn class"
       MEMBER_BAD_2 = "Parameter should be of Wwn or D,P notation"
       ZONE_BAD = "Parameter should be of Zone class"
       CFG_BAD = "Parameter should be of ZoneConfiguration class"
       CFGSAVE_CANC = "cfgsave was cancelled"
       CFGSAVE_NOCHANGE = "cfgsave: nothing changed, nothing to save"
       TRANS_NOTOWNER = "Cannot abort transaction you are not owner of"
       OBJ_NOTEXIST = "does not exist"
       MEMBERS_EMPTY = "Cannot create. Object has no members"
       ALIAS_MEMBER_BAD = "Not correct alias member"
       TRANS_UNEXPECTED="Cannot get transaction details"
       TRANS_UNLOCKABLE="Cannot get transaction lock"
       
       # used to raise modifyable "does not exist message" 
       def self.does_not_exist(str) #:nodoc:
         new("#{str} #{OBJ_NOTEXIST}")
       end
       
       def self.members_empty #:nodoc:
         new(MEMBERS_EMPTY)
       end
       
       def self.cannot_obtain_transaction_lock
         new(TRANS_UNLOCKABLE)
       end
     end
     
     # simple Transaction class that processes Switch#cfg_transaction output
     # 
     # Value of +id+ means:
     # [:id]  -1 - no transaction exist
     #
     #        nil - unexpected result
     #
     #        string - string representation of current transaction id
     
     class Transaction 
       attr_writer :abortable
       # Specifies the id of Transaction
       attr_accessor :id
       
       # takes hash returned by cfg_transaction command 
       def initialize(opts={}) #:nodoc:
         # empty hash means unexpected result of cfg_transaction
         if [:id, :abortable].all? {|k| opts.key? k}
           @id = opts[:id]
           @abortable = opts[:abortable]
         end
       end
       
       # Returns abortable flag
       def abortable?
         @abortable
       end
     end
  end
  
  # manipulator object used on #obj_manipulate to insert block of commands into standard obj manipulation template, see the #obj_manipulate
  class ObjectManipulator #:nodoc:
    def checks(&block)
      @checks = block
    end
    
    def run_checks
      @checks.call if @checks
    end
    
    def in_session(&block)
      @in_session = block
    end
    
    def run_session
      @in_session.call if @in_session
    end
  end
end; end; end

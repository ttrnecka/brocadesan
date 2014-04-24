require 'net/ssh'
require 'yaml'

# Brocade namespace
module  Brocade 
# SAN namespace  
module SAN
  
  # configuration class
  class Configuration #:nodoc:
    def self.cmd_mapping_path(_class)
      File.realpath("../config/#{_class.name.underscore}_cmd_mapping.yml",__FILE__)
    end
    
    def self.parser_path
      File.realpath("../config/parser_mapping.yml",__FILE__)
    end
  end
  
  # Class to model SAN switch from Brocade
  class Switch #< BrocadeSanDevice
    
    include SshDevice
    
    # Maps each method name to command to be run to obtain it and to hash key where it ill be stored
    # 
    # See lib/config/brocade/san/switch_cmd_mapping.yml for details
    #
    # Example:
    #  :name:
    #   :cmd: switchshow
    #   :attr: switch_name
    #
    # This will cause that class will have method called name(forced=true).
    # When the method is called first time or +forced+ is true the +switchshow+ command
    # will be queried on the switch.
    # Subsequently you need to edit the Response parser to parse the value and store it into
    # Response +parsed+ hash under +:switch_name+ key.
    # At the end the +:switch_name+ key is returned from +configuration+ attribute
  
    CMD_MAPPING=YAML.load(File.read(Configuration::cmd_mapping_path(self)))
    
    # Maps each command to the parser method to use
    PARSER_MAPPING=YAML.load(File.read(Configuration::parser_path))
    
    # zone configuration, zone and zone aliases naming rule
    # must start with an alphabetic character and may contain 
    # alphanumeric characters and the underscore ( _ ) character.
    NAME_RULE='^[a-z][a-z_\d]*$'
    
    # Used to dynamically create named methods based on CMD_MAPPING
    def self.attributes(args)
      args.each do |arg|
       define_method arg do |forced=false|
         self.get(arg,forced)
       end
      end
    end
    
    # verifies if name matches convetion defined in NAME_RULE
    # raises Switch::Error: Incorrect name format if not
    # this method is used internally mostly
    
    def self.verify_name(name)
      raise Switch::Error.new("Incorrect name format \"#{name}\"") if !name.match(/#{NAME_RULE}/i)
    end
    
    # Creates a Switch instance and tests a connection.
    #
    # Checks as well if the switch is virtual fabric enabled since that defines the way it will be queried further.
    def initialize(*params)
      super(*params)
      @configuration={}
      self.vf
    end
    
    # Hash containing parsed attributes
    #
    # Can be used to obtain parsed attributes for which there is no named method.
    # These attributes however has to be obtained as colateral of running another public method.
    #
    # Example:
    #
    #  # this will call fosconfig --show (see CMD_MAPPING)
    #  # and load :fc_routing_service, :i_scsi_service and others into configuration as well
    #  # the command however returns only whether the virtual_fabric is enabled/disabled
    #
    #  switch.configuration
    #  => nil
    #  switch.vf
    #  => "enabled"
    #  switch.configuration
    #  => {:parsing_position=>"end", :fc_routing_service=>"disabled", :i_scsi_service=>"Service not supported on this Platform", :i_sns_client_service=>"Serv
    #  ice not supported on this Platform", :virtual_fabric=>"enabled", :ethernet_switch_service=>"disabled"}
    
    attr_reader :configuration 
    
    # Fabric id of the switch to be queried. Can be set using +set_context+.
    # 
    # If the given +fid+ does not exist default switch for the provided
    # account will be queried.
    
    attr_reader :fid
    
    attributes CMD_MAPPING.keys
    
    # Sets the FID of the switch to be queried and clears cache. 
    # Next queries will be done directly on switch.
    #
    # If not +fid+ is given it will set it to default 128.
    # If the switch does not support virtual fabrics this will be ignored.
    #
    # Returns the fid that was set
    def set_context(fid=128)
      @loaded={}
      @fid = fid.to_i==0 ? 128 : fid.to_i
    end
    
    # gets the +attr+
    #
    # +attr+ has to be speficied in the CMD_MAPPING
    #
    # named methods are wrappers around this method so you should not use this directly
    def get(attr,forced=false)
      raise Switch::Error.new('Unknown attribute') if CMD_MAPPING[attr.to_sym].nil?
      
      cmd=CMD_MAPPING[attr.to_sym][:cmd]
      
      refresh(cmd) if !@loaded || !@loaded[key(cmd)] || forced
      
      @configuration[CMD_MAPPING[attr.to_sym][:attr].to_sym]
    end
    
    # returns switches in the fabric in hash form
    
    def fabric(forced=false)
      cmd="fabricshow"
      filter = ""

      if !@loaded || !@loaded[key(cmd+filter)] || forced
        refresh(cmd,filter)
      end
      @configuration[:fabric]
    end
    
    # If called with +true+ argument it will get the virtual_fabric from the switch instead of cache
    #
    # Returns value in (string) format
    
    def vf(forced=false)
      if !@configuration[:vf] || forced
        response=query("switchshow|grep \"^LS Attributes\"")
        @configuration[:vf] = response.data.split("\n").size == 2 ? "enabled" : "disabled"
      end
      @configuration[:vf]
    end
    
    # Returns all ZoneConfiguration's array
    
    def zone_configurations(full=false,forced=false)
      get_configshow(full,forced)[:zone_configurations]
    end
    
    # Returns effective ZoneConfiguration
    
    def effective_configuration(full=false,forced=false)
      self.zone_configurations(full,forced).select {|z| z.effective == true}.first
    end
    
    # returns all zones defined on the switch as array of Zone
    
    def zones(forced=false)
      get_configshow(true,forced)[:zones]
    end
    
    # returns all zones defined on the switch as array of Alias
    
    def aliases(forced=false)
      get_configshow(true,forced)[:aliases]
    end
    
    # returns Zone with name of +str+ if exists, +nil+ otherwise
    def find_zone(str)
      zone = find(str,:object=>:zone)
    end
    
    # returns Zone array of Zones with name matching +regexp+ if exists, [] otherwise
    #
    # find is case insesitive
    def find_zones(regexp)
      zones = find(regexp,:object=>:zone,:find_mode=>:partial)
      return [] if zones==[nil]
      zones
    end
    
    # returns Alias with name of +str+ if exists, +nil+ otherwise
    def find_alias(str)
      al = find(str,:object=>:alias)
    end
    
    # returns Alias array of Aliases with name matching +regexp+ if exists, [] otherwise
    #
    # find is case insesitive
    def find_aliases(regexp)
      aliases = find(regexp,:object=>:alias,:find_mode=>:partial)
      return [] if aliases==[nil]
      aliases
    end
    
    # returns all WWNs
    #
    # mode => :local (default), :cached, :all
    #
    # :local - returns all local WWNs
    #
    # :cached - returns wwns cached from remote switches
    #
    # :all - returns all local and remote wwns
    def wwns(forced=false,mode=:local)
      if mode==:local
        get_ns(true,forced,:local=>true)
      elsif mode==:cached
        get_ns(true,forced,:remote=>true)
      else
        get_ns(true,forced,:local=>true).concat get_ns(true,forced,:remote=>true)
      end 
    end
    
    # returns WWN of given +value+ if exists, +nil+ if not
    #
    # if +forced+ is true it will load the data from switch instead of the cache 
    #
    # :fabric_wide => searches whole fabric
    def find_wwn(value,forced=true,opts={:fabric_wide=>false})
      objs = opts[:fabric_wide]==true ? get_ns(true,forced,:local=>true).concat(get_ns(true,forced,:remote=>true)) : get_ns(true,forced,:local=>true)
      objs.find {|k| value.downcase == k.value.downcase}
    end
    
    # finds configuration object by +str+. Case insensitive.
    # If not object type is specified it searches :zone. Find only saved objects. If the object was created but the transaction is not confirmed it will not find it.
    #
    # :object => :zones (default), :aliases
    # :find_mode => :partial, :full(default)
    #
    # Example:
    #
    # switch.find("zone1",:object=>:zone)
    def find(str,opts={})
      obj = !opts[:object].nil? && [:zone,:alias].include?(opts[:object]) ? opts[:object] : :zone
      mode = !opts[:find_mode].nil? && [:partial].include?(opts[:find_mode]) ? opts[:find_mode] : :full
      grep_exp = mode==:full ? " | grep -i -E ^#{obj}\..*#{str}:" : " | grep -i -E ^#{obj}\..*#{str}"  
      
      response=query("configshow"+grep_exp)
      response.parse
      
      #objs=get_configshow(true)[obj]
      objs=response.parsed[:find_results]
      objs||=[]
      
      result=[]
      
      objs.each do |item|
         i = obj==:zone ? Zone.new(item[:obj]) : Alias.new(item[:obj]) 
         item[:members].split(";").each do |member|
           i.add_member(member)
         end
         result<<i
      end
      result
    end
    
    def query(*cmds) #:nodoc
      cmds.map! {|cmd| fullcmd(cmd)}
      super(*cmds)
    end
    
    private
    
    def get_configshow(full=false,forced=false)
      cmd="cfgshow"
      filter = full==false ? "-e cfg: -e configuration:" : ""
      
      if !@loaded || !@loaded[key(cmd+filter)] || forced
        refresh(cmd,filter)
      end
        
        #storing configs  
        tmp_cfg={}
        tmp_cfg[:zone_configurations]=[]
          
          
        # storing defined
        @configuration[:defined_configuration][:cfg].each do |config,members|
   
          effective =  @configuration[:effective_configuration][:cfg].keys[0]==config ? true : false
          
          cfg=ZoneConfiguration.new(config,:effective=>effective)
          members.each do |member|
            cfg.add_member member
          end
          
          tmp_cfg[:zone_configurations]<<cfg
        end
        
        if full
          # storing zones
          tmp_cfg[:zones]=[]
          
          if @configuration[:defined_configuration][:zone]  
            # storing defined
            active_zones = tmp_cfg[:zone_configurations].select {|z| z.effective == true}.first.members           
            @configuration[:defined_configuration][:zone].each do |zone,members|
              active = active_zones.include?(zone) ? true : false
              z=Zone.new(zone,:active=>active)
              members.each do |member|
                z.add_member member
              end
              tmp_cfg[:zones]<<z
            end
          end
          
          
          # storing aliases
          tmp_cfg[:aliases]=[]
          
          if @configuration[:defined_configuration][:alias]  
            # storing defined
            @configuration[:defined_configuration][:alias].each do |al_name,members|
              al=Alias.new(al_name)            
              members.each do |member|
                al.add_member member
              end
              tmp_cfg[:aliases]<<al
            end
          end
        end
      
      tmp_cfg
    end

    def get_ns(full=false,forced=false,opts={:local=>true})
      cmd = opts[:local] ? "nsshow -t" : "nscamshow -t"
      key = opts[:local] ? :wwn_local : :wwn_remote
      filter = "" #full==false ? "-e cfg: -e configuration:" : ""
      
      if !@loaded || !@loaded[key(cmd+filter)] || forced
        refresh(cmd,filter)
      end
        
      #storing wwns  
      tmp_wwns=[]
          
      # storing defined
      @configuration[key].each do |wwn|
        domain_id=wwn[:domain_id]==0 ? self.domain.to_i : wwn[:domain_id]
        w=Wwn.new(wwn[:value],wwn[:dev_type],domain_id,wwn[:port_index],:symbol=>wwn[:symbol])
        tmp_wwns<<w
      end
      tmp_wwns
    end
    
    def refresh(cmd,filter="")
      grep_exp=filter.empty? ? "" : " | grep #{filter}" 
      response=query(cmd+grep_exp)
      response.parse
      
      #puts response.data
  
      @configuration||={}
      @configuration.merge!(response.parsed)
      
      @loaded||={}
      # when we use filter we need to mark the cmd as false
      @loaded[key(cmd)]=false
      @loaded[key(cmd+filter.to_s)]=true
      
      return @loaded[key(cmd)]
    end
    
    def key(cmd)
      cmd.gsub(/\s+/,'_').to_sym
    end
    
    def fullcmd(cmd)
      if @configuration[:vf]=="enabled" && @fid
        cmds = cmd.split("|") 
        if cmds.size>1
          "fosexec --fid #{@fid} \'#{cmds.shift}\' |#{cmds.join("|")}"
        else
          "fosexec --fid #{@fid} \'#{cmds.shift}\'"
        end
      else
        cmd
      end
    end
  end
  
  class Switch
    # class extending SshDevice::Response
     class Response < self::Response
      
      # Wrapper around SshDevice::Response +parse+ that
      # includes before and after hooks
      
      def parse # :nodoc:
        before_parse
        super
        after_parse
      end
      
      private 
      
      def before_parse
        reset
        @parsed[:find_results]=[]
      end
      
      def after_parse
        @parsed[:ports].uniq! if @parsed[:ports]
        @parsed.delete(:pointer)
        @parsed.delete(:last_key)
        @parsed.delete(:key)
        @parsed.delete(:domain)
        @parsed.delete(:was_popped)
        @parsed.delete(:find_results) if @parsed[:find_results].empty?
      end
      
      def parse_line(line)
        return if line.empty?
        # we detect which command output we parse - commands start with > on the XML line
        @parsed[:parsing_position] = case 
          when line.match(/^#{Switch::QUERY_PROMPT}/) then line.gsub(/(fosexec --fid \d+ \')|\'$|\' \|.*$/,"").split(" ")[1]
          else @parsed[:parsing_position]
        end
        #do not process if we are on query line
        return if line.match(/^#{Switch::QUERY_PROMPT}/)
  
        # we parse only certain commands
        case 
          when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='simple' ? k : nil }.compact.join("|")}/i)
            parse_simple(line)
          when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='oneline' ? k : nil }.compact.join("|")}/i)
            parse_oneline(line)
          when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='multiline' ? k : nil }.compact.join("|")}/i)
            parse_multiline(line)
          when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='cfgshow' ? k : nil }.compact.join("|")}/i)
            parse_cfgshow(line)
          when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='ns' ? k : nil }.compact.join("|")}/i)
            parse_ns(line)
        end
      end
      
      def parse_oneline(line)
        @parsed[@parsed[:parsing_position].to_sym]=line
      end
    
      def parse_multiline(line)
        if line.match(/^\s*[a-z]+.*:/i)
          arr = line.split(":")
          @parsed[arr[0].strip.gsub(/\s+/,"_").gsub(/([a-z])([A-Z])/,'\1_\2').downcase.to_sym]=arr[1..-1].join(":").strip
        else
          @parsed[@parsed[:parsing_position].to_sym]||=""
          @parsed[@parsed[:parsing_position].to_sym]+=line+"\n"
        end
      end
      
      def parse_simple(line)
        case
          #extra handling
          when line.match(/^zoning/) 
            @parsed[:zoning_enabled]=line.match(/:\s+ON/) ? true : false
            @parsed[:active_config]=@parsed[:zoning_enabled] ? line.gsub(/(.*\()|(\).*)/,'') : nil
                
          when line.match(/^LS Attributes/)
            @parsed[:ls_attributes]||={}
            sub_ls_attrs=line.gsub(/(.*\[)|(\].*)/,'').split(",")
            sub_ls_attrs.each do |attr|
              if attr.match(/Address Mode/)
                @parsed[:ls_attributes][:address_mode]=attr.gsub(/Address Mode/,'').strip
              else
                key , value = attr.split(":").map {|a| a.strip.downcase}
                @parsed[:ls_attributes][key.gsub(/\s+/,"_").to_sym]=value
              end
            end
          # port line in director
          when line.match(/\s?\d{1,3}\s+\d{1,2}\s+\d{1,2}\s+[\dabcdef-]{6}/i)
            l=line.split
            @parsed[:ports]||=[]
            @parsed[:ports]<<{:index => l[0].to_i,:slot=>l[1].to_i, :port=>l[2].to_i, :address=>l[3].strip, :media => l[4].strip, 
                              :speed=>l[5].strip, :state=>l[6].strip, :proto=>l[7].strip, :comment=>l[8..-1].join(" ")}
          # port line in san blade
          when line.match(/\s?\d{1,3}\s+\d{1,2}\s+[\dabcdef]{6}/i)
            l=line.split
            @parsed[:ports]||=[]
            @parsed[:ports]<<{:index => l[0].to_i, :port=>l[1].to_i, :address=>l[2].strip, :media => l[3].strip, 
                              :speed=>l[4].strip, :state=>l[5].strip, :proto=>l[6].strip, :comment=>l[7..-1].join(" ")}
          when line.match(/^Index|^=/)
            ""
          when line.match(/Created switches:/)
            @parsed[:created_switches]=line.split(":")[1].strip.split(" ").map {|l| l.to_i}
          #fabrics
          when line.match(/^\s*\d+:\s[a-f0-9]{6}/i)
            l=line.split(" ")
            @parsed[:fabric]||=[]
            @parsed[:fabric] << {:domain_id => l[0].gsub(/:/,"").strip, :sid => l[1].strip, :wwn=>l[2].strip, :eth_ip=>l[3].strip, :fc_ip=>l[4].strip, :name=>l[5].strip.gsub(/\"|>/,""), :local => l[5].strip.match(/^>/) ? true : false }
          when line.match(/^(zone|alias)\./)
            l=line.gsub!(/^(zone|alias)\./,"").split(":")
            @parsed[:find_results] << {:obj=>l.shift,:members=>l.join(":")}
          #default handling
          else
            if line.match(/^\s*[a-z]+.*:/i)
              arr = line.split(":")
              @parsed[str_to_key(arr[0])]=arr[1..-1].join(":").strip
            end
          end  
      end
      
      def parse_cfgshow(line)
        # once effective_configuration is loaded we ignore rest
        return if @parsed[:effective_configuration] and !@parsed[:effective_configuration][:cfg].nil?
        
        # we use array stack to point to the object being parsed
        @parsed[:pointer]||=[]
        @parsed[:key]||=[]
        @parsed[:last_key]||=nil
        @parsed[:was_popped]||=false
        
        if (matches=line.match(/^\s*([a-z]+\s*[a-z]+):(.*)/i))
          key=str_to_key(matches[1]) 
          after_colon=matches[2].strip
          
          # superkey
          if after_colon.empty?
            @parsed[key]||={}
            # we have new superkey so we pop the old from pointer stack
            # and we push the new in 
            @parsed[:pointer].pop if !@parsed[:pointer].empty? 
            @parsed[:pointer].push @parsed[key]
          # subkey
          else
            # sometimes the previous key does not have any members (or  they are filtered out)
            # in that case the key and pointer were not poped below so we pop them now
            if @parsed[:last_key]==key && !@parsed[:was_popped]
              @parsed[:pointer].pop
              @parsed[:key].pop
            end
            # we define the last subkey as hash
            # and push the array to pointer stack
            @parsed[:pointer].last[key]||={}
            @parsed[:pointer].push @parsed[:pointer].last[key] 
            
            # first value is name of the key
            # 2nd is list of key members 
            value=after_colon.split(" ")[0].strip 
            members=after_colon.split(" ").length>1 ? after_colon.split(" ")[1..-1].join(" ") : ""
            
            @parsed[:key].push value
          
            # adding value into the current pointer
            @parsed[:pointer].last[value]||=[]
            
            # assign members into the last pointer array item
            if !members.empty?
              @parsed[:pointer].last[value]||=[]
              members.split(";").each do |member|
                @parsed[:pointer].last[value]<<member.strip if !member.match(/^\s*$/)
              end
              # if the line does not end with ; next line starts with new key or super key
              # hence we remove last pointer from stack as we are done with it
              if !line.strip.match(/;$/)
                @parsed[:pointer].pop
                @parsed[:key].pop 
                @parsed[:was_popped]=true
              else
                @parsed[:was_popped]=false
              end
            else
              @parsed[:was_popped]=false
            end
          end
          @parsed[:last_key]=key
        # this line defines another members of last pointer key array item
        elsif line.match(/^\t/)
          @parsed[:last_key]=nil
          # sometimes it is not defined yet
          # we push the members in
          @parsed[:pointer].last[@parsed[:key].last]||=[]
          line.split(";").each do |member|
            @parsed[:pointer].last[@parsed[:key].last]<<member.strip if !member.match(/^\s*$/)
          end
          # if the line does not end with ; next line starts with new key or super key
          # hence we remove last pointer from stack as we are done with it 
          if !line.strip.match(/;$/)
            @parsed[:pointer].pop
            @parsed[:key].pop
            @parsed[:was_popped]=true
          else
            @parsed[:was_popped]=false
          end
        end
        true
      end
      
      def parse_ns(line)
        @parsed[:domain]||=0
        
        case
        
        # changing domain id
        when line.match(/Switch entry for/)
          @parsed[:domain]=line.split(" ").last.to_i
        
        # new WWN
        when line.match(/(^\s+N |^\s+U )/)
          @parsed[:key]= @parsed[:domain]==0 ? :wwn_local : :wwn_remote
          @parsed[@parsed[:key]]||=[]
          @parsed[@parsed[:key]].push Hash.new
          @parsed[@parsed[:key]].last[:value]=line.split(";")[2]
          @parsed[@parsed[:key]].last[:domain_id]=@parsed[:domain] 
          @parsed[@parsed[:key]].last[:symbol]||=""
        
        # symbol
        when line.match(/(PortSymb|NodeSymb)/)
          @parsed[@parsed[:key]].last[:symbol]=line.split(":")[1..-1].join(":").strip
        
        # detype  
        when line.match(/(Device type)/)     
          @parsed[@parsed[:key]].last[:dev_type]=line.split(":")[1].strip
        when line.match(/(Port Index)/)
          @parsed[@parsed[:key]].last[:port_index]=line.split(":")[1].strip.to_i
        end
        
      end
      
      def str_to_key(str)
        str.strip.gsub(/\s+/,"_").gsub(/([a-z])([A-Z])/,'\1_\2').downcase.to_sym
      end
    end
  end
  
  class Switch
    # class extending SshDevice::Error
     class Error < self::Error
     end
  end
end; end

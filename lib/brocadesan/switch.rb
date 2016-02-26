require 'net/ssh'
require 'yaml'

# Brocade namespace
module  Brocade 
# SAN namespace  
module SAN
  # TODO: zoneshow, cfgshow and alishow tests
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
  class Switch 
    
    include SshDevice
    
    # Maps each method name to command to be run to obtain it and to hash key where it ill be stored.
    # As well sets the format of the returned value. This is used only for documentation purposes.
    # 
    # See lib/config/brocade/san/switch_cmd_mapping.yml for details
    #
    # Example:
    #  :name:
    #   :cmd: switchshow
    #   :attr: switch_name
    #   :format: string
    #
    # This will cause that class will have instance method called name(forced=true).
    # When the method is called first time or +forced+ is true the +switchshow+ command
    # will be queried on the switch.
    # The query response will be then parsed and stored in Response +parsed+ hash under +:switch_name+ key.
    # The +parsed+ hash is then merged into switch +configuration+ hash.
    # At the end the +:switch_name+ key is returned from +configuration+ hash.
    #
    # The parser needs to ensure that it parses the +cmd+ output and stores the proper value into Response +parsed+ under +:attr+ key.
  
    CMD_MAPPING=YAML.load(File.read(Configuration::cmd_mapping_path(self)))
    
    # Maps each command to the parser method to use
    #
    # See lib/config/parser_mapping.yml for details
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
      raise Switch::Error.incorrect(name) if !name.match(/#{NAME_RULE}/i)
    end
    
    # Creates a Switch instance and tests a connection.
    #
    # Checks as well if the switch is virtual fabric enabled since that defines the way it will be queried further.
    def initialize(*params)
      super(*params)
      @configuration={}
      vf
    end
    
    # Hash containing parsed attributes
    #
    # Can be used to obtain parsed attributes for which there is no named method.
    # These attributes however has to be obtained as colateral of running another public method.
    #
    # Generally this attribute should not be accessed directly but named method for the given attribute should be created.
    #
    # Example:
    #
    #  # this will call switchshow (see CMD_MAPPING)
    #  # and load :several switchow values into configuration as well
    #  # the command however returns only whether the ls_attributtes
    #
    #  switch.configuration
    #  => nil
    #  switch.ls_attributes
    #  => {:fid=>"128", :base_switch=>"no", :default_switch=>"yes", :address_mode=>"0"}
    #  switch.configuration
    #  => {:vf=>"enabled", :parsing_position=>"end", :switch_name=>"H2C04R065-U03-A01", :switch_type=>"62.3", :switch_state=>"Online", ...
    #  switch.configuration[:switch_name]
    #  => "H2C04R065-U03-A01"
    #
    #  # this swichname will be taken from cache as the switchshow was started as part of ls_attributes
    #  switch.name
    #  => "H2C04R065-U03-A01"
    
    
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
    
    # override VF settings
    # all commands will run only on base switch
    # this is to allow to run certain commands on VF enabled switches untill the fosexec is fixed 
    def override_vf
      @configuration[:override_vf]=true
    end
    # gets the +attr+
    #
    # +attr+ has to be speficied in the CMD_MAPPING
    #
    # named methods are wrappers around this method so you should not use this directly
    def get(attr,forced=false)
      raise Switch::Error.unknown if CMD_MAPPING[attr.to_sym].nil?
      
      cmd=CMD_MAPPING[attr.to_sym][:cmd]
      
      refresh(cmd,"",forced)
      
      @configuration[CMD_MAPPING[attr.to_sym][:attr].to_sym]
    end
    
    # returns switches in the fabric in hash form
    
    def fabric(forced=false)
      cmd="fabricshow"
      refresh(cmd,"",forced)
      @configuration[:fabric]
    end
    
    # If called with +true+ argument it will get the virtual_fabric from the switch instead of cache
    #
    # Returns value in (string) format
    
    def vf(forced=false)
      if !@configuration[:vf] || forced
        # using this instead of fosconfig --show as that command does not work everywhere
        # we could user #ls_attributes method but that loaded whole switchshow os this will be a bit faster, especially with big switches
        # it needs to be faster as vf is called during initialization
        # if the switch is vf there will be LS Attributes line, otherwise it will be empty
        response=query("switchshow|grep \"^LS Attributes\"")
        @configuration[:vf] = response.data.split("\n").size == 2 ? "enabled" : "disabled"
      end
      @configuration[:vf]
    end
    
    # Returns ZoneConfigurations array
    #
    # If +full+ is set to true it loads full configurations with zones and aliases, otherwise it gets just the names.
    #
    # It laods even zone configurations that were create as part of ongoing transaction.
    def zone_configurations(full=false,forced=false)
      get_configshow(full,forced)[:zone_configurations]
    end
    
    # Returns effective ZoneConfiguration
    #
    # If +full+ is set to true it loads full effective configuration with zones and aliases, otherwise it gets just the name
    def effective_configuration(full=false,forced=false)
      zone_configurations(full,forced).select {|z| z.effective == true}.first
    end
    
    # returns all zones defined on the switch including zones created in ongoing transaction as array of Zone
    
    def zones(forced=false)
      get_configshow(true,forced)[:zones]
    end
    
    # returns all aliases defined on the switch including aliases created in ongoing transaction as array of Alias
    
    def aliases(forced=false)
      get_configshow(true,forced)[:aliases]
    end
    
    # returns Zone with name of +str+ if exists, +nil+ otherwise
    def find_zone(str)
      find(str,:object=>:zone)
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
    # +mode+
    #
    # [:local]  returns all local WWNs
    # [:cached] returns wwns cached from remote switches
    # [:all]    returns all local and remote wwns
    
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
    # +opts+
    #
    # [:fabric_wide]  searches whole fabric
    def find_wwn(value,forced=true,opts={:fabric_wide=>false})
      objs = opts[:fabric_wide]==true ? get_ns(true,forced,:local=>true).concat(get_ns(true,forced,:remote=>true)) : get_ns(true,forced,:local=>true)
      objs.find {|k| value.downcase == k.value.downcase}
    end
    
    # finds configuration object by +str+. Case insensitive.
    # If the +object+ option is not specified it searches :zone objects. It finds only saved objects. If the object was created but the transaction is not confirmed it will not find it.
    #
    # +opts+
    #
    # [:object]     :zones (default) - finds zones
    #
    #               :aliases - finds aliases
    # [:find_mode]  :partial - find partial matches
    #
    #               :exact(default) - finds exact matches
    #
    # Example:
    #
    # switch.find("zone1",:object=>:zone)
    def find(str,opts={})
      # do not change the following 3 lines without writing test for it     
      obj = !opts[:object].nil? && [:zone,:alias].include?(opts[:object]) ? opts[:object] : :zone
      mode = !opts[:find_mode].nil? && [:partial,:exact].include?(opts[:find_mode]) ? opts[:find_mode] : :exact
      grep_exp = mode==:exact ? " | grep -i -E ^#{obj}\.#{str}:" : " | grep -i -E ^#{obj}\..*#{str}.*:"  
      
      response = script_mode do
        query("configshow"+grep_exp)
      end
      response.parse
      
      #output of configshow is stored to find_results
      
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
      # result is array of Zone or Alias instances
      result
    end
    
    # finds configuration objects that have member specified by +str+. Case insensitive.
    # If the +object+ option is not specified it searches :zone objects.
    # See find_by_member_from_cfgshow.
    #
    # +opts+
    #
    # [:object]     :all (default) - finds all objects (zones, configs, aliases)
    #
    #               :aliases - finds aliases
    #
    #               :zones - finds zones
    #
    # [:find_mode]  :partial - find partial matches
    #
    #               :exact(default) - finds exact matches
    #
    # [:transaction]  false (defualt) - ignores object in ongoing transaction
    #
    #                 true - includes objects in ongoing transaction
    #
    # Example:
    #
    # switch.find_by_member("zone1",:object=>:cfg)
    #
    # Note:
    #
    # Zone can be only members of zone configuration and alias can be only members of zones so finding object that have them as members works with default :all :object.
    # However WWNs can be part both of zones and aliases so that is why there is option to speficy the object

    def find_by_member(str,opts={})
      obj = !opts[:object].nil? && [:zone,:alias,:all].include?(opts[:object]) ? opts[:object] : :all
      obj = "zone|alias|cfg" if obj==:all
      mode = !opts[:find_mode].nil? && [:partial,:exact].include?(opts[:find_mode]) ? opts[:find_mode] : :exact
      
      trans_inc = !opts[:transaction].nil? && [true,false].include?(opts[:transaction]) ? opts[:transaction] : false
      
      base_grep1 = "^#{obj}\."
      base_grep2 = mode==:exact ? "(:|;)#{str}(;|$)" : ":.*#{str}"
    
      if trans_inc
        grep_exp1 = /#{base_grep1}/i
        grep_exp2 = /#{base_grep2}/i
        response = script_mode do
          query("cfgshow")
        end
        response.send :cfgshow_to_configshow, grep_exp1, grep_exp2
      else
        grep_exp = " | grep -i -E \"#{base_grep1}\""
        grep_exp += " | grep -i -E \"#{base_grep2}\""
        response = script_mode do
          query("configshow"+grep_exp)
        end
      end
      
      response.parse
      #output of configshow is stored to find_results
      
      objs=response.parsed[:find_results]
      objs||=[]
      
      result=[]
      
      objs.each do |item|
         i = case item[:type]
         when :zone
            Zone.new(item[:obj])
         when :alias
            Alias.new(item[:obj])
         when :cfg
           ZoneConfiguration.new(item[:obj])
         end 
         item[:members].split(";").each do |member|
           i.add_member(member)
         end
         result<<i
      end
      # result is array of Zone, Alias, and ZoneConfiguration instances
      result
    end
    
    def query(*cmds) #:nodoc
      if get_mode=="interactive"
        cmds[0]=fullcmd(cmds[0])
      else
        cmds.map! {|cmd| fullcmd(cmd)}
      end
      super(*cmds)
    end
    
    private
    
    def should_refresh?(cmd, forced)
      !@loaded || !@loaded[key(cmd)] || forced  
    end
     
    def get_configshow(full=false,forced=false)
      cmd="cfgshow"
      filter = full==false ? "-e cfg: -e configuration:" : ""
      
      refresh(cmd,filter,forced)
        
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
      
      refresh(cmd,filter,forced)
        
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
    
    def refresh(cmd,filter="",forced=true)
      return @loaded[key(cmd)] if !should_refresh?(cmd+filter,forced)
      grep_exp=filter.empty? ? "" : " | grep #{filter}"
      response=script_mode do
        query(cmd+grep_exp)
      end
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
      if @configuration[:vf]=="enabled" && @fid && !@configuration[:override_vf]
        cmds = cmd.split("|") 
        if cmds.size>1
          "fosexec --fid #{@fid} -cmd \'#{cmds.shift}\' |#{cmds.join("|")}"
        else
          "fosexec --fid #{@fid} -cmd \'#{cmds.shift}\'"
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
      
      # transfers cfgshow to configshow format
      def cfgshow_to_configshow(*greps)
        # check if we have configshow output
        return false if !@data.match(/> cfgshow/m)
        # replace command
        @data.gsub!("cfgshow","configshow")
        # remove all lines below Effective configuration: included and Defined configuration line
        @data.gsub!(/(Defined configuration:\s*|Effective configuration:.*)/im,"")
        # remove spaces followig ; (includes newlines)
        @data.gsub!(/;\s+/m,";")
        # remove newlines before first member
        @data.gsub!(/\t\n\t+/m,":")
        # removes tab before first member
        @data.gsub!(/([a-z_0-9])\t+([a-z_0-9])/im,'\1:\2')
        # substitute alias,zone and cfg name
        @data.gsub!(/^\s*(zone|alias|cfg):\s+/,'\1.')
        #removes any empty character except newline
        @data.gsub!(/[ \t]+\n/,"\n")
        greps.each do |grep_t|
          @data=@data.split("\n").grep(grep_t).join("\n")
        end
        @data="> configshow\n#{@data}"
        true
      end
      
      def before_parse
        reset
        @parsed[:find_results]=[]
        @parsed[:base]={}
      end
      
      def after_parse
        @parsed[:ports].uniq! if @parsed[:ports]
        to_purge = [:pointer,:last_key,:key,:domain,:was_popped]
        to_purge<<:find_results if @parsed[:find_results].empty?
        to_purge<<:base if @parsed[:base].empty?
        to_purge.each {|k| @parsed.delete(k)}
      end
      
      def parse_line(line)
        return if line.empty?
        # we detect which command output we parse - commands start with defined prompt on the XML line
        @parsed[:parsing_position] = case
          # stripping fosexec, all pipes and ' to get pure command 
          when line.match(/^#{@prompt}/) then line.gsub(/(fosexec --fid \d+ \')|\'$|\' \|.*$/,"").split(" ")[1]
          else @parsed[:parsing_position]
        end
        #some default processing
        if line.match(/^#{@prompt}/)
          case @parsed[:parsing_position]
          when "islshow"
            @parsed[:isl_links]||=[]
          when "trunkshow"
            @parsed[:trunk_links]||=[]
          when "agshow"
            @parsed[:ag]||=[]
          when "cfgtransshow"
            # if empty hash is returned the response was unexpected
            @parsed[:cfg_transaction]={}
          end
        end
        #do not process if we are on command line
        return if line.match(/^#{@prompt}/)
  
        # we parse only certain commands definned in PARSER_MAPPING
        # all other commands are ignored by parser
        # you can call them usign query and parse by yourself if you need some other
        # or define parser mapping, command mapping and update given parser
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
          when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='trunk' ? k : nil }.compact.join("|")}/i)
            parse_trunk(line)
        end
      end
      
      # parser used to parse commands with 1 line output
      def parse_oneline(line)
        @parsed[@parsed[:parsing_position].to_sym]=line
      end
      
      # parser used to parse commands with multi lines output
      def parse_multiline(line)
        # switchstatusshow
        case
        when line.match(/^\s*[a-z]+.*:/i)
          arr = line.split(":")
          @parsed[arr[0].strip.gsub(/\s+/,"_").gsub(/([a-z])([A-Z])/,'\1_\2').downcase.to_sym]=arr[1..-1].join(":").strip
        when line.match(/^There is no outstanding/) && @parsed[:parsing_position]=="cfgtransshow"
          @parsed[:cfg_transaction] = {:id=>-1, :abortable=>nil, :msg => "no transaction"}
        when line.match(/^Current transaction token is (.+)$/) && @parsed[:parsing_position]=="cfgtransshow"
          @parsed[:cfg_transaction][:id] = $1
        when line.match(/It is(.+)abortable$/) && @parsed[:parsing_position]=="cfgtransshow"
          @parsed[:cfg_transaction][:abortable] = $1.match(/not/) ? false : true
        else
          #supportshow
          @parsed[@parsed[:parsing_position].to_sym]||=""
          @parsed[@parsed[:parsing_position].to_sym]+=line+"\n"
        end
      end
      
      # parser for multiline output where each line is independent
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
          when line.match(/Created switches/)
            @parsed[:created_switches]=line.split(":")[1].strip.split(" ").map {|l1| l1.to_i}
          #fabrics
          when line.match(/^\s*\d+:\s[a-f0-9]{6}/i)
            l=line.split(" ")
            @parsed[:fabric]||=[]
            @parsed[:fabric] << {:domain_id => l[0].gsub(/:/,"").strip, :sid => l[1].strip, :wwn=>l[2].strip, :eth_ip=>l[3].strip, :fc_ip=>l[4].strip, :name=>l[5].strip.gsub(/\"|>/,""), :local => l[5].strip.match(/^>/) ? true : false }
          when line.match(/^(zone|alias|cfg)\./)
            l=line.gsub!(/^(zone|alias|cfg)\./,"").split(":")
            @parsed[:find_results] << {:obj=>l.shift,:members=>l.join(":"), :type => $1.to_sym}
          #agshow
          when line.match(/^([a-f0-9]{2}:){7}[a-f0-9]{2}\s+\d+/i) && @parsed[:parsing_position]=="agshow"
            l=line.split(" ")
            @parsed[:ag]||=[]
            @parsed[:ag] << {:wwn => l[0].strip, :ports => l[1].to_i, :eth_ip=>l[2].strip, :version=>l[3].strip, :local => l[4].strip.match(/^local/) ? true : false, :name => l[5].strip } 
          #islshow
          #   1:  0->  0 10:00:00:05:33:23:86:00   1 H2C04R065-U03-A sp:  8.000G bw: 64.000G TRUNK QOS
          when line.match(/\d+:\s*\d+->.+sp:/)
            l_tricky, l_simple = line.split("->")
            l_t = l_tricky.split(":")
            
            l = l_simple.split(" ")
            @parsed[:isl_links]||=[]
            @parsed[:isl_links] << {:id => l_t[0].to_i, 
                                    :source_port_index => l_t[1].to_i, 
                                    :destination_port_index => l[0].to_i, 
                                    :destination_switch_wwn => l[1].strip, 
                                    :destination_switch_domain => l[2].to_i, 
                                    :destination_switch_name => l[3].strip, 
                                    :speed => l[5].to_i,
                                    :bandwidth => l[7].to_i,
                                    :trunk => l[8..-1].include?("TRUNK"),
                                    :qos => l[8..-1].include?("QOS"),
                                    :cr_recov => l[8..-1].include?("CR_RECOV")
                                    }
          #default handling if it doesno match specialized match
          # parse lines formated like 
          # param: value
          else
            if line.match(/^\s*[a-z]+.*:/i)
              arr = line.split(":")
              @parsed[str_to_key(arr[0])]=arr[1..-1].join(":").strip
            end
          end  
      end
      
      # parser dedicated to cfgshow format
      def parse_cfgshow(line)
        # once effective_configuration is loaded we ignore rest
        return if @parsed[:effective_configuration] and !@parsed[:effective_configuration][:cfg].nil?
        
        # we use array stack to point to the object being parsed
        @parsed[:pointer]||=[]
        @parsed[:pointer].push @parsed[:base] if @parsed[:pointer].empty?
        @parsed[:key]||=[]
        @parsed[:last_key]||=nil
        @parsed[:was_popped]||=false
        
        if (matches=line.match(/^\s*([a-z]+\s*[a-z]+):(.*)/i))
          key=str_to_key(matches[1]) 
          after_colon=matches[2].strip
          
          # superkey -> defined_configuration, efective_configuration, cfg, zone, alias
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
      
      # name server parser
      def parse_ns(line)
        @parsed[:domain]||=0
        @parsed[:key] = @parsed[:parsing_position]=="nsshow" ? :wwn_local : :wwn_remote
        @parsed[@parsed[:key]]||=[]
        
        case
        
        # changing domain id
        when line.match(/Switch entry for/)
          @parsed[:domain]=line.split(" ").last.to_i
        
        # new WWN
        when line.match(/(^\s+N |^\s+U )/)
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
      
      # trunk parser
      def parse_trunk(line)
        return if line.match(/No trunking/i)
        @parsed[:trunk_links]||=[]
        l_tricky, l_simple = line.split("->")
        l_t = l_tricky.split(":")
           
        l = l_simple.split(" ")
        case
        when line.match(/\d+:\s*\d+->/)
          @parsed[:trunk_links]<<{:id => l_t[0].to_i, :members => [
                                    { 
                                    :source_port_index => l_t[1].to_i, 
                                    :destination_port_index => l[0].to_i, 
                                    :destination_switch_wwn => l[1].strip, 
                                    :destination_switch_domain => l[2].to_i, 
                                    :deskew => l[4].to_i,
                                    :master => l[5]=="MASTER"
                                    }]
                                 }
        else
          @parsed[:trunk_links].last[:members]<<{ 
                                    :source_port_index => l_t[0].to_i, 
                                    :destination_port_index => l[0].to_i, 
                                    :destination_switch_wwn => l[1].strip, 
                                    :destination_switch_domain => l[2].to_i, 
                                    :deskew => l[4].to_i,
                                    :master => l[5]=="MASTER"
                                    }
        end
      end
      
      # transforamtino method to define parsed key based on the string
      def str_to_key(str)
        str.strip.gsub(/\s+/,"_").gsub(/([a-z])([A-Z])/,'\1_\2').downcase.to_sym
      end
    end
  end
  
  class Switch
    # class extending SshDevice::Error
     class Error < self::Error
       WRONG_FORMAT="Error: Incorrect format"
       def self.incorrect(str) #:nodoc:
         self.new("#{WRONG_FORMAT} - #{str}")
       end
       
       def self.unknown
         self.new("Unknown attribute")
       end
     end
  end
end; end

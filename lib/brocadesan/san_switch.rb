require 'net/ssh'
require 'yaml'

# Class to model SAN switch from Brocade
class SanSwitch < BrocadeSanDevice
  # Maps each method name to command to be run to obtain it and to hash key where it ill be stored
  # 
  # See lib/config/san_switch_cmd_mapping.yml for details
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

  CMD_MAPPING=YAML.load(File.read(File.join("lib","config","#{self.name.underscore}_cmd_mapping.yml")))
  
  # Maps each command to the parser method to use
  PARSER_MAPPING=YAML.load(File.read(File.join("lib","config","parser_mapping.yml")))
  
  # Used to dynamically create named methods based on CMD_MAPPING
  def self.attributes(args)
    args.each do |arg|
     define_method arg do |forced=false|
       self.get(arg,forced)
     end
    end
  end
  
  # Creates a SanSwitch instance and tests a connection.
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
    raise SanSwitch::Error.new('Unknown attribute') if CMD_MAPPING[attr.to_sym].nil?
    
    cmd=CMD_MAPPING[attr.to_sym][:cmd]
    
    refresh(cmd) if !@loaded || !@loaded[key(cmd)] || forced
    
    @configuration[CMD_MAPPING[attr.to_sym][:attr].to_sym]
  end
  
  private
  
  def refresh(cmd)
    response=query(fullcmd(cmd))
    response.parse
    
    #puts response.data

    @configuration||={}
    @configuration.merge!(response.parsed)
    
    @loaded||={}
    @loaded[key(cmd)]=true
    
    return @loaded[key(cmd)]
  end
  
  def key(cmd)
    cmd.gsub(/\s+/,'_').to_sym
  end
  
  def fullcmd(cmd)
    if @configuration[CMD_MAPPING[:vf][:attr].to_sym]=="enabled" && @fid 
      "fosexec --fid #{@fid} \'#{cmd}\'"
    else
      cmd
    end
  end
end

class SanSwitch
  # classs extending BrocadeSanDevice::Response
  class Response < self::Response
    
    # Wrapper around BrocadeSanDevice::Response +parse+ that
    # includes before and after hooks
    
    def parse
      before_parse
      super
      after_parse
    end
    
    private 
    
    def before_parse
    end
    
    def after_parse
      @parsed[:ports].uniq! if @parsed[:ports]
    end
    
    def parse_line(line)
      return if line.empty?
      # we detect which command output we parse - commands start with > on the XML line
      @parsed[:parsing_position] = case 
        when line.match(/^#{SanSwitch::QUERY_PROMPT}/) then line.gsub(/(fosexec --fid \d+ \')|\'$/,"").split(" ")[1]
        else @parsed[:parsing_position]
      end
      #do not process if we are on query line
      return if line.match(/^#{SanSwitch::QUERY_PROMPT}/)

      # we parse only certain commands
      case 
        when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='simple' ? k : nil }.compact.join("|")}/i)
          parse_simple(line)
        when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='oneline' ? k : nil }.compact.join("|")}/i)
          parse_oneline(line)
      end
    end
    
    def parse_oneline(line)
      @parsed[@parsed[:parsing_position].to_sym]=line
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
        #default handling
        when line.match(/Created switches:/)
          @parsed[:created_switches]=line.split(":")[1].strip.split(" ").map {|l| l.to_i}
        else
          if line.match(/^\s*[a-z]+.*:/i)
            arr = line.split(":")
            @parsed[arr[0].strip.gsub(/\s+/,"_").gsub(/([a-z])([A-Z])/,'\1_\2').downcase.to_sym]=arr[1..-1].join(":").strip
          end
        end  
    end
  end
end

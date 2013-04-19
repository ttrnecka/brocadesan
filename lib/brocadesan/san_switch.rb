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
  
  attributes CMD_MAPPING.keys
  
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
    response=query(cmd)
    response.parse

    @configuration||={}
    @configuration.merge!(response.parsed)
    
    @loaded||={}
    @loaded[key(cmd)]=true
    
    return @loaded[key(cmd)]
  end
  
  def key(cmd)
    cmd.gsub(/\s+/,'_').to_sym
  end
end

class SanSwitch
  # classs extending BrocadeSanDevice::Response
  class Response < self::Response
    private 
    
    def parse_line(line)
      return if line.empty?
      # we detect which command output we parse - commands start with > on the XML line
      @parsed[:parsing_position] = case 
        when line.match(/^#{SanSwitch::QUERY_PROMPT}/) then line.split(" ")[1]
        else @parsed[:parsing_position]
      end
      #do not process if we are on query line
      return if line.match(/^#{SanSwitch::QUERY_PROMPT}/)

      # we parse only certain commands
      case 
        when @parsed[:parsing_position].match(/#{PARSER_MAPPING.map{ |k,v| v=='simple' ? k : nil }.compact.join("|")}/i)
          parse_simple(line)
      end
    end
  
    def parse_simple(line)
      case
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
        when line.match(/\s?\d{1,3}\s+\d{1,2}\s+\d{1,2}\s+[\dabcdef]{6}/i)
          ""
        #  l=line.split
        #  @switches.last[:ports][l[0].to_i]={:slot=>l[1].strip, :portid=>l[2].strip, :fcid=>l[3].strip, :speed=>l[5].strip, :state=>l[6].strip, :comment=>line.slice(48..line.length)}
        # port line in san blade
        when line.match(/\s?\d{1,3}\s+\d{1,2}\s+[\dabcdef]{6}/i)
          ""
        #  l=line.split
        #  @switches.last[:ports][l[0].to_i]={:slot=>0, :portid=>l[1].strip, :fcid=>l[2].strip, :speed=>l[4].strip, :state=>l[5].strip, :comment=>line.slice(44..line.length)}
        when line.match(/^Index|^=/)
          ""
        else
          if line.match(/:/)
            arr = line.split(":")
            @parsed[arr[0].gsub(/\s+/,"_").gsub(/([a-z])([A-Z])/,'\1_\2').downcase.to_sym]=arr[1..-1].join(":").strip
          end
        end  
    end
  end
end

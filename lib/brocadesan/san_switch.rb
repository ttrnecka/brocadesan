require 'net/ssh'
require 'yaml'

class SanSwitch < BrocadeSanDevice
  
  attr_reader :configuration
  CMD_MAPPING=YAML.load(File.read(File.join("lib","config","switch_cmd_mapping.yml")))
  
  def name(forced=false)
    cmd=CMD_MAPPING[:name][:cmd]
    refresh(cmd) if !@loaded || !@loaded[key(cmd)] || forced
    @configuration[CMD_MAPPING[:name][:attr].to_sym]  
  end
  
  def refresh(cmd) 
    response=query(cmd)
    response.parse
    
    @configuration||={}
    @configuration.merge!(response.parsed)
    
    @loaded||={}
    @loaded[key(cmd)]=true
    
    return @loaded[key(cmd)]
  end
  
  private
  
  def key(cmd)
    cmd.gsub(/\s+/,'_').to_sym
  end
end

class SanSwitch
  class Response < self::Response
    private 
    
    def parse_line(line)
      return if line.empty?
      # we detect which command output we parse - commands start with > on the XML line
      @parsed[:parsing_position] = case 
        when line.match(/^>/) then line.split(" ")[1]
        else @parsed[:parsing_position]
      end
      
      #do not process if we are on query line
      return if line.match(/^#{SanSwitch::QUERY_PROMPT}/)
      
      # we parse only certain commands
      case 
        when @parsed[:parsing_position].match(/SWITCHSHOW/i)
          parse_switchshow(line)
      end
    end
  
    def parse_switchshow(line)
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
          arr = line.split(":")
          @parsed[arr[0].gsub(/\s+/,"_").gsub(/([a-z])([A-Z])/,'\1_\2').downcase.to_sym]=arr[1..-1].join(":").strip
        end  
    end
  end
end

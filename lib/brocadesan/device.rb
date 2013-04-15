require 'net/ssh'

class BrocadeSanDevice
  QUERY_PROMPT="> "
  
  def initialize(address,user,password,opts={})
      @address=address
      @user=user
      @password=password
      @opts=opts
      @connection=nil
  end
  
  def self.open_connection(address,user,password,opts={})
    dev=self.new(address,user,password,opts)
    dev.connect
    return dev
  end
  
  def connect
    @connection = Net::SSH.start(@address,@user, :password=>@password)
  end
  
  def query(cmd)
    raise BrocadeSanDevice::Error, "No connection" if @connection.nil?
    
    output=BrocadeSanDevice::Response.new
    
    @connection.exec cmd do |ch, stream, data|
      if stream == :stderr
        output.errors=data
      else
        output.data=QUERY_PROMPT+cmd+"\n"+data
      end
    end
    
    return output
  end
  
  
  class Response
    attr_accessor :data, :errors, :parsed
  
    def initialize
      @errors=""
      @data=""
      @parsed = {
       :parsing_position=>nil
      }
    end
    
    def reset
      @parsed = {
       :parsing_position=>nil
      }
    end
    
    def parse
      reset if !@parsed.kind_of? Hash
      @data.split("\n").each do |line|
        parse_line line
      end
      @parsed[:parsing_position]="end"
    end
    
    private 
    
    def parse_line(line)
    end
  end
  
  class Error < Exception; end
end
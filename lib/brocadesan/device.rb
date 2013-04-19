require 'net/ssh'

class BrocadeSanDevice
  QUERY_PROMPT="> "
  
  def initialize(address,user,password,opts={})
      @address=address
      @user=user
      @password=password
      @opts=opts
      @session=nil
  end
  
  def query(cmd)
    output=nil
    if @session
      output=exec(@session,cmd)
    else
      Net::SSH.start @address, @user, :password=>@password do |ssh|
        output=exec(ssh,cmd)
      end
    end
    
    return output
  end
  
  def session
    @session=Net::SSH.start @address, @user, :password=>@password
    yield
    
  ensure
    @session.close if @session
  end
  
  private
  
  def exec(ssh_session,cmd)
    output=BrocadeSanDevice::Response.new
    ssh_session.exec cmd do |ch, stream, data|
      if stream == :stderr
        output.errors=data
      else
        output.data=QUERY_PROMPT+cmd+"\n"+data
      end
    end
    
    return output
  end
end

class BrocadeSanDevice
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
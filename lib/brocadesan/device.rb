require 'net/ssh'

# Basic wrapper class that runs SSH queries on the device and returns Response
#
# It is used to extend further classes with SSH query mechanism
 
class BrocadeSanDevice
  
  # default query prompt that will preceed each command started you +query+ in the Response +data+
  QUERY_PROMPT="> "
  
  # Initialization method, +opts+ not used yet 
  def initialize(address,user,password,opts={}) # :nodoc:
      @address=address
      @user=user
      @password=password
      @opts=opts
      @session=nil
  end
  
  # Queries +cmds+ commands directly. 
  # This method is to be used to extend this API 
  # or 
  # to do more difficult queries that have to be parsed separately
  #
  # Query command will open connection to device if called outside session block
  # or use existing if called within session block.
  #
  # Example:
  #   >> device.query("switchname")
  #   => #<BrocadeSanDevice::Response:0x2bb1e00 @errors="", @data="sanswitchA", @parsed={:parsing_position=>"end"}>
  #
  # 
  # Returns instance of Response or raises error if the connectionm cannot be opened
  def query(*cmds)
    output=nil
    if @session && !@session.closed?
      output=exec(@session,cmds)
    else
      Net::SSH.start @address, @user, :password=>@password do |ssh|
        output=exec(ssh,cmds)
      end
    end
    
    return output
  end
  
  # Opens a session
  # 
  # All queries within the session use the same connection. This speeds up the query processing.
  # 
  # The connection is closed at the end of the block
  #
  # Example:
  #   device.session do 
  #     device.query("switchname")
  #     device.version
  #   end
  # 
  # 
  def session
    @session=Net::SSH.start @address, @user, :password=>@password
    yield
    
  ensure
    @session.close if @session
  end
  
  private
  
  def exec(ssh_session,cmds)
    # this approach is used to use Response of the calling class
    output=self.class::Response.new
    cmds.each do |cmd|
      output.data+=QUERY_PROMPT+cmd+"\n"
      ssh_session.exec! cmd do |ch, stream, data|
        if stream == :stderr
          output.errors+=data
        else
          output.data+=data
        end
      end
      output.errors+="\n"
      output.data+="\n"
    end
    return output
  end
end


class BrocadeSanDevice
  # This class defines the device response and it should not be manipulated directly
  # Only exception is direct usage of query method which returns instance of this class

  class Response
    # contains output of the command
    attr_accessor :data
    # contains errors raised by SSH exec
    attr_accessor :errors
    # contains parsed information after the parse method ran
    attr_accessor :parsed # :nodoc:
  
    #initialization method
    def initialize # :nodoc:
      @errors=""
      @data=""
      @parsed = {
       :parsing_position=>nil
      }
    end
    
    # Resets all parsed data
    #
    def reset # :nodoc:
      @parsed = {
       :parsing_position=>nil
      }
    end
    
    # Parse the current data and stores result to +parsed+.
    #
    # Any class that extends this class should override the private parse_line method and store results into +parsed+ hash
    def parse # :nodoc:
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
  
  # Class using for raising specific errors
  class Error < Exception; end
end
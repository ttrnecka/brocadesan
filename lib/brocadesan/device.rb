require 'net/ssh'

# Basic wrapper class that runs SSH queries on the device and returns Response
#
# It is used to extend further classes with SSH query mechanism
 
module SshDevice
  
  # default query prompt that will preceed each command started you +query+ in the Response +data+
  QUERY_PROMPT="> "
  
  # Initialization method, +opts+ not used yet 
  # opts
  # => :interactive => +true+ / +false+
  #    will use interactive query
  #    can be set later
  def initialize(address,user,password,opts={}) # :nodoc:
      @address=address
      @user=user
      @password=password
      @opts=opts
      @session=nil
  end
  
  # get current query mode
  # response is either +interactive+ or +script+
  def get_mode
    [true,false].include?(@opts[:interactive]) ? (@opts[:interactive]==true ? "interactive" : "script") : "script"
  end
  
  # sets current query mode
  # +mode+ : interactive or script
  #
  # interactive - meant to do interactive queries in scripted manner
  def set_mode(mode)
    @opts[:interactive] = mode == "interactive" ? true : false
    get_mode
  end
  
  # Queries +cmds+ commands directly. 
  # This method is to be used to extend this API 
  # or 
  # to do more difficult queries that have to be parsed separately
  #
  # When started in interactive mode be sure the command is followed by inputs for that command.
  # If command will require additional input and there is no one provided the command will receive +enter+
  #
  # Query command will open connection to device if called outside session block
  # or use existing if called within session block.
  #
  # Example:
  #   >> class Test
  #   >>   include SshDevice
  #   >> end
  #   >> device = Test.new("address","user","password")
  #   >> device.query("switchname")
  #   => #<Test::Response:0x2bb1e00 @errors="", @data="> switchname\nsanswitchA\n", @parsed={:parsing_position=>"end"}>
  #
  # 
  # Returns instance of Response or raises error if the connectionm cannot be opened
  #
  # Raises Error if SSH returns error. SSH error will be available in the exception message
  def query(*cmds)
    output=nil
    if @session && !@session.closed?
      output=exec(@session,cmds)
    else
      Net::SSH.start @address, @user, :password=>@password do |ssh|
        output=exec(ssh,cmds)
      end
    end
    
    raise self.class::Error.new(output.errors) if !output.errors.empty?
    
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
    
    @opts[:interactive]||=false
    # this approach is used to use Response of the calling class
    if @opts[:interactive]==true
      interactive_exec(ssh_session,cmds)
    else
      standard_exec(ssh_session,cmds)
    end
  end
  
  def standard_exec(ssh_session,cmds)
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
      output.errors+="\n" if !output.errors.empty?
      output.data+="\n"
    end
    return output
  end
  
  # interactive exec considers cmds as inputs, only first item is considered as command
  def interactive_exec(ssh_session,cmds)
    output=self.class::Response.new
    cmd=cmds.shift
    output.data+=QUERY_PROMPT+cmd+"\n"
    ssh_session.open_channel do |channel|
      channel.request_pty
      channel.exec cmd do |ch, success|
        abort "could not execute #{cmd}" unless success
        ch.on_data do |ch, data|
          output.data+=data
          if !data.match(/\n$/)
            stdin = cmds.empty? ? "\n" : cmds.shift+"\n"
            ch.send_data stdin
            output.data+=stdin
          end
        end

        ch.on_extended_data do |ch, type, data|
          output.errors+=data
        end      
      end
    end  
    ssh_session.loop
    return output
  end
end


module SshDevice
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
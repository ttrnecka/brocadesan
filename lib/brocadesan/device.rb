require 'net/ssh'

# Basic wrapper class that runs SSH queries on the device and returns Response
#
# It is used to extend further classes with SSH query mechanism
 
module SshDevice
  
  # default query prompt that will preceed each command started by +query+ in the Response +data+
  #
  # value is "> "
  #
  # This way the parser can separate from commands and data. The default will work everwhere where the retunned data is not prepended by "> "
  #
  # Ignore the ssh prompt like this:
  # super_server(admin)> cmd
  # super_server(admin)> data
  #
  # This on the other hand would be problem. In this case override the prompt
  # super_server(admin)> cmd
  # super_server(admin)>> data
  
  DEFAULT_QUERY_PROMPT="> "
  
  attr_reader :prompt
  
  # Initialization method
  # 
  # +opts+ can be:
  #
  # [:interactive] +true+ / +false+
  #                will use interactive query
  #                can be set later
  # [:prompt]      +prompt+
  #                will override the DEFAULT_QUERY_PROMPT
  def initialize(address,user,password,opts={}) 
      @address=address
      @user=user
      @password=password
      @opts=opts
      @session=nil
      @session_level=0
      @prompt = opts[:prompt] ? opts[:prompt].to_s : DEFAULT_QUERY_PROMPT
  end
  
  # get current query mode
  #
  # returns either +interactive+ or +script+
  #
  # default mode is +script+
  def get_mode
    [true,false].include?(@opts[:interactive]) ? (@opts[:interactive]==true ? "interactive" : "script") : "script"
  end
  
  # sets current query mode
  #
  # +mode+: interactive or script
  #
  # interactive - used to do interactive queries in scripted manner by providing all responses in advance, see #query
  def set_mode(mode)
    @opts[:interactive] = mode.to_s == "interactive" ? true : false
    get_mode
  end
  
  # Queries +cmds+ commands directly. 
  # This method is to be used to implement higlevel API 
  # or 
  # to do more difficult queries that have to be parsed separately and for which there is now highlevel API
  #
  # When started in interactive mode be sure the command is followed by inputs for that command.
  # If command will require additional input and there is not one provided the prompt will receive +enter+.
  # It will do this maximum of 100 times, then it gives up and returns whatever it got until then.
  #
  # Query command will open connection to device if called outside session block
  # or use existing session if called within session block.
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
  # Returns instance of Response or raises Error if the connection cannot be opened
  #
  # Raises Error if SSH returns error. SSH error will be available in the exception message
  def query(*cmds)
    output=nil
    if session_exist?
      output=exec(@session,cmds)
    else
      Net::SSH.start @address, @user, :password=>@password do |ssh|
        output=exec(ssh,cmds)
      end
    end
    
    raise self.class::Error.new(output.errors) if !output.errors.empty?
    
    return output
  end
  
  # Opens a session block
  # 
  # All queries within the session block use the same connection. This speeds up the query processing.
  # 
  # The connection is closed at the end of the block
  # 
  # The command supports session blocks within session blocks. Session will be closed only at the last block
  #
  # Example:
  #   device.session do 
  #     device.query("switchname")
  #     device.version
  #   end
  # 
  # Raises SshDevice::Error if run without block
  def session
    raise self.class::Error.new(self.class::Error::SESSION_WTIHOUT_BLOCK) if !block_given?
    @session_level+=1
    if !session_exist?
      @session=Net::SSH.start @address, @user, :password=>@password
    end 
    yield
    
  ensure
    @session_level-=1
    @session.close if @session && @session_level==0
  end
  
  private
  
  def session_exist?
    @session && !@session.closed?
  end
  
  def exec(ssh_session,cmds)
    
    @opts[:interactive]||=false

    if @opts[:interactive]==true
      interactive_exec(ssh_session,cmds)
    else
      standard_exec(ssh_session,cmds)
    end
  end
  
  def standard_exec(ssh_session,cmds)
    output=new_output
    cmds.each do |cmd|
      output.data+=@prompt+cmd+"\n"
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
    output=new_output
    # instance variable is used for pure testability, this could do with local variable otherwise
    @retries = 0
    cmd=cmds.shift
    output.data+=@prompt+cmd+"\n"
    ssh_session.open_channel do |channel|
      channel.request_pty
      channel.exec cmd do |ch, success|
        abort "could not execute #{cmd}" unless success
        ch.on_data do |ch1, data|
          output.data+=data
          # data is multiline, if the very last character is not newline then the command expects response
          
          if !data.match(/\n$/)
            @retries+=1 if cmds.empty?
            stdin = cmds.empty? ? "\n" : cmds.shift+"\n"
            ch1.send_data stdin
            output.data+=stdin
          end
          # we do not want to send newline to infinity so we exit
          # if we are still getting response after 100 empty command
          # if the command is newline explicitely this will not increase the @retriy          
          ch.close if @retries==100
        end

        ch.on_extended_data do |ch1, type, data|
          output.errors+=data
        end      
      end
    end  
    ssh_session.loop
    return output
  end
  
  def new_output
    # this approach is used to use Response of the calling class
    self.class::Response.new(@prompt)
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
    def initialize(prompt) # :nodoc:
      @errors=""
      @data=""
      @parsed = {
       :parsing_position=>nil
      }
      @prompt=prompt
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
    # Any class that inherits from this class should override the private parse_line method and store results into +parsed+ hash
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
  class Error < StandardError; 
    SESSION_WTIHOUT_BLOCK = "Error: Session can run only with block" 
  end
end
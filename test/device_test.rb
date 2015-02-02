require 'brocadesan'
require 'minitest/autorun'
require 'output_helpers'

class DeviceTest < MiniTest::Test
  include SshStoryWriter
  include Mock::Net::SSH
  patch_revert
  
  def setup
    @device = TestDevice.new("test","test","test")
    #Net::SSH::set_error ""
  end
  
  def test_device_setup
    assert_instance_of TestDevice, @device
  end
  
  def test_prompt
    assert_equal @device.prompt, TestDevice::DEFAULT_QUERY_PROMPT
    @new_device = TestDevice.new("test","test","test",:prompt => "$ ")
    assert_equal @new_device.prompt, "$ "
  end
  
  def test_get_mode
    @device.instance_variable_set(:@opts,{:interactive=>true})
    assert_equal "interactive", @device.get_mode
    
    @device = TestDevice.new("test","test","test", :interactive=>true)
    assert_equal "interactive", @device.get_mode
    
    @device.set_mode("script")
    assert_equal "script", @device.get_mode
  end
  
  def test_set_mode
    assert_equal "interactive", @device.set_mode("interactive")
    
    assert_equal "interactive", @device.set_mode(:interactive)
    
    assert_equal "script", @device.set_mode("script")
    
    assert_equal "script", @device.set_mode(:script)
    
    assert_equal "script", @device.set_mode("blabla")
  end

  def test_session
    #stub start with test connection coming from net/ssh/test
    Net::SSH.stub :start, connection do
      @device.session do 
        assert_instance_of Net::SSH::Connection::Session, @device.instance_variable_get(:@session)
        assert_equal 1, @device.instance_variable_get(:@session_level)
        @device.session do
          assert_equal 2, @device.instance_variable_get(:@session_level)
        end
        refute @device.instance_variable_get(:@session).closed?
        assert_equal 1, @device.instance_variable_get(:@session_level)
      end
    end
    assert @device.instance_variable_get(:@session).closed?
    
    # session can we called only with block, raises error otherwise
    exp = assert_raises(TestDevice::Error) do
      @device.session
    end
  end
  
  def test_script_mode
    #stub start with test connection coming from net/ssh/test
    @device.set_mode :interactive
    assert_equal "interactive", @device.get_mode
    Net::SSH.stub :start, connection do
      @device.script_mode do 
        assert_equal "script", @device.get_mode
      end
    end
    assert_equal "interactive", @device.get_mode
    
    # this can we called only with block, raises error otherwise
    exp = assert_raises(LocalJumpError) do
      @device.script_mode
    end
  end
  
   def test_interactive_mode
    #stub start with test connection coming from net/ssh/test
    @device.set_mode :script
    assert_equal "script", @device.get_mode
    Net::SSH.stub :start, connection do
      @device.interactive_mode do 
        assert_equal "interactive", @device.get_mode
      end
    end
    assert_equal "script", @device.get_mode
    
    # this can we called only with block, raises error otherwise
    exp = assert_raises(LocalJumpError) do
      @device.interactive_mode
    end
  end
  
  def test_query_in_session
    cmds = ["test"]
    exp_response = write_non_interactive_story(cmds,["test_ok"],TestDevice::DEFAULT_QUERY_PROMPT)
    Net::SSH.stub :start, connection do
      @device.session do 
        response=@device.query(cmds[0])
        assert_instance_of TestDevice::Response, response
        assert_equal exp_response, response.data
      end
    end
  end
  
  def test_interactive_query
    cmds = ["cfgsave","y"]
    replies = ["confirm? [y,n]"]
    exp_response = write_interactive_story(cmds,replies,TestDevice::DEFAULT_QUERY_PROMPT)
    
    @device.set_mode("interactive")
    # connection is net/ssh/test method
    @device.instance_variable_set(:@session,connection)
    
    response=nil
    assert_scripted do

      response=@device.query("cfgsave","y")
      
      assert_equal exp_response, response.data
    end    
    assert_instance_of TestDevice::Response, response
    
    # response safety net test for infinite newline response
    # create story with 150 newline commands
    cmds = Array.new(150, "")
    replies = Array.new(150,"confirm? [y,n]")
    exp_response = write_interactive_story(cmds,replies,TestDevice::DEFAULT_QUERY_PROMPT)
    
    
    # this is pure hack, this raises RuntimeError as the connection script is expecting 150 responses
    # but there are only 100 if them as expected
    # since the script did not match reality we had to assume this worked
    # we do not get any response so we cannot check it precisly
    # but we at least check the internal retries value
    # not the best test but so far the best I came up with
    
    assert_raises RuntimeError do
      # story contains 150 new line responses
      # this closses the channel after 100
      @device.query("")
    end
        
    assert_equal 100, @device.instance_variable_get(:@retries)
  end

  def test_non_interactive_query
    cmds = ["cfgshow","switchshow"]
    replies = ["not_available","is_available"]
    error = "cannot execute this"
    # write non itneractive ssh story that should play out when running the query
    exp_response = write_non_interactive_story(cmds,replies,TestDevice::DEFAULT_QUERY_PROMPT)
    
    # connection is net/ssh/test method
    @device.instance_variable_set(:@session,connection)
    response=nil
    assert_scripted do

      response=@device.query(*cmds)
      
      assert_equal exp_response, response.data
    end
    assert_instance_of TestDevice::Response, response
    
    #errors
    # write story endig with error
    exp_response = write_failed_simple_story(cmds[0],error,TestDevice::DEFAULT_QUERY_PROMPT)
    exp = assert_raises TestDevice::Error do 
      @device.query(cmds[0])
    end
    assert_equal "#{error}\n", exp.message
  end
end

class ResponseTest < MiniTest::Test
  def setup
    @response = TestDevice::Response.new("> ")
  end
  
  def test_parse
    #parse should end with end
    @response.parsed="test"
    @response.parse
    assert_equal a={:parsing_position=>"end"},  @response.parsed
  end
  
  def test_prompt
    assert_equal @response.instance_variable_get(:@prompt), "> "
  end
end

class TestDevice
  include SshDevice
end

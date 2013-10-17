require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'
#require 'net/ssh/test'

class DeviceTest < MiniTest::Test
  def setup
    @device = TestDevice.new("test","test","test")
    Net::SSH::set_error ""
  end
  
  def test_device_setup
    assert_instance_of TestDevice, @device
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
    
    assert_equal "script", @device.set_mode("script")
    
    assert_equal "script", @device.set_mode("blabla")
  end
  
  def test_query
    response=@device.query("test","test2")
    assert_instance_of TestDevice::Response, response
    assert_equal TestDevice::QUERY_PROMPT+"test\n"+Net::SSH::get_data+"\n"+TestDevice::QUERY_PROMPT+"test2\n"+Net::SSH::get_data+"\n", response.data
    
    Net::SSH::set_error "error"
    exp = assert_raises TestDevice::Error do 
      @device.query("test")
    end
    assert_equal Net::SSH::get_error+"\n", exp.message
    
  ensure
    Net::SSH::set_error ""
  end
  
  def test_query_in_session
    @device.session do 
      response=@device.query("test")
      assert_instance_of TestDevice::Response, response
      assert_equal TestDevice::QUERY_PROMPT+"test\n"+Net::SSH::get_data+"\n", response.data
    end
  end
  
  def test_session
    @device.session do 
      assert_instance_of Net::SSH::Session, @device.instance_variable_get(:@session)
    end
    assert @device.instance_variable_get(:@session).closed?
  end
end

class ResponseTest < MiniTest::Test
  def setup
    @response = TestDevice::Response.new
  end
  
  def test_parse
    #parse should end with end
    @response.parsed="test"
    @response.parse
    assert_equal a={:parsing_position=>"end"},  @response.parsed
  end
end

class TestDevice
  include SshDevice
end

module Net::SSH
  @@data="Response"
  @@error=""
  @@channel="channel"
  
  def self.get_data
    @@data
  end
  
  def self.get_error
    @@error
  end
  
  def self.get_channel
    @@channel
  end

  def self.set_data(x)
    @@data=x
  end
  
  def self.set_error(x)
    @@error=x
  end
  
  def self.set_channel(x)
    @@channel=x
  end
  
  def self.start(host, user, options={}, &block)
    
    if block
      yield Session.new
    else
      return Session.new
    end
  end
  
  class Session 
    def exec!(command, &block)
      @data=Net::SSH::get_data.dup
      @error=Net::SSH::get_error.dup
      @ch=Net::SSH::get_channel.dup
      
      if block
        block.call(@ch, :stdout, @data)
        block.call(@ch, :stderr, @error)
      else
        $stdout.print(data)
      end
    end
      
    def close
      @closed=true
    end
    
    def closed?
      @closed.nil? ? false : @closed
    end
  end
end
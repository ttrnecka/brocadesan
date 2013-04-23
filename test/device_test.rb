require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'
#require 'net/ssh/test'

class DeviceTest < MiniTest::Unit::TestCase
  #include Net::SSH::Test
  def setup
    @device = BrocadeSanDevice.new("test","test","test")
  end
  
  def test_device_setup
    assert_instance_of BrocadeSanDevice, @device
  end
  
  def test_query
    response=@device.query("test","test2")
    assert_instance_of BrocadeSanDevice::Response, response
    assert_equal BrocadeSanDevice::QUERY_PROMPT+"test\n"+Net::SSH::DATA+"\n"+BrocadeSanDevice::QUERY_PROMPT+"test2\n"+Net::SSH::DATA+"\n", response.data
    assert_equal Net::SSH::ERROR+"\n"+Net::SSH::ERROR+"\n", response.errors
  end
  
  def test_query_in_session
    @device.session do 
      response=@device.query("test")
      assert_instance_of BrocadeSanDevice::Response, response
      assert_equal BrocadeSanDevice::QUERY_PROMPT+"test\n"+Net::SSH::DATA+"\n", response.data
      assert_equal Net::SSH::ERROR+"\n", response.errors
    end
  end
  
  def test_session
    @device.session do 
      assert_instance_of Net::SSH::Session, @device.instance_variable_get(:@session)
    end
    assert @device.instance_variable_get(:@session).closed?
  end
end

class ResponseTest < MiniTest::Unit::TestCase
  def setup
    @response = BrocadeSanDevice::Response.new
  end
  
  def test_parse
    #parse should end with end
    @response.parsed="test"
    @response.parse
    assert_equal a={:parsing_position=>"end"},  @response.parsed
  end
end

module Net::SSH
  DATA="Response"
  ERROR="Error"
  CHANNEL="channel"
  
  def self.start(host, user, options={}, &block)
    
    if block
      yield Session.new
    else
      return Session.new
    end
  end
  
  class Session 
    def exec!(command, &block)
      @data=DATA
      @error=ERROR
      @ch=CHANNEL
      
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
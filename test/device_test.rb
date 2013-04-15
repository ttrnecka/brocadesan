require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

class DeviceTest < MiniTest::Unit::TestCase
  def setup
    @ssh_con = DummySSHConnection.new
    reload_connection
  end
  
  def reload_connection
    # Net:SSH start is stub with DummySSHConnection that will mimic any further Net:SSH commands required
    Net::SSH.stub :start, @ssh_con do 
      @device = BrocadeSanDevice.open_connection("test","test","test")
    end
  end
  
  def test_connection_setup
    assert_instance_of BrocadeSanDevice, @device
    assert @device.instance_variable_get(:@connection)===@ssh_con
  end

    
  def test_connect_method
    @device.instance_variable_set(:@connection,nil)
    Net::SSH.stub :start, @ssh_con do 
      @result=@device.connect
    end
    assert_equal  @device.instance_variable_get(:@connection), @ssh_con
    
    #good connection returns connection
    assert_equal @result, @ssh_con
    
  end
  
  def test_query
    #returns Response Object if connection ok
    response=@device.query("test")
    assert_instance_of BrocadeSanDevice::Response, response
    assert_equal BrocadeSanDevice::QUERY_PROMPT+"test\n"+DummySSHConnection::DATA, response.data
    assert_equal DummySSHConnection::ERROR, response.errors
    
    #returns exception if there is no connection
    exception = assert_raises(BrocadeSanDevice::Error) do 
      @device = BrocadeSanDevice.new("test","test","test")
      @device.query("test")
    end
    assert_match /No connection/, exception.message
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

class DummySSHConnection
  DATA="Response"
  ERROR="Error"
  CHANNEL="channel"
  
  def exec(command, &block)
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
  
  def self.start(host, user, options={}, &block)
    return self.new
  end  
end
require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

class SanSwitchTest < MiniTest::Unit::TestCase
  include OutputReader
  def setup
    @ssh_con = DummySSHConnection.new
    reload_connection
  end
  
  def reload_connection
    # Net:SSH start is stub with DummySSHConnection that will mimic any further Net:SSH commands required
    Net::SSH.stub :start, @ssh_con do 
      @device = SanSwitch.open_connection("test","test","test")
    end
  end
  
  def test_connection_setup
    assert_instance_of SanSwitch, @device
  end
  
  def test_name
    self.output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "switch" do |file,output|
      response=SanSwitch::Response.new
      response.data=output
      @device.stub :query, response do 
        assert_equal read_yaml_for(file)[:switch_name], @device.name
        
        # clear configuration
        @device.instance_variable_set(:@configuration,{})
        assert_nil  @device.name #nil if not reloaded
        assert_equal read_yaml_for(file)[:switch_name], @device.name(true) # ok if reloaded
      end
    end
  end
  
  def test_refresh
    
    #returns true and runs query if not loaded or forced, runs query
    @device.instance_variable_set(:@connection,@tmp_con=MiniTest::Mock.new)
    @tmp_con.expect :exec, [], ["switchname"]
    @tmp_con.expect :nil?, false
    assert_equal true, @device.refresh("switchname")
    @tmp_con.verify
    
    reload_connection
    @device.refresh("switchname")
    assert_equal true, @device.instance_variable_get(:@loaded)[:switchname]
  end
end

class SanSwitchResponseTest < MiniTest::Unit::TestCase
  include OutputReader

  def test_parse   
    self.output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "" do |file, output|
      response=SanSwitch::Response.new
      response.data=output
      response.parse
      assert_equal read_yaml_for(file), response.parsed
    end
  end
end

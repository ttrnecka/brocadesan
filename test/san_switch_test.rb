require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

class SanSwitchTest < MiniTest::Unit::TestCase
  include OutputReader
  def setup
    init_dev
  end
  
  def init_dev
    @device = SanSwitch.new("test","test","test")
  end
  
  def test_device_setup
    assert_instance_of SanSwitch, @device
  end
  
  def test_get
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "switch" do |file,output|
      response=SanSwitch::Response.new
      response.data=output
      @device.stub :query, response do 
        assert_equal read_yaml_for(file)[:switch_name], @device.get(:name)        
        # clear configuration
        @device.instance_variable_set(:@configuration,{})
        assert_nil  @device.get(:name) #nil if not reloaded
        assert_equal read_yaml_for(file)[:switch_name], @device.get(:name,true) # ok if reloaded
        
        #raise error if unknow parameter is requested
        assert_raises SanSwitch::Error do 
           @device.get(:dummy,true)
        end
      end
    end
  end
  
  def test_refresh
    
    #returns true and runs query if not loaded or forced, runs query
    @device.instance_variable_set(:@configuration,{:name=>"test", :parsing_position=>"test"})
    @device.send(:refresh, "switchshow")
    assert_equal a = {:name=>"test", :parsing_position=>"end"}, @device.configuration
    assert_equal true, @device.instance_variable_get(:@loaded)[:switchshow]
    
  end
  
  def test_dynamic_methods
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "" do |file,output|
      response=SanSwitch::Response.new
      response.data=output
      init_dev
      @device.stub :query, response do 
        SanSwitch::CMD_MAPPING.each do |k,v|
          #puts "#{v[:attr].to_sym}: #{read_yaml_for(file)[v[:attr].to_sym]} = #{@device.method(k).call}"
          assert_equal read_yaml_for(file)[v[:attr].to_sym], @device.method(k).call        
          # clear configuration
          @device.instance_variable_set(:@configuration,{})
          assert_nil  @device.method(k).call #nil if not reloaded
          assert_equal read_yaml_for(file)[v[:attr].to_sym], @device.method(k).call(true) # ok if reloaded
        end
      end
    end
  end
end

class SanSwitchResponseTest < MiniTest::Unit::TestCase
  include OutputReader

  def test_parse   
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "" do |file, output|
      response=SanSwitch::Response.new
      response.data=output
      response.parse
      assert_equal read_yaml_for(file), response.parsed
    end
  end
end

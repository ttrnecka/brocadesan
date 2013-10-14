require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

module Brocade module SAN
  
class ZoneConfigurationTest < MiniTest::Test
  include OutputReader
  def setup
    init_dev
  end
  
  def init_dev
    @switch = Switch.new("test","test","test")
  end
  
  def test_new_zone_config
    cfg=ZoneConfiguration.new("test",:effective=>true)
    assert_equal "test", cfg.name
    assert cfg.effective
    assert_raises Switch::Error do
      zone=ZoneConfiguration.new("test-d")
    end
  end
  
  def test_members
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "cfgshow_" do |file,output|
      response=Switch::Response.new
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @switch.stub :query, response do 
        @switch.zone_configurations.each_with_index do |cfg,i|
          assert_equal yaml[:defined_configuration][:cfg].values[i], cfg.members
        end
      end
    end
  end
  
  def test_add_member
    cfg=ZoneConfiguration.new("test")
    cfg.add_member "test1"
    assert_equal ["test1"], cfg.members
    cfg.add_member "test2"
    assert_equal ["test1","test2"], cfg.members
    
    assert_raises Switch::Error do
      # cannot start with number 
      cfg.add_member "3zone"
    end
    assert_raises Switch::Error do
      # can contain only alphanumeric and underscore
      cfg.add_member "zone&"
    end
    assert_raises Switch::Error do
      cfg.add_member "zone-d"
    end
  end
end

end; end

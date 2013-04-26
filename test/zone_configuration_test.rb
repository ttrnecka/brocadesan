require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

module Brocade module SAN
  
class ZoneConfigurationTest < MiniTest::Unit::TestCase
  include OutputReader
  def setup
    init_dev
  end
  
  def init_dev
    @switch = Switch.new("test","test","test")
  end
  
  def test_new_zone_config
    cfg=ZoneConfiguration.new("test",@switch,:effective=>true)
    assert_equal "test", cfg.name
    assert cfg.effective
    
    assert_raises Switch::Error do 
      cfg=ZoneConfiguration.new("test","switch",:effective=>true)
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
end

end; end

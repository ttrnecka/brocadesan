require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

module Brocade module SAN
  
class ZoneTest < MiniTest::Unit::TestCase
  include OutputReader
  def setup
    init_dev
  end
  
  def init_dev
    @switch = Switch.new("test","test","test")
  end
  
  def test_new_zone 
    zone=Zone.new("test",@switch,:active=>true)
    assert_equal "test", zone.name
    assert zone.active
    
    assert_raises Switch::Error do 
      zone=Zone.new("test","switch",:active=>true)
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
        @switch.zones.each_with_index do |zone,i|
          assert_equal yaml[:defined_configuration][:zone].values[i], zone.members
        end
      end
    end
  end
end

end; end
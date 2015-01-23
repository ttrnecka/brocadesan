require 'brocadesan'
require 'minitest/autorun'
require 'output_helpers'

module Brocade module SAN
  
class ZoneTest < MiniTest::Test
  include OutputReader
  include Mock::Net::SSH
  patch_set
  
  def setup
    init_dev
  end
  
  def init_dev
    @switch = Switch.new("test","test","test")
  end
  
  def test_new_zone 
    zone=Zone.new("test",:active=>true)
    assert_equal "test", zone.name
    assert zone.active
    assert_raises Switch::Error do
      zone=Zone.new("test-d",:active=>true)
    end
  end
  
  def test_members
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "cfgshow_" do |file,output|
      response=new_mock_response
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
  
  def test_add_member
    z=Zone.new("test")
    z.add_member "test1"
    assert_equal ["test1"], z.members
    z.add_member "test2"
    assert_equal ["test1","test2"], z.members
  end
  
  def test_validity_verification
    name = "*invalid_name_for_zone_member"
    exp = assert_raises(Switch::Error) do
      Zone::verify_member_name name
    end
    assert_equal Switch::Error.incorrect(name).message, exp.message
    
    name = "invalid-name_for_zone_member"
    exp = assert_raises(Switch::Error) do
      Zone::verify_member_name name
    end
    assert_equal Switch::Error.incorrect(name).message, exp.message
    
    assert_silent do
      Zone::verify_member_name "50:00:10:20:30:40:50:60"
      Zone::verify_member_name "2,61"
      Zone::verify_member_name "alias_name"
    end
  end
end

end; end
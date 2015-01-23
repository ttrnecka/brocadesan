require 'brocadesan'
require 'minitest/autorun'
require 'output_helpers'

module Brocade module SAN
  
class AliasTest < MiniTest::Test
  include OutputReader
  include Mock::Net::SSH
  patch_set
  
  def setup
    init_dev
  end
  
  def init_dev
    @switch = Switch.new("test","test","test")
  end
  
  def test_new_alias 
    al=Alias.new("test")
    assert_equal "test", al.name
    assert_raises Switch::Error do
      zone=Alias.new("test-d")
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
        @switch.aliases.each_with_index do |al,i|
          assert_equal yaml[:defined_configuration][:alias].values[i], al.members
        end
      end
    end
  end
  
  def test_add_member
    a=Alias.new("test")
    a.add_member "50:00:10:20:30:40:50:60"
    assert_equal ["50:00:10:20:30:40:50:60"], a.members
    a.add_member "2,61"
    assert_equal ["50:00:10:20:30:40:50:60","2,61"], a.members
    
    assert_raises(Switch::Error) do
      a.add_member "invalid_name_for_alias_member"
    end
  end
  
  def test_validity_verification
    name = "invalid_name_for_alias_member"
    exp = assert_raises(Switch::Error) do
      Alias::verify_member_name name
    end
    assert_equal Switch::Error.incorrect(name).message, exp.message
    assert_silent do
      Alias::verify_member_name "50:00:10:20:30:40:50:60"
      Alias::verify_member_name "2,61"
    end
  end
end

end; end

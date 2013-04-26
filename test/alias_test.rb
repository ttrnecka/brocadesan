require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

module Brocade module SAN
  
class AliasTest < MiniTest::Unit::TestCase
  include OutputReader
  def setup
    init_dev
  end
  
  def init_dev
    @switch = Switch.new("test","test","test")
  end
  
  def test_new_alias 
    al=Alias.new("test",@switch)
    assert_equal "test", al.name
    
    assert_raises Switch::Error do 
      al=Alias.new("test","switch")
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
        @switch.aliases.each_with_index do |al,i|
          assert_equal yaml[:defined_configuration][:alias].values[i], al.members
        end
      end
    end
  end
end

end; end
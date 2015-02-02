require 'brocadesan'
require 'minitest/autorun'
require 'output_helpers'

module Brocade module SAN
  
class WwnTest < MiniTest::Test
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
    wwn=Wwn.new("50:10:20:30:40:50:60:7f","device","1",2,:symbol=>"text")
    assert_equal "50:10:20:30:40:50:60:7f", wwn.value
    assert_equal "50:10:20:30:40:50:60:7f", wwn.name
    assert_equal "device", wwn.dev_type
    assert_equal 1, wwn.domain_id
    assert_equal 2, wwn.port_index
    assert_equal "text", wwn.symbol
    
    wwn=Wwn.new("50:10:20:30:40:50:60:7f","device",1,"2")
    assert_equal 1, wwn.domain_id
    assert_equal 2, wwn.port_index
    assert_equal "", wwn.symbol
        
    assert_raises Switch::Error do
      wwn=Wwn.new("50:10:20:30:40:50:60:7R","device",1,"2")
    end
  end
    
end

end; end
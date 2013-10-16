require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

module Brocade module SAN
  
class ProvisioningTest < MiniTest::Test
  include OutputReader
  def setup
    init_dev
  end
  
  def init_dev
    @agent = Provisioning::Agent.new("test","test","test")
    @response=Switch::Response.new
  end
  
  def test_device_setup
    assert_instance_of Provisioning::Agent, @agent
  end
  
  def test_verify   
    @response.data="> configshow |grep \"RBAC\"\n"
    @agent.stub :query, @response do 
      assert_equal true, @agent.send(:verify)
    end
    
    @response.data="> configshow |grep \"RBAC\"\nRBAC permission denied.\n"
    @agent.stub :query, @response do 
      exp = assert_raises Provisioning::Agent::Error do
        @agent.send(:verify)
      end
      assert_equal Provisioning::Agent::Error::BAD_USER, exp.message
    end
    
  end
  
  def test_check_transaction
    @response.data="> cfgtransshow\nThere is no outstanding zoning transactions\n"
    @agent.stub :query, @response do 
      assert_equal false, @agent.check_for_running_transaction
    end
    
    @response.data="> cfgtransshow\nCurrent transaction token is 271010736\nIt is abortable\n"
    @agent.stub :query, @response do 
      assert_equal true, @agent.check_for_running_transaction
    end
  end
  
  def test_alias_add
    # should raise error if not alias
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.alias_add("test_string")
    end
    assert_equal Provisioning::Agent::Error::ALIAS_BAD, exp.message
    
    a = Alias.new("test")
    
    # test if alias exists already
    @agent.stub :find_alias, ["exits"] do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.alias_add(a)
      end
      assert_equal Provisioning::Agent::Error::ALIAS_EXISTS, exp.message
    end
    
    # test if transaction is ongoing
    @agent.stub :check_for_running_transaction, true do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.alias_add(a)
      end
      assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
    end
    
    @response.data="> alicreate \"test\",\"50:00; 50:02\"\nInvalid alias\n"
    # test aliacreate complains
    @agent.stub :find_alias, [] do 
      @agent.stub :check_for_running_transaction, false do
        @agent.stub :query, @response do 
          exp = assert_raises Provisioning::Agent::Error do    
            @agent.alias_add(a)
          end
          assert_equal "Invalid alias", exp.message
        end
        @response.data="> alicreate \"test\",\"50:00; 50:02\"\n"
        @agent.stub :query, @response do 
          @agent.stub :cfg_save, true do 
            assert_equal true, @agent.alias_add(a)
          end
        end
      end
    end
    
  end
  
   
end

end; end
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
    assert_equal nil, @agent.instance_variable_get(:@transaction)
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
  
  def test_transaction
    @agent.stub :cfg_save, :cfg_save do 
      @agent.stub :abort_transaction, :abort_transaction do
        @agent.stub :check_for_running_transaction, false do
          # if all is good call cfg_save
          res = @agent.transaction do      
          end
          assert_equal :cfg_save, res
          # else raise error and abort transaction
          exp = assert_raises RuntimeError do    
            res = @agent.transaction do
              raise "test"      
            end
          end
          assert_equal "test", exp.message
          
          @agent.transaction do 
            assert_equal true, @agent.instance_variable_get(:@transaction)
            assert_instance_of Net::SSH::Session, @agent.instance_variable_get(:@session)
          end
          assert_equal nil, @agent.instance_variable_get(:@transaction)
        end
        @agent.stub :check_for_running_transaction, true do
          # if there is transaction already in progress raises error
          exp = assert_raises Provisioning::Agent::Error do    
            @agent.transaction do
            end
          end
          assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
        end
      end
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
  
  def test_alias_create
    # should raise error if not alias
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.alias_create("test_string")
    end
    assert_equal Provisioning::Agent::Error::ALIAS_BAD, exp.message
    
    a = Alias.new("test")
    
    # test if transaction is ongoing
    @agent.stub :check_for_running_transaction, true do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.alias_create(a)
      end
      assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
    end
    
    @response.data="> alicreate \"test\",\"50:00; 50:02\"\nInvalid alias\n"
    # test aliacreate complains
     
    @agent.stub :check_for_running_transaction, false do
      @agent.stub :query, @response do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.alias_create(a)
        end
        assert_equal "Invalid alias", exp.message
      end
      @response.data="> alicreate \"test\",\"50:00; 50:02\"\n"
      @agent.stub :query, @response do 
        @agent.stub :cfg_save, true do 
          assert_equal true, @agent.alias_create(a)
        end
      end
    end
  end
  
  def test_alias_delete
    # should raise error if not alias
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.alias_delete("test_string")
    end
    assert_equal Provisioning::Agent::Error::ALIAS_BAD, exp.message
    
    a = Alias.new("test")
    
    
    # test if transaction is ongoing
    @agent.stub :check_for_running_transaction, true do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.alias_delete(a)
      end
      assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
    end
      
    @response.data="> alidelete \"test\"\nnot found\n"
    # test aliacreate complains
    @agent.stub :check_for_running_transaction, false do
      @agent.stub :query, @response do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.alias_delete(a)
        end
        assert_equal "not found", exp.message
      end
      @response.data="> alidelete \"test\"\n"
      @agent.stub :query, @response do 
        @agent.stub :cfg_save, true do 
          assert_equal true, @agent.alias_delete(a)
        end
      end
    end
  end
  
  def test_alias_change
    # should raise error if not alias
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.alias_change("test_string")
    end
    assert_equal Provisioning::Agent::Error::ALIAS_BAD, exp.message
    
    a = Alias.new("test")
    
    
    # test if transaction is ongoing
    @agent.stub :check_for_running_transaction, true do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.alias_change(a)
      end
      assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
    end
      
    @response.data="> alidelete \"test\"\nnot found\n"
    # test aliacreate complains
    @agent.stub :check_for_running_transaction, false do
      @agent.stub :query, @response do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.alias_change(a)
        end
        assert_equal "not found", exp.message
      end
      @response.data="> alidelete \"test\"\n"
      @agent.stub :query, @response do 
        @agent.stub :cfg_save, true do 
          assert_equal true, @agent.alias_change(a)
        end
      end
    end
  end
  
  def test_zone_create
    # should raise error if not zone
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.zone_create("test_string")
    end
    assert_equal Provisioning::Agent::Error::ZONE_BAD, exp.message
    
    a = Zone.new("test")
    
    # test if transaction is ongoing
    @agent.stub :check_for_running_transaction, true do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.zone_create(a)
      end
      assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
    end
    
    @response.data="> zonecreate \"test-04\",\"koza; byk\"\ninvalid name\n"
    # test aliacreate complains
     
    @agent.stub :check_for_running_transaction, false do
      @agent.stub :query, @response do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.zone_create(a)
        end
        assert_equal "invalid name", exp.message
      end
      @response.data="> zonecreate \"test\",\"koza; byk\"\n"
      @agent.stub :query, @response do 
        @agent.stub :cfg_save, true do 
          assert_equal true, @agent.zone_create(a)
        end
      end
    end
  end
  
  def test_alias_delete
    # should raise error if not alias
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.zone_delete("test_string")
    end
    assert_equal Provisioning::Agent::Error::ZONE_BAD, exp.message
    
    a = Zone.new("test")
    
    
    # test if transaction is ongoing
    @agent.stub :check_for_running_transaction, true do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.zone_delete(a)
      end
      assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
    end
      
    @response.data="> zonedelete \"test\"\nnot found\n"
    # test aliacreate complains
    @agent.stub :check_for_running_transaction, false do
      @agent.stub :query, @response do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.zone_delete(a)
        end
        assert_equal "not found", exp.message
      end
      @response.data="> zonedelete \"test\"\n"
      @agent.stub :query, @response do 
        @agent.stub :cfg_save, true do 
          assert_equal true, @agent.zone_delete(a)
        end
      end
    end
  end
  
  def test_zone_change
    # should raise error if not alias
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.zone_change("test_string")
    end
    assert_equal Provisioning::Agent::Error::ZONE_BAD, exp.message
    
    a = Zone.new("test")
    
    
    # test if transaction is ongoing
    @agent.stub :check_for_running_transaction, true do 
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.zone_change(a)
      end
      assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
    end
      
    @response.data="> zonedelete \"test\"\nnot found\n"
    # test aliacreate complains
    @agent.stub :check_for_running_transaction, false do
      @agent.stub :query, @response do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.zone_change(a)
        end
        assert_equal "not found", exp.message
      end
      @response.data="> zonedelete \"test\"\n"
      @agent.stub :query, @response do 
        @agent.stub :cfg_save, true do 
          assert_equal true, @agent.zone_change(a)
        end
      end
    end
  end
  
  def test_cfgsave
    # should raise error if cancelled
    @response.data="> cfgsave\nOperation cancelled...\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.cfg_save
      end
      assert_equal Provisioning::Agent::Error::CFGSAVE_CANC, exp.message
      assert_equal 'script', @agent.get_mode
    end
    
    # should raise error nothing changed
    @response.data="> cfgsave\nNothing changed: nothing to save, returning ...\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.cfg_save
      end
      assert_equal Provisioning::Agent::Error::CFGSAVE_NOCHANGE, exp.message
      assert_equal 'script', @agent.get_mode
    end
    
    # should return true if saved
    @response.data="> cfgsave\nUpdating flash ...\n"
    @agent.stub :query, @response do
      assert_equal true, @agent.cfg_save
      assert_equal 'script', @agent.get_mode
    end
    
  end
  
  def test_transaction_abort   
    @response.data="> cfgtransabort\n"
    @agent.stub :query, @response do
      assert_equal true, @agent.abort_transaction
    end

    @response.data="> cfgtransabort\nThere is no outstanding transactions\n"
    @agent.stub :query, @response do
      assert_equal false, @agent.abort_transaction
    end
    
    # should raise error if there is transaction but we do not own it
    @response.data="> cfgtransabort\ntrans_abort: there is an outstanding  transaction, and you are not owner of that transaction.\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.abort_transaction
      end
      assert_equal Provisioning::Agent::Error::TRANS_NOTOWNER, exp.message
    end
    
    # should raise error if unexpected reply
    @response.data="> cfgtransabort\nkvakvakva\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.abort_transaction
      end
      assert_equal "kvakvakva", exp.message
    end
  end
  
   
end

end; end
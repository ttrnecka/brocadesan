require 'brocadesan'
require 'minitest/autorun'
require 'output_helpers'

module Brocade module SAN
  
class ProvisioningTest < MiniTest::Test
  include OutputReader
  include Mock::Net::SSH
  patch_set
  
  def setup
    init_dev
  end
  
  def init_dev
    @agent = Provisioning::Agent.create("test","test","test")
    @response=new_mock_response
  end
  
  def test_device_setup
    assert_instance_of Provisioning::Agent, @agent
    assert_equal nil, @agent.instance_variable_get(:@transaction)
    assert @agent.instance_variable_get(:@configuration)[:override_vf]
    
    # this hack ensures I can test verify false inside create
    Provisioning::Agent.class_eval do 
      alias_method :old_verify, :verify
      def verify
        false
      end
    end 
    exp = assert_raises Provisioning::Agent::Error do
      @agent = Provisioning::Agent.create("test","test","test")
    end
    assert_equal Provisioning::Agent::Error::BAD_USER, exp.message
    Provisioning::Agent.class_eval do 
      alias_method :verify, :old_verify
      undef_method :old_verify
    end 
  end
  
  
  def test_verify   
    @response.data="> configshow |grep \"RBAC\"\n"
    @agent.stub :query, @response do 
      assert_equal true, @agent.send(:verify)
    end
    
    @response.data="> configshow |grep \"RBAC\"\nRBAC permission denied.\n"
    @agent.stub :query, @response do 
      assert_equal false, @agent.send(:verify)
    end
  end
  
  def test_lock_transaction
    @agent.instance_variable_set(:@transaction,Provisioning::Agent::Transaction.new({:id=>"32323",:abortable=>true}))
    # returns true if transaction is already in progress (transaction block within transaction)
    assert @agent.send :lock_transaction
    
    @agent.instance_variable_set(:@transaction,nil)
    # if there is existing different transaction from outside
    @agent.stub :get_transaction,true do
      assert_equal false, @agent.send(:lock_transaction)  
    end   
    
    # locking
    @agent.multistub [
      [:get_transaction, false],
      [:alias_create,:alias_create],
      [:alias_delete,:alias_delete]
    ] do
      assert @agent.send(:lock_transaction)
      # normaly this should be of Transaction instance but we stubbed it
      assert_equal false, @agent.instance_variable_get(:@transaction)
    end
    
    # some uneexpected error
    error = lambda {
      raise "unexpected"
    }
    @agent.stub :get_transaction,error do
      assert_equal false, @agent.send(:lock_transaction)  
    end
  end
  
  def test_get_transaction
    # not transaction
    @response.data="> cfgtransshow\nThere is no outstanding zoning transaction\n"
    @agent.stub :query, @response do
      @agent.query_stub do 
        assert_equal false, @agent.get_transaction
        assert_equal "cfgtransshow", @agent.instance_variable_get(:@query_string)
      end
    end
    # abortable
    @response.data="> cfgtransshow\nCurrent transaction token is 271010736\nIt is abortable\n"
    @agent.stub :query, @response do
      trans =  @agent.get_transaction
      assert_instance_of Brocade::SAN::Provisioning::Agent::Transaction, trans
      assert_equal "271010736", trans.id
      assert_equal true, trans.abortable?
    end
    # not abortable
    @response.data="> cfgtransshow\nCurrent transaction token is 0xfffffff0\nIt is not abortable\n"
    @agent.stub :query, @response do
      trans =  @agent.get_transaction
      assert_instance_of Brocade::SAN::Provisioning::Agent::Transaction, trans
      assert_equal "0xfffffff0", trans.id
      assert_equal false, trans.abortable?
    end
    # error
    @response.data="> cfgtransshow\nunexpected shit\nunexpected shit2\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do
        @agent.get_transaction
      end
      assert_equal Provisioning::Agent::Error::TRANS_UNEXPECTED, exp.message
    end
  end
  
  def test_transaction
    @agent.multistub [ 
      [:cfg_save, :cfg_save], 
      [:abort_transaction, :abort_transaction],
      [:check_for_running_transaction, false],
      [:lock_transaction, true],
      [:get_transaction, true]
    ] do
      # if all is good call cfg_save - > last method of transaction block
      res = @agent.transaction do      
      end
      assert_equal :cfg_save, res
          
      # else raise error and abort transaction
      # strus abort transaction which then set trans_aborted instance variable
      @agent.abort_transaction_stub do
        exp = assert_raises RuntimeError do    
          res = @agent.transaction do
            raise "test"      
          end
        end
        # confirm abort_transaction was started
        assert @agent.instance_variable_get(:@trans_aborted)
        assert_equal "test", exp.message
      end      
         
      @agent.transaction do 
        assert_equal true, @agent.instance_variable_get(:@transaction)
        assert_instance_of Mock::Net::SSH::Session, @agent.instance_variable_get(:@session)
        assert_equal 1, @agent.instance_variable_get(:@transaction_level)
        @agent.transaction do
          assert_equal 2, @agent.instance_variable_get(:@transaction_level)
        end
      end
      assert_equal 0, @agent.instance_variable_get(:@transaction_level)
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
    
    @agent.multistub [
      [:lock_transaction, false],
      [:check_for_running_transaction, false]
    ] do
      # if we cannot lock transactino for some reason
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.transaction do
        end
      end
      assert_equal Provisioning::Agent::Error::TRANS_UNLOCKABLE, exp.message
    end
  end
  
  def test_check_for_running_transaction
    @response.data="> cfgtransshow\nThere is no outstanding zoning transaction\n"
    @agent.stub :query, @response do 
      assert_equal false, @agent.check_for_running_transaction
    end
    
    # old version response
    @response.data="> cfgtransshow\nThere is no outstanding zoning transactions\n"
    @agent.stub :query, @response do 
      assert_equal false, @agent.check_for_running_transaction
    end
    
    @response.data="> cfgtransshow\nCurrent transaction token is 271010736\nIt is abortable\n"
    @agent.stub :query, @response do 
      assert_equal true, @agent.check_for_running_transaction
    end
    
    #verify we are sending the proper command
    @agent.query_stub do
      @agent.check_for_running_transaction
      assert_equal "cfgtransshow", @agent.instance_variable_get(:@query_string)
    end
  end
  
  def test_transaction_abort   
    @response.data="> cfgtransabort\n"
    @agent.stub :query, @response do
      assert_equal true, @agent.abort_transaction
      
      #verify we are sending the proper command
      @agent.query_stub do
        @agent.abort_transaction
        assert_equal "cfgtransabort", @agent.instance_variable_get(:@query_string)
      end
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
  
  def test_exist?
    @response.data="> alishow\n"
    @agent.stub :query, @response do
      @agent.query_stub do
        assert_equal true, @agent.exist?("test")
        # verifies the cmd sent to switch
        assert_equal "zoneshow \"test\"", @agent.instance_variable_get(:@query_string)
        @agent.instance_variable_set(:@query_string,"")
        assert_equal true, @agent.exist?("test",:object => :zone)
        assert_equal "zoneshow \"test\"", @agent.instance_variable_get(:@query_string)
        @agent.instance_variable_set(:@query_string,"")
        assert_equal true, @agent.exist?("test",:object => :alias)
        assert_equal "alishow \"test\"", @agent.instance_variable_get(:@query_string)
        @agent.instance_variable_set(:@query_string,"")
        assert_equal true, @agent.exist?("test",:object => :cfg)
        assert_equal "cfgshow \"test\"", @agent.instance_variable_get(:@query_string)
        @agent.instance_variable_set(:@query_string,"")
        assert_equal true, @agent.exist?("test",:object => :test)
        assert_equal "zoneshow \"test\"", @agent.instance_variable_get(:@query_string)
        @agent.instance_variable_set(:@query_string,"")
      end
    end
    @response.data="> alishow\ndoes not exist\n"
    @agent.stub :query, @response do
      assert_equal false, @agent.exist?("test")
      assert_equal false, @agent.exist?("test",:object => :zone)
      assert_equal false, @agent.exist?("test",:object => :alias)
      assert_equal false, @agent.exist?("test",:object => :cfg)
      assert_equal false, @agent.exist?("test",:object => :test)
    end
  end
  
  def test_cfgsave
    # should raise error if cancelled
    @response.data="> cfgsave\nOperation cancelled...\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :cfg_save
      end
      assert_equal Provisioning::Agent::Error::CFGSAVE_CANC, exp.message
      assert_equal 'script', @agent.get_mode
    end
    
    # should raise error nothing changed
    @response.data="> cfgsave\nNothing changed: nothing to save, returning ...\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :cfg_save
      end
      assert_equal Provisioning::Agent::Error::CFGSAVE_NOCHANGE, exp.message
      assert_equal 'script', @agent.get_mode
    end
    
    # should return true if saved
    @response.data="> cfgsave\nUpdating flash ...\n"
    @agent.stub :query, @response do
      @agent.query_stub do
        assert_equal true, @agent.send(:cfg_save)
        assert_equal 'script', @agent.get_mode
        assert_equal "cfgsave,y", @agent.instance_variable_get(:@query_string)
      end
    end 
  end
  
  def test_cfgenable
    cfg = ZoneConfiguration.new("test")
    
    # should raise error if not zone configuration
    exp = assert_raises Provisioning::Agent::Error do    
      @agent.cfg_enable("test")
    end
    assert_equal Provisioning::Agent::Error::CFG_BAD, exp.message
    
    # should raise error if cancelled
    @response.data="> cfgenable test\nOperation cancelled...\n"
    @agent.stub :query, @response do
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.cfg_enable(cfg)
      end
      assert_equal Provisioning::Agent::Error::CFGSAVE_CANC, exp.message
      assert_equal 'script', @agent.get_mode
    end
    
    # should return true if saved
    @response.data="> cfgenable test\nUpdating flash ...\n"
    @agent.stub :query, @response do
      @agent.query_stub do
        assert_equal true, @agent.cfg_enable(cfg)
        assert_equal 'script', @agent.get_mode
        assert_equal "cfgenable \"test\",y", @agent.instance_variable_get(:@query_string)
      end
    end 
  end
  
  def test_obj_create
     zones = [Zone.new("koza"),Zone.new("byk")]
     als = [Alias.new("koza"),Alias.new("byk")]
     wwns = ["50:01:02:03:04:05:06:07"]
     objs = [
       {:obj=>ZoneConfiguration.new("zctest"), 
        :klass=>ZoneConfiguration, 
        :cmd => "cfgcreate",
        :member_name => "Zone",
        :error=>Provisioning::Agent::Error::CFG_BAD,:method=>:cfg_create,
        :msg_invalid => "> cfgcreate \'test-04\',\'koza; byk\'\nInvalid name\n",
        :resp_invalid => "Invalid name",
        :msg_ok => "> cfgcreate \'test\',\'koza; byk\'\n",
        :resp_ok => "",
        :msg_duplicate => "> cfgcreate cfg1, zone1\n\'cfg1\' duplicate name\n",
        :resp_duplicate => "\'cfg1\' duplicate name",
        :members => zones.map {|z| z.to_s}
       },
       {:obj=>Zone.new("zonetest"), 
        :klass=>Zone, 
        :cmd => "zonecreate",
        :member_name => "Alias",
        :error => Provisioning::Agent::Error::ZONE_BAD,:method=>:zone_create,
        :msg_invalid => "> zonecreate \'test-04\',\'koza; byk\'\nInvalid name\n",
        :resp_invalid => "Invalid name",
        :msg_ok => "> zonecreate \'test\',\'koza; byk\'\n",
        :resp_ok => "",
        :msg_duplicate => "> zonecreate WYN_vls1_node3_fc0, 5B:49:9B:AF:F0:93:00:13\n\'WYN_vls1_node3_fc0\' duplicate name\n",
        :resp_duplicate => "\'WYN_vls1_node3_fc0\' duplicate name",
        :members => als.map {|a| a.to_s}
        },
       {:obj=>Alias.new("aliastest"), 
        :klass=>Alias,
        :cmd => "alicreate",
        :member_name => "Wwn", 
        :error => Provisioning::Agent::Error::ALIAS_BAD,:method=>:alias_create,
        :msg_invalid => "> alicreate \'test\',\'50:00; 50:02\'\nInvalid alias\n",
        :resp_invalid => "Invalid alias",
        :msg_ok => "> alicreate \'test\',\'50:00; 50:02\'\n",
        :resp_ok => "",
        :msg_duplicate => "> alicreate WYN_vls1_node3_fc0, 5B:49:9B:AF:F0:93:00:13\n\'WYN_vls1_node3_fc0\' duplicate name\n",
        :resp_duplicate => "\'WYN_vls1_node3_fc0\' duplicate name",
        :members => wwns.map {|w| w.to_s}
        }
     ]
    
    # should raise error if obj is not ok
    objs.each do |obj|
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :obj_create,"query_string",obj[:klass]
      end
      assert_equal obj[:error], exp.message
      # test wrapper - enough to test teh wrapper for this
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send obj[:method],"query_string"
      end
      assert_equal obj[:error], exp.message
      
      # test if transaction is ongoing
      @agent.stub :check_for_running_transaction, true do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.send :obj_create,obj[:obj],obj[:klass]
        end
        assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
      end
      
      @agent.stub :check_for_running_transaction, false do
        @agent.stub :exist?, true do
          # empty members check
          @response.data=obj[:msg_invalid]
          @agent.stub :query, @response do 
            exp = assert_raises Provisioning::Agent::Error do    
              @agent.send :obj_create,obj[:obj],obj[:klass]
            end
            assert_equal Provisioning::Agent::Error::MEMBERS_EMPTY, exp.message
          end
          
          # set members
          obj[:members].each do |mem|
            obj[:obj].add_member mem
          end
          @agent.stub :zones, zones do 
            # check invalid objects responses
            @response.data=obj[:msg_invalid]
            @agent.stub :query, @response do 
              exp = assert_raises Provisioning::Agent::Error do    
                @agent.send :obj_create,obj[:obj],obj[:klass]
              end
              assert_equal obj[:resp_invalid], exp.message
            end
            # check ok response
            @response.data=obj[:msg_ok]
            @agent.multistub [
              [:query, @response], 
              [:cfg_save, true],
              [:pull, obj[:obj]]
            ] do 
              @agent.query_stub do
                assert_equal obj[:obj], @agent.send(:obj_create,obj[:obj],obj[:klass])
                # checks the cmd sent to query
                assert_equal "#{obj[:cmd]} \'#{obj[:obj].name}\', \'#{obj[:obj].members.join(";")}\'", @agent.instance_variable_get(:@query_string)
              end
            end
            
            # check duplicate respones
            @response.data= obj[:msg_duplicate]
            @agent.stub :query, @response do 
              exp = assert_raises Provisioning::Agent::Error do    
                @agent.send(:obj_create,obj[:obj],obj[:klass])
              end
              assert_equal obj[:resp_duplicate], exp.message
            end
          end
        end
        # checking members exists
        # do not do the following for alias
        next if obj[:klass]==Alias
        #obj[:obj].add_member("test2")
        @response.data=obj[:msg_ok]
        @agent.multistub [
          [:exist?, false],
          [:query, @response],
          [:pull, obj[:obj]],
          [:zones, []]
        ] do  
          exp = assert_raises Provisioning::Agent::Error do    
            @agent.send(:obj_create,obj[:obj],obj[:klass])
          end
          assert_equal "#{obj[:member_name]} #{obj[:members][0]} #{Provisioning::Agent::Error::OBJ_NOTEXIST}", exp.message
            
          # special test only for zone members
          # if member is wwn check should not be done
          if obj[:klass]==Zone
            a = Zone.new("test")
            a.add_member("50:00:10:20:30:40:50:60")
            @agent.stub :cfg_save, true do
              assert_equal obj[:obj], @agent.zone_create(a)
            end
          end
        end
      end  
    end 
  end
  
  def test_obj_delete
    
    objs = [
       {:obj=>ZoneConfiguration.new("zctest"), 
        :klass=>ZoneConfiguration, 
        :cmd => "cfgdelete",
        :member_name => "Zone",
        :error=>Provisioning::Agent::Error::CFG_BAD,
        :method=>:cfg_delete,
        :msg_not_found => "> cfgdelete \'test\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> cfgedelete \'test\'\n",
        :resp_ok => ""
       },
       {:obj=>Zone.new("zonetest"), 
        :klass=>Zone, 
        :cmd => "zonedelete",
        :member_name => "Alias",
        :error => Provisioning::Agent::Error::ZONE_BAD,
        :method=>:zone_delete,
        :msg_not_found => "> zonedelete \'test\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> zonedelete \'test\'\n",
        :resp_ok => ""
        },
       {:obj=>Alias.new("aliastest"), 
        :klass=>Alias,
        :cmd => "alidelete",
        :member_name => "Wwn", 
        :error => Provisioning::Agent::Error::ALIAS_BAD,
        :method=>:alias_delete,
        :msg_not_found => "> alidelete \'test\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> alidelete \'test\'\n",
        :resp_ok => ""
        }
     ]
     
    objs.each do |obj|
      # should raise error if not alias
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :obj_delete, "query_string",obj[:klass]
      end
      assert_equal obj[:error], exp.message
      
      # test wrapper - enough to test teh wrapper for this
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send obj[:method],"query_string"
      end
      assert_equal obj[:error], exp.message
      
      # test if transaction is ongoing
      @agent.stub :check_for_running_transaction, true do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.send :obj_delete,obj[:obj],obj[:klass]
        end
        assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
      end
      
      
      # test delete complains
      @agent.stub :check_for_running_transaction, false do
        @response.data=obj[:msg_not_found]
        @agent.stub :query, @response do 
          exp = assert_raises Provisioning::Agent::Error do    
             @agent.send :obj_delete ,obj[:obj],obj[:klass]
          end
          assert_equal obj[:resp_not_found], exp.message
        end
        @response.data=obj[:msg_ok]
        @agent.multistub [
          [:query, @response],
          [:cfg_save, true],
          [:pull, obj[:obj]]
        ] do
          @agent.query_stub do 
            assert_equal obj[:obj], @agent.send(:obj_delete,obj[:obj],obj[:klass])
            # checks the cmd sent to query
            assert_equal "#{obj[:cmd]} \'#{obj[:obj].name}\'", @agent.instance_variable_get(:@query_string)
          end
        end
      end
    end
  end
  
  def test_obj_change
    # obj_change call obj delete and obj create, so we test only that thei are called
    # the responses of obj_delete and obj_create are tested in their respective tests
    objs = [
      {:obj=>Zone.new("zonetest"), 
       :klass=>Zone, 
       :queries => ["zonedelete","zonecreate"],
       :method => :zone_change
       },
      {:obj=>Alias.new("aliastest"), 
       :klass=>Alias,
       :queries => ["alidelete","alicreate"],
       :method => :alias_change
       }
    ]
    @response.data="> alidelete \'test\'\n"
    objs.each do |obj|
      @agent.multistub [
        [:check_for_running_transaction, false],
        [:lock_transaction, true],
        [:get_transaction, true],
        [:query, @response],
        [:raise_if_members_do_not_exist, :true], 
        [:cfg_save, true],
        [:pull, obj[:obj]]
      ] do
        @agent.query_stub do
          assert_equal obj[:obj], @agent.send(:obj_change,obj[:obj],obj[:klass])
          # checks the cmd sent to query
          assert_equal "#{obj[:queries][0]} \'#{obj[:obj].name}\'#{obj[:queries][1]} \'#{obj[:obj].name}\', \'#{obj[:obj].members.join(";")}\'", @agent.instance_variable_get(:@query_string)
          @agent.instance_variable_set(:@query_string,"")
          # test wrapper method
          @agent.send obj[:method],obj[:obj]
          assert_equal "#{obj[:queries][0]} \'#{obj[:obj].name}\'#{obj[:queries][1]} \'#{obj[:obj].name}\', \'#{obj[:obj].members.join(";")}\'", @agent.instance_variable_get(:@query_string)
        end
      end
    end
  end
  
  def test_obj_remove  
     objs = [
       {:obj=>ZoneConfiguration.new("zctest"), 
        :klass=>ZoneConfiguration, 
        :cmd => "cfgremove",
        :name => "Config",
        :member_name => "Zone",
        :member => Zone.new("zonetest"), 
        :members_ok => [Zone.new("zonetest")],
        :error=>Provisioning::Agent::Error::CFG_BAD,
        :error_member => Provisioning::Agent::Error::ZONE_BAD,
        :method=>:cfg_remove,
        :msg_not_found => "> cfgremove \'zctest\',\'zonetest\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> cfgremove \'zctest\',\'zonetest\'\n",
        :resp_ok => ""
       },
       {:obj=>Zone.new("zonetest"), 
        :klass=>Zone, 
        :cmd => "zoneremove",
        :name => "Zone",
        :member_name => "Alias",
        :member => Alias.new("aliastest"),
        :members_ok => [Alias.new("aliastest"), Wwn.new("50:01:02:03:04:05:06:07","target",1,1),"50:01:02:03:04:05:06:07","1,1"], 
        :error => Provisioning::Agent::Error::ZONE_BAD,
        :error_member => Provisioning::Agent::Error::MEMBER_BAD,
        :method=>:zone_remove,
        :msg_not_found => "> zoneremove \'zonename\',\'aliastest\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> zoneremove \'zonename\',\'aliastest\'\n",
        :resp_ok => ""
        },
       {:obj=>Alias.new("aliastest"), 
        :klass=>Alias,
        :cmd => "aliremove",
        :name => "Alias",
        :member_name => "Wwn", 
        :member => "50:01:02:03:04:05:06:07", 
        :members_ok => [Wwn.new("50:01:02:03:04:05:06:07","target",1,1),"50:01:02:03:04:05:06:07","1,1"],
        :error => Provisioning::Agent::Error::ALIAS_BAD,
        :error_member => Provisioning::Agent::Error::ALIAS_MEMBER_BAD,
        :method=>:alias_remove,
        :msg_not_found => "> aliremove \'aliastest\',\'50:00; 50:02\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> aliremove \'aliastest\',\'50:00; 50:02\'\n",
        :resp_ok => ""
        }
     ]
    
    
    objs.each do |obj|
      # should raise error if obj is not ok
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :obj_remove,"query_string",obj[:klass],"member"
      end
      assert_equal obj[:error], exp.message
      # should raise error if member is not ok
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :obj_remove,obj[:obj],obj[:klass],"member"
      end
      assert_equal obj[:error_member], exp.message
      
      # test wrapper - enough to test teh wrapper for this
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send obj[:method],"query_string","member"
      end
      assert_equal obj[:error], exp.message
      
      # test if transaction is ongoing
      @agent.stub :check_for_running_transaction, true do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.send :obj_remove,obj[:obj],obj[:klass],obj[:member]
        end
        assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
      end
      
      @agent.stub :check_for_running_transaction, false do
        @response.data=obj[:msg_not_found]
        @agent.stub :query, @response do 
          exp = assert_raises Provisioning::Agent::Error do    
             @agent.send :obj_remove ,obj[:obj],obj[:klass],obj[:member]
          end
          assert_equal obj[:resp_not_found], exp.message
        end
        
        # ok response
        
        @response.data=obj[:msg_ok]
        @agent.multistub [
          [:query, @response], 
          [:cfg_save, true], 
          [:exist?, true],
          [:pull, obj[:obj]]
        ] do
          @agent.query_stub do
            obj[:members_ok].each do |mem_ok|
              assert_equal obj[:obj], @agent.send(:obj_remove,obj[:obj],obj[:klass],mem_ok)
              assert_equal "#{obj[:cmd]} \'#{obj[:obj].name}\', \'#{mem_ok}\'", @agent.instance_variable_get(:@query_string)
              @agent.instance_variable_set(:@query_string,"")
              # test wrapper method
              @agent.send obj[:method],obj[:obj],mem_ok
              assert_equal "#{obj[:cmd]} \'#{obj[:obj].name}\', \'#{mem_ok}\'", @agent.instance_variable_get(:@query_string)
              @agent.instance_variable_set(:@query_string,"")
            end       
          end
        end
        
        # checking obj exists
        @response.data=obj[:msg_ok]
        @agent.multistub [
          [:exist?, false],
          [:query, @response]
        ] do  
          exp = assert_raises Provisioning::Agent::Error do    
            @agent.send(:obj_remove,obj[:obj],obj[:klass],obj[:member])
          end
          assert_equal "#{obj[:name]} #{obj[:obj].name} #{Provisioning::Agent::Error::OBJ_NOTEXIST}", exp.message
        end 
      end     
    end 
  end
  
  def test_obj_add
     
     objs = [
       {:obj=>ZoneConfiguration.new("zctest"), 
        :klass=>ZoneConfiguration, 
        :cmd => "cfgadd",
        :name => "Config",
        :member_name => "Zone",
        :member => Zone.new("zonetest"), 
        :members_ok => [Zone.new("zonetest")],
        :error=>Provisioning::Agent::Error::CFG_BAD,
        :error_member => Provisioning::Agent::Error::ZONE_BAD,
        :method=>:cfg_add,
        :msg_not_found => "> cfgadd \'zctest\',\'zonetest\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> cfgadd \'zctest\',\'zonetest\'\n",
        :resp_ok => ""
       },
       {:obj=>Zone.new("zonetest"), 
        :klass=>Zone, 
        :cmd => "zoneadd",
        :name => "Zone",
        :member_name => "Alias",
        :member => Alias.new("aliastest"), 
        :members_ok => [Alias.new("aliastest"), Wwn.new("50:01:02:03:04:05:06:07","target",1,1),"50:01:02:03:04:05:06:07","1,1"], 
        :error => Provisioning::Agent::Error::ZONE_BAD,
        :error_member => Provisioning::Agent::Error::MEMBER_BAD,
        :method=>:zone_add,
        :msg_not_found => "> zoneadd \'zonename\',\'aliastest\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> zoneadd \'zonename\',\'aliastest\'\n",
        :resp_ok => ""
        },
       {:obj=>Alias.new("aliastest"), 
        :klass=>Alias,
        :cmd => "aliadd",
        :name => "Alias",
        :member_name => "Wwn", 
        :member => "50:01:02:03:04:05:06:07", 
        :members_ok => [Wwn.new("50:01:02:03:04:05:06:07","target",1,1),"50:01:02:03:04:05:06:07","1,1"],
        :error => Provisioning::Agent::Error::ALIAS_BAD,
        :error_member => Provisioning::Agent::Error::ALIAS_MEMBER_BAD,
        :method=>:alias_add,
        :msg_not_found => "> aliadd \'aliastest\',\'50:00; 50:02\'\nnot found\n",
        :resp_not_found => "not found",
        :msg_ok => "> aliadd \'aliastest\',\'50:00; 50:02\'\n",
        :resp_ok => ""
        }
     ]
    
    
    objs.each do |obj|
      # should raise error if obj is not ok
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :obj_add,"query_string",obj[:klass],"member"
      end
      assert_equal obj[:error], exp.message
      # should raise error if member is not ok
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send :obj_add,obj[:obj],obj[:klass],"member"
      end
      assert_equal obj[:error_member], exp.message
      
      # test wrapper - enough to test teh wrapper for this
      exp = assert_raises Provisioning::Agent::Error do    
        @agent.send obj[:method],"query_string","member"
      end
      assert_equal obj[:error], exp.message
      
      # test if transaction is ongoing
      @agent.stub :check_for_running_transaction, true do 
        exp = assert_raises Provisioning::Agent::Error do    
          @agent.send :obj_add,obj[:obj],obj[:klass],obj[:member]
        end
        assert_equal Provisioning::Agent::Error::TRNS_IPRG, exp.message
      end
      
      @agent.stub :check_for_running_transaction, false do
        @response.data=obj[:msg_not_found]
        @agent.stub :query, @response do 
          exp = assert_raises Provisioning::Agent::Error do    
             @agent.send :obj_add ,obj[:obj],obj[:klass],obj[:member]
          end
          assert_equal obj[:resp_not_found], exp.message
        end
        
        # ok response
        
        @response.data=obj[:msg_ok]
        @agent.multistub [
          [:query, @response], 
          [:cfg_save, true], 
          [:exist?, true],
          [:pull, obj[:obj]]
        ] do
          @agent.query_stub do
            obj[:members_ok].each do |mem_ok|
              assert_equal obj[:obj], @agent.send(:obj_add,obj[:obj],obj[:klass],mem_ok)
              assert_equal "#{obj[:cmd]} \'#{obj[:obj].name}\', \'#{mem_ok}\'", @agent.instance_variable_get(:@query_string)
              @agent.instance_variable_set(:@query_string,"")
              # test wrapper method
              @agent.send obj[:method],obj[:obj],mem_ok
              assert_equal "#{obj[:cmd]} \'#{obj[:obj].name}\', \'#{mem_ok}\'", @agent.instance_variable_get(:@query_string)
              @agent.instance_variable_set(:@query_string,"")
            end     
          end
        end
        
        # checking obj exists
        # do not do the following for alias
        # the #exist? method is run for both object and member
        # the following stub only checks the obj
        @response.data=obj[:msg_ok]
        @agent.multistub [
          [:exist?, false],
          [:query, @response]
        ] do  
          exp = assert_raises Provisioning::Agent::Error do    
            @agent.send(:obj_add,obj[:obj],obj[:klass],obj[:member])
          end
          assert_equal "#{obj[:name]} #{obj[:obj].name} #{Provisioning::Agent::Error::OBJ_NOTEXIST}", exp.message
              
          # following hack ensures the exist? will be started for the 2nd run only so the member exists part
          @agent.raise_if_obj_do_not_exist_stub do
            exp = assert_raises Provisioning::Agent::Error do    
              @agent.send(:obj_add,obj[:obj],obj[:klass],obj[:member])
            end
            # ignore assert for Alias as it will not check if member exist-> will not raise error 
            if !obj[:name]=="Alias"
              assert_equal "#{obj[:member_name]} #{obj[:member]} #{Provisioning::Agent::Error::OBJ_NOTEXIST}", exp.message
            end
            @agent.instance_variable_set(:@run,nil)
          end
        end 
      end     
    end 
  end
  
  def test_obj_purge
    # obj_purge call obj remove and obj delete, so we test only that they are called
    # the responses of obj_delete and obj_remove are tested in their respective tests
    objs = [
       {:obj=>Zone.new("zonetest"), 
        :klass=>Zone, 
        :queries => ["cfgremove","zonedelete"],
        :method => :zone_purge,
        :parents => [ZoneConfiguration.new("cfgtest")]
        },
       {:obj=>Alias.new("aliastest"), 
        :klass=>Alias,
        :queries => ["zoneremove","alidelete"],
        :method => :alias_purge,
        :parents => [Zone.new("zonetest")]
        }
     ]
     # some ok response
     @response.data="> alidelete \'test\'\n"
     objs.each do |obj|
       @agent.multistub [
          [:check_for_running_transaction, false],
          [:lock_transaction, true],
          [:query, @response],
          [:cfg_save, true],
          [:exist?, true],
          [:get_transaction, true],
          [:find_by_member, obj[:parents]],
          [:pull, obj[:obj]]
       ] do
         @agent.query_stub do
           assert_equal obj[:obj], @agent.send(:obj_purge,obj[:obj],obj[:klass])
           # checks the cmd sent to query
           assert_equal "#{obj[:queries][0]} \'#{obj[:parents][0]}\', \'#{obj[:obj]}\'#{obj[:queries][1]} \'#{obj[:obj]}\'", @agent.instance_variable_get(:@query_string)
           @agent.instance_variable_set(:@query_string,"")
           # test wrapper method
           @agent.send obj[:method],obj[:obj]
           assert_equal "#{obj[:queries][0]} \'#{obj[:parents][0]}\', \'#{obj[:obj]}\'#{obj[:queries][1]} \'#{obj[:obj]}\'", @agent.instance_variable_get(:@query_string)
         end
       end
     end
  end
  
  def test_object_pull
    tmp_zone=Zone.new("zonetest")
    tmp_zone.add_member "alias1"
    tmp_zone.add_member "alias3"
    
    tmp_alias=Alias.new("aliastest")
    tmp_alias.add_member "50:01:43:80:12:0E:25:18"
    
    tmp_cfg = ZoneConfiguration.new("cfgtest")
    tmp_cfg.add_member "zone1"
    tmp_cfg.add_member "zone2"
    tmp_cfg.add_member "zone3"
    
    objs = [
       {:obj=>tmp_zone, 
        :klass=>Zone, 
        :queries => ["zoneshow"],
        :method => :zone_purge,
        :msg_ok => "> zoneshow \"zonetest\"\n zone:  zonetest alias1;\n\talias3\n",
        :msg_bad => "> zoneshow\nerror\n"
        },
       {:obj=>tmp_alias, 
        :klass=>Alias,
        :queries => ["alishow"],
        :method => :alias_purge,
        :msg_ok => "> alishow \"aliastest\"\n alias:  aliastest\n\t50:01:43:80:12:0E:25:18",
        :msg_bad => "> alishow\nerror\n"
        },
       {:obj=>tmp_cfg, 
        :klass=>ZoneConfiguration,
        :queries => ["cfgshow"],
        :method => :alias_purge,
        :msg_ok => "> cfgshow \"cfgtest\"\n cfg: cfgtest  zone1;\n\tzone2;zone3\n",
        :msg_bad => "> cfgshow\nerror\n"
        }
     ]
    objs.each do |obj|
      @response.data=obj[:msg_ok]
      @agent.stub :query, @response do
        @agent.query_stub do
          test_obj = @agent.send(:obj_pull,obj[:obj],obj[:klass])
          assert_equal obj[:obj].name, test_obj.name
          assert_equal obj[:obj].members, test_obj.members
          assert_equal "#{obj[:queries][0]} \"#{obj[:obj]}\"", @agent.instance_variable_get(:@query_string)
          @agent.instance_variable_set(:@query_string,"")
        end
      end
      
      # not processable means we could not find it
      @response.data=obj[:msg_bad]
      @agent.stub :query, @response do
        @agent.query_stub do
          assert_nil @agent.send(:obj_pull,obj[:obj],obj[:klass])
        end
      end
      
      # string instead of object, asks 3 times and returns nil in this case
      @response.data=obj[:msg_bad]
      @agent.stub :query, @response do
        @agent.query_stub do
          assert_nil @agent.send(:obj_pull,"test",String)
          assert_equal "cfgshow \"test\"zoneshow \"test\"alishow \"test\"", @agent.instance_variable_get(:@query_string)
        end
      end
      # very difficult to test if one of the response would be ok so skipping
    end
  end
  
  def test_rename_object
    objs = [
       {:obj=>Zone.new("zonetest"), 
        :new_obj=>Zone.new("zonetest_new"),
        :klass=>Zone, 
        :msg_ok => "> zoneobjectrename \"zonetest\", \"zonetest_new\"\n",
        :msg_not_found => "> zoneobjectrename \"zonetest\", \"zonetest_new\"\nnot found \"zonetest\"\n"
        },
       {:obj=>Alias.new("aliastest"),
        :new_obj=>Alias.new("aliastest_new"), 
        :klass=>Alias,
        :msg_ok => "> zoneobjectrename \"aliastest\", \"aliastest_new\"\n",
        :msg_not_found => "> zoneobjectrename \"aliastest\", \"aliastest_new\"\nnot found \"aliastest\"\n"
        },
       {:obj=>ZoneConfiguration.new("cfgtest"),
        :new_obj=>ZoneConfiguration.new("cfgtest_new"),
        :klass=>Alias,
        :msg_ok => "> zoneobjectrename \"cfgtest\", \"cfgtest_new\"\n",
        :msg_not_found => "> zoneobjectrename \"cfgtest\", \"cfgtest_new\"\nnot found \"cfgtest\"\n"
        },
       {:obj=>"test", 
        :new_obj=>"test_new",
        :klass=>"String",
        :msg_ok => "> zoneobjectrename \"test\", \"test_new\"\n",
        :msg_not_found => "> zoneobjectrename \"test\", \"test_new\"\nnot found \"test\"\n"
        }
     ]
     
    objs.each do |obj|
      #response ok
      @response.data = obj[:msg_ok] 
      @agent.multistub [
        [:query, @response],
        [:pull, obj[:new_obj]],
        [:cfg_save, :cfg_save]
      ] do
        @agent.query_stub do
          test_obj = @agent.send(:rename_object,obj[:obj],"#{obj[:obj]}_new")
          assert_equal obj[:new_obj].to_s, test_obj.to_s
          assert_equal "zoneobjectrename \"#{obj[:obj]}\", \"#{obj[:obj]}_new\"", @agent.instance_variable_get(:@query_string)
          @agent.instance_variable_set(:@query_string,"")
        end
      end
      
      #response bad
      @response.data = obj[:msg_not_found] 
      @agent.multistub [
        [:query, @response],
        [:pull, obj[:obj]],
        [:cfg_save, :cfg_save]
      ] do
        @agent.query_stub do
          exp = assert_raises Provisioning::Agent::Error do
            test_obj = @agent.send(:rename_object,obj[:obj],"#{obj[:obj]}_new")
          end
          assert_equal "not found \"#{obj[:obj]}\"", exp.message
        end
      end
    end
  end
  
  def test_get_obj_type
    assert_equal :zone, @agent.send(:get_obj_type, Zone.new("test"))
    assert_equal :alias, @agent.send(:get_obj_type, Alias.new("test"))
    assert_equal :cfg, @agent.send(:get_obj_type, ZoneConfiguration.new("test"))
    assert_equal :all, @agent.send(:get_obj_type, "test")
  end
end

end; end

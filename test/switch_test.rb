require 'brocadesan'
require 'minitest/autorun'
require 'output_helpers'

module Brocade module SAN
  
class SwitchTest < MiniTest::Test
  include OutputReader
  include SshStoryWriter
  include Mock::Net::SSH
  patch_set
    
  def setup
    init_dev
  end
  
  def init_dev
    @device = Switch.new("test","test","test")
  end
  
  def test_query
    response=@device.query("test")
    assert_instance_of Switch::Response, response
    assert_equal @device.prompt+"test\n"+Mock::Net::SSH::get_data+"\n", response.data
    # check fullcmd is started
    @i=0
    inc = lambda {|cmd| @i+=1;cmd}
    @device.stub :fullcmd, inc do
      response=@device.query("test")
      assert_equal 1, @i
      @i=0
      response=@device.query("test","test")
      assert_equal 2, @i
    end
  end
  
  def test_interactive_query
    cmds = ["fosexec --fid 99 'cfgsave'","y"]
    replies = ["confirm? [y,n]"]
    exp_response = write_interactive_story(cmds,replies,TestDevice::DEFAULT_QUERY_PROMPT)
    
    @device.set_mode("interactive")
    @device.set_context 99
    # connection is net/ssh/test method
    @device.instance_variable_set(:@session,connection)
    
    response=nil
    assert_scripted do
      response=@device.query("cfgsave","y")
      assert_equal exp_response, response.data
    end    
    
  end
  
  def test_device_setup
    assert_instance_of Switch, @device
  end
  
  def test_set_context
    @device.set_context(3)
    assert_equal 3, @device.fid
    assert_empty @device.instance_variable_get(:@loaded)
    assert_equal 3, @device.fid
    @device.set_context("A3")
    assert_equal 128, @device.fid
  end
  
  def test_get
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "switch_" do |file,output|
      init_dev
      response=new_mock_response
      response.data=output
      yaml=read_yaml_for(file)
           
      @device.stub :query, response do 
        assert_equal yaml[:switch_name], @device.get(:name)        
        # clear configuration
        @device.instance_variable_set(:@configuration,{})
        assert_nil  @device.get(:name) #nil if not reloaded
        assert_equal yaml[:switch_name], @device.get(:name,true) # ok if reloaded
        
        #raise error if unknow parameter is requested
        assert_raises Switch::Error do 
           @device.get(:dummy,true)
        end
      end
    end
  end
  
  def test_vf
    response=new_mock_response
    response.data="> switchshow |grep \"^LS Attributes\"\n"
    @device.stub :query, response do 
      assert_equal "disabled", @device.vf(true)        
    end
    
    response.data="> switchshow |grep \"^LS Attributes\"\nLS Attributes:  [FID: 128, Base Switch: No, Default Switch: Yes, Address Mode 0]\n"
    
    @device.stub :query, response do 
      # running it without force should still show the same
      assert_equal "disabled", @device.vf        
      
      assert_equal "enabled", @device.vf(true)
    end
  end
  
  def test_get_with_vf
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "vf_switch" do |file,output|
      init_dev
      response=new_mock_response
      response.data=output
      @device.configuration[:vf]="enabled"
      @device.set_context 99
        
      @device.stub :query, response do 
        assert_equal read_yaml_for(file)[:switch_name], @device.get(:name)        
      end
    end
  end
  
  def test_refresh
    #returns true and runs query if not loaded or forced, runs query
    @device.instance_variable_set(:@configuration,{:name=>"test", :parsing_position=>"test"})
    @device.send(:refresh, "switchshow")
    assert_equal a = {:name=>"test", :parsing_position=>"end"}, @device.configuration
    assert_equal true, @device.instance_variable_get(:@loaded)[:switchshow]
  end
  
  def test_dynamic_methods
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "" do |file,output|
      response=new_mock_response
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @device.stub :query, response do 
        Switch::CMD_MAPPING.each do |k,v|
          #puts "#{v[:attr].to_sym}: #{read_yaml_for(file)[v[:attr].to_sym]} = #{@device.method(k).call}"
          assert_equal yaml[v[:attr].to_sym], @device.method(k).call        
          # clear configuration
          @device.instance_variable_set(:@configuration,{})
          assert_nil  @device.method(k).call #nil if not reloaded
          assert_equal yaml[v[:attr].to_sym], @device.method(k).call(true) # ok if reloaded
        end
      end
    end
  end
  
  def test_fullcmd
    assert_equal "test", @device.send(:fullcmd,"test")
    
    #vf enabled but no fid
    @device.configuration[:vf]="enabled"
    assert_equal "test", @device.send(:fullcmd,"test")
    
    #vf enabled and fid given
    @device.set_context 99
    assert_equal "fosexec --fid 99 \'test\'", @device.send(:fullcmd,"test")
    
    #vf enabled and fid given and piped commnad
    @device.set_context 99
    assert_equal "fosexec --fid 99 \'test\' |grep shit", @device.send(:fullcmd,"test|grep shit")
    
    #vf enabled and fid given and piped commnad
    @device.set_context 99
    assert_equal "fosexec --fid 99 \'test\' | grep shit| grep shit2", @device.send(:fullcmd,"test| grep shit| grep shit2")
  end
  
  def test_zone_cfgs_and_effective_cfg_and_zones
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "cfgshow_" do |file,output|
      response=new_mock_response
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @device.stub :query, response do 
        cfgs=@device.zone_configurations.map {|c| c.name }
        yaml[:defined_configuration][:cfg].each do |config, members|
          assert cfgs.include?(config)
        end   
        ef_cfg=@device.zone_configurations.map {|c| c.name if c.effective }.delete_if {|c| c==nil}
        assert_equal yaml[:defined_configuration][:cfg].keys[0], ef_cfg.first
        
        #test if effective_configuration method
        assert_equal yaml[:defined_configuration][:cfg].keys[0], @device.effective_configuration.name
        
        # test zones
        if yaml[:defined_configuration][:zone]
          zones=@device.zones.map {|z| z.name }
          yaml[:defined_configuration][:zone].each do |zone, members|
            assert zones.include?(zone)
          end   
          
          # testig active zones
          zones_1=@device.effective_configuration(true).members
          zones_2=@device.zones
          
          zones_2.each do |zone|
            if zones_1.include? zone.name
              assert zone.active, "Zone should be active"
            else
              refute zone.active, "Zone should not be active"
            end
          end
        end
        
        # test aliases
        if yaml[:defined_configuration][:alias]
          aliases=@device.aliases.map {|a| a.name }
          yaml[:defined_configuration][:alias].each do |al, members|
            assert aliases.include?(al)
          end   
        end
      end
    end
  end
  
  def test_find_zone_alias
    
    response=new_mock_response
    response.data="> configshow |grep -i -E zone.VAL_lis9swep01_m1p1_IEVA16:\nzone.VAL_lis9swep01_m1p1_IEVA16:ieva16_A1_ho;ieva16_B1_ho;ida16R24c7_bay12_m1p1"
    init_dev

    @device.stub :query, response do 
      z=@device.find_zone("VAL_lis9swep01_m1p1_IEVA16")
      assert_equal "VAL_lis9swep01_m1p1_IEVA16", z[0].name
      assert_equal ["ieva16_A1_ho","ieva16_B1_ho","ida16R24c7_bay12_m1p1"], z[0].members
    end          
    
    response.data="> configshow |grep -i -E zone.unknown:"
        
    @device.stub :query, response do 
      z=@device.find_zone("unknown")
      assert_equal [], z
    end         
    
    # test find aliases

    response.data="> configshow |grep -i -E ^alias.ivls01n0_1:\nalias.ivls01n0_1:50:02:26:40:8F:DC:20:00"

    @device.stub :query, response do 
      a=@device.find_alias("ivls01n0_1")
      assert_equal "ivls01n0_1", a[0].name
      assert_equal ["50:02:26:40:8F:DC:20:00"], a[0].members
    end          
    
    response.data="> configshow |grep -i -E ^alias.unknown:"
        
    @device.stub :query, response do 
      a=@device.find_alias("unknown")
      assert_equal [], a
    end 
  end
  
  
  def test_find_zones_aliases
    
    response=new_mock_response
    response.data="> configshow |grep -i -E ^zone.VAL_lis9swep01_m1p1\nzone.VAL_lis9swep01_m1p1_IEVA16:ieva16_A1_ho;ieva16_B1_ho;ida16R24c7_bay12_m1p1\nzone.VAL_lis9swep01_m1p1_IVLS01:ivls01n2_1;ivls01n3_1;ida16R24c7_bay12_m1p1"
    init_dev

    @device.stub :query, response do 
      z=@device.find_zones("VAL_lis9swep01_m1p1")
      assert_equal ["VAL_lis9swep01_m1p1_IEVA16","VAL_lis9swep01_m1p1_IVLS01"], z.map {|zone| zone.name }
      assert_equal [["ieva16_A1_ho","ieva16_B1_ho","ida16R24c7_bay12_m1p1"],["ivls01n2_1","ivls01n3_1","ida16R24c7_bay12_m1p1"]], z.map {|zone| zone.members }
    end          
    
    response.data="> configshow |grep -i -E zone.unknown:"
        
    @device.stub :query, response do 
      z=@device.find_zones("unknown")
      assert_equal [], z
    end      
    
    response.data="> configshow |grep -i -E ^alias.ivls01n\nalias.ivls01n0_1:50:02:26:40:8F:DC:20:00\nalias.ivls01n1_1:50:02:26:40:8F:DC:20:01\nalias.ivls01n2_1:50:02:26:40:8F:DC:20:02\nalias.ivls01n3_1:50:02:26:40:8F:DC:20:03\nalias.ivls01n4_1:50:02:26:40:8F:DC:20:04\nalias.ivls01n5_1:50:02:26:40:8F:DC:20:05"
    
    @device.stub :query, response do 
      a=@device.find_aliases("ivls01n")
      assert_equal ["ivls01n0_1","ivls01n1_1","ivls01n2_1","ivls01n3_1","ivls01n4_1","ivls01n5_1"], a.map {|al| al.name }
      assert_equal [["50:02:26:40:8F:DC:20:00"],["50:02:26:40:8F:DC:20:01"],["50:02:26:40:8F:DC:20:02"],["50:02:26:40:8F:DC:20:03"],["50:02:26:40:8F:DC:20:04"],["50:02:26:40:8F:DC:20:05"]], a.map {|al| al.members }
    end          
    
    response.data="> configshow |grep -i -E alias.unknown:"
        
    @device.stub :query, response do 
      a=@device.find_aliases("unknown")
      assert_equal [], a
    end      
  end
  
  def test_find_by_member
    response=new_mock_response
    
    # find owners of zone
    response.data="> configshow |grep -i -E \"^zone|alias|cfg\.\"  | grep -i -E \"(:|;)zone_a(;|$)\""
    response.data<<"\n"
    response.data<<"cfg.ecs_a:zone_a;zone_b;zone_c\n"
    

    @device.stub :query, response do 
      owners=@device.find_by_member("zone_a")
      assert_equal "ecs_a", owners[0].name
      owners=@device.find_by_member("zone_b")
      assert_equal "ecs_a", owners[0].name
      owners=@device.find_by_member("zone_c")
      assert_equal "ecs_a", owners[0].name
      owners=@device.find_by_member("zone_d")
    end
    
    # cannot find anything
    response.data="> configshow |grep -i -E \"^zone|alias|cfg\.\"  | grep -i -E \"(:|;)zone_a(;|$)\""
    response.data<<"\n"
    response.data<<"\n"
    
    @device.stub :query, response do 
      owners=@device.find_by_member("zone_a")
      assert_empty owners
    end
    
    # find owners of wwn
    response.data="> configshow |grep -i -E \"^zone|alias|cfg\.\"  | grep -i -E \"(:|;)50:00:01:02:03:04:05:06(;|$)\""
    response.data<<"\n"
    response.data<<"zone.zone_a:50:00:01:02:03:04:05:06;50:00:01:02:03:04:06:06;50:00:01:02:03:04:06:07\n"
    response.data<<"alias.alias_a:50:00:01:02:03:04:06:05;50:00:01:02:03:04:06:06;50:00:01:02:03:04:06:07\n"
    
    @device.stub :query, response do 
      owners=@device.find_by_member("50:00:01:02:03:04:05:06")
      assert_equal 2, owners.size
      assert_instance_of Zone, owners[0]
      assert_instance_of Alias, owners[1]
    end
    
    # test transaction => true
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "cfgshow_2" do |file,output|
      z1 = Zone.new("zone1")
      z1.add_member "alias1"
      z1.add_member "alias2"
        
      z2 = Zone.new("zone2")
      z2.add_member "alias1"
      z2.add_member "alias3"
      
      z3 = Zone.new("zone3")
      z3.add_member "alias3"
      z3.add_member "alias4"
      
      z5 = Zone.new("zone5")
      z5.add_member "alias1"
      z5.add_member "alias4"
      
      response.data=output.dup
      @device.stub :query, response do  
        zones = @device.find_by_member("alias2",:object=>:all, :transaction => true)
        assert_equal z1.name, zones[0].name
        assert_equal z1.members, zones[0].members
      end
      response.data=output.dup
      @device.stub :query, response do  
        zones = @device.find_by_member("alias1",:object=>:all, :transaction => true)
        assert_equal 3, zones.size
        assert_equal z1.name, zones[0].name
        assert_equal z1.members, zones[0].members
        assert_equal z2.name, zones[1].name
        assert_equal z2.members, zones[1].members
        assert_equal z5.name, zones[2].name
        assert_equal z5.members, zones[2].members
      end
    end
    
    @device.query_stub do
      @device.stub :old_query, response do 
        # no parameters -> :exact and :all
        @device.find_by_member("test")
        assert_equal "configshow | grep -i -E \"^zone|alias|cfg.\" | grep -i -E \"(:|;)test(;|$)\"",@device.instance_variable_get(:@query_string)
        @device.instance_variable_set(:@query_string,"")   
        # find zone
        @device.find_by_member("test", :object => :zone)
        assert_equal "configshow | grep -i -E \"^zone.\" | grep -i -E \"(:|;)test(;|$)\"",@device.instance_variable_get(:@query_string)
        @device.instance_variable_set(:@query_string,"")
        # find alias
        @device.find_by_member("test", :object => :alias)
        assert_equal "configshow | grep -i -E \"^alias.\" | grep -i -E \"(:|;)test(;|$)\"",@device.instance_variable_get(:@query_string)
        @device.instance_variable_set(:@query_string,"")
        #find partial
        @device.find_by_member("test", :find_mode => :partial)
        assert_equal "configshow | grep -i -E \"^zone|alias|cfg.\" | grep -i -E \":.*test\"",@device.instance_variable_get(:@query_string)
        @device.instance_variable_set(:@query_string,"")
        #find by partial and zone
        @device.find_by_member("test", :find_mode => :partial, :object=>:zone)
        assert_equal "configshow | grep -i -E \"^zone.\" | grep -i -E \":.*test\"",@device.instance_variable_get(:@query_string)
        @device.instance_variable_set(:@query_string,"")
        @device.find_by_member("test", :transaction => true)
        assert_equal "cfgshow",@device.instance_variable_get(:@query_string)
        @device.instance_variable_set(:@query_string,"")
      end
    end 
  end
  
  def test_wwns
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "ns_" do |file,output|
      response=new_mock_response
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @device.stub :query, response do 
        wwns=@device.wwns.map {|w| w.value}
        yaml[:wwn_local].each do |wwn|
          assert wwns.include?(wwn[:value]), "WWN #{wwn} is not included in #{wwns.inspect}"
        end
        wwns=@device.wwns(false,:cached).map {|w| w.value}
        yaml[:wwn_remote].each do |wwn|
          assert wwns.include?(wwn[:value]), "WWN #{wwn} is not included in #{wwns.inspect}"
        end   
        wwns=@device.wwns(false,:all).map {|w| w.value}
        yaml[:wwn_local].each do |wwn|
          assert wwns.include?(wwn[:value]), "WWN #{wwn} is not included in #{wwns.inspect}"
        end
        yaml[:wwn_remote].each do |wwn|
          assert wwns.include?(wwn[:value]), "WWN #{wwn} is not included in #{wwns.inspect}"
        end
      end
    end
  end
  
  def test_find_wwn
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "ns_1" do |file,output|
      response=new_mock_response
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @device.stub :query, response do 
        
        # test find wwn
        yaml[:wwn_local].each do |wwn|
          w=@device.find_wwn(wwn[:value])
          assert_equal wwn[:value], w.value
          
          # test insensitive
          w=@device.find_wwn(wwn[:value].upcase)
          assert_equal wwn[:value], w.value
        end
        
        yaml[:wwn_remote].each do |wwn|
          w=@device.find_wwn(wwn[:value],true,:fabric_wide=>true)
          assert_equal wwn[:value], w.value
          
          # test insensitive
          w=@device.find_wwn(wwn[:value].upcase,true,:fabric_wide=>true)
          assert_equal wwn[:value], w.value
        end
        
        assert_nil @device.find_wwn("unknown")
      end
    end
  end
  
  def test_fabric
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "fabricshow_" do |file,output|
      response=new_mock_response
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @device.stub :query, response do 
        
        assert_equal yaml[:fabric], @device.fabric
        # clear configuration
        @device.instance_variable_set(:@configuration,{})
        assert_nil  @device.fabric #nil if not reloaded
        assert_equal yaml[:fabric], @device.fabric(true) # ok if reloaded
        
        assert @device.instance_variable_get(:@loaded)[:fabricshow], "Should be true"
      end
    end
  end
  
end

class SwitchResponseTest < MiniTest::Test
  include OutputReader

  def test_parse   
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "" do |file, output|
      response=new_mock_response
      response.data=output
      response.parse
      assert_equal read_yaml_for(file), response.parsed
    end
  end
  
  def test_after_before_parse
    response=new_mock_response
    response.parsed[:ports]=["A","B","A"]
    response.parse
    assert_equal nil, response.parsed[:ports]
  end
end

end; end
require 'brocadesan'
require 'minitest/autorun'
require 'output_reader'

module Brocade module SAN
  
class SwitchTest < MiniTest::Unit::TestCase
  include OutputReader
  def setup
    init_dev
  end
  
  def init_dev
    @device = Switch.new("test","test","test")
  end
  
  def test_query
    response=@device.query("test")
    assert_instance_of Switch::Response, response
    assert_equal Switch::QUERY_PROMPT+"test\n"+Net::SSH::DATA+"\n", response.data
    assert_equal Net::SSH::ERROR+"\n", response.errors
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
      response=Switch::Response.new
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
  
  def test_get_with_vf
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "vf_switch" do |file,output|
      init_dev
      response=Switch::Response.new
      response.data=output
      @device.configuration[:virtual_fabric]="enabled"
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
      response=Switch::Response.new
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
    @device.configuration[:virtual_fabric]="enabled"
    assert_equal "test", @device.send(:fullcmd,"test")
    
    #vf enabled and fid given
    @device.set_context 99
    assert_equal "fosexec --fid 99 \'test\'", @device.send(:fullcmd,"test")
  end
  
  def test_zone_cfgs_and_effective_cfg_and_zones
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "cfgshow_" do |file,output|
      response=Switch::Response.new
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
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "cfgshow_2" do |file,output|
      response=Switch::Response.new
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @device.stub :query, response do 
        
        # test find zones
        yaml[:defined_configuration][:zone].each do |zone, members|
          z=@device.find_zone(zone)
          assert_equal zone, z.name
          assert_equal yaml[:defined_configuration][:zone][zone], z.members
          
          # test insensitive
          z=@device.find_zone(zone.upcase)
          assert_equal zone, z.name
        end
        
        assert_nil @device.find_zone("unknown")
        
        # test find aliases
        yaml[:defined_configuration][:alias].each do |al, members|
          a=@device.find_alias(al)
          assert_equal al, a.name
          assert_equal yaml[:defined_configuration][:alias][al], a.members
          
          # test insensitive
          a=@device.find_alias(al.upcase)
          assert_equal al, a.name
        end
        
        assert_nil @device.find_alias("unknown")
        
      end
    end
  end
  
  
  def test_find_zones_aliases
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "cfgshow_2" do |file,output|
      response=Switch::Response.new
      response.data=output
      init_dev
      yaml=read_yaml_for(file)
      @device.stub :query, response do 
        
        # test find zones
        
        z=@device.find_zones('zone')
        assert_equal yaml[:defined_configuration][:zone].keys.find_all {|k| k.match(/zone/i)}, z.map {|zone| zone.name}
          
        # test insensitive
        z=@device.find_zones('zone'.upcase)
        assert_equal yaml[:defined_configuration][:zone].keys.find_all {|k| k.match(/zone/i)}, z.map {|zone| zone.name}
        
        assert_empty @device.find_zones("unknown")
        
        # test find aliases
        
        a=@device.find_aliases('alias')
        assert_equal yaml[:defined_configuration][:alias].keys.find_all {|k| k.match(/alias/i)}, a.map {|a| a.name}
          
        # test insensitive
        a=@device.find_aliases('alias'.upcase)
        assert_equal yaml[:defined_configuration][:alias].keys.find_all {|k| k.match(/alias/i)}, a.map {|a| a.name}
        
        assert_empty @device.find_aliases("unknown")
        
      end
    end
  end
  
  
end

class SwitchResponseTest < MiniTest::Unit::TestCase
  include OutputReader

  def test_parse   
    @output_dir=File.join(Dir.pwd,"test","outputs")
    read_all_starting_with "" do |file, output|
      response=Switch::Response.new
      response.data=output
      response.parse
      assert_equal read_yaml_for(file), response.parsed
    end
  end
  
  def test_after_before_parse
    response=Switch::Response.new
    response.parsed[:ports]=["A","B","A"]
    response.parse
    assert_equal nil, response.parsed[:ports]
  end
end

end; end
require 'yaml'
require 'net/ssh/test'

module OutputReader
  
  attr_accessor :output_dir
  
  def read_all_starting_with(regexp,&block)
    @output_dir=Dir.pwd if @output_dir.nil?
    files=Dir.glob(File.join(@output_dir,"#{regexp}*.txt"))
    files.each do |f|
      contents = File.read(f)
      yield f, contents
    end
  end
  
  def read_yaml_for(file)
    parts=file.split(".")
    file_name=parts[0..-2].join(".")
    YAML.load(File.read("#{file_name}.yml"))
  end
  
  def new_mock_response
    Brocade::SAN::Switch::Response.new("> ")
  end
end

# this is used to check the _exec methods in device
# for the remaining test see the below monkeypath mock 
module SshStoryWriter
  include Net::SSH::Test
  
  # creates a interactive ssh story for testing and returns expeced response for that story
  def write_interactive_story(cmds,partial_replies,prompt="")
    cmd=cmds.shift
    response = "#{prompt}"
    story do |session|
      channel = session.opens_channel
      channel.sends_request_pty
      channel.sends_exec cmd
      response +="#{cmd}\n"
      partial_replies.each_with_index do |pr,i|
        channel.gets_data pr
        channel.sends_data "#{cmds[i]}\n"
        
        response +="#{pr}"
        response +="#{cmds[i]}\n"
      end
      channel.gets_close
      channel.sends_close
    end
    
    return response
  end
  
  # creates non interactive ssh story for testing and returns expeced response for that story
  def write_non_interactive_story(cmds,replies,prompt="")
    response = ""
    story do |session|
      replies.each_with_index do |reply,i|
        channel = session.opens_channel
        channel.sends_exec cmds[i]
        channel.gets_data reply
        channel.gets_close
        channel.sends_close
        response +="#{prompt}#{cmds[i]}\n"
        response +="#{reply}\n"
      end

    end
    
    return response
  end
  
  def write_failed_simple_story(cmd,error,prompt="")
    response = ""
    story do |session|
      channel = session.opens_channel
      channel.sends_exec cmd
      channel.gets_extended_data error
      #session.gets_channel_extended_data(channel, error)
      channel.gets_close
      channel.sends_close
      response +="#{prompt}#{cmd}\n"
      #response +="#{reply}\n"

    end
    
    return response
  end
end

# patch for request_pry based on https://github.com/test-kitchen/test-kitchen/blob/master/spec/kitchen/ssh_spec.rb#L86-L113
module Net

  module SSH

    module Test

      class Channel

        def sends_request_pty
          pty_data = ["xterm", 80, 24, 640, 480, "\0"]

          script.events << Class.new(Net::SSH::Test::LocalPacket) do
            def types
              if @type == 98 && @data[1] == "pty-req"
                @types ||= [
                  :long, :string, :bool, :string,
                  :long, :long, :long, :long, :string
                ]
              else
                super
              end
            end
          end.new(:channel_request, remote_id, "pty-req", false, *pty_data)
        end
      end
    end
  end
end

# simplified mock module that is used to monkey patch/stub Net::SSH.start
# the stubed method resturns mocked Session
# the session for now response to exec!, closed? and close
# which is sufficient for my testing
# Usage:
# put following into subclasees MiniTest::Test that should use this mock
#  include Mock::Net::SSH
#  patch_set
#
# or
#
# put following into subclasees MiniTest::Test that should not use this mock
# mention this explicitely as some other test might have set it
#  include Mock::Net::SSH
#  patch_revert
#
module Mock
module Net
module SSH
  
  def self.included(base)
    base.extend(ClassMethods)  
  end
  
  def initialize(*args)
     patch_configure
     super(*args)     
  end
  
  def patch_configure;  end
        
  module ClassMethods
    def patch_set
      alias_method :patch_configure, :monkey_patch
    end
    
    def patch_revert
      alias_method :patch_configure, :monkey_patch_revert
    end
  end
  
  @@data="Response"
  @@error=""
  @@channel="channel"
  
  def self.get_data
    @@data
  end
  
  def self.get_error
    @@error
  end
  
  def self.get_channel
    @@channel
  end

  def self.set_data(x)
    @@data=x
  end
  
  def self.set_error(x)
    @@error=x
  end
  
  def self.set_channel(x)
    @@channel=x
  end
  
  class Session 
    def exec!(command, &block)
      @data=Mock::Net::SSH::get_data.dup
      @error=Mock::Net::SSH::get_error.dup
      @ch=Mock::Net::SSH::get_channel.dup
      
      if block
        block.call(@ch, :stdout, @data)
        block.call(@ch, :stderr, @error)
      else
        $stdout.print(data)
      end
    end
      
    def close
      @closed=true
    end
    
    def closed?
      @closed.nil? ? false : @closed
    end
  end
  
  private
  def monkey_patch
    ::Net::SSH.instance_eval do
      singleton = self.singleton_class
      if !singleton.respond_to? :old_start 
        singleton.send(:alias_method, :old_start, :start)
      
        def self.start(host, user, options={}, &block)  
          if block
            yield Mock::Net::SSH::Session.new
          else
            return Mock::Net::SSH::Session.new
          end
        end
      end
    end    
  end
  
  def monkey_patch_revert
    ::Net::SSH.instance_eval do
      if self.singleton_class.respond_to? :old_start
        self.singleton_class.send(:alias_method, :start, :old_start)
        self.singleton_class.send(:undef_method, :old_start)
      end
    end    
  end
end
end
end

module Kernel
  # stubs query method by another method that assiges the parameters to @test_string and runing original query
  def query_stub(&block)
   self.instance_eval do
      self.singleton_class.send(:alias_method, :old_query, :query)
      @query_string=""
      def query(*cmds)
        @query_string||=""
        @query_string<<cmds.join(",")
        old_query(*cmds)
      end
    end
    yield
    self.instance_eval do 
      self.singleton_class.send(:alias_method, :query, :old_query)
      self.singleton_class.send(:undef_method, :old_query)
    end  
  end
  
  # stubs query method by another method that assiges the parameters to @test_string and runing original query
  def abort_transaction_stub(&block)
   self.instance_eval do
      self.singleton_class.send(:alias_method, :old_abort_transaction, :abort_transaction)
      def abort_transaction
        @trans_aborted=true
        old_abort_transaction
      end
    end
    yield
    self.instance_eval do 
      self.singleton_class.send(:alias_method, :abort_transaction, :old_abort_transaction)
      self.singleton_class.send(:undef_method, :old_abort_transaction)
    end  
  end
  
  # stubs query method by another method that assiges the parameters to @test_string and runing original query
  def raise_if_obj_do_not_exist_stub(&block)
   self.instance_eval do
      self.singleton_class.send(:alias_method, :old_raise_if_obj_do_not_exist, :raise_if_obj_do_not_exist)
      def raise_if_obj_do_not_exist(obj)
        if !@run.nil?
          old_raise_if_obj_do_not_exist(obj)
        end
        @run=true
      end
    end
    yield
    self.instance_eval do 
      self.singleton_class.send(:alias_method, :raise_if_obj_do_not_exist, :old_raise_if_obj_do_not_exist)
      self.singleton_class.send(:undef_method, :old_raise_if_obj_do_not_exist)
    end  
  end
  
  def multistub(cmds,&block)
    if !cmds.empty?
      cmd = cmds.shift
      stub cmd[0], cmd[1] do
          multistub cmds, &block        
      end
    else
      yield
    end
  end
end
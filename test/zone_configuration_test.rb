require 'brocadesan'
require 'minitest/autorun'

class ZoneConfigurationTest < MiniTest::Unit::TestCase
  def test_new_zone_config
    cfg=ZoneConfiguration.new("test",:effective=>true)
    assert_equal "test", cfg.name
    assert cfg.effective
  end
end

require 'brocadesan'
require 'minitest/autorun'

class ZoneConfigurationTest < MiniTest::Unit::TestCase
  def test_new_zone
    assert_equal "test", ZoneConfiguration.new("test").name
  end
end

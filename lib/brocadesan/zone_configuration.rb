class ZoneConfiguration
  attr_reader :name
  def initialize(name,opts={})
      @name=name
      @opts=opts
  end
end
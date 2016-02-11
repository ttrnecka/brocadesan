Gem::Specification.new do |s|
  s.name        = 'brocadesan'
  s.version     = '0.4.5'
  s.date        = '2016-02-11'
  s.summary     = "Brocade SAN library"
  s.description = "Gem to manipulate FABOS based devices"
  s.authors     = ["Tomas Trnecka"]
  s.email       = 'trnecka@gmail.com'
  s.files       = `git ls-files`.split("\n") 
  s.homepage    = 'http://rubygems.org/gems/brocadesan'
  s.add_runtime_dependency "net-ssh", "~> 2.9"
  s.add_development_dependency "minitest",["~> 5.0"]
  s.add_development_dependency "rake-notes",["~> 0.2"]
end
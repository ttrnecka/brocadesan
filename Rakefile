require 'rake/testtask'
require 'rdoc/task'
require 'yaml'

  Rake::TestTask.new do |t|
    t.libs = ["lib","test"]
    t.warning = false
    t.verbose = true
    t.test_files = FileList['test/**/*_test.rb']
  end
 
  Rake::RDocTask.new do |rd|
    rd.main = "README"
    rd.title    = "BrocadeSAN"
    rd.rdoc_files.include("README","lib/**/*.rb")
    
    rd.before_running_rdoc do 
      Rake::Task["generate_meta"].invoke
    end
  end
  
  task :generate_meta do
    files=Dir.glob("lib/brocadesan/config/brocade/san/*cmd_mapping.yml")
    doc=""
    files.each do |file|
      doc+="class Brocade::SAN::#{File.basename(file.gsub("_cmd_mapping.yml","")).split('_').map{|e| e.capitalize}.join}\n"
      hash=YAML.load(File.read(file))
      hash.each do |method,v|
        doc+="##\n"
        doc+="# :method: #{method.to_s}\n"
        doc+="# If called with +true+ argument it will get the #{v[:attr]} from the switch instead of cache\n"
        doc+="#\n"
        doc+="# Returns value in (string) format\n"
        doc+="\n"
      end
      doc+="end\n"
      File.open("lib/meta_methods.rb", 'w') {|f| f.write(doc) }
    end
  end

desc "Run tests"
task :default => :test
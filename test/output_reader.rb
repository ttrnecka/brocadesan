require 'yaml'

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
end
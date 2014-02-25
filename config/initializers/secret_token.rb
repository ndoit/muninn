require 'yaml'
require 'pathname'
if ENV.has_key?("SECRET_KEY")
  Rails.application.config.secret_key_base = ENV["SECRET_KEY"]
  puts "Secret key found in ENV."
else
  file_name = Pathname.new("config/secret_key.yml")
  data = YAML::load_file(file_name)
  if !data
  	data = {}
  end

  if data.has_key?("SECRET_KEY")
  	secret_key = data["SECRET_KEY"]
    puts "Secret key found in #{file_name}."
  else
  	secret_key = SecureRandom.hex(64)
  	puts "New secret key generated."
    data['SECRET_KEY'] = secret_key
    File.open(file_name, 'w') { |f| YAML.dump(data, f) }
  end
  Rails.application.config.secret_key_base = secret_key
  ENV["SECRET_KEY"] = secret_key
end

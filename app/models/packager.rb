class Packager
  attr_accessor :primary_label

  def self.is_integer(val)
    !!(val.to_s =~ /^[-+]?[0-9]+$/)
  end

  def initialize(primary_label)
  	@primary_label = primary_label
  end
  
  def package(params, create_required, primary_label)
    #Extract the "package" representing the object in question.
    LogTime.info("Extracting package from parameters.")
	package = extract_package_from(params, create_required, primary_label)
	if !package[:success]
	  return package
	end
	
    LogTime.info("Package complete: " + package.to_s)
	return package
  end

  def extract_package_from(params, create_required, primary_label)
    package = params.clone
	if package.has_key?(:id)
	  if Packager.is_integer(package[:id])
		package["Id"] = package[:id].to_i
		package["UniqueProperty"] = nil
      else
		package["Id"] = nil
		package["UniqueProperty"] = package[:id].to_s
	  end
	else
	  package["Id"] = nil
	  package["UniqueProperty"] = nil
    end
	
	package[:CreateRequired] = create_required
	
	package.delete(:id)
	package[:success] = true
	return package
  end
end
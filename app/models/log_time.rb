class LogTime
  def self.start_clock
    if !defined? @@last_time
      this_moment = Time.now.utc
      @@last_time = this_moment.to_f
	  Rails.logger.info "LogTime clock started at " + this_moment.to_s + "."
	end
  end
  
  def self.time_stamp
    start_clock
	this_moment = Time.now.utc
    elapsed_string = '%.3f' % ((this_moment.to_f - @@last_time) * 1000)
	now_string = this_moment.strftime('%Y-%m-%d %H:%M:%S UTC')
	
	return "--" + now_string + " (elapsed " + elapsed_string + " ms)"
  end
  
  def self.debug(str)
    start_clock
    Rails.logger.debug str.ljust(100) + time_stamp
    @@last_time = Time.now.utc.to_f
  end
  
  def self.info(str)
    start_clock
    Rails.logger.info str.ljust(100) + time_stamp
    @@last_time = Time.now.utc.to_f
  end
end
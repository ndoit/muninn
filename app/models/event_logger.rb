require "active_record"
#require "mysql"

class EventLogger
  def self.log_event
    ActiveRecord::Base.connection.execute("
      CREATE TABLE Demos (
        Id int
        )
      ")
    insert_result = ActiveRecord::Base.connection.execute("
      INSERT INTO Demos (Id) VALUES (1)
      ")
    select_result = ActiveRecord::Base.connection.execute("
      SELECT * FROM Demos
      ")
    LogTime.info(select_result.to_s)
  end

  def self.regenerate
    ActiveRecord::Base.connection.execute("
      CREATE TABLE RequestLogs (
        Id int
        )
      ")
  end

end
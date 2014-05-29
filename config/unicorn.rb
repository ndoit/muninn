app_path = "/opt/biportal/muninn"

working_directory "/opt/biportal/muninn"
listen "/opt/biportal/muninn/tmp/sockets/unicorn.sock", :backlog => 64
worker_processes 2 # this should be >= nr_cpus
pid "#{app_path}/tmp/pids/unicorn.pid"
stderr_path "#{app_path}/log/unicorn.log"
stdout_path "#{app_path}/log/unicorn.log"

#!/usr/bin/env ruby
require "socket"
include Socket::Constants

MAX_CLIENT = 42
PORT = 4242

# Volcano FTP class
 
  def connect(port)
    # Prepare instance 
    if (@socket)
      puts "Serveyr already running ... \r\n"
    else
      @socket = TCPServer.new("127.0.0.1", PORT)
      @socket.listen(MAX_CLIENT)
      puts "Connexion established ......\r\n" 
    end
  end  


begin  
  if (ARGV[0] == "start")
   ftp = connect(PORT)
  end
  if (ARGV[0] == "quit")
    SystemExit
    puts "Connexion close ...\r\n"
  end
end


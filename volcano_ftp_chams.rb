#!/usr/bin/env ruby
require "socket"
include Socket::Constants

# Volcano FTP contants
BINARY_MODE = 0
ASCII_MODE = 1
MIN_PORT = 1025
MAX_PORT = 65534

# Volcano FTP class
class VolcanoFtp
  
  def initialize(port)
    # Prepare instance 
    @socket = TCPServer.new("127.0.0.1", 4242)
    @socket.listen(42)

    @pids = []
    @transfert_type = BINARY_MODE
    @tsocket = nil
    puts "Server ready to listen for clients on port #{port}"
  end

  def ftp_syst(args)
    @cs.write "215 UNIX Type: L8\r\n"
    0
  end

  def ftp_noop(args)
    @cs.write "200 Don't worry my lovely client, I'm here ;)"
    0
  end

  def ftp_502(*args)
    puts "Command not found"
    @cs.write "502 Command not implemented\r\n"
    0
  end

  def ftp_exit(args)
    @cs.write "221 Thank you for using Volcano FTP\r\n"
    -1
  end

  def ftp_quit(args)
    @cs.write "221 Thank you for using Volcano FTP\r\n"
    -1
  end
  
  def ftp_list(args)
    ls = IO.read("|-") or exec("ls -l")
    @cs.puts "#{ls}\r\n"
    @cs.write "Information of file or current directory\r\n"
    @cs.write "200 Command okay\r\n"
   # @cs.close
    0
  end
  
  def ftp_retr(args)
    if (args)
      if (File.file?(args))
        if(File.exist?(args))
          file = open("#{args}", "r")
          fileRead = file.read
          @cs.puts(fileRead)
          @cs.write "150 File status okay\r\n"
          @cs.write "226 entire file was successfully written to the server's TCP buffers\r\n"
          #  @cs.close
        else
          @cs.write "551 the server had trouble reading the file from disk.\r\n"
        end
      end
    else
      @cs.write "<<retr>> <<fichier>>\r\n"
    end
    0
  end
    
  def run
    myTab = ["pwd", "cwd", "quit", "list", "stor", "retr", "exit", "502", "noop", "syst"]
    while (42)
      selectResult = IO.select([@socket], nil, nil, 1)
      if selectResult == nil or selectResult[0].include?(@socket) == false
        @pids.each do |pid|
          if not Process.waitpid(pid, Process::WNOHANG).nil?
            ####
            # Do stuff with newly terminated processes here
            
            ####
            @pids.delete(pid)
          end
        end
        p @pids
      else
        @cs,  = @socket.accept
        peeraddr = @cs.peeraddr.dup
        @pids << Kernel.fork do
          puts "[#{Process.pid}] Instanciating connection from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          @cs.write "220-\r\n\r\n Welcome to Volcano FTP server !\r\n\r\n220 Connected\r\n"
          while not (line = @cs.gets).nil?
            line.strip! # remove non-space characters from a string. 
            if myTab.include?(line.chomp.split(' ')[0].downcase)
              puts "[#{Process.pid}] Client sent : --#{line}--"
              ####
              # Handle commands here
              puts "[#{Process.pid}] Client sent : --#{line.chomp}--"
              cmd_ = "ftp_#{line.chomp.split(' ')[0].downcase}".to_sym
              ##cmd = cmd_.to_sym
              #send :"#{cmd_}", line.chomp.split(' ')[1]
              break if not send(:"#{cmd_}", line.chomp.split(' ')[1]).zero?
              ####
            else
              @cs.write "Command --#{line.chomp}-- not found \r\n"
            end
          end
          puts "[#{Process.pid}] Killing connection from #{peeraddr[2]}:#{peeraddr[1]}"
          @cs.close
          Kernel.exit!
        end
      end
    end
  end

protected

  # Protected methods go here

end

# Main

if ARGV[0]
  begin
    ftp = VolcanoFtp.new(ARGV[1])
    ftp.run
  rescue SystemExit, Interrupt
    puts "Caught CTRL+C, exiting"
  rescue RuntimeError => e
    puts e
  end
end
#!/usr/bin/env ruby
require "socket"
require 'yaml'
include Socket::Constants

# Volcano FTP contants
BINARY_MODE = 0
ASCII_MODE = 1
MIN_PORT = 1025
MAX_PORT = 65534

# Volcano FTP class
class VolcanoFtp
  def initialize
    #file of configuration
    if(File.exists?("volcano_config.yml"))
      fileConfig = YAML.load_file('volcano_config.yml')
      if fileConfig['adr_bind'].nil? or
        fileConfig['port'].nil? or
        fileConfig['directory_root'].nil?
        puts "Error ! Parsing configuration file: volcano_config.yml"
    	  Process.exit!(true)
      end
        # Prepare instance 
        port = fileConfig['port']
        @socket = TCPServer.new("", port)
        @socket.listen(fileConfig['adr_bind'])
        
        @pids = []
        @nbr_file = 0
        @path_root = fileConfig['directory_root']
        @transfert_type = BINARY_MODE
        @tsocket = nil
        puts "Server ready to listen for clients on port #{port}"
    end
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

  def ftp_quit(args, pid)
    @cs.write "221 Thank you for using Volcano FTP\r\n"
    @cs.write "Good bye\r\n"
    #Process.kill(args, pid)
    #Process.exit!
    #@cs.shutdown(1)
    -1
  end
  
  def ftp_pwd(args)
    @cs.write "257 " + Dir.getwd + "\r\n"
    0
  end
  
  def ftp_cwd(args)
    if (args == "/")
      link = @path_root.to_s
    else
      puts link = @path_root.to_s + "/"+ args
    end
    if Dir.exist?(link)
      Dir.chdir(link)
      @cs.write "200 dir changed \r\n"
    else
      @cs.write "550 Failed to change dir.\r\n"
    end
    0
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
  
  def     ftp_stor(args)
    
    if (!@socket)
      @cs.write "425 No connection TCP was established\r\n"
    end

    if (args)
      if(File.file?(args) and File.exist?(args))
        file = File.open(args,"r")
        content = file.read
        file = File.new("#{args}", "w")
        if !file.write("#{content}")
          @cs.write "451, 452, or 552 The server had trouble saving the file to disk"
        else
          @cs.write "226 the entire file was successfully received and stored\r\n"
          @nbr_file += 1
        end
      else
        file = File.new("#{args}", "w")
        @cs.write "226 the entire file was successfully received and stored\r\n"
      end

    else
      @cs.write "451, 452, or 552 file doesn't exist\r\n"
    end
    0
  end
  
  def ftp_log (args)
    File.open('volcano_log.yml', 'a+'){ |out|
      out.puts args.to_yaml
    }
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
          date = DateTime.now
          puts "[#{Process.pid}] " << date.to_s << " Instanciating connecting from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          log = {'pid' => Process.pid, 'date' => date.to_s, 'ip' => @cs.peeraddr[2], 'port' => @cs.peeraddr[1], 'status' => 'connecting', 'nb_file' => @nbr_file}
          ftp_log(log)
          while not (line = @cs.gets).nil?
            line.strip! # remove non-space characters from a string. 
            if myTab.include?(line.chomp.split(' ')[0].downcase)
              #puts "[#{Process.pid}] Client sent : --#{line}--"
              ####
              # Handle commands here
              puts "[#{Process.pid}] Client sent : --#{line.chomp}--"
              cmd_ = "ftp_#{line.chomp.split(' ')[0].downcase}".to_sym
              ##cmd = cmd_.to_sym
              #send :"#{cmd_}", line.chomp.split(' ')[1]
              if line.chomp.split(' ')[0].downcase == "quit"
                ftp_quit("HUP", Process.pid)
                break
              else
                #send(:"#{cmd_}", line.chomp.split(' ')[1])
               break if not send(:"#{cmd_}", line.chomp.split(' ')[1]).zero?
             end
              ####
            else
              @cs.write "Command --#{line.chomp}-- not found \r\n"
            end
          end
          puts "[#{Process.pid}] Killing connection from #{peeraddr[2]}:#{peeraddr[1]}"
          date = DateTime.now
          puts "[#{Process.pid}] " << date.to_s << " Killing connection from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          log = {'pid' => Process.pid, 'date' => date.to_s, 'ip' => @cs.peeraddr[2], 'port' => @cs.peeraddr[1], 'status' => 'killing', 'nb_file' => @nbr_file}
          @cs.shutdown(1)
          ftp_log(log)
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

#if ARGV[0]
  begin
    ftp = VolcanoFtp.new
    ftp.run
  rescue SystemExit, Interrupt
    puts "Caught CTRL+C, exiting"
  rescue RuntimeError => e
    puts e
  end
  #end
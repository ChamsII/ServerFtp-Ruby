#!/usr/bin/env ruby
require "socket"
require 'net/ftp'
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
        #@path_root = fileConfig['directory_root']
        File.stat(@absolute_path = File.absolute_path('volcano_config.yml'));
        @path_root = File.dirname(@absolute_path)
        #puts"#{@path_root}"
        @transfert_type = BINARY_MODE
        @tsocket = nil
        write_statut(fileConfig, Process.pid)
        #@config = {:root => fileConfig['directory_root']}
        puts "Server ready to listen for clients on port #{port}"
    end
  end
  
  def write_statut(fileConfig, pid)
    fileConfig['pid'] = pid
    File.open('volcano_config.yml', 'w'){ |out|
      out.puts fileConfig.to_yaml
    }
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
    @cs.write "502 Command not implemented\r\n"
    0
  end

  def ftp_501(*args)
    @cs.write "502\r\n"
    0
  end
  
  def ftp_exit(args)
    @cs.write "221 Thank you for using Volcano FTP\r\n"
    -1
  end

  def ftp_quit(args)
    @cs.write "221 Thank you for using Volcano FTP\r\n"
    @cs.write "426 Good bye\r\n"
    -1
  end
  
  def ftp_pwd(args)
    #@cs.write "#{@path_root}"
    @cs.write "257 '"+ @path_root + "' \r\n"
    0
  end
  
  def ftp_cwd(args)
    if (args.nil?)
      ftp_argnil(args)
    else
      begin
        Dir.chdir(args)
        @cs.write "200 dir changed to #{Dir.pwd} \r\n"
      rescue
        @cs.write "550 Failed to change dir to #{args} \r\n"
      end
      0
    end
  end  

  
  def ftp_list(args)
    if(!args.nil?)
      viewrep = File.absolute_path(args)
    end
     if (args.nil? || File.exist?(args))
      if (args.nil? || @path_root == viewrep[0,@path_root.size])
        list = IO.read("|-") or exec("ls -l #{args}")
        @cs.write "125 data channel open, start tranfer\r\n"
        @cs.puts "#{list}\n"  #/!\ doit etre sur le canal de donnÃ©
        @cs.write "150 transfer finished\r\n"
      else
        @cs.write "550 Failed to list directory #{args} : permission denied\r\n"
      end
    else
        @cs.write "550 Failed to list directory #{args} : file don't exist\r\n"
    end
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
        else
          @cs.write "551 the server had trouble reading the file from disk.\r\n"
        end
      end
    else
      @cs.write "501 <<retr>> <<fichier>>\r\n"
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
          @cs.write "552 The server had trouble saving the file to disk"
        else
          @cs.write "226 the entire file was successfully received and stored\r\n"
          @nbr_file += 1
        end
      else
        file = File.new("#{args}", "w")
        @cs.write "226 the entire file was successfully received and stored\r\n"
      end
    else
      @cs.write "451 file doesn't exist\r\n"
    end
    0
  end
  
  def ftp_log (args)
    File.open('volcano_log.yml', 'a+'){ |out|
      out.puts args.to_yaml
    }
  end
    
  def ftp_user(args)
      @cs.write "331 User name ok\r\n"
      0
  end
  
  def ftp_pass(args)
      @cs.write "230 User logged in\r\n"
      0
  end
  
  def ftp_mode(args)
     if (args != "S")
       @cs.write "550 mode not suported\r\n"
     else
       @cs.write "200 Ok stream mode suported\r\n"
     end
     0
   end
  
  def run
    myTab = ["pwd", "cwd", "quit", "list", "stor", "retr", "exit", "noop", "syst", "user", "pass", "mode", "put", "get"]
    thread = 0
    while (42)
      selectResult = IO.select([@socket], nil, nil, 1)
      if selectResult == nil or selectResult[0].include?(@socket) == false
        @pids.each do |pid|
          #if not Process.waitpid(pid, Process::WNOHANG).nil?
          if not pid.alive?
		        puts pid.inspect
            ####
            # Do stuff with newly terminated processes here
            ####
            @pids.delete(pid)
          end
        end
        if @pids.count != thread
          puts "Number of people connected : #{thread}"
          thread = @pids.count
          p @pids
        end
      else
          @cs,  = @socket.accept
          peeraddr = @cs.peeraddr.dup
          @pids << Thread.new {
          puts "[#{Process.pid}] Instanciating connection from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          @cs.write "220-\r\n\r\n  ---- Welcome to Volcano FTP server ------ !\r\n\r\n220 Connected\r\n"
          date = DateTime.now
          puts "[#{Process.pid}] " << date.to_s << " Instanciating connecting from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          log = {'pid' => Process.pid, 'date' => date.to_s, 'ip' => @cs.peeraddr[2], 'port' => @cs.peeraddr[1], 'status' => 'connecting', 'nb_file' => @nbr_file}
          ftp_log(log)
          Thread.current["pwd"] = @path_root
         # Dir.chdir(@path_root)
          while not (line = @cs.gets).nil?
            line.strip! # remove non-space characters from a string. 
            if myTab.include?(line.chomp.split(' ')[0].downcase)
              puts "[#{Process.pid}] Client sent : -- #{line.chomp} --"
              cmd_ = "ftp_#{line.chomp.split(' ')[0].downcase}".to_sym
              break if send(:"#{cmd_}", line.chomp.split(' ')[1]) < 0
             else
              ftp_501(nil)
            end
          end
          puts "[#{Process.pid}] Killing connection from #{peeraddr[2]}:#{peeraddr[1]}"
          date = DateTime.now
          puts "[#{Process.pid}] " << date.to_s << " Killing connection from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          log = {'pid' => Process.pid, 'date' => date.to_s, 'ip' => @cs.peeraddr[2], 'port' => @cs.peeraddr[1], 'status' => 'killing', 'nb_file' => @nbr_file}
          @cs.shutdown(1)
          ftp_log(log)
          @cs.close
        }
      end
    end
  end

protected

  # Protected methods go here

end

def get_etat()
  if(File.exists?("volcano_config.yml"))
    config = YAML.load_file('volcano_config.yml')
    return config['pid']
  else
    puts "Error ! Parsing configuration file: volcano_config.yml"
    Process.exit!(true)
  end
end

def write_quit()
  config = YAML.load_file('volcano_config.yml')
  config['pid'] = "nil"
  File.open('volcano_config.yml', 'w'){ |out|
    out.puts config.to_yaml
  }
  0
end

def start_ftp(etat)
 if (etat == "nil")
    begin
      ftp = VolcanoFtp.new
      ftp.run
    rescue SystemExit, Interrupt
      puts "Caught CTRL+C, exiting"
    rescue RuntimeError => e
      puts e
    end
  else
   puts "Serveur already running \r\n"
 end
end

def quit_ftp(etat)
  if (etat == "nil")
    puts "serveur already close \r\n"
  else
    begin
      write_quit()
      Process.kill(9, etat)    #Process.kill("HUP", etat)
      SystemExit
      puts "Connexion close ...\r\n"
    rescue Errno::ESRCH
      puts "Connexion close ...\r\n"
    end
  end
end

def restart_ftp(etat)
  if (etat == "nil")
    puts "Server not started yet \r\n"
  else
    quit_ftp(etat)
    etat = get_etat()
    puts "Restart server \r\n"
    start_ftp(etat)
  end
end
# Main

if ARGV[0]
  begin
    etat = get_etat()
    case ARGV[0]
    when "start"
      start_ftp(etat)
    when "quit"
      quit_ftp(etat)
    when "restart"
      restart_ftp(etat)
    else
      puts "Usage : ./volcano_ftp start|quit|restart"
    end
  rescue SystemExit, Interrupt
    puts "Caught CTRL+C, exiting"
  rescue RuntimeError => e
    puts e
  end
else
  puts "Usage : ./volcano_ftp start|quit|restart"
end
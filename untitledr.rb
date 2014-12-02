#!/usr/bin/env ruby
require "socket"
require "yaml"
include Socket::Constants

# Volcano FTP contants
BINARY_MODE = 0
ASCII_MODE = 1
MIN_PORT = 1025
MAX_PORT = 65534

# Volcano FTP class
class VolcanoFtp
  def initialize
    # Prepare instance
	confFileName = "volcano_config.yml"
	confFile = YAML.load_file(confFileName)
	if confFile['port'].nil? or
	   confFile['adr_bind'].nil? or
	   confFile['directory_root'].nil?
		parse_error(confFileName)
	end
	port = confFile['port']
	@socket = TCPServer.new("", port)
    @socket.listen(42)

    @pids = []
    @transfert_type = BINARY_MODE
    @tsocket = nil
	  @rootPath = "/"
	  @config = {:root => confFile['root_directory']}
    puts "Server ready to listen for clients on port #{port}"
  end
  
  def manage_commands(line)
    cmd = line.split(' ')
	case cmd[0]
		when "PWD"
			self.ftp_pwd
		when "CWD"
			puts line
			@cs.write "250 Requested file action okay, completed\r\n"
		when "QUIT"
			self.ftp_exit(nil)
			return 0
		when "LIST"
			self.ftp_list(Dir.pwd)
		when "STOR"
			puts line
		when "RETR"
			puts line
		when "USER"
		    @cs.write "331 User name ok\r\n"
	    when "PASS"
		    @cs.write "230 User logged in\r\n"
		when "SYST"
		    self.ftp_syst(nil)
		when "PORT"
		    self.ftp_port(cmd[1])
		when "TYPE"
		    puts "Type: #{cmd[1]}"
			@cs.write "200 Command OK\r\n"
		else
			self.ftp_502(nil)
	end
	1
  end

  def ftp_syst(args)
    @cs.write "215 UNIX Type: L8\r\n"
    0
  end

  def ftp_noop(args)
    @cs.write "200 Don't worry my lovely client, I'm here ;) \r\n"
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
  
  def ftp_list(dir = '.')
	open_data_transfer do |data_socket|
	    puts "toto011"
		list = Thread.current[:cwd].get_list
		puts "toto02"
		data_socket.puts("----" + Thread.current[:cwd].ftp_name + "----")
		puts "toto03"
		list.each {|file| data_socket.puts(file.ftp_size.to_s + "\t" + file.ftp_name + "\r\n");puts file.ftp_name }
		data_socket.puts("----" + Thread.current[:cwd].ftp_name + "----")
	end
	Thread.current[:data_socket].close if Thread.current[:data_socket]
	Thread.current[:data_socket] = nil

	@cs.write "200 OK\r\n"
    0
  end
  
  def ftp_pwd
    @cs.write "257 '" + @rootPath + "' Root path\r\n"
    0
  end
  
  def ftp_port(str)
    ap = str.split(",")
	ipAddress = ap[0]+'.'+ap[1]+'.'+ap[2]+'.'+ap[3]
	port = ap[4].to_i() * 256 + ap[5].to_i()
	puts "Created data socket to #{ipAddress}:#{port}"
	if Thread.current[:data_socket]
		Thread.current[:data_socket].close
		Thread.current[:data_socket] = nil
	end
	Thread.current[:data_socket] = TCPSocket.new(ipAddress, port)
	Thread.current[:passive] = false
	@cs.write "200 Command OK\r\n"
    0
  end
  
  def parse_error(fileName)
    puts "Error parsing configuration file: #{fileName}"
	Process.exit!(true)
  end

  def run																		#  SERVER-PI  #
    pidCount = 0
    while (42)
      selectResult = IO.select([@socket], nil, nil, 1)
      if selectResult == nil or selectResult[0].include?(@socket) == false
        @pids.each do |pid|
          if not pid.alive?
		    puts pid.inspect
            ####
            # Do stuff with newly terminated processes here
            ####
			@pids.delete(pid)
          end
        end
		if @pids.count != pidCount
			pidCount = @pids.count
			p @pids
		end
      else
        @cs,  = @socket.accept
        peeraddr = @cs.peeraddr.dup
        @pids << Thread.new {
          puts "[#{Process.pid}] Instanciating connection from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          @cs.write "220-\r\n\r\n Welcome to Volcano FTP server !\r\n\r\n220 Connected\r\n"
		  Thread.current[:cwd] = @config[:root]
          while not (line = @cs.gets).nil?
		    line.strip!
            puts "[#{Process.pid}] Client sent : --#{line}--"
			break if manage_commands(line).zero?
          end
          puts "[#{Process.pid}] Killing connection from #{peeraddr[2]}:#{peeraddr[1]}"
          @cs.close
        }
      end
    end
  end

protected

  # Protected methods go here
  
  	def open_data_transfer(&block)
		client_socket = nil
		if (Thread.current[:passive])
			client_socket = Thread.current[:data_socket].accept
			@cs.write "150 File status OK\r\n"
		else
			client_socket = Thread.current[:data_socket]
			@cs.write "125 File status OK\r\n"
		end
		
		yield(client_socket)
		puts "ok!"
		return true
		ensure
			client_socket.close if client_socket && Thread.current[:passive]
			client_socket = nil    
	end

end

class RootPath
	attr_reader :ftp_name, :ftp_size, :ftp_dir

	def initialize(path)
		@path = path
		#@ftp_name = path.split('/').last
		@ftp_name = '/'# unless @ftp_name
		@ftp_dir = File.directory?(path)
		@ftp_size = File.size?(path)
		@ftp_size = 0 unless @ftp_size
	end
	
	def create_file(name, dir = false)
		if dir
		begin
			Dir.mkdir(@path + '/' + name)
			return RootPath.new(@path + '/' + name)
		rescue
			return false
		end
		else
		RootPath.new(@path + '/' + name)
		end
	end

	def get_list
	    puts "get_list"
		output = Array.new
		Dir.entries(@path).sort.each do |file|          
			output << RootPath.new(@path + (@path == '/'? '': '/') + file)
		end
		puts output
		return output
	end
	
	def get_parent
		path = @path.split('/')
		return nil unless path.pop
		return nil if path.size <= 1
		return RootPath.new(path.join('/'))
	end

	def retrieve_file(output)
		output << File.new(@path, 'r').read
	end
  
	def store_file(input)
		return false unless File.open(@path, 'w') do |f|
			f.write input.read
		end
		@ftp_size = File.size?(@path)
	end
end

# Main

begin
	puts "Starting Volcano FTP!"
	ftp = VolcanoFtp.new
	ftp.run
rescue SystemExit, Interrupt
	puts "Caught CTRL+C, exiting"
rescue RuntimeError => e
	puts e
end
require 'nokogiri'
require 'terminal-table'


	rows = []
	rows << ['event','timestamp','module','other','userName']
	Dir.glob("*/events.xml") do |file|
		@doc = Nokogiri::XML(File.open(File.expand_path(file)))
		events = @doc.xpath("//event")
		@userId = ARGV[0]
		@userName = "no Data found"
		events.each do |event|
        		@module = event.xpath('@module')[0]
			@timestamp = event.xpath('@timestamp')[0]
			@eventName = event.xpath('@eventname')[0]
			if !@module.to_s.eql?"CHAT"
			@userId = event.xpath('//userId')[0].content
			@userName = event.xpath("//name")[0].content
			
        			if @userId == ARGV[0]
					#puts "event:"
                			#puts "-----\n"
                			#puts "userId: " + @userId
                			#puts "user_name: " + @userName
                			#puts "timestamp: " + event.xpath('@timestamp')[0]
                			#puts "event name: " + event.xpath('@eventname')[0]
                			#puts "module: " + @module
                			#puts
					rows << [@eventName,@timestamp,@module,"----",@userId]
        			end
			else
				@senderId = event.xpath('//senderId')[0].content
				if @senderId == ARGV[0]
					@msg = event.xpath('//message')[0].content.to_s.strip
					rows << [@eventName,@timestamp,@module, @msg, @senderId]
				end
			end
		end
	end
 	
	table = Terminal::Table.new :title => "info in database", :headings =>["id: " + @userId,"name: " +  @userName], :rows => rows
        puts table


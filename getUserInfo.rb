#!/usr/bin/ruby

require "nokogiri"
require "csv"

def getUserInfo(userId, dirId)
  # Initalise an empty row array
  CSV.open("info.csv", "wb") do |csv|
    # Search in all directories for a file of name events.xml
    if userId.nil?
      puts "You did not not specify an id, please provide an id as an argument before you run this script" +
             exit
    end

    csv << ["info in database for user with ID(" + userId + ")"]
    # fill up the headings
    csv << ["event", "timestamp", "module", "Msg (if applicable)"]

    Dir.glob(dirId + "/events.xml") do |file|
      # Open the file using Nokogiri
      doc = Nokogiri::XML(File.open(File.expand_path(file)))
      events = doc.xpath("//event")
      userid = userId
      events.each do |event|
        _module = event.at_xpath("@module")
        timestamp = event.at_xpath("@timestamp").to_s
        eventName = event.at_xpath("@eventname")
        next if ["PRESENTATION", "WHITEBOARD"].include? _module.to_s
        if ["VOICE"].include? _module.to_s
          participanId = event.at_xpath("participant")
          next if participanId.nil?
          if participanId.content == userId
            csv << [eventName, timestamp, _module]
          end
        elsif _module.to_s.eql? "CHAT"
          senderId = event.at_xpath("senderId")
          next if senderId.nil?
          if senderId.content == userId
            msg = event.at_xpath("message").content.to_s.strip
            csv << [eventName, timestamp, _module, msg]
          end
        elsif ["StopWebcamShareEvent", "StartWebcamShareEvent"].include? eventName.to_s
          if event.at_xpath("stream").content.to_s.include? userId
            csv << [eventName, timestamp, _module, ""]
          end
        else
          userid = event.at_xpath("userId")
          if userid.nil?
            userid = event.at_xpath("userid")
            next if userid.nil?
          end
          if userid.content == userId
            csv << [eventName, timestamp, _module]
          end
        end
      end
    end
  end
  puts "user info's have been generated and inserted to info.csv file.\nPath: " + Dir.pwd + "/info.csv"
end

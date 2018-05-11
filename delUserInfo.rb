#!/usr/bin/ruby

require "nokogiri"
require "csv"
require "fileutils"
require "terminal-table"

$startSpeaking = 0
$removalList = []
$audioFile
$rows = []

def delUserInfo(userid, dirId)
  if userid.nil?
    puts "You did not specify an id, please provide an id as an argument before you run this script"
    exit
  end

  recordingStart = 0
  meetingEnd = 0
  $rows << ["event", "userId", "module", "removed", "start", "end"]

  Dir.glob(dirId + "/events.xml") do |file|
    doc = Nokogiri::XML(File.open(File.expand_path(file)))
    events = doc.xpath("//event")
    meetingEnd = Integer(events.last.at_xpath("@timestamp").to_s)
    directory = File.dirname(File.absolute_path(file))
    events.each do |event|
      eventname = event.at_xpath("@eventname")
      if event.at_xpath("@eventname").content.to_s.eql? "StartRecordingEvent"
        recordingStart = Integer(event.at_xpath("recordingTimestamp").content.to_s)
      elsif event.at_xpath("@eventname").content.to_s.eql? "ParticipantJoinEvent"
        if getUserId(event) == userid
          $startSpeaking = (Integer(event.at_xpath("@timestamp").to_s) - recordingStart) / 1000
          removeEvent(event)
        end
      elsif ["ParticipantMutedEvent", "ParticipantTalkingEvent", "ParticipantJoinedEvent"].include? eventname.to_s
        participant = event.at_xpath("participant")
        if participant.content == userid
          if eventname.to_s.eql? "ParticipantJoinedEvent"
            removeEvent(event)
          elsif eventname.to_s.eql? "ParticipantMutedEvent"
            removeParticipantMutedEvent(event, directory, recordingStart)
          elsif eventname.to_s.eql? "ParticipantTalkingEvent"
            removeParticipantTalkingEvent(event, directory, recordingStart)
          else
            puts "undetected event" + event
          end
        end
      elsif ["StopWebcamShareEvent", "StartWebcamShareEvent"].include? eventname.to_s
        if event.at_xpath("stream").content.to_s.include? userid
          removeEvent(event)
        end
      else
        if getUserId(event) == userid
          removeEvent(event)
        end
      end
    end
    File.open(File.expand_path(file), "w") { |f| doc.write_xml_to f }
  end
  puts "All events concerning user with Id: " + userid + " have been removed."
  table = Terminal::Table.new :title => "information deleted", :headings => ["id: " + userid], :rows => $rows
  puts table
  removeAudio(meetingEnd - recordingStart)
end

def getUserId(event)
  userId = event.at_xpath("userId")
  if userId.nil?
    userId = event.at_xpath("userid")
  end
  if userId.nil?
    userId = event.at_xpath("participant")
  end
  if userId.nil?
    userId = event.at_xpath("senderId")
  end
  if userId.nil?
    return "unknown"
  else
    return userId.content.to_s
  end
end

def removeEvent(event)
  event.remove
  _module = event.at_xpath("@module")
  userID = getUserId(event)
  eventName = event.at_xpath("@eventname")
  return if ["WHITEBOARD"].include? _module.to_s
  $rows << [eventName, userID, _module, "XXXXX", "", ""]
end

def true?(obj)
  obj.to_s == "true"
end

def removeParticipantMutedEvent(event, directory, recordingStart)
  if !true?(event.at_xpath("muted").content.to_s)
    return
  end
  timestamp = (Integer(event.at_xpath("@timestamp").to_s) - recordingStart) / 1000
  eventName = event.at_xpath("@eventname")
  _module = event.at_xpath("@module")
  userID = getUserId(event)
  Dir.glob(directory + "/audio/*.opus") do |audioFile|
    puts "requested audio removal form file: " + audioFile + ", between[" + Time.at($startSpeaking).utc.strftime("%H:%M:%S").to_s + "," + Time.at(timestamp).utc.strftime("%H:%M:%S").to_s + "]"
    $audioFile = audioFile
    $removalList.push(make_audioRemovalRequest($startSpeaking.to_s, timestamp.to_s))
  end
  $rows << [eventName, userID, _module, "XXXXX", Time.at($startSpeaking).utc.strftime("%H:%M:%S").to_s, Time.at(timestamp).utc.strftime("%H:%M:%S").to_s]
  $startSpeaking = timestamp
  removeAudioEvent(event)
end

def removeParticipantTalkingEvent(event, directory, recordingStart)
  talking = event.at_xpath("talking").content
  timestamp = (Integer(event.at_xpath("@timestamp").to_s) - recordingStart) / 1000
  eventName = event.at_xpath("@eventname")
  _module = event.at_xpath("@module")
  userID = getUserId(event)
  if true?(talking)
    $startSpeaking = timestamp
  else
    Dir.glob(directory + "/audio/*.opus") do |audioFile|
      puts "requested audio removal form file: " + audioFile + ", between[" + Time.at($startSpeaking).utc.strftime("%H:%M:%S").to_s + "," + Time.at(timestamp).utc.strftime("%H:%M:%S").to_s + "]"
      $audioFile = audioFile
      $removalList.push(make_audioRemovalRequest($startSpeaking.to_s, timestamp.to_s))
    end
  end
  $rows << [eventName, userID, _module, "XXXXX", Time.at($startSpeaking).utc.strftime("%H:%M:%S").to_s, Time.at(timestamp).utc.strftime("%H:%M:%S").to_s]
  $startSpeaking = timestamp
  removeAudioEvent(event)
end

def removeAudioEvent(event)
  event.remove
end

def make_audioRemovalRequest(start, finish)
  {:start => start, :finish => finish}
end

def removeAudio(meetingDuration)
  if ($audioFile.nil?) || ($removalList.nil?)
    puts "No audio has been removed"
    return
  end
  totalTime = 0
  command = ["ffmpeg", "-i", $audioFile, "-af"]
  filter = "volume=volume=0:enable='"

  loop do
    filter += "between(t\\," + $removalList.first[:start] + "\\," + $removalList.first[:finish] + ")"
    totalTime += Integer($removalList.first[:finish]) - Integer($removalList.first[:start])
    $removalList.shift
    if $removalList.empty?
      break
    end
    filter += "+"
  end
  filter += "'"

  command << filter

  command << "-y"
  command << "temp.wav"
  system(*command)
  FileUtils.mv "temp.wav", $audioFile
  puts "All audio recordings have been removed"
  puts "Recording total time: " + Time.at(meetingDuration / 1000).utc.strftime("%H:%M:%S").to_s + " in seconds."
  puts "Total time muted: " + Time.at(totalTime).utc.strftime("%H:%M:%S").to_s + " in seconds."
end

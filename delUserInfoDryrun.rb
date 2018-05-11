#!/usr/bin/ruby

require 'nokogiri'
require 'csv'
require 'fileutils'
require 'terminal-table'

$startSpeaking = 0
$removalList = []
$audioFile
$meetingStart
$start_speaking

def delUserInfoDryrun(userid, dir_id)
  if userid.nil?
    puts 'You did not specify an id.'
    puts 'Please provide an id as an argument before you run this script'
    exit
  end
  recording_start = 0
  meeting_end = 0
  $start_speaking = 0
  rows = []
  rows << %w[event userId module removed start end]

  Dir.glob("#{dir_id}/events.xml") do |file|
    doc = Nokogiri::XML(File.open(File.expand_path(file)))
    events = doc.xpath('//event')
    meeting_end = Integer(events.last.at_xpath('@timestamp').to_s)
    directory = File.dirname(File.absolute_path(file))
    events.each do |event|
      next if %w[PRESENTATION WHITEBOARD].include? event.at_xpath('@module').to_s
      e_name = event.at_xpath('@eventname').to_s
      if e_name.eql? 'StartRecordingEvent'
        recording_start = Integer(event.at_xpath('recordingTimestamp').content.to_s)
      end
      unless user?(event, userid)
        display_event_dry(event, rows, '')
        next
      end
      if e_name.eql? 'ParticipantJoinEvent'
        e_stamp = event.at_xpath('@timestamp').to_s
        $start_speaking = (Integer(e_stamp) - recording_start)
      end
      remove_event_dry(event, rows, directory, recording_start)
    end
    File.open(File.expand_path(file), 'w') { |f| doc.write_xml_to f }
  end
  puts "Dry run of data concerning user with Id: #{userid}"
  table = Terminal::Table.new title: 'Info', headings: ["id: #{userid}"], rows: rows
  puts table
  remove_audio_dry(meeting_end - recording_start)
end

def display_event_dry(event, rows, delete, start = '', finish = '')
  e_name = event.at_xpath('@eventname')
  e_module = event.at_xpath('@module')
  rows << [e_name, get_uid(event), e_module, delete, start, finish]
end

def remove_event_dry(event, rows, directory, r_start)
  e_module = event.at_xpath('@module')
  e_name = event.at_xpath('@eventname').to_s
  if e_name.eql? "ParticipantMutedEvent"
    return removeParticipantMutedEventDry(event, rows, directory, r_start) 
  elsif e_name.eql? "ParticipantTalkingEvent"
    return removeParticipantTalkingEventDry(event, rows, directory, r_start)
  elsif e_name.eql? "ParticipantJoinEvent"
   return display_event_dry(event, rows, 'X', start = 'user joined at: ', f_time($start_speaking))
  end
  display_event_dry(event, rows, 'X')
end

def user?(event, user_id)
  e_name = event.at_xpath('@eventname').to_s
  if %w[StopWebcamShareEvent StartWebcamShareEvent].include? e_name
    e_stream = event.at_xpath('stream').content.to_s
    return e_stream.include? user_id
  end
  get_uid(event) == user_id
end

def get_uid(event)
  userid = event.at_xpath('userId')
  userid.nil? && userid = event.at_xpath('userid')
  userid.nil? && userid = event.at_xpath('senderId')
  userid.nil? && userid = event.at_xpath('participant')
  userid.nil? ? 'unkown' : userid.content
end

def true?(obj)
  obj.to_s == 'true'
end

def removeParticipantMutedEventDry(event, rows, directory, recording_start)
  !true?(event.at_xpath('muted').content.to_s) && return
  t_stamp = (Integer(event.at_xpath('@timestamp').to_s) - recording_start)
  Dir.glob("#{directory}/audio/*.opus") do |audioFile|
    puts "req -r audio: [#{f_time($start_speaking)}, #{f_time(t_stamp)}]"
    $audioFile = audioFile
    $removalList.push(make_audio_removal_request($start_speaking.to_s, t_stamp.to_s))
  end
  display_event_dry(event, rows, 'X', f_time($start_speaking), f_time(t_stamp))
  $start_speaking = t_stamp
end

def removeParticipantTalkingEventDry(event, rows, directory, recording_start)
  t_stamp = (Integer(event.at_xpath('@timestamp').to_s) - recording_start)
  if true?(event.at_xpath('talking').content)
    $start_speaking = t_stamp
    display_event_dry(event, rows, 'X', 'start:', f_time($start_speaking))
  else
    Dir.glob("#{directory}/audio/*.opus") do |audiofile|
      puts "req -r audio: [#{f_time($start_speaking)}, #{f_time(t_stamp)}]"
      $audioFile = audiofile
      $removalList.push(make_audio_removal_request($start_speaking.to_s, t_stamp.to_s))
    end
    display_event_dry(event, rows, 'X', f_time($start_speaking), f_time(t_stamp))
    $start_speaking = t_stamp
  end
end

def make_audio_removal_request(start, finish)
  { start: start, finish: finish }
end

def remove_audio_dry(meetingDuration)
  if $audioFile.nil? || $removalList.nil?
    puts 'No audio has been removed'
    return
  end
  total_time = 0
  command = ['ffmpeg', '-i', $audioFile, '-af']
  filter = "volume=volume=0:enable='"

  loop do
    filter += 'between(t\\,' + $removalList.first[:start]
    filter += '\\,' + $removalList.first[:finish] + ')'
    total_time += Integer($removalList.first[:finish]) - Integer($removalList.first[:start])
    $removalList.shift
    $removalList.empty? && break
    filter += '+'
  end
  filter += "'"

  command << filter
  command << '-y'
  command << 'temp.wav'

  # system(*command)
  # FileUtils.mv "temp.wav", $audioFile
  puts "command that was going to run: \n#{command.join(' ')}"
  puts "Recording total time: #{f_time(meetingDuration)} ."
  puts "Total time that was going to be muted: #{f_time(total_time)} ."
end

def f_time(time)
  Time.at(time / 1000).utc.strftime('%H:%M:%S')
end

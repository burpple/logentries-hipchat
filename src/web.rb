require 'sinatra'
require 'cgi'

api_token = ENV['HIPCHAT_TOKEN']
client = HipChat::Client.new(api_token)
room_id = ENV['HIPCHAT_ROOM_ID']
username = 'Logentries'

get '/' do
  puts "Hello World!"
  client[room_id].send(username, 'Hello!')
  "Hello World!"
end

post '/alert' do
  puts params
  payload = JSON.parse(params[:payload])
  puts payload
  alert_name = payload['alert']['name']
  if alert_name == "Scale Dynos"
    message = payload['event']['m']
    message = message.sub(/.*Scale/, 'Scale')
    message = message.split('by').collect(&:strip)
    message = "<b>#{CGI.escapeHTML(message.first)}</b> by <b>#{CGI.escapeHTML(message.last)}</b>"
    puts message
    client[room_id].send("Logentries", message, color: 'purple', notify: 1)
  elsif alert_name.start_with? "GET request"
    # do nothing. simply a ping to keep heroku dyno alive.
    puts "#{alert_name} received!"
  else
    message = "%s: %s" % [payload['alert']['name'], payload['event']['m']]
    puts message
    client[room_id].send(username, message, color: 'red', notify: 1)
  end
end

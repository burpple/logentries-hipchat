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
    message = CGI.escapeHTML("<b>#{message.first}</b> by <b>#{message.last}</b>")
    puts message
    client[room_id].send("Logentries/Heroku", message, color: 'purple', notify: 1)
  else
    message = "%s: %s" % [payload['alert']['name'], payload['event']['m']]
    puts message
    client[room_id].send(username, message, color: 'red', notify: 1)
  end
end

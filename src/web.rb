require 'sinatra'
require 'cgi'
require 'redis'
require 'uri'

api_token = ENV['HIPCHAT_TOKEN']
client = HipChat::Client.new(api_token)
room_id = ENV['HIPCHAT_ROOM_ID']
username = 'Logentries'
uri = URI.parse(ENV['REDISTOGO_URL']) rescue nil
REDIS = uri ? Redis.new(:host => uri.host, :port => uri.port, :password => uri.password) : Redis.new

get '/' do
  puts "Hello World!"
  client[room_id].send(username, 'Hello!')
  "Hello World!"
end

post '/alert' do
  # puts params
  payload = JSON.parse(params[:payload])
  alert_name = payload['alert']['name']
  if alert_name == "Scale Dynos"
    message = payload['event']['m']
    message = message.sub(/.*Scale/, 'Scale')
    message = message.split('by').collect(&:strip)

    prev_web     = REDIS.get("web_dynos").to_i
    prev_workers = REDIS.get("worker_dynos").to_i
    web     = message.first.scan(/(?<=web=)\d/).first.to_i
    workers = message.first.scan(/(?<=worker=)\d/).first.to_i
    
    notif_message = "<b>#{CGI.escapeHTML(message.first)}</b> by <b>#{CGI.escapeHTML(message.last)}</b>"
    notify = false
    if prev_web == web and prev_workers == workers
      # no change, don't notify
      puts "Scale alert received, but ignoring due to no change."
    elsif prev_web == web
      # scaled worker
      worker_alert_threshold = 4 # notify if exceed this
      worker_cooldown_threshold = 1 # notify if go below this
      if prev_workers < worker_alert_threshold and workers >= worker_alert_threshold
        notif_message += " (Workers exceeded threshold of <b>#{worker_alert_threshold}</b>)"
        notify = true
      elsif prev_workers > worker_cooldown_threshold and workers <= worker_cooldown_threshold
        notif_message += " (Workers below cooldown threshold of <b>#{worker_cooldown_threshold}</b>)"
        notify = true
      end
    elsif prev_workers == workers
      # scaled web
      notify = true
    end
    REDIS.set "web_dynos", web
    REDIS.set "worker_dynos", workers
    if notify
      puts notif_message
      client[room_id].send("Logentries", notif_message, color: 'purple', notify: 1)
    end
      
  elsif alert_name.start_with? "GET request"
    # do nothing. simply a ping to keep heroku dyno alive.
    puts "#{alert_name} received!"
  else
    puts payload
    message = "%s: %s" % [payload['alert']['name'], payload['event']['m']]
    puts message
    client[room_id].send(username, message, color: 'red', notify: 1)
  end
end

require 'sinatra'
require 'cgi'
require 'redis'

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
    
    notif_message = ""
    if prev_web == web and prev_workers == workers
      # no change, don't notify
      puts "Scale alert received, but ignoring due to no change."
    elsif prev_web == web
      # scaled worker
      worker_alert_threshold = 4 # notify if exceed this
      worker_cooldown_threshold = 1 # notify if go below this
      if prev_workers < worker_alert_threshold and workers >= worker_alert_threshold
        notif_message = "Workers exceeded threshold, now #{worker_alert_threshold}"
      elsif prev_workers > worker_cooldown_threshold and workers <= worker_cooldown_threshold
        notif_message = "Workers back below cooldown threshold, now #{worker_cooldown_threshold}"
      end
    elsif prev_workers == workers
      # scaled web
      notif_message = "<b>#{CGI.escapeHTML(message.first)}</b> by <b>#{CGI.escapeHTML(message.last)}</b>"
    end
    REDIS.set "web_dynos", web
    REDIS.set "worker_dynos", workers
    if notif_message != ""
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

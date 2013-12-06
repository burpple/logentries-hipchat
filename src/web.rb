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
    scaled_by = message.last

    prev_web     = REDIS.get("web_dynos").to_i
    prev_workers = REDIS.get("worker_dynos").to_i
    web_alert_active    = REDIS.get("web_alert_active").to_i == 1
    worker_alert_active = REDIS.get("worker_alert_active").to_i == 1
    web     = message.first.scan(/(?<=web=)\d+/).first.to_i
    workers = message.first.scan(/(?<=worker=)\d+/).first.to_i
    
    notif_message = "<b>#{CGI.escapeHTML(message.first)}</b> by <b>#{CGI.escapeHTML(scaled_by)}</b>"
    notify = false
    if prev_web == web and prev_workers == workers
      # no change, don't notify
      puts "Scale alert received, but ignoring due to no change."
    elsif prev_web == web
      # scaled worker
      worker_alert_threshold = 4 # notify if reach this
      worker_cooldown_threshold = 1 # notify if go below this
      if prev_workers < worker_alert_threshold and workers >= worker_alert_threshold
        notif_message += " (Workers reached threshold of <b>#{worker_alert_threshold}</b>)"
        notify = true
        REDIS.set "worker_alert_active", 1
      elsif worker_alert_active and prev_workers > worker_cooldown_threshold and workers <= worker_cooldown_threshold
        notif_message += " (Workers below cooldown threshold of <b>#{worker_cooldown_threshold}</b>)"
        notify = true
        REDIS.del "worker_alert_active"
      end
    elsif prev_workers == workers
      # scaled web
      web_alert_threshold = 5 # notify if reach this
      web_cooldown_threshold = 2 # notify if go below this
      if prev_web < web_alert_threshold and web >= web_alert_threshold
        notif_message += " (Web dynos reached threshold of <b>#{web_alert_threshold}</b>)"
        notify = true
        REDIS.set "web_alert_active", 1
      elsif web_alert_active and prev_web > web_cooldown_threshold and web <= web_cooldown_threshold
        notif_message += " (Web dynos below cooldown threshold of <b>#{web_cooldown_threshold}</b>)"
        notify = true
        REDIS.del "web_alert_active"
      else
        # alert unless is autoscale
        notify = scaled_by != "dan@oneuphero.com"
      end
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

#!/usr/bin/env ruby
# coding : utf-8
require 'faraday'
require 'faraday_middleware'
require 'pry'

class Feedy

  attr_accessor :feeds, :entries

  def initialize
    @conn = Faraday.new(url: 'https://cloud.feedly.com') do |faraday|
      faraday.request :json
      faraday.adapter Faraday.default_adapter
      faraday.use FaradayMiddleware::Mashify
      faraday.use FaradayMiddleware::ParseJson
    end
    @feeds = []
    @entries = []
  end

  def unread_feeds
    res = get "/v3/markers/counts"
    @feeds = res.unreadcounts.select{|u| u.count > 0 and u.id.match(/IoT$/)}
  end

  def feed_entries
    @feeds.map do |feed|
      @entries += unread_entries(feed)
    end
  end

  def unread_entries(feed)
    res = get "/v3/streams/contents", {streamId: feed.id, unreadOnly: true}
    res.items
  end

  def mark_as_read(entry_id)
    post '/v3/markers', {
      action: "markAsRead",
      entryIds: [entry_id],
      type: "entries",
    }
  end

  private

  def get(url, params=nil)
    @conn.get do |req|
      req.headers["Authorization"] = "Bearer #{ENV['FEEDY_API_KEY']}"
      req.url url, params
    end.body
  end

  def post(url, params=nil)
    res = @conn.post do |req|
      req.headers["Authorization"] = "Bearer #{ENV['FEEDY_API_KEY']}"
      req.body = params.to_json
      req.url url
    end
    res.body
  end

end

class Slack
  def initialize
    @conn = Faraday.new(url: 'https://slack.com') do |faraday|
      faraday.request :url_encoded
      faraday.adapter Faraday.default_adapter
    end
  end

  def send_message(message)
    post '/api/chat.postMessage', {
      token: ENV["SLACK_API_KEY"],
      channel: ENV["SLACK_CHANNEL"],
      username: 'feedly bot',
      text: message
    }
  end

  private

  def post(url, params=nil)
    @conn.post do |req|
      req.body = params
      req.url url
    end
  end

end

begin
  fd = Feedy.new
  fd.unread_feeds
  fd.feed_entries

  puts "Unread Feed's entry count: #{fd.entries.size}"

  sl = Slack.new
  fd.entries.each do |e|
    send_message = "【新着】: #{e.origin.title} #{e.title} #{e.alternate[0].href}"
    send_message += " \n"
    puts send_message
    send_message += e.summary.content.gsub(%r{<("[^"]*"|'[^']*'|[^'">])*>}, "") if e.summary and e.summary.content
    send_message += " \n"
    send_message += e.visual.url if e.visual and e.visual.url and e.visual.url != 'none'
    send_message += " \n　\n　\n"
    sl.send_message send_message
    fd.mark_as_read(e.id)
  end
rescue
  sl = Slack.new
  sl.send_message "access tokenの期限が切れたみたいだよ Σ(ﾟДﾟ)"
end


module Firering
  include Firering::HTTP
  include Firering::Streaming

  extend self

  attr_accessor :token, :subdomain

  # calls /users/me route on campfire to get the authenticated user information, including token
  def authenticate(subdomain, user, password, &block)
    Firering.subdomain = subdomain
    user("me", user, password) do |user|
      Firering.token = user.token
      block.call(user)
    end
  end

  # non default user and password parameters are only used when user id is "me"
  # to authenticate the user and get his auth token.
  def user(id, user = Firering.token, password = "X", &block)
    http(:get, "/users/#{id}.json", nil, user, password) do |http|
      user = Firering::User.new(http.response, :user)
      block.call(user)
    end
  end

  # returns all rooms. For getting the users, each specific room must be queries with Firering.room
  # multi: if true, gets all the users from each room as Firering::User objects
  def rooms(multi = true, &block)
    http(:get, "/rooms.json") do |http|

      rooms = Yajl::Parser.parse(http.response, :symbolize_keys => true)[:rooms]
      if multi
        ids = rooms.map { |data| data[:id] }
        rooms_multi(ids, &block)
      else
        rooms.map! { |room| Firering::Room.new(room) }
        block.call(rooms)
      end
    end
  end

  # helper for returning all rooms with all existing users (saves the step of going through each room)
  def rooms_multi(ids, &block)
    multi = EventMachine::MultiRequest.new
    rooms = []
    ids.each { |id| multi.add(room(id) { |room| rooms << room }) }
    multi.callback  { block.call(rooms) }
  end

  # Returns an existing room. Also includes all the users currently inside the room.
  def room(id, &block)
    http(:get, "/room/#{id}.json") do |http|
      room = Firering::Room.new(http.response, :room)
      block.call(room)
    end
  end

  # Updates an existing room. Only admins can rename a room, although any
  # user (except guests) may set the topic. Omitting either tag results in
  # that attribute being ignored. To remove a room topic, simply provide an
  # empty topic tag.
  #
  # update_room "1", "name" => "Name", "topic" => "Topic"
  def update_room(id, data, &block)
    http(:put, "/room/#{id}.json", { :room => data }, &block)
  end

  # Returns a collection of upto 100 recent messages in the room. Accepts an
  # additional optional parameter ‘limit’ to restrict the number of messages
  # returned.
  def room_recent_messages(id, limit = nil, &block)
    http(:get, "/room/#{id}/recent.json", (limit ? { :limit => limit } : nil)) do |http|
      messages = Yajl::Parser.parse(http.response, :symbolize_keys => true)[:messages]
      messages.map! { |msg| Firering::Message.new(msg) }
      block.call(messages)
    end
  end

  # Returns all the messages containing the supplied term.
  def search_messages(query, &block)
    http(:get, "/search/#{query}.json") do |http|
      messages = Yajl::Parser.parse(http.response, :symbolize_keys => true)[:messages]
      messages.map! { |msg| Firering::Message.new(msg) }
      block.call(messages)
    end
  end

  # Returns all the messages sent today to a room.
  def today_messages(room_id, &block)
    http(:get, "/room/#{room_id}/transcript.json") do |http|
      messages = Yajl::Parser.parse(http.response, :symbolize_keys => true)[:messages]
      messages.map! { |msg| Firering::Message.new(msg) }
      block.call(messages)
    end
  end

  # Returns all the messages sent on a specific date to a room.
  def messages_on(room_id, year, month, day, &block)
    http(:get, "/room/#{room_id}/transcript/#{year}/#{month}/#{day}.xml") do |http|
      messages = Yajl::Parser.parse(http.response, :symbolize_keys => true)[:messages]
      messages.map! { |msg| Firering::Message.new(msg) }
      block.call(messages)
    end
  end

  # Join a room.
  def room_join(room_id, &block)
    http(:post, "/room/#{room_id}/join.json", &block)
  end

  # Leave a room.
  def room_leave(room_id, &block)
    http(:post, "/room/#{room_id}/leave.json", &block)
  end

  # Locks a room.
  def room_lock(room_id, &block)
    http(:post, "/room/#{room_id}/lock.json", &block)
  end

  # Unlocks a room.
  def room_unlock(room_id, &block)
    http(:post, "/room/#{room_id}/unlock.json", &block)
  end

  # Sends a new message with the currently authenticated user as the sender.
  # The XML for the new message is returned on a successful request.
  #
  # The valid types are:
  #
  # * TextMessage  (regular chat message)
  # * PasteMessage (pre-formatted message, rendered in a fixed-width font)
  # * SoundMessage (plays a sound as determined by the message, which can be either “rimshot”, “crickets”, or “trombone”)
  # * TweetMessage (a Twitter status URL to be fetched and inserted into the chat)
  #
  # If an explicit type is omitted, it will be inferred from the content (e.g.,
  # if the message contains new line characters, it will be considered a paste).
  #
  # :type => "TextMessage",  :body => "Hello"
  def speak(room_id, data, &block)
    # Response Status: 201 Created
    http(:post, "/room/#{room_id}/speak.json", "message" => data) do |http|
      block.call(Firering::Message.new(http.response))
    end
  end

  def text(room_id, text, &block)
    speak(room_id, {:type => "TextMessage", :body => text}, &block)
  end

  def paste(room_id, paste, &block)
    speak(room_id, {:type => "PasteMessage", :body => paste}, &block)
  end

  def rimshot(room_id, &block)
    speak(room_id, {:type => "SoundMessage", :body => "rimshot"}, &block)
  end

  def crickets(room_id, &block)
    speak(room_id, {:type => "SoundMessage", :body => "crickets"}, &block)
  end

  def trombone(room_id, &block)
    speak(room_id, {:type => "SoundMessage", :body => "trombone"}, &block)
  end

  def tweet(room_id, tweet_url, &block)
    speak(room_id, {:type => "TweetMessage", :body => tweet_url}, &block)
  end

  # Highlights a message / Removes a message highlight.
  def highlight_message(message_id, yes_or_no, &block)
    http(yes_or_no ? :post : :delete, "/messages/#{message_id}/star.json", &block)
  end

end

__END__

Upload a file
POST /room/#{id}/uploads.xml

Uploads a file to the room. File parameter in the multipart post body should be called ‘upload’.
Request

Content-Type: multipart/form-data; boundary=---------------------------XXX

Content-Length: 8922

-----------------------------XXX
Content-Disposition: form-data; name="upload"; filename="me.jpg"
Content-Type: image/jpeg
...

Response

Status: 201 Created

<upload>
  <byte-size type="integer">8922</byte-size>
  <content-type>image/jpeg</content-type>
  <created-at type="datetime">2009-11-20T23:26:51Z</created-at>
  <id type="integer">1</id>
  <name>me.jpg</name>
  <room-id type="integer">1</room-id>
  <user-id type="integer">1</user-id>
  <full-url>http://account.campfirenow.com/room/1/uploads/1/me.jpg</full-url>
</upload>

--------------------------------------------------------------------------------

Recently uploaded files
GET /room/#{id}/uploads.xml

Returns a collection of upto 5 recently uploaded files in the room.
Response

Status: 200 OK

<uploads type="array">
  <upload>
    <byte-size type="integer">135</byte-size>
    <content-type>application/octet-stream</content-type>
    <created-at type="datetime">2009-11-20T23:26:51Z</created-at>
    <id type="integer">1</id>
    <name>char.rb</name>
    <room-id type="integer">1</room-id>
    <user-id type="integer">1</user-id>
    <full-url>http://account.campfirenow.com/room/1/uploads/4/char.rb</full-url>
  </upload>
  ...
</uploads>
require "#{File.dirname(__FILE__)}/test_helper"

loaded = true
begin
  require 'stomp'
rescue Object => e
  loaded = false
end
if loaded #only run these test if stomp gem installed

require 'activemessaging/adapters/stomp'


class FakeTCPSocket
  attr_accessor :sent_messages
  def initialize; @sent_messages=[]; end
  def puts(s=""); @sent_messages << s; end
  def write(s=""); self.puts s; end
  def ready?; true; end
end


module Stomp
  class Connection

    attr_accessor :subscriptions

    def socket
      @socket = FakeTCPSocket.new if @socket.nil?
      @socket
    end

    def receive=(msg)
      # stomp 1.0.5 code, now no longer works
      # sm = Stomp::Message.new do |m|
      #   m.command = 'MESSAGE'
      #   m.body = msg
      #   m.headers = {'message-id'=>'testmessage1', 'content-length'=>msg.length, 'destination'=>'destination1'}
      # end

      sm = Stomp::Message.new("MESSAGE\ndestination:/queue/stomp/destination/1\nmessage-id: messageid1\ncontent-length:#{msg.length}\n\n#{msg}\0\n")

      sm.command = 'MESSAGE'
      sm.headers = {'message-id'=>'testmessage1', 'content-length'=>msg.length, 'destination'=>'destination1'}

      @test_message = ActiveMessaging::Adapters::Stomp::Message.new(sm)
    end

    def receive
      @test_message
    end
  end
end

class StompTest < Minitest::Test

  def setup
    @connection = ActiveMessaging::Adapters::Stomp::Connection.new({})
    @d = "/queue/stomp/destination/1"
    @message = "mary had a little lamb"
    @connection.stomp_connection.receive = @message
  end

  def sent_command
    @connection.stomp_connection.socket.sent_messages[0]
  end

  def sent_headers
    @connection.stomp_connection.socket.sent_messages.drop(1).take_while { |line| !line.empty? }
  end

  def sent_body
    (@connection.stomp_connection.socket.sent_messages.drop_while {|line| !line.empty?}).drop(1).first
  end

  def test_initialize
    i = { :retryMax => 4,
          :deadLetterQueue=>'/queue/dlq',
          :login=>"",
          :passcode=> "",
          :host=> "localhost",
          :port=> "61613",
          :reliable=>FALSE,
          :reconnectDelay=> 5,
          :clientId=> 'cid',
          :deadLetterQueuePrefix=>"DLQ."}

    @connection = ActiveMessaging::Adapters::Stomp::Connection.new(i)
    assert_equal 4, @connection.retryMax
    assert_equal '/queue/dlq', @connection.deadLetterQueue
    assert_equal "DLQ.", @connection.deadLetterQueuePrefix
    assert_equal true, @connection.supports_dlq?
  end

  def test_disconnect
    @connection.disconnect
    assert_equal "DISCONNECT", sent_command
  end

  def test_subscribe
    @connection.subscribe @d, {}
    assert_equal "SUBSCRIBE", sent_command
    assert sent_headers.include?("content-length:0"), "No content-length header was sent"
    assert sent_headers.include?("destination:#{@d}"), "No destination header was sent"
    assert_equal 1, @connection.stomp_connection.subscriptions.count
    assert_equal({:'content-type'=>'text/plain; charset=UTF-8', :'content-length'=>'0', :destination=>@d}, @connection.stomp_connection.subscriptions[@d])
  end

  def test_unsubscribe
    @connection.subscribe @d, {}
    @connection.stomp_connection.socket.sent_messages = []
    @connection.unsubscribe @d, {}
    assert_equal "UNSUBSCRIBE", sent_command
    assert sent_headers.include?("content-length:0"), "No content-length header was sent"
    assert sent_headers.include?("destination:#{@d}"), "No destination header was sent"
    assert_equal 0, @connection.stomp_connection.subscriptions.count
  end

  def test_send
    @connection.send(@d, @message, {})
    assert_equal 'SEND', sent_command
    assert sent_headers.include?("content-length:#{@message.length}"), "No content-length header was sent"
    assert sent_headers.include?("destination:#{@d}"), "No destination header was sent"
#    assert_equal @message, @connection.stomp_connection.socket.sent_messages[5]
    assert_equal @message, sent_body
  end

  def test_receive
    m = @connection.receive
    assert_equal @message, m.body
  end

  def test_received
    m = @connection.receive
    m.headers[:transaction] = 'test-transaction'
    @connection.received m, {:ack=>'client'}
  end

  def test_unreceive
    @connection = ActiveMessaging::Adapters::Stomp::Connection.new({:retryMax=>4, :deadLetterQueue=>'/queue/dlq'})
    @connection.stomp_connection.receive = @message
    m = @connection.receive
    m.headers["a13g-retry-count"] = 5
    @connection.unreceive m, {:ack=>'client'}
  end

  def test_unreceive_with_dlq_prefix
    @connection = ActiveMessaging::Adapters::Stomp::Connection.new({:retryMax=>4, :deadLetterQueuePrefix=>'DLQ.'})
    @connection.stomp_connection.receive = @message
    m = @connection.receive
    m.headers["a13g-retry-count"] = 5
    @connection.unreceive m, {:ack=>'client', :destination=>"/queue/myqueue"}
  end

  def test_add_dlq_prefix
    @connection = ActiveMessaging::Adapters::Stomp::Connection.new({:deadLetterQueuePrefix=>'DLQ.'})
    dlq = @connection.add_dlq_prefix("/queue/myqueue")
    assert_equal "/queue/DLQ.myqueue", dlq
    dlq = @connection.add_dlq_prefix("/queue/something/myqueue")
    assert_equal "/queue/something/DLQ.myqueue", dlq
    dlq = @connection.add_dlq_prefix("/topic/myqueue")
    assert_equal "/topic/DLQ.myqueue", dlq
    dlq = @connection.add_dlq_prefix("myqueue")
    assert_equal "DLQ.myqueue", dlq
  end

end

end # if loaded

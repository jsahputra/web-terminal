require 'faye/websocket'
require 'eventmachine'
require 'pty'
require 'json'


$url = 'ws://'+ARGV[0]+'/session/'+(ARGV[1] || Socket.gethostname)

STDERR.puts "Connecting to #{$url}"

reader, writer, _ = PTY.spawn("bash", "-i")
writer.set_encoding("ASCII-8BIT")
reader.set_encoding("ASCII-8BIT")

def connect
  p [:connect, $url]
  $ws = Faye::WebSocket::Client.new($url, 'shell')
end

module Reader
  def receive_data(string)
    EM.next_tick {
      p [:write, string]
      $ws.send string
    }
  end
end

EM.run {
  connect

  EM.attach(reader, Reader)

  $ws.on :open do |event|
    p [:open]
    #$ws.send('Connected')
  end

  $ws.on :error do |event|
    p [:error, event.message]
  end

  $ws.on :message do |event|
    p [:message, event.data]
    if event.data.start_with?("&{") && event.data.end_with?("}")
      data = JSON.parse(event.data[1..-1])
      case data['action']
      when 'screenshot'
        system('scrot', 'output.png')
        system('convert', 'output.png', '-geometry', (data['size'] || '800x800'), 'output.png')
        data = File.open('output.png', 'rb', &:read)
        data64 = Base64.encode64(data).gsub(/\r?\n/,'')
        $ws.send("&" + ({ "action" => "screenshot", "uri" => "data:image/png;base64,"+data64 }).to_json)
      end
    else
      writer.write(event.data)
    end
  end

  $ws.on :close do |event|
    p [:close, event.code, event.reason]
    $ws = nil
    connect unless $quit
    EM.stop if $quit
  end
}

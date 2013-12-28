require 'eventmachine'
require 'rack'
require 'sinatra'
require 'thin'
require 'faye/websocket'
require 'json'


class SocketSet
  attr_reader :id
  def send data
    @websocket.send data
  end
end

class RemoteServer < SocketSet
  def self.sessions
    @sessions ||= {}
  end
  def self.add(websocket)
    session = TerminalPTY.new(websocket)
    sessions[session.id] = session
  end
  def self.remove(session)
    sessions.delete session.id
  end
  def self.list
    sessions.values.map do |session|
      { 'id' => session.id }
    end
  end
  def self.write(id, data)
    if session = sessions[id]
      session.send data
    end
  end
end

class RemoteClient < SocketSet
  def self.clients
    @clients ||= {}
  end

  def self.add(websocket)
    client = TerminalClient.new(websocket)
    (clients[client.id] ||= []) << client
    client
  end

  def self.remove(client)
    if clients[client.id]
      clients[client.id] = clients[client.id].reject { |client_| client_ == client }
    end
  end

  def self.write(id, data)
    clients = self.clients[id]
    if clients && ! clients.empty?
      clients.each { |c| c.send data }
    end
  end
end

class TerminalPTY < RemoteServer
  def initialize(websocket)
    @id = URI.parse(websocket.url).path.split(%r'/',3)[2]
    @websocket = websocket

    @log = File.open("log-#{@id}.log", "wb")

    websocket.onmessage = lambda do |event|
      TerminalClient.write(@id, event.data)
    end

    websocket.onclose = lambda do |event|
      p [:close, event.code, event.reason]
      websocket = nil
      TerminalPTY.remove(self)
    end
  end
  def send data
    @log.write(data)
    super(data)
    @log.flush
  end
end

class TerminalClient < RemoteClient
  class << self
    alias_method :real_add, :add
    def add(sock)
      client = real_add(sock)
      TerminalPTY.write(client.id, "\f")
    end
  end

  def initialize(websocket)
    @id = URI.parse(websocket.url).path.split(%r'/', 3)[2]
    @websocket = websocket

    websocket.onmessage = lambda do |event|
      p [:got_message, event.data]
      TerminalPTY.write(@id, event.data)
    end

    websocket.onclose = lambda do |event|
      p [:close, event.code, event.reason]
      websocket = nil
      TerminalClient.remove(self)
    end
  end
end


class App < Sinatra::Base
  get '/' do
    [302, {'Location' => '/terminal.html'}, ""]
  end
  get '/quit' do
    Thread.new {
      sleep 1
      EM.stop
      exit!
    }
    [302, {'Location' => '/terminal.html'}, ""]
  end
  get '/connections' do
    [200, { 'Content-Type' => 'application/json'}, TerminalPTY.list.to_json]
  end
  get '/*' do
    file = request.path.sub(/static\//, '')
    path = File.join(File.dirname(__FILE__), file)
    type = case File.extname(file)
      when '.js'; 'text/javascript'
      when '.html'; 'text/html'
      when '.css'; 'text/css'
    end
    headers = {}
    headers['Content-Type'] = type if type
    text = File.open(path, 'rb') { |fp| fp.read }

    [200, headers, text]
  end
end

class WebSock
  def initialize(app)
    @app = app
  end
  def call(env)
    if Faye::WebSocket.websocket?(env)
      path = env['PATH_INFO']
      case true
      when path.start_with?('/client')
        ws = Faye::WebSocket.new(env, ['chat', 'shell', '', 'undefined'], :ping => 15)
        p [:client_add, env['PATH_INFO']]
        TerminalClient.add(ws)
        return ws.rack_response
      when path.start_with?('/session')
        ws = Faye::WebSocket.new(env, ['chat', 'shell', '', 'undefined'], :ping => 15)
        TerminalPTY.add(ws)
        return ws.rack_response
      else
        p [:fail_add, env.inspect]
        return [404, {}, "Invalid path."]
      end
    else
      @app.call(env)
    end
  rescue Exception => e
    STDERR.puts "#{e.class}: #{e.message}: #{e.backtrace.join("\n      ")}"
  end
end

Faye::WebSocket.load_adapter('thin')

EM.run {
  thin = Rack::Handler.get('thin')

  thin.run(WebSock.new(App.new), :Port => (ARGV[0] || 3036).to_i) do |server|
    # You can set options on the server here, for example to set up SSL:
    #server.ssl_options = {
    #  :private_key_file => 'path/to/ssl.key',
    #  :cert_chain_file  => 'path/to/ssl.crt'
    #}
    #server.ssl = true
  end
}


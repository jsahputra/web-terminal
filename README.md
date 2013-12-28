web-terminal
============

License: MIT License

Purpose: Allow one or more users connect to a remote machine via HTTP(S) &
execute shell commands.

It relies on:
* Ruby 2.0
* faye-websocket-ruby
* thin
* term.js


TODO
----

* Authentication
* SSL support

Warning
-------

This is not ready for production use - it is a proof-of-concept
application for accessing a remote shell.

It is totally insecure.


server-app.rb
-------------

usage: ruby server-app.rb <port>

1. Run the server app that connects clients to ptys.
2. Connect to the app at http://localhost:<port>/ in a modern web
   browser


remote-pty.rb
-------------

usage: ruby remote-pty.rb <host>:<port> [<id>]

1. Create a process that connects to the server and offers a remote
   shell.



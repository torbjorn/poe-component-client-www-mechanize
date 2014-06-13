package t::lib::TestUtils;

use Mojolicious::Lite;

# sub import {

#     my $daemon = Mojo::Server::Daemon->new(listen => ['http://*:8080']);

#     $daemon->unsubscribe('request');
#     $daemon->on(request => sub {

#         my ($daemon, $tx) = @_;

#         # Request
#         my $method = $tx->req->method;
#         my $path   = $tx->req->url->path;

#         # Response
#         $tx->res->code(200);
#         $tx->res->headers->content_type('text/plain');
#         $tx->res->body("$method request for $path!");

#         # Resume transaction
#         $tx->resume;

#     });

#     $daemon->run;

# }

1;

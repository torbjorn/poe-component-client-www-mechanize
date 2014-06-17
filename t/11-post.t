#!/usr/bin/perl

use strict;
use warnings;
use utf8::all;
use Test::Most;
# use Test::Warnings;

use HTTP::Request::Common qw/GET/;
use HTTP::Request::Params;
use POE qw(Component::Client::WWW::Mechanize);

use t::lib::TestUtils qw/server_handler/;

POE::Component::Client::WWW::Mechanize->spawn;

my ($uri,$html);

# defining a callback to create a session
POE::Session->create(
    package_states => [
        main => [
            qw/
                  _start
                  _stop
                  process_response
                  process_response2
                  clean_up
                  server_handler
              /
          ]
    ]
);
POE::Kernel->run;

done_testing;

exit;

sub _start {
    $_[KERNEL]->alias_set( "test" );
    $_[KERNEL]->post( "mech", post => $uri, {
        param1 => "value1"
    }, "process_response" );
}
sub _stop {}

sub server_handler {

    my($request,$response,$dirmatch) = @_[ARG0,ARG1,ARG2];

    # Webby content generation stuff here
    $response->code( 200 );
    $response->content_type( "text/html" );
    $response->content( $html );

    $_[KERNEL]->post( "httpd", "DONE", $response ) or die $!;

}
sub process_response {

    note "request #1";

    my $request = $_[ARG0]->[0];
    my $response = $_[ARG1]->[0];

    my $session = $_[KERNEL]->alias_resolve( "mech" );
    my $mech = $session->get_heap()->{mech};

    $_[KERNEL]->post( "mech", post => $uri, {test=>"value"}, "process_response2", (undef)x3,
                      a_header => "a value"
                  );

    ## tests

    isa_ok $response, "HTTP::Response";
    ok $response->is_success, "success is ok";

    my $params = HTTP::Request::Params->new({
        req => $request
    })->params;

    is $params->{param1}, "value1", "POST parameters";

}
sub process_response2 {

    note "request #2";

    my $request = $_[ARG0]->[0];
    my $response = $_[ARG1]->[0];

    $_[KERNEL]->yield( "clean_up" );

    my $params = HTTP::Request::Params->new({
        req => $request
    })->params;

    ok $response->is_success, "success is ok";
    is $request->header( "A-Header" ), "a value", "custom header";

}

sub clean_up {
    $_[KERNEL]->post( mech => "shutdown" );
    $_[KERNEL]->post( httpd => "SHUTDOWN" );
}

BEGIN {

    $uri = "http://localhost:8000/?foo=bar";

    $html = <<EOC;
<!doctype html>

<html lang="en">
<head>
  <meta charset="utf-8">

  <title>HTML Title</title>
  <meta name="description" content="HTML5 Sample content">
  <meta name="author" content="PoCo::Mech">

  <link rel="stylesheet" href="css/styles.css?v=1.0">

</head>

<body>
HTML Content

<form method="post" action="$uri">
<input name="testinput" value="a defaultvalue"/>
<input type="submit"/>
</form>

<a href="$uri&step=2">This is a link</a>

<script src="js/a_script_file.js"></script>
</body>
</html>
EOC

}

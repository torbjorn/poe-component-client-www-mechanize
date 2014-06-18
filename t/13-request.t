#!/usr/bin/perl

use strict;
use warnings;
use utf8::all;
use Test::Most;
use Test::Warnings;

use HTTP::Request::Common qw/GET/;

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
    $_[KERNEL]->post( "mech", get => $uri, "process_response" );
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

    my $response = $_[ARG1]->[0];

    isa_ok( $response, "HTTP::Response" );
    ok( $response->is_success, "success is ok" );

    my $session = $_[KERNEL]->alias_resolve( "mech" );
    my $mech = $session->get_heap()->{mech};

    subtest "some mech tests" => sub {

        plan tests => 13;

        ok $mech->success, "success";
        is $mech->uri, $uri, "uri";
        cmp_deeply $mech->response, $response, "response";
        is $mech->status, $response->code, "status";
        is $mech->content_type, "text/html", "content_type";
        is $mech->base, $uri, "base";
        ok $mech->forms, "html has forms";
        ok $mech->current_form, "current_form";
        ok $mech->links, "html has links";
        ok $mech->is_html, "response is html";
        is $mech->title, "HTML Title", "html title";

        ok $mech->content, "content";
        ok $mech->text, "text";

    };

    ## add (undef)x3 to get to pass parameters
    $_[KERNEL]->post( "mech", get => $uri, "process_response2", (undef)x3,
                      a_header => "a value" );

}
sub process_response2 {

    note "request #2";

    my $request = $_[ARG0]->[0];
    my $response = $_[ARG1]->[0];

    ok $response->is_success, "success is ok";
    is $request->header( "A-Header" ), "a value", "custom header";
    is $request->headers->referer, $uri, "http referer";

    $_[KERNEL]->yield( "clean_up" );

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

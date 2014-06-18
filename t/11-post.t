#!/usr/bin/perl

use strict;
use warnings;
use utf8::all;
use Test::Most;
# use Test::Warnings;

use HTTP::Request::Common qw/GET/;
use HTTP::Request::Params;
use POE qw(Component::Client::WWW::Mechanize);

my $uri;
BEGIN { $uri = "http://localhost:8000/?foo=bar" };
use t::lib::TestUtils $uri;

POE::Component::Client::WWW::Mechanize->spawn;

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

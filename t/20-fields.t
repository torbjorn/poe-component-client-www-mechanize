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
    $_[KERNEL]->post( "mech", get => $uri, "process_response" );
}
sub _stop {}

sub process_response {

    note "checking fields";

    my $c = sub { $poe_kernel->call( "mech", @_ ) };

    my $session = $_[KERNEL]->alias_resolve( "mech" );
    my $mech = $session->get_heap()->{mech};

    my @forms = $c->("forms");

    cmp_deeply \@forms, [ignore, ignore],
        "forms returns 2 things" ;

    note "field(...) in form 1";

    ok $c->( "form_number", 1 ), "form 1";
    is $forms[0]->param("testinput"), "a defaultvalue", "original field value";
    ok $c->( field => "testinput", "a changed value" ), "call field" ;
    is $forms[0]->param("testinput"), "a changed value", "field changed";
    is $c->( value => "testinput" ), $forms[0]->param("testinput"),
        "value() matches form's param()";

    note "tick(...) in form 2";

    ok $c->( "form_number", 2 ), "form 2";
    ok !$forms[1]->param("box2"), "checkbox starts false";
    lives_ok { $c->( "tick", "box2", "value2" ) } "ticking box" ;
    is $forms[1]->param("box2"), "value2", "checkbox true";

    note "set_fields(...) in form 1";

    ok $c->( "form_name", "form1" ), "form 1 again";
    $c->( "set_fields", testinput => "a 3rd value" );
    is $forms[0]->param("testinput"), "a 3rd value", "set_fields";
    $c->( "set_visible", "a 4th value" );
    is $forms[0]->param("testinput"), "a 4th value", "set_visible";

    note "heading to form 2";

    ok $c->( "form_id", "form2" ), "back to form 2";
    ok $forms[1]->param("box2"), "checkbox still ticked";
    lives_ok { $c->( "untick", "box2", "value2" ) } "unticking...";
    ok !$forms[1]->param("box2"), "checkbox now unticked";

    $_[KERNEL]->yield( "clean_up" );

}

sub clean_up {
    $_[KERNEL]->post( mech => "shutdown" );
    $_[KERNEL]->post( httpd => "SHUTDOWN" );
}

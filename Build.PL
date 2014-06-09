
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'POE::Component::Client::WWW::Mechanize',
    license             => 'artistic2',
    dist_author         => 'Torbjørn Lindahl <torbjorn.lindahl@gmail.com>',
    dist_version_from   => 'lib/POE/Component/Client/WWW/Mechanize.pm',
    build_requires => {
        'Test::Most' => 0,
    },
    requires => {

    },
    add_to_cleanup      => [ 'POE-Component-Client-WWW-Mechanize-*' ],
    # sign => 1,
    dynamic_config => 0,
);

$builder->create_build_script();

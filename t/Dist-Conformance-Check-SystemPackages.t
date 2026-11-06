#!/usr/bin/env perl
use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Test2::V0;
use Test2::Plugin::NoWarnings;
use FindBin::libs;

use Fixture();
use Dist::Conformance::Check::SystemPackages();
use Dist::Conformance::Snapshot::Directory();
use Dist::Conformance::Snapshot::Tree();

my $CLASS = Dist::Conformance::Check::SystemPackages::;

sub snapshot_of ($metamerge) {
    my $root = defined $metamerge ? Fixture::checkout( 'metamerge.yml' => $metamerge ) : Fixture::checkout();
    return Dist::Conformance::Snapshot::Directory->new( root => $root );
}

sub check_of ($metamerge) { return [ Fixture::make_check( $CLASS, {} )->check( snapshot_of($metamerge) ) ] }

# The errors of a declaration, or the empty string when it is valid.
sub refusal_of ($declaration) {
    return eval { $CLASS->declared( snapshot_of("x_system_packages:\n$declaration") ); q{} } // $@;
}

subtest declared => sub {
    my $both = "x_system_packages:\n  deb:\n    - ffmpeg\n    - libmagic-dev\n  programs:\n    - ffmpeg -version\n";
    is( $CLASS->declared( snapshot_of($both) ),                                         { deb => [qw{ffmpeg libmagic-dev}], programs => ['ffmpeg -version'] }, 'the packages and the programs, as written' );
    is( $CLASS->declared( snapshot_of("x_system_packages:\n  deb: [ffmpeg]\n") ),       { deb => ['ffmpeg'], programs => [] },                                 'programs is optional, and then empty' );
    is( $CLASS->declared( snapshot_of(undef) ),                                         { programs => [] },                                                    'no metamerge.yml declares nothing' );
    is( $CLASS->declared( snapshot_of("resources:\n  homepage: https://test.test\n") ), { programs => [] },                                                    'and nor does one without the key' );
    is( $CLASS->declared( snapshot_of("x_system_packages: {}\n") ),                     { programs => [] },                                                    'or with the key and nothing in it' );

    my $root = Fixture::checkout( 'metamerge.yml' => $both );
    is( $CLASS->declared("$root"), $CLASS->declared( snapshot_of($both) ), 'a directory is read as a checkout' );
    is( $CLASS->declared($root),   $CLASS->declared("$root"),              'whether a string or a Mojo::File' );

    my %fetched;
    my $tree = Dist::Conformance::Snapshot::Tree->new(
        paths => { 'metamerge.yml' => Dist::Conformance::Snapshot::blob_sha($both), 'lib/Bogus.pm' => 'sha-of-bogus' },
        fetch => sub ($path) { $fetched{$path}++; return $both },
    );
    is( $CLASS->declared($tree), { deb             => [qw{ffmpeg libmagic-dev}], programs => ['ffmpeg -version'] }, 'a remote tree is read like a checkout' );
    is( \%fetched,               { 'metamerge.yml' => 1 },                                                          'and only metamerge.yml is fetched' );

    like( dies { $CLASS->declared( snapshot_of("x_system_packages:\n  deb: [Bad]\n") ) }, qr{\Ametamerge[.]yml\ is\ not\ valid:\n\ \ /x_\w+/deb/0:}, 'an invalid declaration dies with its errors' );
    like( dies { $CLASS->declared( snapshot_of("- a\n") ) },                              qr/\Ametamerge[.]yml\ does\ not\ hold\ a\ mapping/,        'and so does a file that is not a mapping' );
    like( dies { $CLASS->declared('/bogus/checkout') },                                   qr/is\ not\ a\ directory/,                                 'and a directory that is not there' );
};

subtest 'deb package names' => sub {
    is( refusal_of("  deb: [ffmpeg, libmagic-dev, g++, libstdc++6, python3.12, 0ad]\n"), q{}, 'lowercase letters, digits, +, - and ., from a letter or a digit' );
    is( refusal_of("  deb: [xz]\n"),                                                     q{}, 'two characters are enough' );
    like( refusal_of("  deb: [x]\n"),            qr{/deb/0:},         'one is not' );
    like( refusal_of("  deb: [ffmpeg-]\n"),      qr{/deb/0:},         'a name that ends in -, which apt reads as a removal, is refused' );
    like( refusal_of("  deb: [libMagic]\n"),     qr{/deb/0:},         'and so is an uppercase letter' );
    like( refusal_of("  deb: [-ffmpeg]\n"),      qr{/deb/0:},         'and a leading -' );
    like( refusal_of("  deb: [.ffmpeg]\n"),      qr{/deb/0:},         'and a leading .' );
    like( refusal_of("  deb: ['ffmpeg=7.0']\n"), qr{/deb/0:},         'and a version' );
    like( refusal_of("  deb: ['ffmpeg vlc']\n"), qr{/deb/0:},         'and two names in one' );
    like( refusal_of("  deb: ['ffmpeg/sid']\n"), qr{/deb/0:},         'and a release' );
    like( refusal_of("  deb: [ffmpeg, Bad]\n"),  qr{/deb/1:},         'each name is checked, and the error names which' );
    like( refusal_of("  deb: []\n"),             qr{/deb:},           'an empty list is refused, as a declaration that says nothing' );
    like( refusal_of("  deb: ffmpeg\n"),         qr{/deb:.*array},    'a list is a list, not one name' );
    like( refusal_of("  deb: [[ffmpeg]]\n"),     qr{/deb/0:.*string}, 'and a name is a string' );
};

subtest 'packagers' => sub {
    is( refusal_of("  rpm: [perl-Moose]\n"), q{}, 'another packager has the generic rule, until it has its own' );
    like( refusal_of("  rpm: [perl-]\n"),      qr{/rpm/0:},                         'which also refuses a trailing -' );
    like( refusal_of("  Deb: [ffmpeg]\n"),     qr{Properties\ not\ allowed:\ Deb},  'a packager is lowercase' );
    like( refusal_of("  9deb: [ffmpeg]\n"),    qr{Properties\ not\ allowed:\ 9deb}, 'and starts with a letter' );
    like( refusal_of("  deb-src: [ffmpeg]\n"), qr{Properties\ not\ allowed},        'and is only letters and digits' );
    like( refusal_of("  - ffmpeg\n"),          qr{/x_system_packages:.*object},     'the declaration is a mapping of packagers' );
};

subtest programs => sub {
    is( refusal_of("  programs: ['ffmpeg -version', 'magic --help']\n"), q{}, 'a list of command lines' );
    like( refusal_of("  programs: ['']\n"),            qr{/programs/0:},      'an empty one is refused' );
    like( refusal_of("  programs: ['   ']\n"),         qr{/programs/0:},      'and so is one of spaces' );
    like( refusal_of("  programs: [\"a\\nb\"]\n"),     qr{/programs/0:},      'and one of two lines, because the output is one per line' );
    like( refusal_of("  programs: []\n"),              qr{/programs:},        'an empty list is refused' );
    like( refusal_of("  programs: ffmpeg -version\n"), qr{/programs:.*array}, 'and so is one command that is not in a list' );
};

subtest check => sub {
    is( check_of(undef),                                                                    [ 'pass', 'there is no metamerge.yml, so it needs no system packages' ],          'no file passes' );
    is( check_of("name: x\n"),                                                              [ 'pass', 'metamerge.yml declares no system packages' ],                          'and so does a file without the key' );
    is( check_of("x_system_packages:\n  deb: [ffmpeg, xz]\n  programs: [ffmpeg]\n"),        [ 'pass', 'metamerge.yml declares 2 deb packages and 1 program' ],                'a valid declaration passes, and says what it holds' );
    is( check_of("x_system_packages:\n  deb: [xz]\n  rpm: [xz, file]\n"),                   [ 'pass', 'metamerge.yml declares 1 deb package and 2 rpm packages' ],            'each packager is counted' );
    is( check_of("x_system_packages:\n  deb: [xz]\n  rpm: [xz]\n  programs: [xz, file]\n"), [ 'pass', 'metamerge.yml declares 1 deb package, 1 rpm package and 2 programs' ], 'with the programs last' );
    is( check_of("x_system_packages:\n  programs: [xz]\n"),                                 [ 'pass', 'metamerge.yml declares 1 program' ],                                   'and programs alone' );
    is( check_of("x_system_packages:\n  deb: [ffmpeg-]\n"),                                 [ 'fail', match(qr{\Ametamerge[.]yml\ is\ not\ valid:\ /x_\w+/deb/0:\ }) ],       'an invalid one fails, with the error on one line' );
    is( check_of("x_system_packages: [\n"),                                                 [ 'fail', match(qr/\Ametamerge[.]yml\ does\ not\ parse\ as\ YAML/) ],             'and so does a file that does not parse' );
    like( dies { Fixture::make_check( $CLASS, { file => 'x.yml' } ) }, qr/Properties\ not\ allowed:\ file/, 'the check takes no configuration of its own' );
};

subtest update => sub {
    my $root   = Fixture::checkout( 'metamerge.yml' => "x_system_packages:\n  deb: [x]\n" );
    my $before = Fixture::tree_of($root);
    my $update = Fixture::run_update( Fixture::make_check( $CLASS, {} ), $root );
    is( Fixture::tree_of($root), $before,                                                           'nothing is written' );
    is( $update->manual,         [ match(qr/deb\/0.*:\ SystemPackages\ has\ no\ automatic\ fix/) ], 'and a person is told what is wrong' );
};

done_testing;

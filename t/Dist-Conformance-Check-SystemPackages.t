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

subtest entries => sub {
    is( refusal_of("  deb:\n    - name: libssl3\n      ubuntu/24.04: libssl3t64\n    - ubuntu/24.04: libfoo-t64\n    - debian: libbar\n"), q{}, 'an entry can name a package for a distro, or for a release of one' );
    like( refusal_of("  deb:\n    - {}\n"),                                   qr{/deb/0:.*Not\ enough\ properties},           'a mapping without a key is refused' );
    like( refusal_of("  deb:\n    - Ubuntu: libfoo\n"),                       qr{/deb/0:.*Properties\ not\ allowed:\ Ubuntu}, 'and so is a key that is not a distro' );
    like( refusal_of("  deb:\n    - ubuntu/24 04: libfoo\n"),                 qr{/deb/0:.*Properties\ not\ allowed},          'or a release' );
    like( refusal_of("  deb:\n    - ubuntu/24.04/x: libfoo\n"),               qr{/deb/0:.*Properties\ not\ allowed},          'and a key has one / at most' );
    like( refusal_of("  deb:\n    - name: libssl3\n      debian: libbar-\n"), qr{/deb/0/debian:},                             'each value has the name rule of the packager' );
    like( refusal_of("  deb:\n    - name: x\n"),                              qr{/deb/0/name:},                               'name too' );
    like( refusal_of("  deb:\n    - debian: [libbar]\n"),                     qr{/deb/0/debian:},                             'and a value is one name' );
    like( refusal_of("  rpm:\n    - fedora: perl-\n"),                        qr{/rpm/0/fedora:},                             'another packager has its rule in a mapping too' );
};

my $SOURCE = <<'YAML';
    - name: jellyfin
      uri: https://repo.test.test/ubuntu
      suites: ['{codename}', stable]
      components: [main]
      key: https://repo.test.test/key.gpg
      fingerprint: 0123456789ABCDEF0123456789abcdef01234567
YAML

# The errors of $SOURCE with the line for $field replaced by $line, or removed when $line is undef.
sub source_refusal ( $field, $line ) {
    my $source = $SOURCE =~ s/^\ {6}\Q$field\E:[^\n]*\n//mr;
    $source =~ s/^(\ {4}-\ name:)/$1/m;
    $source .= "      $line\n" if defined $line;
    return refusal_of("  sources:\n    deb:\n$source");
}

subtest sources => sub {
    is( refusal_of("  sources:\n    deb:\n$SOURCE"), q{}, 'an apt archive with a fingerprint' );
    is( source_refusal( 'distros',       'distros: [ubuntu/24.04, debian]' ),             q{}, 'with the distros that it is for' );
    is( source_refusal( 'pin',           "pin: { priority: 600, packages: 'ffmpeg*' }" ), q{}, 'and a pin' );
    is( source_refusal( 'architectures', 'architectures: [amd64, arm64]' ),               q{}, 'and its architectures' );
    like( source_refusal( 'fingerprint', undef ),                                                              qr{/sources/deb/0/fingerprint:\ Missing},  'a source without a fingerprint is refused' );
    like( source_refusal( 'fingerprint', 'fingerprint: 0123456789ABCDEF0123456789ABCDEF0123456' ),             qr{/sources/deb/0/fingerprint:},           'and one of 39 digits' );
    like( source_refusal( 'fingerprint', 'fingerprint: 0123456789ABCDEF0123456789ABCDEF012345678' ),           qr{/sources/deb/0/fingerprint:},           'and of 41' );
    like( source_refusal( 'fingerprint', 'fingerprint: 0123456789ABCDEF0123456789ABCDEF0123456G' ),            qr{/sources/deb/0/fingerprint:},           'and one that is not hex' );
    like( source_refusal( 'fingerprint', "fingerprint: '0123 4567 89AB CDEF 0123 4567 89AB CDEF 0123 4567'" ), qr{/sources/deb/0/fingerprint:},           'and one with spaces' );
    like( source_refusal( 'key',         undef ),                                                              qr{/sources/deb/0/key:\ Missing},          'the key is required' );
    like( source_refusal( 'key',         'key: ftp://repo.test.test/key.gpg' ),                                qr{/sources/deb/0/key:},                   'and is http or https' );
    like( source_refusal( 'uri',         'uri: repo.test.test' ),                                              qr{/sources/deb/0/uri:},                   'and so is the archive' );
    like( source_refusal( 'name',        'name: Jellyfin' ),                                                   qr{/sources/deb/0/name:},                  'a name is lowercase' );
    like( source_refusal( 'suites',      'suites: []' ),                                                       qr{/sources/deb/0/suites:},                'one suite at least' );
    like( source_refusal( 'suites',      "suites: ['{release}']" ),                                            qr{/sources/deb/0/suites/0:},              '{codename} is the only placeholder' );
    like( source_refusal( 'suites',      "suites: ['{codename', stable]" ),                                    qr{/sources/deb/0/suites/0:},              'and is whole' );
    like( source_refusal( 'distros',     'distros: [Ubuntu]' ),                                                qr{/sources/deb/0/distros/0:},             'a distro has the form of a key of an entry' );
    like( source_refusal( 'distros',     'distros: []' ),                                                      qr{/sources/deb/0/distros:},               'and the list is not empty' );
    like( source_refusal( 'pin',         'pin: { packages: ffmpeg }' ),                                        qr{/sources/deb/0/pin/priority:\ Missing}, 'a pin has a priority' );
    like( source_refusal( 'pin',         'pin: { priority: high }' ),                                          qr{/sources/deb/0/pin/priority:},          'which is an integer' );
    like( source_refusal( 'name',        "name: jellyfin\n      mirror: x" ),                                  qr{Properties\ not\ allowed:\ mirror},     'and no other key is allowed' );
    like( refusal_of("  sources:\n    rpm:\n$SOURCE"), qr{/sources:.*Properties\ not\ allowed:\ rpm}, 'only deb takes sources' );
    like( refusal_of("  sources:\n    deb: []\n"),     qr{/sources/deb:},                             'an empty list of sources is refused' );
    like( refusal_of("  sources: [ffmpeg]\n"),         qr{/sources:.*object},                         'and sources is not a packager' );
    is( $CLASS->declared( snapshot_of("x_system_packages:\n  sources:\n    deb:\n$SOURCE") )->{sources}{deb}[0]{fingerprint}, '0123456789ABCDEF0123456789abcdef01234567', 'declared gives the sources as written' );
};

subtest resolve => sub {
    my $declared = {
        deb => [
            'ffmpeg',
            { name           => 'libssl3', 'ubuntu/24.04' => 'libssl3t64', ubuntu => 'libssl3u' },
            { 'ubuntu/24.04' => 'libfoo-t64' },
            { debian         => 'libbar' },
            'ffmpeg',
        ],
        rpm     => ['ffmpeg-free'],
        sources => {
            deb => [
                { name => 'every',  uri => 'https://every.test.test',  suites => [qw/{codename} {codename}-updates stable/], components => ['main'], key => 'https://every.test.test/k', fingerprint => 'F' x 40 },
                { name => 'noble',  uri => 'https://noble.test.test',  suites => ['noble'],  components => ['main'], key => 'https://noble.test.test/k',  fingerprint => 'E' x 40, distros => ['ubuntu/24.04'] },
                { name => 'debian', uri => 'https://debian.test.test', suites => ['stable'], components => ['main'], key => 'https://debian.test.test/k', fingerprint => 'D' x 40, distros => ['debian'] },
            ],
        },
        programs => ['ffmpeg -version'],
    };
    my sub on (%host) { return $CLASS->resolve( $declared, packager => 'deb', %host ) }

    my $noble = on( distro => 'ubuntu', release => '24.04', codename => 'noble' );
    is( $noble->{packages}, [qw{ffmpeg libssl3t64 libfoo-t64}], 'on the release, the release wins, an entry for another distro is skipped, and a duplicate is dropped' );
    is( on( distro => 'ubuntu', release => '22.04', codename => 'jammy' )->{packages},    [qw{ffmpeg libssl3u}],       'on another release of the distro, the distro wins, and an entry only for the release is skipped' );
    is( on( distro => 'debian', release => '12',    codename => 'bookworm' )->{packages}, [qw{ffmpeg libssl3 libbar}], 'on another distro, name is the default' );
    my $nowhere = on( codename => 'noble' );
    is( $nowhere->{packages},                                        [qw{ffmpeg libssl3}],                                                            'without a distro, only name matches' );
    is( [ map { $_->{name} } @{ $nowhere->{sources} } ],             ['every'],                                                                       'and only a source without distros applies' );
    is( $CLASS->resolve( $declared, packager => 'rpm' ),             { packages => ['ffmpeg-free'], sources => [], programs => ['ffmpeg -version'] }, 'another packager has its own packages, and no sources' );
    is( $CLASS->resolve( $declared, packager => 'pkg' )->{packages}, [],                                                                              'and one that is not declared has none' );

    is( [ map { $_->{name} } @{ $noble->{sources} } ],                                                            [qw{every noble}],                                                                                                                                               'a source applies to every host, or to the hosts of its distros' );
    is( $noble->{sources}[0]{suites},                                                                             [qw{noble noble-updates stable}],                                                                                                                                '{codename} is filled in each suite' );
    is( $noble->{sources}[1],                                                                                     { name => 'noble', uri => 'https://noble.test.test', suites => ['noble'], components => ['main'], key => 'https://noble.test.test/k', fingerprint => 'E' x 40 }, 'and a resolved source has no distros' );
    is( [ map { $_->{name} } @{ on( distro => 'debian', release => '12', codename => 'bookworm' )->{sources} } ], [qw{every debian}],                                                                                                                                              'a distro in distros matches each of its releases' );
    is( $declared->{sources}{deb}[0]{suites}[0],                                                                  '{codename}',                                                                                                                                                    'the declaration is not changed' );
    is( $noble->{programs},                                                                                       ['ffmpeg -version'],                                                                                                                                             'and the programs are those of every host' );

    like( dies { on( distro => 'debian', release => '12' ) },        qr/\AThe\ source\ every\ needs\ the\ codename/, 'a source that needs a codename dies without one' );
    like( dies { $CLASS->resolve( $declared, distro => 'debian' ) }, qr/needs\ a\ packager/,                         'a packager is required' );
    is( $CLASS->resolve( { programs => [] }, packager => 'deb' ), { packages => [], sources => [], programs => [] }, 'a declaration of nothing resolves to nothing' );
};

subtest os_release => sub {
    my $text = <<'OS';
# a comment
PRETTY_NAME="Ubuntu 24.04.1 LTS"
NAME='Ubuntu'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
QUOTED="say \"hi\" \\ \$HOME"

  ID_LIKE=debian
not a variable
OS
    my $vars = Dist::Conformance::Check::SystemPackages::os_release($text);
    is( [ @{$vars}{qw{ID VERSION_ID VERSION_CODENAME}} ],          [qw{ubuntu 24.04 noble}],                                             'bare and double-quoted values' );
    is( $vars->{NAME},                                             'Ubuntu',                                                             'single-quoted' );
    is( $vars->{PRETTY_NAME},                                      'Ubuntu 24.04.1 LTS',                                                 'with spaces' );
    is( $vars->{QUOTED},                                           'say "hi" \\ $HOME',                                                  'and with escapes in double quotes' );
    is( $vars->{ID_LIKE},                                          'debian',                                                             'leading space is allowed' );
    is( [ sort keys %$vars ],                                      [qw{ID ID_LIKE NAME PRETTY_NAME QUOTED VERSION_CODENAME VERSION_ID}], 'and comments, blank lines and other lines are skipped' );
    is( Dist::Conformance::Check::SystemPackages::os_release(q{}), {},                                                                   'an empty file has no variables' );
};

subtest check => sub {
    is( check_of(undef),                                                                    [ 'pass', 'there is no metamerge.yml, so it needs no system packages' ],          'no file passes' );
    is( check_of("name: x\n"),                                                              [ 'pass', 'metamerge.yml declares no system packages' ],                          'and so does a file without the key' );
    is( check_of("x_system_packages:\n  deb: [ffmpeg, xz]\n  programs: [ffmpeg]\n"),        [ 'pass', 'metamerge.yml declares 2 deb packages and 1 program' ],                'a valid declaration passes, and says what it holds' );
    is( check_of("x_system_packages:\n  deb: [xz]\n  rpm: [xz, file]\n"),                   [ 'pass', 'metamerge.yml declares 1 deb package and 2 rpm packages' ],            'each packager is counted' );
    is( check_of("x_system_packages:\n  deb: [xz]\n  rpm: [xz]\n  programs: [xz, file]\n"), [ 'pass', 'metamerge.yml declares 1 deb package, 1 rpm package and 2 programs' ], 'with the programs last' );
    is( check_of("x_system_packages:\n  deb: [xz]\n  sources:\n    deb:\n$SOURCE"),         [ 'pass', 'metamerge.yml declares 1 deb package and 1 deb source' ],              'and each packager of sources' );
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

#!/usr/bin/env perl
use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Test2::V0;
use Test2::Plugin::NoWarnings;
use FindBin::libs;

use Fixture();
use Dist::Conformance::Check::Shebangs();
use Dist::Conformance::Snapshot::Directory();

my %CONFIG = ( shebang => '{{SHEBANG}}' );

sub shebangs ( $config = {}, %variables ) { return Fixture::make_check( Dist::Conformance::Check::Shebangs::, { %CONFIG, %$config }, SHEBANG => '#!perl', %variables ) }
sub check_of ( $root, @args ) { return [ shebangs(@args)->check( Dist::Conformance::Snapshot::Directory->new( root => $root ) ) ] }

subtest switches_of => sub {
    my $switches_of = \&Dist::Conformance::Check::Shebangs::switches_of;
    is( $switches_of->('#!perl'),                      q{},      'a bare perl names perl, with no switches' );
    is( $switches_of->('#!/usr/bin/perl'),             q{},      'and so does its path' );
    is( $switches_of->('#! /usr/bin/env perl '),       q{},      'and env perl, with spaces around it' );
    is( $switches_of->('#!/opt/perl5/bin/perl5.40.1'), q{},      'and a perl with its version in the name' );
    is( $switches_of->('#!/usr/bin/perl -w -T'),       '-w -T',  'the switches after perl' );
    is( $switches_of->('#!/bin/sh'),                   undef,    'another interpreter is not perl' );
    is( $switches_of->('#!/usr/bin/perlcritic'),       undef,    'nor is a program whose name starts with perl' );
    is( $switches_of->('#!/usr/bin/env python perl'),  undef,    'nor env with another program' );
    is( $switches_of->('use strict;'),                 undef,    'and a line that is no shebang is none' );
};

subtest check => sub {
    my $root = Fixture::checkout(
        'bin/good'       => "#!perl\nprint 1;\n",
        'bin/env'        => "#!/usr/bin/env perl\nprint 1;\n",
        'script/sub/abs' => "#!/usr/bin/perl\n",
        't/a.t'          => "#!/usr/bin/env perl\nuse Test2::V0;\n",
        't/data/x.sh'    => "#!/bin/sh\n",
        't/data/plain'   => "no shebang\n",
        'lib/Foo.pm'     => "#!/usr/bin/env perl\npackage Foo;\n",
    );
    is( check_of($root), [ 'fail', 'do not start with #!perl: bin/env, script/sub/abs, t/a.t' ], 'each Perl program under the paths at any depth that starts otherwise, and nothing else, and nothing outside them' );
    is( check_of( $root, { paths => [qw{bin lib/Foo.pm absent}] } ), [ 'fail', 'do not start with #!perl: bin/env, lib/Foo.pm' ], 'paths can name a file, and one that is absent is skipped' );
    is( check_of( $root, {}, SHEBANG => '#!/usr/bin/env perl' ), [ 'fail', 'do not start with #!/usr/bin/env perl: bin/good, script/sub/abs' ], 'the shebang is the variable, so a repository can choose env perl' );
    is( check_of( Fixture::checkout( 'bin/good' => "#!perl\n" ) ), [ 'pass', 'every Perl program starts with #!perl' ], 'a repository whose programs all start with it passes' );
    is( check_of( Fixture::checkout() ),                           [ 'pass', 'every Perl program starts with #!perl' ], 'and so does one with none' );

    my $linked = Fixture::checkout( 'bin/real' => "#!perl\n", 'elsewhere' => "#!/usr/bin/env perl\n" );
    symlink '../elsewhere', $linked->child(qw{bin link}) or die "Cannot symlink: $!";
    is( check_of($linked), [ 'pass', 'every Perl program starts with #!perl' ], 'a symbolic link is not judged by what it points at' );

    my $snapshot = Dist::Conformance::Snapshot::Directory->new( root => $root );
    is( dies { Fixture::make_check( Dist::Conformance::Check::Shebangs::, \%CONFIG )->check($snapshot) },                       "shebang needs the variables SHEBANG in .conformance.yml: nothing sets them\n",  'a shebang whose variable nothing sets dies, naming it' );
    is( dies { Fixture::make_check( Dist::Conformance::Check::Shebangs::, { shebang => '#!/bin/sh' } )->check($snapshot) },      "shebang is #!/bin/sh, which is no shebang line that names perl\n",              'and so does one that does not name perl' );
    like( dies { Fixture::make_check( Dist::Conformance::Check::Shebangs::, {} ) }, qr{/shebang:\ Missing\ property}, 'shebang is required' );
};

subtest update => sub {
    my $root = Fixture::checkout(
        'bin/env'  => "#!/usr/bin/env perl\nprint 1;\n",
        'bin/good' => "#!perl\n",
        'bin/bare' => '#!/usr/bin/perl',
        'bin/t'    => "#!/usr/bin/perl -T\nprint 1;\n",
    );
    chmod 0755, $root->child(qw{bin env}) or die "Cannot chmod: $!";
    my $update = Fixture::run_update( shebangs(), $root );
    is( $update->changes, [ map { { action => 'replace', path => $_ } } qw{bin/bare bin/env} ], 'each program that starts otherwise is rewritten' );
    is( $root->child(qw{bin env})->slurp,               "#!perl\nprint 1;\n",                                                  'its first line is replaced, and the rest stays' );
    is( $root->child(qw{bin bare})->slurp,              "#!perl\n",                                                            'a program of one line without a newline gets one' );
    is( sprintf( '%o', $root->child(qw{bin env})->stat->mode & oct 7777 ), '755',                                                                  'and it stays executable' );
    is( $root->child(qw{bin t})->slurp,                 "#!/usr/bin/perl -T\nprint 1;\n",                                      'a program that passes perl switches is left alone' );
    is( $update->manual,                                ['Start bin/t with #!perl by hand: its first line passes perl -T'],    'and left to a person' );
    is( Fixture::run_update( shebangs(), $root )->changes, [],                                                                 'so a second update has nothing to do' );

    my $dry    = Fixture::checkout( 'bin/env' => "#!/usr/bin/env perl\n" );
    my $before = Fixture::tree_of($dry);
    is( Fixture::run_update( shebangs(), $dry, 1 )->changes, [ { action => 'replace', path => 'bin/env' } ], 'a dry run says what it would rewrite' );
    is( Fixture::tree_of($dry),                              $before,                                         'and changes nothing on disk' );
};

done_testing;

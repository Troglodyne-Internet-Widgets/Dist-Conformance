#!/usr/bin/env perl
use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Test2::V0;
use Test2::Plugin::NoWarnings;
use FindBin::libs;

use Fixture();
use Dist::Conformance::Check::PerlSlopConfig();
use Dist::Conformance::Snapshot::Directory();

my %CONFIG = (
    file   => '.perl-slop.json',
    schema => { type => 'object', additionalProperties => 0, properties => { before_edit => { type => 'object' }, before_commit => { type => 'object' } } },
);

sub config_check (%config)          { return Fixture::make_check( Dist::Conformance::Check::PerlSlopConfig::, { %CONFIG, %config } ) }
sub check_of     ( $root, %config ) { return [ config_check(%config)->check( Dist::Conformance::Snapshot::Directory->new( root => $root ) ) ] }

subtest check => sub {
    is( check_of( Fixture::checkout() ),                                                              [ 'info', 'there is no .perl-slop.json' ],                                    'an absent file is info' );
    is( check_of( Fixture::checkout(), missing => 'fail' ),                                           [ 'fail', 'there is no .perl-slop.json' ],                                    'or what the flavor says' );
    is( check_of( Fixture::checkout( '.perl-slop.json' => '{"before_edit":' ) ),                      [ 'fail', match(qr/\A[.]perl-slop[.]json\ does\ not\ parse\ as\ JSON/) ],     'a file that does not parse fails' );
    is( check_of( Fixture::checkout( '.perl-slop.json' => '[]' ) ),                                   [ 'fail', '.perl-slop.json does not hold an object at its top level' ],       'and so does one that is not an object' );
    is( check_of( Fixture::checkout( '.perl-slop.json' => '{"before_edit":{},"before_comit":{}}' ) ), [ 'fail', match(qr/schema:\ \/:\ Properties\ not\ allowed:\ before_comit/) ], 'a misspelled key fails, and is named' );
    is( check_of( Fixture::checkout( '.perl-slop.json' => '{"before_edit":[]}' ) ),                   [ 'fail', match(qr/\/before_edit:\ Expected\ object/) ],                      'and so does a value of the wrong type' );
    is( check_of( Fixture::checkout( '.perl-slop.json' => '{"before_edit":{"lib/":["x"]}}' ) ),       [ 'pass', 'valid' ],                                                          'a file that matches passes' );
};

subtest update => sub {
    my $root   = Fixture::checkout( '.perl-slop.json' => '{"typo":1}' );
    my $before = Fixture::tree_of($root);
    my $update = Fixture::run_update( config_check(), $root );
    is( $update->changes,                                                   [],                                                              'nothing is written' );
    is( Fixture::tree_of($root),                                            $before,                                                         'at all' );
    is( $update->manual,                                                    [ match(qr/typo.*:\ PerlSlopConfig\ has\ no\ automatic\ fix/) ], 'and a person is told what is wrong' );
    is( Fixture::run_update( config_check(), Fixture::checkout() )->manual, [],                                                              'an absent optional file needs nothing' );
};

done_testing;

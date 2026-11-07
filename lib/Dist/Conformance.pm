package Dist::Conformance;

# ABSTRACT: Whether the development harness of a repository conforms to its standards, and bringing it up to date

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base -base, -signatures;

use List::Util();
use Module::Runtime();
use Mojo::File();

use Dist::Conformance::Check();
use Dist::Conformance::Config();
use Dist::Conformance::Flavor();
use Dist::Conformance::Schema();
use Dist::Conformance::Snapshot::Directory();
use Dist::Conformance::Source::Directory();
use Dist::Conformance::Source::Git();
use Dist::Conformance::Update();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance;

    my $conformance = Dist::Conformance->new( root => '/bogus/checkout' );
    for my $result ( @{ $conformance->check } ) {
        say join "\t", @{$result}{qw{status check detail}};
    }

    my $plan = $conformance->update( dry_run => 1 );
    say "$_->{action} $_->{path}" for map { @{ $_->{changes} } } @$plan;

=head1 DESCRIPTION

Dist::Conformance answers one question about a repository: does its
development harness conform to the standards of an organization, and if not,
can the tool bring it up to date?

The harness is everything around the code that makes working on it safe: the
agent's instructions in F<CLAUDE.md>, the perlcritic profile and the
configuration of the other tools, the git hooks that run them, the files that
the build needs, and the Claude Code settings that load the right plugin.

Four pieces answer the question:

=over

=item The standards

A tree of flavor files and templates, in a git repository that is fetched into
a cache, or in a directory.  See L<Dist::Conformance::Source>, and the layout
in L<Dist::Conformance::Flavor/THE STANDARDS REPOSITORY>.

=item A flavor

A named set of checks with their configuration, which builds on other flavors
with C<extends>.  There is one for each kind of repository: a distribution on a
perl you control, one on an installed perl, a deployed service.  See
L<Dist::Conformance::Flavor>.

=item The choice of the repository

F<.conformance.yml> at the root of the repository names its flavor and source,
the checks it skips, and what it sets differently.  See
L<Dist::Conformance::Config>.

=item The checks

One module for each question, each told by its configuration what to expect.
Each can check a snapshot of a repository, local or remote, and update a local
checkout.  See L<Dist::Conformance::Check>, which also says how to write one.

=back

The program L<conformance> runs all of this from the shell.

=attr root

The directory of a checkout.  Required unless L</snapshot> is given; L</update>
needs it.

=attr snapshot

The L<Dist::Conformance::Snapshot> to check.  Default a
L<Dist::Conformance::Snapshot::Directory> of L</root>.  For a repository that
is not on this machine, pass a L<Dist::Conformance::Snapshot::Tree>.

=attr config

The validated F<.conformance.yml>.  Default the file of the snapshot.  A caller
that has the configuration from somewhere else passes it through
L<Dist::Conformance::Config/validate>.

=attr cache

The cache directory of a git source.  Default as
L<Dist::Conformance::Source::Git/cache> says.

=attr offline

When true, a git source is not fetched, and its cached copy is used.

=attr standards

A directory that replaces the C<git> or the C<directory> of the source, and
keeps its C<path>, such as a checkout of the standards that you are editing.

=attr source

The L<Dist::Conformance::Source>.  Default built from the configuration and
the attributes above.

=attr flavor

The L<Dist::Conformance::Flavor>, loaded from the source.

=cut

has 'root';
has snapshot => sub ($self) {
    die "Dist::Conformance needs a root or a snapshot\n" if !defined $self->root;
    return Dist::Conformance::Snapshot::Directory->new( root => $self->root );
};
has config => sub ($self) { Dist::Conformance::Config::load( $self->snapshot ) };
has 'cache';
has offline => 0;
has 'standards';
has source => sub ($self) { $self->build_source };
has flavor => sub ($self) { Dist::Conformance::Flavor->load( $self->source, $self->config->{flavor} ) };

=method build_source

The source that the C<source> key of the configuration describes, with
L</standards>, L</cache> and L</offline> applied.

=cut

sub build_source ($self) {
    my $config = $self->config->{source};
    my %path   = ( path => $config->{path} // q{} );
    if ( defined $self->standards ) {
        return Dist::Conformance::Source::Directory->new( directory => $self->standards, %path );
    }
    if ( defined $config->{git} ) {
        my %options = ( url => $config->{git}, offline => $self->offline, %path );
        $options{ref}   = $config->{ref} if defined $config->{ref};
        $options{cache} = $self->cache   if defined $self->cache;
        return Dist::Conformance::Source::Git->new(%options);
    }
    my $directory = Mojo::File->new( $config->{directory} );
    $directory = Mojo::File->new( $self->root )->child( $config->{directory} ) if !$directory->is_abs && defined $self->root;
    return Dist::Conformance::Source::Directory->new( directory => "$directory", %path );
}

=method skipped

The names of the checks that F<.conformance.yml> skips, as a hash reference.
Dies when it skips or configures a check that the flavor does not run.

=cut

sub skipped ($self) {
    my $config = $self->config;
    my $flavor = $self->flavor;
    my %runs   = map { $_ => 1 } $flavor->check_names;
    my @wrong  = (
        ( map { "/skip/$_" } grep { !$runs{ $config->{skip}[$_] } } 0 .. $#{ $config->{skip} } ),
        ( map { "/checks/$_" } grep { !$runs{$_} } sort keys %{ $config->{checks} } ),
    );
    if (@wrong) {
        my $name = $flavor->name;
        Dist::Conformance::Schema::refuse( $Dist::Conformance::Config::FILE, map { "$_: names a check that the flavor $name does not run" } @wrong );
    }
    return { map { $_ => 1 } @{ $config->{skip} } };
}

=method checks

The L<Dist::Conformance::Check> objects that run, in order, with the
configuration of the flavor and of F<.conformance.yml> merged and validated.
Memoized.  Dies on a check whose module does not load or is not a check, and on
a configuration that its schema refuses; each message names the check and the
flavor.

=cut

sub checks ($self) {
    return $self->{checks} //= do {
        my $flavor  = $self->flavor;
        my $skipped = $self->skipped;
        my %merged  = %{ $flavor->checks };
        Dist::Conformance::Flavor::merge_checks( \%merged, $self->config->{checks} );
        my %variables = ( %{ $flavor->variables }, %{ $self->config->{variables} } );
        [
            map  { $self->make_check( $_, $merged{$_}, \%variables ) }
            grep { !$skipped->{$_} } $flavor->check_names
        ];
    };
}

=method make_check

C<($name, $config, \%variables)>.  The check C<$name> of the flavor, from its
merged configuration.

=cut

sub make_check ( $self, $name, $config, $variables ) {
    my $flavor = $self->flavor->name;
    my $module = $config->{module} // $name;
    my $class  = index( $module, '::' ) >= 0 ? $module : "Dist::Conformance::Check::$module";
    if ( !Dist::Conformance::Schema::matches( $Dist::Conformance::Check::MODULE, $class ) ) {
        die "The flavor $flavor runs the check $name, but $class is not the name of a module\n";
    }
    if ( !eval { Module::Runtime::require_module($class); 1 } ) {
        die( "The flavor $flavor runs the check $name, but its module $class does not load: " . Dist::Conformance::Schema::first_line($@), "\n" );
    }
    die "The flavor $flavor runs the check $name, but $class is not a Dist::Conformance::Check\n" if !$class->isa('Dist::Conformance::Check');
    my $repo = exists $self->config->{checks}{$name} ? " with $Dist::Conformance::Config::FILE" : q{};
    return $class->from_config(
        name      => $name,
        config    => $config,
        source    => $self->source,
        variables => $variables,
        where     => "the check $name of the flavor $flavor$repo",
    );
}

our %STATUSES = map { $_ => 1 } qw{pass fail info};

=method check

Runs every check of the flavor against the snapshot.  Returns an array
reference of hash references, one for each check of the flavor, in the order of
their names: C<check>, the name; C<status>, which is C<pass>, C<fail>, C<info>,
or C<skip> for a check that F<.conformance.yml> skips; and C<detail>.

A check that dies, or returns a status that is not one of the three, fails, and
its detail says so.  A failure of a check at C<level: info> is reported as
C<info>.

=cut

sub check ($self) {
    my $snapshot = $self->snapshot;
    my %run      = map { $_->name => $_ } @{ $self->checks };
    my @results;
    for my $name ( $self->flavor->check_names ) {
        my $check = $run{$name};
        if ( !$check ) {
            push @results, { check => $name, status => 'skip', detail => "skipped by $Dist::Conformance::Config::FILE" };
            next;
        }
        my ( $status, $detail ) = eval { $check->check($snapshot) };
        if ( !defined $status ) {
            ( $status, $detail ) = ( 'fail', 'the check died: ' . Dist::Conformance::Schema::first_line($@) );
        }
        elsif ( !$STATUSES{$status} ) {
            ( $status, $detail ) = ( 'fail', "the check returned the status $status, which is not pass, fail or info" );
        }
        $status = 'info' if $status eq 'fail' && $check->config->{level} eq 'info';
        push @results, { check => $name, status => $status, detail => $detail // q{} };
    }
    return \@results;
}

=method update

C<(%options)>.  Runs the update of every check that is not skipped on the
checkout, after fetching the standards when the source is git.  With
C<< dry_run => 1 >> it writes nothing, and says what it would write.

Returns an array reference of hash references, one for each check that ran, in
order: C<check>, the name; C<changes>, what it changed or would change, each
with an C<action> and a C<path>; and C<manual>, what is left for a person.  A
check whose update dies has the error in C<manual>, and the other checks still
run.

=cut

sub update ( $self, %options ) {
    my @results;
    for my $check ( @{ $self->checks } ) {
        my $update = Dist::Conformance::Update->new( snapshot => $self->snapshot, dry_run => $options{dry_run} // 0 );
        if ( !eval { $check->update($update); 1 } ) {
            $update->by_hand( 'The update died: ' . Dist::Conformance::Schema::first_line($@) );
        }
        push @results, { check => $check->name, changes => $update->changes, manual => $update->manual };
    }
    return \@results;
}

=func failed

C<($results)>.  Whether any result of L</check> failed.

=cut

sub failed ($results) {
    return List::Util::any { $_->{status} eq 'fail' } @$results;
}

=head1 SEE ALSO

L<conformance>

L<Dist::Conformance::Check>

L<Dist::Conformance::Flavor>

L<Dist::Conformance::Config>

L<Dist::Conformance::Snapshot>

L<Dist::Conformance::Source>

=cut

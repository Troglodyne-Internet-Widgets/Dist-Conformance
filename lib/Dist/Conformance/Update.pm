package Dist::Conformance::Update;

# ABSTRACT: What an update changed, or would change, in a checkout, and what it left to a person

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base -base, -signatures;

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Snapshot::Directory;
    use Dist::Conformance::Update;

    my $update = Dist::Conformance::Update->new(
        snapshot => Dist::Conformance::Snapshot::Directory->new( root => '/bogus/checkout' ),
        dry_run  => 1,
    );
    $update->write( '.perltidyrc', "-l=400\n" );
    $update->by_hand('Write the prose of CLAUDE.md');
    say "$_->{action} $_->{path}" for @{ $update->changes };

=head1 DESCRIPTION

A check's C<update> does not write to the checkout itself.  It calls the
methods of this object, which write unless this is a dry run, and keep a record
either way.  So a dry run takes the same path through every check as a real
one, and says what the real one would change.

A check runs with an object of its own, so the record of an update is the
record of one check.

=attr snapshot

Required.  The writable L<Dist::Conformance::Snapshot> to change.

=attr dry_run

When true, nothing is written, and the changes are what would be written.

=attr changes

The changes, in the order they were made: hash references with an C<action>,
which is C<create>, C<replace> or C<install>, and a C<path>.

=attr manual

The things that no check could do, as sentences for a person.

=cut

has 'snapshot';
has dry_run => 0;
has changes => sub { [] };
has manual  => sub { [] };

=method new

Dies unless L</snapshot> is writable.

=cut

sub new ( $class, @args ) {
    my $self     = $class->SUPER::new(@args);
    my $snapshot = $self->snapshot;
    die "An update needs a snapshot that it can write, such as a Dist::Conformance::Snapshot::Directory\n" if !$snapshot || !$snapshot->writable;
    return $self;
}

=method write

C<($path, $bytes, $mode)>.  Writes C<$bytes> to C<$path> in the snapshot, with
C<$mode>, default 0644, and records a C<create> or a C<replace>.  A file that
already has these bytes is left alone, and nothing is recorded, so a second
update after the first has nothing to do.

=cut

sub write ( $self, $path, $bytes, $mode = oct 644 ) {    ## no critic (Subroutines::ProhibitBuiltinHomonyms) -- a method, never called as the builtin
    my $snapshot = $self->snapshot;
    my $old      = $snapshot->content($path);
    return 0                                 if defined $old && $old eq $bytes;
    $snapshot->write( $path, $bytes, $mode ) if !$self->dry_run;
    push @{ $self->changes }, { action => defined $old ? 'replace' : 'create', path => $path };
    return 1;
}

=method install_hook

C<($name, $bytes)>.  Installs C<$bytes> as the git hook C<$name> of the
checkout, and records an C<install> of the hook's path, unless the hook that is
installed has these bytes already.  When the snapshot is not a git checkout, it
records a line for L</manual> instead.

=cut

sub install_hook ( $self, $name, $bytes ) {
    my $snapshot = $self->snapshot;
    my $dir      = $snapshot->hooks_dir;
    if ( !defined $dir ) {
        $self->by_hand( 'Install the hook ' . $name . ': ' . $snapshot->root . ' is not a git checkout' );
        return 0;
    }
    my $installed = $snapshot->installed_hook($name);
    return 0                                 if defined $installed && $installed eq $bytes;
    $snapshot->install_hook( $name, $bytes ) if !$self->dry_run;
    my $hook = $dir->child($name);
    push @{ $self->changes }, { action => 'install', path => $hook->to_rel( $snapshot->root )->to_string };
    return 1;
}

=method by_hand

C<(@sentences)>.  Records what a person has to do, because no check can do it
safely.

=cut

sub by_hand ( $self, @sentences ) {
    push @{ $self->manual }, @sentences;
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut

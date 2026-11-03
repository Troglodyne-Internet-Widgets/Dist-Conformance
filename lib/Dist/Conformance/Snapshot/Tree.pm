package Dist::Conformance::Snapshot::Tree;

# ABSTRACT: A snapshot from a tree listing and a callback that fetches one file

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Snapshot', -signatures;

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Snapshot::Tree;

    my %blobs    = ( 'CLAUDE.md' => "Load perl-slop:reading-perl first.\n" );
    my $snapshot = Dist::Conformance::Snapshot::Tree->new(
        paths => { map { $_ => Dist::Conformance::Snapshot::blob_sha( $blobs{$_} ) } keys %blobs },
        fetch => sub ($path) { $blobs{$path} },
    );

=head1 DESCRIPTION

A snapshot of a repository that is not on this machine.  The caller gives the
listing of a git tree and a sub that fetches the content of one path, for
example from the recursive tree and the contents endpoints of a forge's API.
The checks then fetch only the files that they read.

This snapshot is not writable, so an update cannot run on it.

=attr paths

Required.  A hash reference from each path to its git blob SHA.  A recursive
git tree gives these as the C<path> and the C<sha> of each C<blob> entry.

=attr fetch

Required.  A code reference that takes a path and returns its bytes.  It is
called at most once per path, and only for a path in L</paths>.

=cut

has 'paths';
has 'fetch';

=method new

Dies unless L</paths> is a hash and L</fetch> is code.

=cut

sub new ( $class, @args ) {
    my $self = $class->SUPER::new(@args);
    die "paths must be a hash reference of path => blob SHA\n" if ref $self->paths ne 'HASH';
    die "fetch must be a code reference\n"                     if ref $self->fetch ne 'CODE';
    return $self;
}

=method content

C<($path)>.  The bytes from L</fetch>, memoized for the life of the object;
C<undef> for a path that the tree does not list.

=cut

sub content ( $self, $path ) {
    return undef if !$self->contains($path);
    my $fetched = $self->{fetched} //= {};
    $fetched->{$path} = $self->fetch->($path) if !exists $fetched->{$path};
    return $fetched->{$path};
}

=head1 SEE ALSO

L<Dist::Conformance::Snapshot>

=cut

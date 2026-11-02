package Dist::Conformance::Snapshot;

# ABSTRACT: What a check can read of a repository: its paths, their blob SHAs and their contents

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base -base, -signatures;

use Carp ();
use Digest::SHA();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Snapshot::Directory;

    my $snapshot = Dist::Conformance::Snapshot::Directory->new( root => '/bogus/checkout' );
    say 'has a profile' if $snapshot->contains('.perlcriticrc');
    say $snapshot->sha('git-hooks/pre-commit') // 'no hook';
    my $text = $snapshot->content('CLAUDE.md');

=head1 DESCRIPTION

A check never touches a repository directly.  It reads a snapshot, which
answers two questions: which paths exist, each with its git blob SHA, and what
the content of one path is.  So the same check runs against a local checkout,
through L<Dist::Conformance::Snapshot::Directory>, and against a repository
that only an API can reach, through L<Dist::Conformance::Snapshot::Tree>.

This class is the interface.  A subclass implements L</paths> and L</content>;
everything else here is built on those two.  A snapshot that a check can also
change is I<writable>: L<Dist::Conformance::Snapshot::Directory> is the only one,
and it adds C<write> and C<install_hook>.

Paths are relative to the root of the repository, with C</> between the
components, as git writes them.  A snapshot lists files and symbolic links, not
directories.

=method paths

Returns a hash reference from each path to its git blob SHA, in lowercase hex.
A subclass must implement it.

=cut

sub paths ($self) { Carp::croak( ref($self) . ' does not implement paths' ) }

=method content

C<($path)>.  Returns the bytes of the file at C<$path>, or C<undef> if the
snapshot has no such path.  A subclass must implement it.

=cut

sub content ( $self, $ ) { Carp::croak( ref($self) . ' does not implement content' ) }

=method contains

C<($path)>.  Whether the snapshot has a file at C<$path>.

=cut

sub contains ( $self, $path ) { return exists $self->paths->{$path} }

=method sha

C<($path)>.  The git blob SHA of C<$path>, or C<undef>.

=cut

sub sha ( $self, $path ) { return $self->paths->{$path} }

=method under

C<($directory)>.  The paths inside C<$directory>, at any depth, relative to it
and sorted.

=cut

sub under ( $self, $directory ) {
    my $prefix = "$directory/";
    my @inside = sort map { substr $_, length $prefix } grep { index( $_, $prefix ) == 0 } keys %{ $self->paths };
    return @inside;
}

=method writable

Whether a check can change this snapshot.  False here.

=cut

sub writable ($) { return 0 }

=func blob_sha

C<($bytes)>.  The SHA that git gives a blob with this content, the same as
C<git hash-object> prints.  So a check can compare a template with a file in a
snapshot that it never downloaded.

=cut

sub blob_sha ($bytes) {
    return Digest::SHA::sha1_hex( 'blob ' . length($bytes) . "\0" . $bytes );
}

=head1 WRITING A SNAPSHOT

Subclass this module, and implement L</paths> and L</content>.  Both can be
lazy, and both can memoize, because a snapshot describes one moment of one
repository.  L</has> and L</sha> call L</paths>.  If listing every path costs
much more than looking at one, override them as well.

=head1 SEE ALSO

L<Dist::Conformance::Snapshot::Directory>

L<Dist::Conformance::Snapshot::Tree>

L<Dist::Conformance::Check>

=cut

package Dist::Conformance::Snapshot;

# ABSTRACT: What a check can read of a repository: its paths, their blob SHAs and their contents

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base -base, -signatures;

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

=cut

# Every path of the snapshot, with its git blob SHA.  A subclass must implement
# it.
# @returns HashRef  from each path to its git blob SHA, in lowercase hex
# @throws  when the subclass does not implement it
# @example my $paths = $snapshot->paths;
sub paths ($self) { die( ref($self) . " does not implement paths\n" ) }

# The bytes of the file at the path that it is given.  A subclass must
# implement it.
# @returns Str|Undef  the bytes, or C<undef> if the snapshot has no such path
# @throws  when the subclass does not implement it
# @example my $text = $snapshot->content('CLAUDE.md');
sub content ( $self, $ ) { die( ref($self) . " does not implement content\n" ) }

# Whether the snapshot has a file at C<$path>.
# @param   path  Str  the path
# @returns Bool
# @example say 'has a profile' if $snapshot->contains('.perlcriticrc');
sub contains ( $self, $path ) { return exists $self->paths->{$path} }

# The git blob SHA of C<$path>.
# @param   path  Str  the path
# @returns Str|Undef  the SHA, or C<undef> when the snapshot has no such path
# @example my $sha = $snapshot->sha('git-hooks/pre-commit');
sub sha ( $self, $path ) { return $self->paths->{$path} }

# The paths inside C<$directory>, at any depth, relative to it and sorted.
# @param   directory  Str  the directory, without a trailing C</>
# @returns the paths, as a list
# @example my @workflows = $snapshot->under('.github/workflows');
sub under ( $self, $directory ) {
    my $prefix = "$directory/";
    my @inside = sort map { substr $_, length $prefix } grep { index( $_, $prefix ) == 0 } keys %{ $self->paths };
    return @inside;
}

# Whether a check can change this snapshot.  False here.
# @returns Bool
# @example die "read-only\n" if !$snapshot->writable;
sub writable ($) { return 0 }

=func blob_sha($bytes)

The SHA that git gives a blob with this content, the same as C<git
hash-object> prints.  So a check can compare a template with a file in a
snapshot that it never downloaded.

=over 4

=item bytes - Str - the content of the blob

=back

Returns Str, the SHA, in lowercase hex.

    my $sha = Dist::Conformance::Snapshot::blob_sha("Load perl-slop:reading-perl first.\n");

=cut

sub blob_sha ($bytes) {
    return Digest::SHA::sha1_hex( 'blob ' . length($bytes) . "\0" . $bytes );
}

=head1 WRITING A SNAPSHOT

Subclass this module, and implement L</paths> and L</content>.  Both can be
lazy, and both can memoize, because a snapshot describes one moment of one
repository.  L<contains|/"contains(path)"> and L<sha|/"sha(path)"> call L</paths>.  If listing every path costs
much more than looking at one, override them as well.

=head1 SEE ALSO

L<Dist::Conformance::Snapshot::Directory>

L<Dist::Conformance::Snapshot::Tree>

L<Dist::Conformance::Check>

=cut

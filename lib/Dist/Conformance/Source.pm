package Dist::Conformance::Source;

# ABSTRACT: Where the standards come from: the flavor files and the templates

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base -base, -signatures;

use Dist::Conformance::Schema();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Source::Directory;

    my $source = Dist::Conformance::Source::Directory->new( directory => '/bogus/standards', path => 'skills/packaging-perl' );
    my $flavor_text = $source->file('conformance/troglodyne.yml');

=head1 DESCRIPTION

A source is a directory tree of standards: flavor files under F<conformance/>,
and the templates that they name, at any path the flavor chooses.  This class
is the interface.  L<Dist::Conformance> builds one of its two
implementations from the C<source> key of F<.conformance.yml>:

=over

=item L<Dist::Conformance::Source::Git>

C<< { git => URL, ref => REF, path => PATH } >>.  A git repository, fetched
into a cache directory.

=item L<Dist::Conformance::Source::Directory>

C<< { directory => DIR, path => PATH } >>.  A directory on this machine, read
as it is.  It works offline, and the tests use it.

=back

In both, C<path> is the directory inside the tree that holds F<conformance/>.
Every path that a flavor names, such as a template, is relative to it.
L<Dist::Conformance::Flavor/THE STANDARDS REPOSITORY> describes the layout.

=attr path

The directory inside the tree that the standards start from.  Default the top
of the tree.

=cut

has path => q{};

# The directory of the whole tree.  A subclass must implement it.
# @returns InstanceOf["Mojo::File"]  the directory
# @throws  when the subclass does not implement it
# @example my $top = $source->root;
sub root ($self) { die( ref($self) . " does not implement root\n" ) }

# A short description of the source for a message, such as the URL and the ref.
# A subclass must implement it.
# @returns Str  the description
# @throws  when the subclass does not implement it
# @example say 'Flavor from ', $source->describe;
sub describe ($self) { die( ref($self) . " does not implement describe\n" ) }

# The directory that L</path> names.
# @returns InstanceOf["Mojo::File"]  the directory
# @throws  as L</root> does
# @example my $standards = $source->base;
sub base ($self) {
    my $root = $self->root;
    return $self->path ne q{} ? $root->child( split m{/}, $self->path ) : $root;
}

# The bytes of the file at C<$relative> below L</base>.
# @param   relative  Str  the path of the file, relative to L</base>
# @returns Str  the bytes
# @throws  when there is no such file, and on an absolute path or a path with a
# C<..> component
# @example my $flavor_text = $source->file('conformance/troglodyne.yml');
sub file ( $self, $relative ) {
    Dist::Conformance::Schema::relative_path( $relative, 'the standards' );
    my $file = $self->base->child( split m{/}, $relative );
    die( "The standards at " . $self->describe . " have no $relative\n" ) if !-e $file || -d _;
    return $file->slurp;
}

# Whether L<file|/"file(relative)"> would find C<$relative>.
# @param   relative  Str  the path of the file, relative to L</base>
# @returns Bool
# @throws  as L</root> does
# @example my $has = $source->exists_file('templates/perlcriticrc');
sub exists_file ( $self, $relative ) {
    my $file = $self->base->child( split m{/}, $relative );
    return -e $file && !-d _;
}

=head1 WRITING A SOURCE

Subclass this module and implement L</root> and L</describe>.  L</root> is the
place to fetch, because every read goes through it.

=head1 SEE ALSO

L<Dist::Conformance::Flavor>

=cut

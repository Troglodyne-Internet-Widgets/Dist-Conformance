package Dist::Conformance::Snapshot::Directory;

# ABSTRACT: A snapshot of a checkout on this machine, which an update can change

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Snapshot', -signatures;

use Carp ();
use File::Find();
use File::Slurper::Temp();
use Mojo::File();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Snapshot::Directory;

    my $snapshot = Dist::Conformance::Snapshot::Directory->new( root => '/bogus/checkout' );
    $snapshot->write( '.perltidyrc', "-l=400\n" );
    $snapshot->write( 'git-hooks/pre-commit', "#!/bin/sh\n", 0755 );
    $snapshot->install_hook( 'pre-commit', "#!/bin/sh\n" );

=head1 DESCRIPTION

The working tree of a checkout, as it is on disk now: not the index, and not a
commit.  Nothing is cached, so a check that runs after an update sees what the
update wrote.

L</paths> walks the whole tree except each F<.git>, and hashes every file.
L<Dist::Conformance::Snapshot/contains>, L<Dist::Conformance::Snapshot/sha> and
L</content> look at one file only.

Every path that this class takes is relative to L</root>.  It dies on an
absolute path and on a path with a C<..> component, so that a flavor cannot
make an update write outside the checkout.

=attr root

Required.  The directory of the checkout.

=cut

has 'root';

# What git hashes: the target of a symbolic link, or the content of a file.
my sub bytes_at ($name) {
    return readlink $name if -l $name;
    return Mojo::File->new($name)->slurp;
}

# Mojo::File's to_abs resolves against the working directory, never a base.
my sub relative_to ( $path, $base ) {
    my $file = Mojo::File->new($path);
    return $file->is_abs ? $file : $base->child($path);
}

=method new

Dies unless L</root> is a directory.

=cut

sub new ( $class, @args ) {
    my $self = $class->SUPER::new(@args);
    Carp::croak('root is required')                              if !defined $self->root;
    Carp::croak( 'root ' . $self->root . ' is not a directory' ) if !-d $self->root;
    $self->root( Mojo::File->new( $self->root ) );
    return $self;
}

=method file

C<($path)>.  The L<Mojo::File> of C<$path> under the root.  Dies on a path
that leaves the root.

=cut

sub file ( $self, $path ) {
    Carp::croak("$path is not a relative path inside the checkout") if $path eq q{} || $path =~ m{\A/|(?:\A|/)[.][.](?:/|\z)};
    return $self->root->child( split m{/}, $path );
}

=method paths

Every file and symbolic link below the root, except inside F<.git>, with its
blob SHA.  A symbolic link is hashed as git hashes it, by its target.

=cut

sub paths ($self) {
    my $root = $self->root;
    my %paths;
    File::Find::find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $name = $File::Find::name;
                if ( $_ =~ m{(?:\A|/)[.]git\z} ) {
                    $File::Find::prune = 1;
                    return;
                }
                return if !-l $name && -d _;
                my $relative = Mojo::File->new($name)->to_rel($root)->to_string;
                $paths{$relative} = Dist::Conformance::Snapshot::blob_sha( bytes_at($name) );
            },
        },
        "$root",
    );
    return \%paths;
}

=method contains

C<($path)>.  Whether C<$path> is a file or a symbolic link.

=cut

sub contains ( $self, $path ) {
    my $file = $self->file($path);
    return -l $file || ( -e _ && !-d _ );
}

=method sha

C<($path)>.  The blob SHA of the one file, or C<undef>.

=cut

sub sha ( $self, $path ) {
    return undef if !$self->contains($path);
    return Dist::Conformance::Snapshot::blob_sha( bytes_at( $self->file($path) ) );
}

=method content

C<($path)>.  The bytes of the file, or C<undef>.  For a symbolic link, the
bytes of what it points at.

=cut

sub content ( $self, $path ) {
    my $file = $self->file($path);
    return undef if !-e $file || -d _;
    return $file->slurp;
}

=method writable

True.

=cut

sub writable ($) { return 1 }

=method write

C<($path, $bytes, $mode)>.  Writes C<$bytes> to C<$path> through a temporary
file and a rename, so that no reader sees half a file.  Makes the missing
directories.  C<$mode> defaults to 0644.

=cut

sub write ( $self, $path, $bytes, $mode = oct 644 ) {    ## no critic (Subroutines::ProhibitBuiltinHomonyms) -- the method of a writable snapshot, never called as the builtin
    my $file = $self->file($path);
    $file->dirname->make_path;
    File::Slurper::Temp::write_binary( "$file", $bytes );
    chmod $mode, "$file" or Carp::croak("Cannot chmod $file: $!");
    return $file;
}

=method hooks_dir

The directory that git runs the hooks of this checkout from, or C<undef> when
the root is not a checkout.  In a worktree that is the F<hooks> of the main
checkout.  C<core.hooksPath> is not read.

=cut

sub hooks_dir ($self) {
    my $dot_git = $self->root->child('.git');
    return $dot_git->child('hooks') if -d $dot_git;
    return undef                    if !-e $dot_git;
    my ($gitdir) = $dot_git->slurp =~ m{\Agitdir:\ *(.+?)\s*\z};
    return undef if !defined $gitdir;
    $gitdir = relative_to( $gitdir, $self->root );
    my $common = $gitdir->child('commondir');
    return $gitdir->child('hooks') if !-e $common;
    ( my $relative = $common->slurp ) =~ s/\s+\z//;
    return relative_to( $relative, $gitdir )->child('hooks');
}

=method installed_hook

C<($name)>.  The bytes of the hook C<$name> that git runs now, or C<undef>.

=cut

sub installed_hook ( $self, $name ) {
    my $dir  = $self->hooks_dir // return undef;
    my $hook = $dir->child($name);
    return -e $hook ? $hook->slurp : undef;
}

=method install_hook

C<($name, $bytes)>.  Writes the hook C<$name> into L</hooks_dir>, executable.
Dies when the root is not a checkout.

=cut

sub install_hook ( $self, $name, $bytes ) {
    Carp::croak("$name is not a hook name") if $name !~ m{\A[[:lower:]][[:lower:]-]*\z};
    my $dir = $self->hooks_dir // Carp::croak( $self->root . ' is not a git checkout' );
    $dir->make_path;
    my $hook = $dir->child($name);
    File::Slurper::Temp::write_binary( "$hook", $bytes );
    chmod oct 755, "$hook" or Carp::croak("Cannot chmod $hook: $!");
    return $hook;
}

=head1 SEE ALSO

L<Dist::Conformance::Snapshot>

=cut

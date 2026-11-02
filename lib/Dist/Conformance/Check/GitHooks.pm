package Dist::Conformance::Check::GitHooks;

# ABSTRACT: The git hooks are tracked, match their templates, and are installed

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();
use Dist::Conformance::Snapshot();

=head1 SYNOPSIS

    checks:
      GitHooks:
        directory: git-hooks
        hooks:
          pre-commit: templates/pre-commit
          post-commit: templates/post-commit
        differ: info
        replace: false
        install: true

=head1 DESCRIPTION

Git neither versions nor clones hooks, so the hooks of the harness are tracked
in a directory of the repository, and each clone installs them.

The check fails when a hook is missing from C<directory>.  It reports C<differ>
when a hook is there and its blob SHA differs from the SHA of its template:
the repository customized it, or it is older.  Otherwise it passes.  It compares
SHAs, so it reads no hook from a remote snapshot.

The update writes each missing hook from its template, executable.  It
overwrites a hook that differs only when C<replace> is true.  Then, when
C<install> is true, it installs each hook into F<.git/hooks> of the checkout,
or of the main checkout of a worktree, unless the installed hook is the same.
The check cannot see F<.git/hooks>, so a clone that never installed them passes
the check and still gets them from the update.

=head1 CONFIGURATION

=over

=item directory

Required.  The directory of the repository that holds the hooks.

=item hooks

Required.  A mapping from each hook name, such as C<pre-commit>, to its
template.

=item differ

The status of a hook that differs from its template.  Default C<info>.

=item replace

Whether an update overwrites a hook that differs.  Default false.

=item install

Whether an update installs the hooks into the checkout.  Default true.

=back

=cut

sub config_schema ($) {
    return {
        required   => [qw{directory hooks}],
        properties => {
            directory => $Dist::Conformance::Schema::PATH,
            hooks     => { type => 'object', additionalProperties => $Dist::Conformance::Schema::PATH },
            differ    => { %$Dist::Conformance::Schema::STATUS, default => 'info' },
            replace   => { type => 'boolean', default => 0 },
            install   => { type => 'boolean', default => 1 },
        },
    };
}

=method hook_path

C<($name)>.  The path of the hook C<$name> in the repository.

=cut

sub hook_path ( $self, $name ) { return $self->config->{directory} . "/$name" }

=method check

=cut

sub check ( $self, $snapshot ) {
    my $hooks   = $self->config->{hooks};
    my @names   = sort keys %$hooks;
    my @missing = $self->missing( $snapshot, map { $self->hook_path($_) } @names );
    return ( 'fail', 'missing: ' . join ', ', @missing ) if @missing;
    my @differ = grep { $snapshot->sha( $self->hook_path($_) ) ne Dist::Conformance::Snapshot::blob_sha( ( $self->template( $hooks->{$_} ) )[0] ) } @names;
    return ( $self->config->{differ}, 'customized or outdated: ' . join ', ', map { $self->hook_path($_) } @differ ) if @differ;
    return ( 'pass', 'match the templates' );
}

=method update

Writes the missing hooks, replaces those that differ if C<replace>, and
installs them if C<install>.

=cut

sub update ( $self, $update ) {
    my ( $hooks, $replace, $install ) = @{ $self->config }{qw{hooks replace install}};
    my $snapshot = $update->snapshot;
    for my $name ( sort keys %$hooks ) {
        my $path   = $self->hook_path($name);
        my ($text) = $self->template( $hooks->{$name} );
        my $have   = $snapshot->content($path);
        if ( !defined $have || ( $replace && $have ne $text ) ) {
            $have = $text if $self->write_template( $update, $path, $hooks->{$name}, oct 755 );
        }
        $update->install_hook( $name, $have ) if $install && defined $have;
    }
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut

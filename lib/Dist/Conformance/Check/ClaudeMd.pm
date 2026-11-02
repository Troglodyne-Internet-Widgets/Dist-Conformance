package Dist::Conformance::Check::ClaudeMd;

# ABSTRACT: CLAUDE.md exists and names the skills that it must

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();

=head1 SYNOPSIS

    checks:
      ClaudeMd:
        file: CLAUDE.md
        template: templates/CLAUDE.md
        mentions:
          - perl-slop:reading-perl

=head1 DESCRIPTION

The instructions that an agent reads first.  The check passes when the file
exists and contains each string of C<mentions>.  It fails when the file is
missing, or when a string is not in it.

Its update writes nothing.  What the file says about a repository is prose that
a person writes, so the update names the file, the template to start from, and
what the file lacks.

=head1 CONFIGURATION

=over

=item file

Required.  The path of the file.

=item mentions

Required.  The strings that the file must contain, such as the names of the
skills that it tells an agent to load.  An empty list asks only that the file
exist.

=item template

The template that a person starts from, named in the update.

=back

=cut

sub config_schema ($) {
    return {
        required   => [qw{file mentions}],
        properties => {
            file     => $Dist::Conformance::Schema::PATH,
            mentions => { type => 'array', items => { type => 'string', minLength => 1 } },
            template => $Dist::Conformance::Schema::PATH,
        },
    };
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my ( $file, $mentions ) = @{ $self->config }{qw{file mentions}};
    my $text   = $snapshot->content($file) // return ( 'fail', "$file is missing" );
    my @absent = grep { index( $text, $_ ) < 0 } @$mentions;
    return ( 'fail', "$file does not name " . join ', ', @absent ) if @absent;
    return ( 'pass', @$mentions ? 'names ' . join ', ',  @$mentions : "$file exists" );
}

=method update

Records what the file needs, for a person.

=cut

sub update ( $self, $update ) {
    my ( $status, $detail ) = $self->check( $update->snapshot );
    return if $status ne 'fail';
    my $start = defined $self->config->{template} ? ', starting from ' . $self->config->{template} : q{};
    $update->by_hand("$detail: write it by hand$start, because its prose cannot be generated");
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut

package Dist::Conformance::Check::CriticProfile;

# ABSTRACT: The perlcritic profile enables or turns off every policy of its template

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Config::Tiny();

use Dist::Conformance::Schema();

=head1 IN A FLAVOR

    checks:
      CriticProfile:
        file: .perlcriticrc
        template: templates/perlcriticrc
        replace: false

=head1 DESCRIPTION

A profile is compared with its template by the policies that each names.  Both
are read as Perl::Critic reads a profile, with L<Config::Tiny>: each section
C<[Name]> enables the policy C<Name>, a section C<[-Name]> turns it off, and the
keys before the first section are global settings.  A name with the prefix
C<Perl::Critic::Policy::> is the same policy as the name without it.

The check passes when the file names each policy that the template enables,
either as C<[Name]>, which enables it, or as C<[-Name]>, which turns it off on
purpose.  It fails when the file is missing, when it does not parse, and when
it does not name a policy that the template enables.  The detail names each
such policy.  So when the template gains a policy, every profile that does not
have it yet fails, by the name of that policy.

What else the file says is the distribution's own business, and does not
change the result:

=over

=item the parameters of a policy

A policy that the template configures, and the file configures differently or
not at all, is there.  An exemption or a threshold of its own is a choice of
the distribution, not a policy that it lacks.

=item a policy that the template does not enable

A policy of the distribution's own, or one that the template has dropped or
turns off, can stay.

=item the global settings and the comments

The first line among them, so a header says nothing about whether a profile
is current.

=back

The update writes the template when the file is missing.  A profile that is
there usually has changes of its own, such as exemptions, so it is replaced
only when C<replace> is true; otherwise the update names the policies to add
by hand.

=head1 CONFIGURATION

=over

=item file

Required.  The path of the profile.

=item template

Required.  The template of the current profile.

=item replace

Whether an update overwrites a profile that is not current.  Default false.

=item header

=item outdated

Deprecated, and ignored.  Each named a first line to compare, which the check
no longer does.  They are accepted so that a flavor that names them still
loads.

=back

=cut

sub config_schema ($) {
    return {
        required   => [qw{file template}],
        properties => {
            file     => $Dist::Conformance::Schema::PATH,
            template => $Dist::Conformance::Schema::PATH,
            replace  => { type => 'boolean', default   => 0 },
            header   => { type => 'string',  minLength => 1 },
            outdated => { type => 'array',   items     => { type => 'string', minLength => 1 } },
        },
    };
}

=func policies

C<($text, $where)>.  The policies of the profile C<$text>, as a hash reference
from the short name of each to C<enabled> or C<disabled>.  Dies, naming
C<$where>, when Perl::Critic could not parse the text either.

=cut

sub policies ( $text, $where ) {
    my $profile = Config::Tiny->read_string($text) // die( "$where does not parse as a perlcritic profile: " . Config::Tiny->errstr . "\n" );
    my %policies;
    for my $section ( grep { $_ ne q{_} } keys %$profile ) {
        my ( $off, $name ) = $section =~ m/\A(-?)(?:Perl::Critic::Policy::)?(.+)\z/;
        $policies{$name} = $off ? 'disabled' : 'enabled';
    }
    return \%policies;
}

=method missing_policies

C<($text)>.  The sorted names of the policies that the template enables and
the profile C<$text> does not name.  Dies when either does not parse.

=cut

sub missing_policies ( $self, $text ) {
    my ( $file, $template ) = @{ $self->config }{qw{file template}};
    my $want    = policies( ( $self->template($template) )[0], $template );
    my $have    = policies( $text,                             $file );
    my @missing = sort grep { $want->{$_} eq 'enabled' && !exists $have->{$_} } keys %$want;
    return @missing;
}

=func lacks

C<(@missing)>.  The detail for a profile that lacks the policies C<@missing>,
without the template.

=cut

sub lacks (@missing) {
    return 'lacks the ' . ( @missing == 1 ? 'policy ' : 'policies ' ) . join ', ', @missing;
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my ( $file, $template ) = @{ $self->config }{qw{file template}};
    my $text    = $snapshot->content($file) // return ( 'fail', "$file is missing" );
    my @missing = eval { $self->missing_policies($text) };
    return ( 'fail', Dist::Conformance::Schema::first_line($@) ) if $@;
    return ( 'pass', "has every policy of $template" )           if !@missing;
    return ( 'fail', lacks(@missing) . " of $template" );
}

=method update

Writes the template when the profile is missing, or when it is not current and
C<replace> is true.  Otherwise names what to add by hand.

=cut

sub update ( $self, $update ) {
    my ( $file, $template ) = @{ $self->config }{qw{file template}};
    my $text = $update->snapshot->content($file);
    if ( defined $text && !$self->config->{replace} ) {
        my @missing = eval { $self->missing_policies($text) };
        if ($@) {
            $update->by_hand( Dist::Conformance::Schema::first_line($@) . ': fix it by hand, or set replace: true to overwrite it' );
        }
        elsif (@missing) {
            $update->by_hand( "$file " . lacks(@missing) . " of $template: add each one to it by hand, or add it as [-Name] to turn it off on purpose, or set replace: true to overwrite it" );
        }
        return;
    }
    my ($status) = $self->check( $update->snapshot );
    $self->write_template( $update, $file, $template ) if $status ne 'pass';
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut

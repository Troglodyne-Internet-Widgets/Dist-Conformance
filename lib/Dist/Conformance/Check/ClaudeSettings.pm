package Dist::Conformance::Check::ClaudeSettings;

# ABSTRACT: .claude/settings.json enables the plugins of the harness

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Cpanel::JSON::XS();

use Dist::Conformance::Schema();

=head1 IN A FLAVOR

    checks:
      ClaudeSettings:
        file: .claude/settings.json
        missing: info
        plugins:
          - perl-slop@troglodyne-marketplace

=head1 DESCRIPTION

Claude Code loads a plugin for a repository when the project settings enable
it, under C<enabledPlugins>, as C<plugin@marketplace>.  The check passes when
the file enables each plugin of C<plugins>.  It reports C<missing> when the
file is absent or does not enable one, and fails when the file does not parse
as a JSON object, which Claude Code would not read either.

The update writes the file when it is absent, and sets each plugin to C<true>
in C<enabledPlugins> when it is there.  It keeps every other key of the file,
and writes it with sorted keys and an indent of two.  A file that does not
parse is left for a person.

=head1 CONFIGURATION

=over

=item file

Required.  The path of the settings.

=item plugins

Required.  The plugins to enable, each as C<plugin@marketplace>.

=item missing

The status when the file is absent or does not enable a plugin.  Default
C<fail>.

=back

=cut

sub config_schema ($) {
    return {
        required   => [qw{file plugins}],
        properties => {
            file    => $Dist::Conformance::Schema::PATH,
            plugins => { type => 'array', items => { type => 'string', pattern => '\A[^@\s]+@[^@\s]+\z' } },
            missing => { %$Dist::Conformance::Schema::STATUS, default => 'fail' },
        },
    };
}

=method settings

C<($snapshot)>.  The parsed settings, C<undef> when the file is absent.  Dies
when it does not parse.

=cut

sub settings ( $self, $snapshot ) {
    my $file = $self->config->{file};
    my $text = $snapshot->content($file) // return undef;
    return Dist::Conformance::Schema::parse_json( $text, $file );
}

=method disabled

C<($settings)>.  The plugins that C<$settings> does not enable.

=cut

sub disabled ( $self, $settings ) {
    my $enabled  = ref $settings->{enabledPlugins} eq 'HASH' ? $settings->{enabledPlugins} : {};
    my @disabled = grep { !$enabled->{$_} } @{ $self->config->{plugins} };
    return @disabled;
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my ( $file, $missing ) = @{ $self->config }{qw{file missing}};
    my $settings = eval { $self->settings($snapshot) };
    return ( 'fail',   Dist::Conformance::Schema::first_line($@) ) if $@;
    return ( $missing, "$file is missing" )                        if !$settings;
    my @disabled = $self->disabled($settings);
    return ( $missing, 'does not enable ' . join ', ', @disabled ) if @disabled;
    return ( 'pass',   'enables ' . join ', ',         @{ $self->config->{plugins} } );
}

=method update

Writes the settings, or enables the plugins in them.

=cut

sub update ( $self, $update ) {
    my $settings = eval { $self->settings( $update->snapshot ) };
    if ($@) {
        $update->by_hand( Dist::Conformance::Schema::first_line($@) . ': fix it by hand' );
        return;
    }
    $settings //= {};
    my @disabled = $self->disabled($settings);
    return if !@disabled;
    $settings->{enabledPlugins}     = {} if ref $settings->{enabledPlugins} ne 'HASH';
    $settings->{enabledPlugins}{$_} = Cpanel::JSON::XS::true() for @disabled;
    $update->write( $self->config->{file}, Dist::Conformance::Schema::encode_json($settings) );
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut

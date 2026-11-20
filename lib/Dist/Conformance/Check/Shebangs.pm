package Dist::Conformance::Check::Shebangs;

# ABSTRACT: Every Perl program starts with the shebang line of the standards

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();
use Dist::Conformance::Snapshot();

=head1 IN A FLAVOR

    variables:
      SHEBANG: '#!perl'
    checks:
      Shebangs:
        shebang: '{{SHEBANG}}'
        paths:
          - bin
          - script
          - t

=head1 DESCRIPTION

A Perl program is a file whose first line is a shebang line that names perl:
C<#!perl>, C<#!/usr/bin/perl>, C<#!/usr/bin/env perl> or the path of any other
perl.  The check reads each file in C<paths>, and fails when a program there
starts with a line other than C<shebang>.  The detail names each such file.

The shebang line decides which perl runs an installed program.  When
ExtUtils::MakeMaker or Module::Build installs a program, it replaces a first
line that names C<perl>, such as C<#!perl> or C<#!/usr/bin/perl>, with the
path of the perl that installs it.  That perl has the modules that the program
needs.  It leaves C<#!/usr/bin/env perl> alone, because the interpreter there
is C<env>.  So that program runs the first perl on the C<PATH> of whoever
starts it, and that perl can lack the modules.  A shebang line of C<#!perl>,
though, works only after the install: a program run from a checkout with it
fails.  A repository whose programs run from its checkout sets the variable
of C<shebang> to C<#!/usr/bin/env perl> in F<.conformance.yml>.

A symbolic link is not judged: what it points at is judged where it is.

The update replaces the first line of each such program with C<shebang>, and
keeps the mode of the file.  A program whose first line passes perl switches,
such as C<-T>, is left to a person, because the switches change how perl runs
it.

=head1 CONFIGURATION

=over

=item shebang

Required.  The first line of every Perl program, without the newline, which
must name perl.  Its placeholders are filled from the variables, so a
repository can set it in F<.conformance.yml>.

=item paths

The paths to read: a directory, whose files at any depth are read, or a file.
A path that the repository does not have is skipped.  Default C<bin>,
C<script> and C<t>.

=back

=cut

sub config_schema ($) {
    return {
        required   => ['shebang'],
        properties => {
            shebang => { type => 'string', minLength => 1 },
            paths   => { type => 'array', items => $Dist::Conformance::Schema::PATH, uniqueItems => 1, default => [qw{bin script t}] },
        },
    };
}

=func switches_of

C<($line)>.  For a shebang line C<$line> that names perl, the switches after
perl, or the empty string when it has none.  C<undef> for any other line.

=cut

sub switches_of ($line) {
    my ($switches) = $line =~ m{\A \#! \s* (?: \S*/ )? (?: env \s+ )? perl [\d.]* ( (?: \s+ \S+ )* ) \s* \z};
    return undef if !defined $switches;
    return $switches =~ s/\A\s+//r;
}

=method shebang

The line that every program must start with, its placeholders filled.  Dies
when a placeholder has no variable, or when the line does not name perl.

=cut

sub shebang ($self) {
    my ( $line, @unfilled ) = $self->fill( $self->config->{shebang} );
    die( 'shebang needs the variables ' . join( ', ', @unfilled ) . " in .conformance.yml: nothing sets them\n" ) if @unfilled;
    die("shebang is $line, which is no shebang line that names perl\n")                                          if !defined switches_of($line);
    return $line;
}

=method astray

C<($snapshot)>.  The sorted paths of the programs in C<paths> that do not
start with L</shebang>, as a hash reference from each path to the switches
that its first line passes perl.

=cut

sub astray ( $self, $snapshot ) {
    my $want = $self->shebang;
    my @paths;
    for my $path ( @{ $self->config->{paths} } ) {
        push @paths, $path, map {"$path/$_"} $snapshot->under($path);
    }
    my %astray;
    for my $path ( grep { $snapshot->contains($_) } @paths ) {
        my $content = $snapshot->content($path) // next;

        # A link's content is what it points at, whose sha is not the link's own.
        next if Dist::Conformance::Snapshot::blob_sha($content) ne $snapshot->sha($path);
        my ($first) = split /\n/, $content, 2;
        next if !defined $first || $first eq $want;
        my $switches = switches_of($first) // next;
        $astray{$path} = $switches;
    }
    return \%astray;
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my $astray = $self->astray($snapshot);
    my $want   = $self->shebang;
    return ( 'pass', "every Perl program starts with $want" ) if !%$astray;
    return ( 'fail', 'do not start with ' . $want . ': ' . join ', ', sort keys %$astray );
}

=method update

Replaces the first line of each program that L</check> names, unless it
passes perl switches.

=cut

sub update ( $self, $update ) {
    my $snapshot = $update->snapshot;
    my $astray   = $self->astray($snapshot);
    my $want     = $self->shebang;
    for my $path ( sort keys %$astray ) {
        if ( $astray->{$path} ne q{} ) {
            $update->by_hand("Start $path with $want by hand: its first line passes perl $astray->{$path}");
            next;
        }
        my ( undef, $rest ) = split /\n/, $snapshot->content($path), 2;
        $update->write( $path, "$want\n" . ( $rest // q{} ), $snapshot->mode($path) );
    }
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

L<ExtUtils::MakeMaker/EXE_FILES>

=cut

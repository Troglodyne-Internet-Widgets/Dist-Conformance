# NAME

Dist::Conformance - Whether the development harness of a repository conforms to its standards, and bringing it up to date

# VERSION

version 0.004

# SYNOPSIS

```perl
use 5.040;
use Dist::Conformance;

my $conformance = Dist::Conformance->new( root => '/bogus/checkout' );
for my $result ( @{ $conformance->check } ) {
    say join "\t", @{$result}{qw{status check detail}};
}

my $plan = $conformance->update( dry_run => 1 );
say "$_->{action} $_->{path}" for map { @{ $_->{changes} } } @$plan;
```

# DESCRIPTION

Dist::Conformance answers one question about a repository: does its
development harness conform to the standards of an organization, and if not,
can the tool bring it up to date?

The harness is everything around the code that makes working on it safe: the
agent's instructions in `CLAUDE.md`, the perlcritic profile and the
configuration of the other tools, the git hooks that run them, the files that
the build needs, and the Claude Code settings that load the right plugin.

Four pieces answer the question:

- The standards

    A tree of flavor files and templates, in a git repository that is fetched into
    a cache, or in a directory.  See [Dist::Conformance::Source](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASource), and the layout
    in ["THE STANDARDS REPOSITORY" in Dist::Conformance::Flavor](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AFlavor#THE-STANDARDS-REPOSITORY).

- A flavor

    A named set of checks with their configuration, which builds on other flavors
    with `extends`.  There is one for each kind of repository: a distribution on a
    perl you control, one on an installed perl, a deployed service.  See
    [Dist::Conformance::Flavor](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AFlavor).

- The choice of the repository

    `.conformance.yml` at the root of the repository names its flavor and source,
    the checks it skips, and what it sets differently.  See
    [Dist::Conformance::Config](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AConfig).

- The checks

    One module for each question, each told by its configuration what to expect.
    Each can check a snapshot of a repository, local or remote, and update a local
    checkout.  See [Dist::Conformance::Check](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ACheck), which also says how to write one.

The program [conformance](https://metacpan.org/pod/conformance) runs all of this from the shell.

# ATTRIBUTES

## root

The directory of a checkout.  Required unless ["snapshot"](#snapshot) is given; ["update"](#update)
needs it.

## snapshot

The [Dist::Conformance::Snapshot](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASnapshot) to check.  Default a
[Dist::Conformance::Snapshot::Directory](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASnapshot%3A%3ADirectory) of ["root"](#root).  For a repository that
is not on this machine, pass a [Dist::Conformance::Snapshot::Tree](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASnapshot%3A%3ATree).

## config

The validated `.conformance.yml`.  Default the file of the snapshot.  A caller
that has the configuration from somewhere else passes it through
["validate" in Dist::Conformance::Config](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AConfig#validate).

## cache

The cache directory of a git source.  Default as
["cache" in Dist::Conformance::Source::Git](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASource%3A%3AGit#cache) says.

## offline

When true, a git source is not fetched, and its cached copy is used.

## standards

A directory that replaces the `git` or the `directory` of the source, and
keeps its `path`, such as a checkout of the standards that you are editing.

## source

The [Dist::Conformance::Source](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASource).  Default built from the configuration and
the attributes above.

## flavor

The [Dist::Conformance::Flavor](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AFlavor), loaded from the source.

# METHODS

## build\_source

The source that the `source` key of the configuration describes, with
["standards"](#standards), ["cache"](#cache) and ["offline"](#offline) applied.

## skipped

The names of the checks that `.conformance.yml` skips, as a hash reference.
Dies when it skips or configures a check that the flavor does not run.

## checks

The [Dist::Conformance::Check](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ACheck) objects that run, in order, with the
configuration of the flavor and of `.conformance.yml` merged and validated.
Memoized.  Dies on a check whose module does not load or is not a check, and on
a configuration that its schema refuses; each message names the check and the
flavor.

## make\_check

`($name, $config, \%variables)`.  The check `$name` of the flavor, from its
merged configuration.

## check

Runs every check of the flavor against the snapshot.  Returns an array
reference of hash references, one for each check of the flavor, in the order of
their names: `check`, the name; `status`, which is `pass`, `fail`, `info`,
or `skip` for a check that `.conformance.yml` skips; and `detail`.

A check that dies, or returns a status that is not one of the three, fails, and
its detail says so.  A failure of a check at `level: info` is reported as
`info`.

## update

`(%options)`.  Runs the update of every check that is not skipped on the
checkout, after fetching the standards when the source is git.  With
`dry_run => 1` it writes nothing, and says what it would write.

Returns an array reference of hash references, one for each check that ran, in
order: `check`, the name; `changes`, what it changed or would change, each
with an `action` and a `path`; and `manual`, what is left for a person.  A
check whose update dies has the error in `manual`, and the other checks still
run.

# FUNCTIONS

## failed

`($results)`.  Whether any result of ["check"](#check) failed.

# SEE ALSO

Please see those modules/websites for more information related to this module.

- [conformance](https://metacpan.org/pod/conformance)
- [Dist::Conformance::Check](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ACheck)
- [Dist::Conformance::Flavor](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AFlavor)
- [Dist::Conformance::Config](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AConfig)
- [Dist::Conformance::Snapshot](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASnapshot)
- [Dist::Conformance::Source](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASource)

# BUGS

Please report any bugs or feature requests on the bugtracker website
[https://github.com/Troglodyne-Internet-Widgets/Dist-Conformance/issues](https://github.com/Troglodyne-Internet-Widgets/Dist-Conformance/issues)

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

# AUTHORS

Current Maintainers:

- George S. Baugh <george@troglodyne.net>

# CONTRIBUTORS

- troglodyne-bot <morpheus@troglodyne.net>
- troglodyne-bot <troglodyne-bot@users.noreply.github.com>
- troglodyne-robot <trogbot@troglodyne.net>

# COPYRIGHT AND LICENSE

Copyright (c) 2026 Troglodyne LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# NAME

Dist::Conformance - Whether the development harness of a repository conforms to its standards, and bringing it up to date

# VERSION

version 0.010

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

The directory of a checkout.  Required unless ["snapshot"](#snapshot) is given; [update](#update-dry_run)
needs it.

## snapshot

The [Dist::Conformance::Snapshot](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASnapshot) to check.  Default a
[Dist::Conformance::Snapshot::Directory](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASnapshot%3A%3ADirectory) of ["root"](#root).  For a repository that
is not on this machine, pass a [Dist::Conformance::Snapshot::Tree](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ASnapshot%3A%3ATree).

## config

The validated `.conformance.yml`.  Default the file of the snapshot.  A caller
that has the configuration from somewhere else passes it through
["validate($data)" in Dist::Conformance::Config](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3AConfig#validate-data).

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

# FUNCTIONS

## failed($results)

Whether any result of ["check"](#check) failed.

- results - ArrayRef\[HashRef\] - the results, as ["check"](#check) returns them

Returns Bool, true when the status of a result is `fail`.

```
exit 1 if Dist::Conformance::failed( $conformance->check );
```

# METHODS

## adopt

Asks every check that is not skipped what configuration would accept the checkout as it is now, through ["adopt" in Dist::Conformance::Check](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ACheck#adopt).

Returns HashRef, from the name of each check that has an answer to the answer, which is what the check would take under `checks` in `.conformance.yml`.

Dies when the checks cannot be made, as ["checks"](#checks) says, and when the adopt of a check dies.

```perl
my $adopted = $conformance->adopt;
```

## build\_source

The source that the `source` key of the configuration describes, with ["standards"](#standards), ["cache"](#cache) and ["offline"](#offline) applied: a directory for ["standards"](#standards) or for `directory`, and else a git repository.

Returns a Dist::Conformance::Source object, the new source.

```perl
my $source = $conformance->build_source;
```

## check

Runs every check of the flavor against the snapshot.

A check that dies, or returns a status that is not one of the three, fails, and its detail says so.  A failure of a check at `level: info` is reported as `info`.

Returns ArrayRef, of hash references, one for each check of the flavor, in the order of their names: `check`, the name; `status`, which is `pass`, `fail`, `info`, or `skip` for a check that `.conformance.yml` skips; and `detail`.

Dies when the checks cannot be made, as ["checks"](#checks) says.

```perl
my $results = $conformance->check;
```

## checks

The [Dist::Conformance::Check](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ACheck) objects that run, in order, with the configuration of the flavor and of `.conformance.yml` merged and validated. Memoized.

Returns ArrayRef\[InstanceOf\["Dist::Conformance::Check"\]\], the checks.

Dies on a check whose module does not load or is not a check, and on a configuration that its schema refuses; each message names the check and the flavor.

```perl
say $_->name for @{ $conformance->checks };
```

## make\_check(name, config, variables)

The check `$name` of the flavor, from its merged configuration.

- name - Str - the name of the check in the flavor
- config - HashRef - its merged configuration, with `module` when the module is not the name
- variables - HashRef - the values of the placeholders of the templates

Returns a Dist::Conformance::Check object, the check.

Dies when the module of the check is not the name of a module, does not load, or is not a [Dist::Conformance::Check](https://metacpan.org/pod/Dist%3A%3AConformance%3A%3ACheck), and when the schema of the check refuses the configuration.

```perl
my $check = $conformance->make_check( 'ClaudeMd', { file => 'CLAUDE.md', mentions => [] }, {} );
```

## skipped

The names of the checks that `.conformance.yml` skips.

Returns HashRef, from the name of each skipped check to 1.

Dies when `.conformance.yml` skips or configures a check that the flavor does not run, with a message that starts with `.conformance.yml is not valid:`.

```perl
my $skipped = $conformance->skipped;
```

## update(dry\_run)

Runs the update of every check that is not skipped on the checkout, after fetching the standards when the source is git.  A check whose update dies has the error in `manual`, and the other checks still run.

- dry\_run - Bool - optional: when true, writes nothing, and says what it would write

Returns ArrayRef, of hash references, one for each check that ran, in order: `check`, the name; `changes`, what it changed or would change, each with an `action` and a `path`; and `manual`, what is left for a person.

Dies when the checks cannot be made, as ["checks"](#checks) says.

```perl
my $results = $conformance->update( dry_run => 1 );
```

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

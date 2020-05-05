use strict;
use warnings;
use Test::More;
BEGIN {
  eval { require version; 1 } or plan skip_all => "this test requires version.pm";
}
use lib 't/lib';
use TestEUPVCommon qw(mm_clean_version);
use ExtUtils::ParseVersion qw(parse_version);
use File::Spec;

my @modules = (
{
  name => 'no $VERSION line',
  versions => {},
  code => <<'---',
package Simple;
---
},
{
  name => 'undefined $VERSION',
  versions => {},
  code => <<'---',
package Simple;
our $VERSION;
---
},
{
  versions => { Simple => '1.23' },
  name => 'declared & defined on same line with "our"',
  code => <<'---',
package Simple;
our $VERSION = '1.23';
---
},
{
  versions => { Simple => '1.23' },
  name => 'declared & defined on separate lines with "our"',
  code => <<'---',
package Simple;
our $VERSION;
$VERSION = '1.23';
---
},
{
  name => 'commented & defined on same line',
  versions => { Simple => '1.23' },
  code => <<'---',
package Simple;
our $VERSION = '1.23'; # our $VERSION = '4.56';
---
},
{
  name => 'commented & defined on separate lines',
  code => <<'---',
package Simple;
# our $VERSION = '4.56';
our $VERSION = '1.23';
---
  versions => { Simple => '1.23' },
},
{
  name => 'choose the right default package based on package/file name',
  code => <<'---',
package Simple::_private;
$VERSION = '0';
package Simple;
$VERSION = '1.23'; # this should be chosen for version
---
  versions => { 'Simple' => '1.23', 'Simple::_private' => '0' },
},
{
  name => 'just read the first $VERSION line',
  code => <<'---',
package Simple;
$VERSION = '1.23'; # we should see this line
$VERSION = eval $VERSION; # and ignore this one
---
  versions => { Simple => '1.23' },
},
{
  name => 'just read the first $VERSION line in reopened package (1)',
  code => <<'---',
package Simple;
$VERSION = '1.23';
package Error::Simple;
$VERSION = '2.34';
package Simple;
---
  versions => { 'Error::Simple' => '2.34', Simple => '1.23' },
},
{
  name => 'just read the first $VERSION line in reopened package (2)',
  code => <<'---',
package Simple;
package Error::Simple;
$VERSION = '2.34';
package Simple;
$VERSION = '1.23';
---
  versions => { 'Error::Simple' => '2.34', Simple => '1.23' },
},
{
  name => 'mentions another module\'s $VERSION',
  code => <<'---',
package Simple;
$VERSION = '1.23';
if ( $Other::VERSION ) {
    # whatever
}
---
  versions => { Simple => '1.23' },
},
{
  name => 'mentions another module\'s $VERSION in a different package',
  code => <<'---',
package Simple;
$VERSION = '1.23';
package Simple2;
if ( $Simple::VERSION ) {
    # whatever
}
---
  versions => { Simple => '1.23' },
},
{
  name => '$VERSION checked only in assignments, not regexp ops',
  code => <<'---',
package Simple;
$VERSION = '1.23';
if ( $VERSION =~ /1\.23/ ) {
    # whatever
}
---
  versions => { Simple => '1.23' },
},
{
  name => '$VERSION checked only in assignments, not relational ops (1)',
  code => <<'---',
package Simple;
$VERSION = '1.23';
if ( $VERSION == 3.45 ) {
    # whatever
}
---
  versions => { Simple => '1.23' },
},
{
  name => '$VERSION checked only in assignments, not relational ops (2)',
  code => <<'---',
package Simple;
$VERSION = '1.23';
package Simple2;
if ( $Simple::VERSION == 3.45 ) {
    # whatever
}
---
  versions => { Simple => '1.23' },
},
{
  name => 'Fully qualified $VERSION declared in package',
  code => <<'---',
package Simple;
$Simple::VERSION = 1.23;
---
  versions => { Simple => '1.23' },
},
{
  name => 'Differentiate fully qualified $VERSION in a package',
  code => <<'---',
package Simple;
$Simple2::VERSION = '999';
$Simple::VERSION = 1.23;
---
  versions => { Simple => '1.23', Simple2 => '999' },
},
{
  name => 'Differentiate fully qualified $VERSION and unqualified',
  code => <<'---',
package Simple;
$Simple2::VERSION = '999';
$VERSION = 1.23;
---
  versions => { Simple => '1.23', Simple2 => '999' },
},
{
  name => 'Differentiate fully qualified $VERSION and unqualified, other order',
  code => <<'---',
package Simple;
$VERSION = 1.23;
$Simple2::VERSION = '999';
---
  versions => { Simple => '1.23', Simple2 => '999' },
},
{
  name => '$VERSION declared as package variable from within "main" package',
  code => <<'---',
$Simple::VERSION = '1.23';
{
  package Simple;
  $x = $y, $cats = $dogs;
}
---
  versions => { Simple => '1.23' },
},
{
  name => '$VERSION wrapped in parens - space inside',
  code => <<'---',
package Simple;
( $VERSION ) = '1.23';
---
  '1.23' => <<'---', # $VERSION wrapped in parens - no space inside
package Simple;
($VERSION) = '1.23';
---
  versions => { Simple => '1.23' },
},
{
  name => '$VERSION follows a spurious "package" in a quoted construct',
  code => <<'---',
package Simple;
__PACKAGE__->mk_accessors(qw(
    program socket proc
    package filename line codeline subroutine finished));

our $VERSION = "1.23";
---
  versions => { Simple => '1.23' },
},
{
  name => '$VERSION using version.pm',
  code => <<'---',
  package Simple;
  use version; our $VERSION = version->new('1.23');
---
  versions => { Simple => '1.23' },
},
{
  name => '$VERSION using version.pm and qv()',
  code => <<'---',
  package Simple;
  use version; our $VERSION = qv('1.230');
---
  versions => { Simple => 'v1.230' },
},
{
  name => 'underscore version with an eval',
  code => <<'---',
  package Simple;
  $VERSION = '1.23_01';
  $VERSION = eval $VERSION;
---
  versions => { Simple => '1.23_01' },
},
{
  name => 'Two version assignments, no package',
  code => <<'---',
  $Simple::VERSION = '1.230';
  $Simple::VERSION = eval $Simple::VERSION;
---
  version => undef,
  versions => { Simple => '1.230' },
},
{
  name => 'Two version assignments, should ignore second one',
  code => <<'---',
package Simple;
  $Simple::VERSION = '1.230';
  $Simple::VERSION = eval $Simple::VERSION;
---
  versions => { Simple => '1.230' },
},
{
  name => 'declared & defined on same line with "our"',
  code => <<'---',
package Simple;
our $VERSION = '1.23_00_00';
---
  versions => { Simple => '1.230000' },
},
{
  name => 'package NAME VERSION',
  code => <<'---',
  package Simple 1.23;
---
  versions => { Simple => '1.23' },
},
{
  name => 'package NAME VERSION',
  code => <<'---',
  package Simple 1.23_01;
---
  versions => { Simple => '1.23_01' },
},
{
  name => 'package NAME VERSION',
  code => <<'---',
  package Simple v1.2.3;
---
  versions => { Simple => 'v1.2.3' },
},
{
  name => 'package NAME VERSION',
  code => <<'---',
  package Simple v1.2_3;
---
  versions => { Simple => 'v1.2_3' },
},
{
  name => 'trailing crud',
  code => <<'---',
  package Simple;
  our $VERSION;
  $VERSION = '1.23-alpha';
---
  versions => { Simple => '1.23' },
},
{
  name => 'trailing crud',
  code => <<'---',
  package Simple;
  our $VERSION;
  $VERSION = '1.23b';
---
  versions => { Simple => '1.23' },
},
{
  name => 'multi_underscore',
  code => <<'---',
  package Simple;
  our $VERSION;
  $VERSION = '1.2_3_4';
---
  versions => { Simple => '1.234' },
},
{
  name => 'non-numeric',
  code => <<'---',
  package Simple;
  our $VERSION;
  $VERSION = 'onetwothree';
---
  versions => { Simple => '0' },
},
{
  name => 'package NAME BLOCK, undef $VERSION',
  code => <<'---',
package Simple {
  our $VERSION;
}
---
  versions => {},
},
{
  name => 'package NAME BLOCK, with $VERSION',
  code => <<'---',
package Simple {
  our $VERSION = '1.23';
}
---
  versions => { Simple => '1.23' },
},
{
  name => 'package NAME VERSION BLOCK (1)',
  code => <<'---',
package Simple 1.23 {
  1;
}
---
  versions => { Simple => '1.23' },
},
{
  name => 'package NAME VERSION BLOCK (2)',
  code => <<'---',
package Simple v1.2.3_4 {
  1;
}
---
  versions => { Simple => 'v1.2.3_4' },
},
{
  name => 'set from separately-initialised variable, two lines',
  code => <<'---',
package Simple;
  our $CVSVERSION   = '$Revision: 1.7 $';
  our ($VERSION)    = ($CVSVERSION =~ /(\d+\.\d+)/);
}
---
  versions => { Simple => '0' },
},
{
  name => 'our + bare v-string',
  code => <<'---',
package Simple;
our $VERSION     = v2.2.102.2;
---
  versions => { Simple => 'v2.2.102.2' },
},
{
  name => 'our + dev release',
  code => <<'---',
package Simple;
our $VERSION = "0.0.9_1";
---
  versions => { Simple => '0.0.9_1' },
},
{
  name => 'our + crazy string and substitution code',
  code => <<'---',
package Simple;
our $VERSION     = '1.12.B55J2qn'; our $WTF = $VERSION; $WTF =~ s/^\d+\.\d+\.//; # attempts to rationalize $WTF go here.
---
  versions => { Simple => '1.12' },
},
{
  name => 'our in braces, as in Dist::Zilla::Plugin::PkgVersion with use_our = 1',
  code => <<'---',
package Simple;
{ our $VERSION = '1.12'; }
---
  versions => { Simple => '1.12' },
},
{
  name => 'calculated version - from Acme-Pi-3.14',
  code => <<'---',
package Simple;
my $version = atan2(1,1) * 4; $Simple::VERSION = "$version";
1;
---
  versions => {
    Simple => '' . (atan2(1,1)*4),
  }
},
{
  name => 'set from separately-initialised variable, one line',
  code => <<'---',
package Simple;
  my $CVSVERSION   = '$Revision: 1.7 $'; our ($VERSION) = ($CVSVERSION =~ /(\d+\.\d+)/);
}
---
  versions => { Simple => '1.7' },
},
{
  name => 'from Lingua-StopWords-0.09/devel/gen_modules.plx',
  code => <<'---',
package Foo;
our $VERSION = $Bar::VERSION;
---
  versions => { Foo => '0' },
},
{
  name => 'from XML-XSH2-2.1.17/lib/XML/XSH2/Parser.pm',
  code => <<'---',
our $VERSION = # Hide from PAUSE
     '1.967009';
$VERSION = eval $VERSION;
---
  versions => { main => '0' },
},
{
  name => 'from MBARBON/Module-Info-0.30.tar.gz',
  code => <<'---',
package Simple;
$VERSION = eval 'use version; 1' ? 'version'->new('0.30') : '0.30';
---
  versions => { Simple => '0.30' },
},
{
  name => '$VERSION inside BEGIN block',
  code => <<'---',
package Simple;
  BEGIN { $VERSION = '1.23' }
---
  versions => { Simple => '1.23' },
},
{
  name => 'our $VERSION inside BEGIN block',
  code => <<'---',
package Simple;
  BEGIN { our $VERSION = '1.23' }
---
  versions => { Simple => '1.23' },
},
{
  name => 'no assumption of primary version merely if a package\'s $VERSION is referenced',
  code => <<'---',
package Simple;
$Foo::Bar::VERSION = '1.23';
---
  versions => { 'Foo::Bar' => '1.23' },
},
{
  name => 'no package statement; fully-qualified $VERSION for main',
  code => <<'---',
$::VERSION = '1.23';
---
  versions => { 'main' => '1.23' },
},
{
  name => 'no package statement; fully-qualified $VERSION for other package',
  code => <<'---',
$Foo::Bar::VERSION = '1.23';
---
  versions => { 'Foo::Bar' => '1.23' },
},
{
  name => 'package statement that does not quite match the filename',
  code => <<'---',
package ThisIsNotSimple;
our $VERSION = '1.23';
---
  versions => { 'ThisIsNotSimple' => '1.23' },
},
);

sub parse_like_mm {
  my ($code, $file) = @_;

  my %packages;
  my @packages;
  my @versions = parse_version(\$code,
    all => 1,
    stop_at_end => 1,
    stop_at_data => 1,
    package_cb => sub {
      my $package = shift;
      push @packages, $package
        unless $packages{$package}++;
    },
  );
  my %versions = @versions;

  my $want_package;
  if ($file =~ /\.pm\z/) {
    (undef, undef, my $filename) = File::Spec->splitpath($file);
    (my $last_part = $filename) =~ s/\.pm\z//;
    ($want_package) = grep /(?:::|\A)\Q$last_part\E\z/, @packages;
  }
  else {
    if (grep $_ eq 'main', @packages or exists $versions{main}) {
      $want_package = 'main';
    }
    else {
      $want_package = $packages[0] || '';
    }
  }

  for my $v (values %versions) {
    $v = mm_clean_version($v);
  }

  my $version = $want_package ? $versions{$want_package} : undef;

  return {
    version   => $version,
    versions  => \%versions,
    packages  => \@packages,
  };
}

for my $test (@modules) {
  my $code = $test->{code};
  my $label = $test->{name};
  if (!defined $label) {
    ($label = $code) =~ s/\n/\\n/g;
  }
  my $versions = $test->{versions};
  my $version = exists $test->{version} ? $test->{version} : $versions->{Simple};

  my $parsed = parse_like_mm($code, 'Simple.pm');

  my $want = {
    version   => $version,
    versions  => $versions,
  };
  my $got = {
    version  => $parsed->{version},
    versions => $parsed->{versions},
  };

  is_deeply $got, $want, $label
    or do {
    diag explain $got;
  exit;

  }
}

done_testing;

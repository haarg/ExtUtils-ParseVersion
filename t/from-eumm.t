use strict;
use warnings;
use Test::More;
use ExtUtils::ParseVersion qw(parse_version);

my $Has_Version = eval { require version; };

# "undef" - means we expect "undef", undef - eval should be never called for this string
my @versions = (
    [ q[$VERSION = '1.00']                              => '1.00' ],
    [ q[*VERSION = \'1.01']                             => '1.01' ],
    [ q[($VERSION) = q$Revision: 32208 $ =~ /(\d+)/g;]  => 32208 ],
    [ q[$FOO::VERSION = '1.10';]                        => '1.10' ],
    [ q[*FOO::VERSION = \'1.11';]                       => '1.11' ],
    [ q[$VERSION = 0.02]                                => 0.02 ],
    [ q[$VERSION = 0.0]                                 => 0.0 ],
    [ q[$VERSION = -1.0]                                => -1.0 ],
    [ q[$VERSION = undef]                               => 'undef' ],
    [ q[$wibble  = 1.0]                                 => undef ],
    [ q[my $VERSION = '1.01']                           => 'undef' ],
    [ q[local $VERSION = '1.02']                        => 'undef' ],
    [ q[local $FOO::VERSION = '1.30']                   => 'undef' ],
    [ q[if( $Foo::VERSION >= 3.00 ) {]                  => undef ],
    [ q[our $VERSION = '1.23';]                         => '1.23' ],
    [ q[$CGI::VERSION='3.63']                           => '3.63' ],
    [ <<'END'                                           => '1.627' ],
$VERSION = "1.627"; # ==> ALSO update the version in the pod text below!
END
    [ q[BEGIN { our $VERSION = '1.23' }]                => '1.23' ],
    [ q[$Something::VERSION == 1.0]                     => undef ],
    [ q[$Something::VERSION <= 1.0]                     => undef ],
    [ q[$Something::VERSION >= 1.0]                     => undef ],
    [ q[$Something::VERSION != 1.0]                     => undef ],
    [ <<'END'                                           => undef ],
my $meta_coder = ($JSON::XS::VERSION >= 1.4) ?
END
    [ <<'END'                                           => '2.3' ],
$Something::VERSION == 1.0
$VERSION = 2.3
END
    [ <<'END'                                           => '2.3' ],
$Something::VERSION == 1.0
$VERSION = 2.3
$VERSION = 4.5
END
    [ <<'END'                                           => '3.074' ],
$VERSION = sprintf("%d.%03d", q$Revision: 3.74 $ =~ /(\d+)\.(\d+)/);
END
    [ <<'END'                                           => '4.8' ],
$VERSION = substr(q$Revision: 2.8 $, 10) + 2 . "";
END
    [ <<'END'                                           => '2.07' ],
our $VERSION = do { my @r = ( q$Revision: 2.7 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r };
END
    [ q[elsif ( $Something::VERSION >= 1.99 ) ]         => undef ],
( $Has_Version ? (
    [ q[use version; $VERSION = qv("1.2.3");]           => version::qv('1.2.3') ],
    [ q[$VERSION = qv("1.2.3")]                         => version::qv('1.2.3') ],
    [ q[$VERSION = v1.2.3]                              => 'v1.2.3' ],
) : ()),
    [ q[package Foo 1.23;]                              => '1.23' ],
    [ q[package Foo::Bar 1.23;]                         => '1.23' ],
    [ q[package Foo v1.2.3;]                            => 'v1.2.3' ],
    [ q[package Foo::Bar v1.2.3;]                       => 'v1.2.3' ],
    [ q[ package Foo::Bar 1.23 ;]                       => '1.23' ],
    [ q[package Foo'Bar 1.23;]                          => '1.23' ],
    [ q[package Foo::Bar 1.2.3;]                        => '1.2.3' ],
    [ q[package Foo 1.230;]                             => '1.230' ],
    [ q[package Foo 1.23_01;]                           => '1.23_01' ],
    [ q[package Foo v1.23_01;]                          => 'v1.23_01' ],
    [ q["package Foo 1.23"]                             => undef ],
    [ <<'END'                                           => '1.23' ],
package Foo 1.23;
our $VERSION = 2.34;
END
    [ <<'END'                                           => '2.34' ],
our $VERSION = 2.34;
package Foo 1.23;
END
    [ <<'END'                                           => '2.34' ],
package Foo::100;
our $VERSION = 2.34;
END
    [ q[package Foo 1.23 { }]                           => '1.23' ],
    [ q[package Foo::Bar 1.23 { }]                      => '1.23' ],
    [ q[package Foo v1.2.3 { }]                         => 'v1.2.3' ],
    [ q[package Foo::Bar v1.2.3 { }]                    => 'v1.2.3' ],
    [ q[ package Foo::Bar 1.23 { }]                     => '1.23' ],
    [ q[package Foo'Bar 1.23 { }]                       => '1.23' ],
    [ q[package Foo::Bar 1.2.3 { }]                     => '1.2.3' ],
    [ q[package Foo 1.230 { }]                          => '1.230' ],
    [ q[package Foo 1.23_01 { }]                        => '1.23_01' ],
    [ q[package Foo v1.23_01 { }]                       => 'v1.23_01' ],
    [ <<'END'                                           => '1.23' ],
package Foo 1.23 {
our $VERSION = 2.34;
}
END
    [ <<'END'                                           => '2.34' ],
our $VERSION = 2.34;
package Foo 1.23 { }
END
    [ <<'END'                                           => '2.34' ],
package Foo::100 {
our $VERSION = 2.34;
}
END
);

for my $test (@versions) {
  my ($code, $want, $label) = @$test;
  if (!defined $label) {
    ($label = $code) =~ s/\n/\\n/g;
  }

  my ($package, $version) = parse_version(\$code);
  $version = 'undef'
    if defined $package && !defined $version;

  is $version, $want, $label;
}

done_testing;

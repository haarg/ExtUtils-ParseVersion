use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use ExtUtils::ParseVersion qw(parse_version);

my $Has_Version = eval 'require version; "version"->import; 1';

# "undef" - means we expect "undef", undef - eval should be never called for this string
my %versions = (q[$VERSION = '1.00']            => '1.00',
                q[*VERSION = \'1.01']           => '1.01',
                q[($VERSION) = q$Revision: 32208 $ =~ /(\d+)/g;] => 32208,
                q[$FOO::VERSION = '1.10';]      => '1.10',
                q[*FOO::VERSION = \'1.11';]     => '1.11',
                '$VERSION = 0.02'               => 0.02,
                '$VERSION = 0.0'                => 0.0,
                '$VERSION = -1.0'               => -1.0,
                '$VERSION = undef'              => 'undef',
                '$wibble  = 1.0'                => undef,
                q[my $VERSION = '1.01']         => 'undef',
                q[local $VERSION = '1.02']      => 'undef',
                q[local $FOO::VERSION = '1.30'] => 'undef',
                q[if( $Foo::VERSION >= 3.00 ) {]=> 'undef',
                q[our $VERSION = '1.23';]       => '1.23',
                q[$CGI::VERSION='3.63']         => '3.63',
                q[$VERSION = "1.627"; # ==> ALSO update the version in the pod text below!] => '1.627',
                q[BEGIN { our $VERSION = '1.23' }]       => '1.23',

                '$Something::VERSION == 1.0'    => undef,
                '$Something::VERSION <= 1.0'    => undef,
                '$Something::VERSION >= 1.0'    => undef,
                '$Something::VERSION != 1.0'    => undef,
                'my $meta_coder = ($JSON::XS::VERSION >= 1.4) ?' => undef,

                qq[\$Something::VERSION == 1.0\n\$VERSION = 2.3\n]                     => '2.3',
                qq[\$Something::VERSION == 1.0\n\$VERSION = 2.3\n\$VERSION = 4.5\n]    => '2.3',

                '$VERSION = sprintf("%d.%03d", q$Revision: 3.74 $ =~ /(\d+)\.(\d+)/);' => '3.074',
                '$VERSION = substr(q$Revision: 2.8 $, 10) + 2 . "";'                   => '4.8',
                q[our $VERSION = do { my @r = ( q$Revision: 2.7 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r };] => '2.07', # Fucking seriously?
                'elsif ( $Something::VERSION >= 1.99 )' => undef,

               );

if( $Has_Version ) {
    $versions{q[use version; $VERSION = qv("1.2.3");]} = qv("1.2.3");
    $versions{q[$VERSION = qv("1.2.3")]}               = qv("1.2.3");
    $versions{q[$VERSION = v1.2.3]} = 'v1.2.3';
}

if( "$]" >= 5.011001 ) {
    $versions{'package Foo 1.23;'         } = '1.23';
    $versions{'package Foo::Bar 1.23;'    } = '1.23';
    $versions{'package Foo v1.2.3;'       } = 'v1.2.3';
    $versions{'package Foo::Bar v1.2.3;'  } = 'v1.2.3';
    $versions{' package Foo::Bar 1.23 ;'  } = '1.23';
    $versions{"package Foo'Bar 1.23;"     } = '1.23';
    $versions{"package Foo::Bar 1.2.3;"   } = '1.2.3';
    $versions{'package Foo 1.230;'        } = '1.230';
    $versions{'package Foo 1.23_01;'      } = '1.23_01';
    $versions{'package Foo v1.23_01;'     } = 'v1.23_01';
    $versions{q["package Foo 1.23"]}        = 'undef';
    $versions{<<'END'}                      = '1.23';
package Foo 1.23;
our $VERSION = 2.34;
END

    $versions{<<'END'}                      = '2.34';
our $VERSION = 2.34;
package Foo 1.23;
END

    $versions{<<'END'}                      = '2.34';
package Foo::100;
our $VERSION = 2.34;
END
}

if( "$]" >= 5.014 ) {
    $versions{'package Foo 1.23 { }'         } = '1.23';
    $versions{'package Foo::Bar 1.23 { }'    } = '1.23';
    $versions{'package Foo v1.2.3 { }'       } = 'v1.2.3';
    $versions{'package Foo::Bar v1.2.3 { }'  } = 'v1.2.3';
    $versions{' package Foo::Bar 1.23 { }'   } = '1.23';
    $versions{"package Foo'Bar 1.23 { }"     } = '1.23';
    $versions{"package Foo::Bar 1.2.3 { }"   } = '1.2.3';
    $versions{'package Foo 1.230 { }'        } = '1.230';
    $versions{'package Foo 1.23_01 { }'      } = '1.23_01';
    $versions{'package Foo v1.23_01 { }'     } = 'v1.23_01';
    $versions{<<'END'}                      = '1.23';
package Foo 1.23 {
our $VERSION = 2.34;
}
END

    $versions{<<'END'}                      = '2.34';
our $VERSION = 2.34;
package Foo 1.23 { }
END

    $versions{<<'END'}                      = '2.34';
package Foo::100 {
our $VERSION = 2.34;
}
END
}

if ( "$]" < 5.012 ) {
  delete $versions{'$VERSION = -1.0'};
}

#%versions = ();
#    $versions{'BEGIN { our $VERSION = \'1.23\' }'} = '1.23';

for my $code ( sort keys %versions ) {
    my $expect = $versions{$code};
    (my $label = $code) =~ s/\n/\\n/g;
    my $warnings = "";
    if (defined $expect) {
        is( parse_version_string($code), $expect, $label );
    } else {
        no warnings qw[redefine once];
        is( parse_version_string($code), 'undef', $label );
    }
    #is($warnings, '', "$label does not cause warnings");
}


sub parse_version_string {
    my $code = shift;
    my ($package, $version) = parse_version(\$code);
    if (!defined $version) {
        $version = 'undef';
    }
    return "$version";
}


done_testing;

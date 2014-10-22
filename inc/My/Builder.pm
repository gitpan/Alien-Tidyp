package My::Builder;

use strict;
use warnings;
use base 'Module::Build';

use lib "inc";
use File::Spec::Functions qw(catfile);
use ExtUtils::Command;
use File::Fetch;
use File::Temp qw(tempdir tempfile);
use Digest::SHA qw(sha1_hex);
use Archive::Extract;
use Config;

sub ACTION_code {
  my $self = shift;

  unless (-e 'build_done') {
    $self->add_to_cleanup('build_done');
    my $inst = $self->notes('installed_tidyp');
    if (defined $inst) {
      $self->config_data('config', { LIBS   => $inst->{lflags},
                                     INC    => $inst->{cflags},
                                   });
    }
    else {
      # important directories
      my $download = 'download';
      my $patches = 'patches';
      my $build_src = 'build_src';
      # we are deriving the subdir name from VERSION as we want to prevent
      # troubles when user reinstalls the newer version of Alien::Tidyp
      my $build_out = catfile('sharedir', $self->{properties}->{dist_version});
      $self->add_to_cleanup($build_out);
      $self->add_to_cleanup($build_src);

      # get sources
      my $url  = $self->notes('tidyp_url');
      my $dir  = $self->notes('tidyp_dir');
      my $sha1 = $self->notes('tidyp_sha1');
      $self->fetch_file($url, $sha1, $download);
      $self->notes('tidyp_src', "$build_src/$dir");
      my $archive = catfile($download, File::Fetch->new(uri => $url)->file);
      my $ae = Archive::Extract->new( archive => $archive );
      die "###ERROR###: cannot extract tarball ", $ae->error unless $ae->extract(to => $build_src);

      # go for build
      $self->build_binaries($build_out, $self->notes('tidyp_src'));
      # store info about build into future Alien::Tidyp::ConfigData
      $self->config_data('share_subdir', $self->{properties}->{dist_version});
      $self->config_data('config', { PREFIX => '@PrEfIx@',
                                     LIBS   => '-L' . $self->quote_literal('@PrEfIx@/lib') . ' -ltidyp',
                                     INC    => '-I' . $self->quote_literal('@PrEfIx@/include/tidyp'),
                                   });
    }
    # mark sucessfully finished build
    local @ARGV = ('build_done');
    ExtUtils::Command::touch();
  }
  $self->SUPER::ACTION_code;
}

sub fetch_file {
  my ($self, $url, $sha1sum, $download) = @_;
  die "###ERROR### _fetch_file undefined url\n" unless $url;
  die "###ERROR### _fetch_file undefined sha1sum\n" unless $sha1sum;
  my $ff = File::Fetch->new(uri => $url);
  my $fn = catfile($download, $ff->file);
  if (-e $fn) {
    print "Checking checksum for already existing '$fn'...\n";
    return 1 if $self->check_sha1sum($fn, $sha1sum);
    unlink $fn; #exists but wrong checksum
  }
  print "Fetching '$url'...\n";
  my $fullpath = $ff->fetch(to => $download);
  die "###ERROR### Unable to fetch '$url'" unless $fullpath;
  if (-e $fn) {
    print "Checking checksum for '$fn'...\n";
    return 1 if $self->check_sha1sum($fn, $sha1sum);
    die "###ERROR### Checksum failed '$fn'";
  }
  die "###ERROR### _fetch_file failed '$fn'";
}

sub check_sha1sum {
  my ($self, $file, $sha1sum) = @_;
  my $sha1 = Digest::SHA->new;
  my $fh;
  open($fh, $file) or die "###ERROR## Cannot check checksum for '$file'\n";
  binmode($fh);
  $sha1->addfile($fh);
  close($fh);
  return ($sha1->hexdigest eq $sha1sum) ? 1 : 0;
}

sub build_binaries {
  die "###ERROR### My::Builder cannot build libtidyp from sources, use rather My::Builder::<platform>";
}

sub quote_literal {
  # this needs to be overriden in My::Builder::<platform>
  my ($self, $path) = @_;
  return $path;
}

sub check_installed_tidyp {
  my ($self) = @_;

  require ExtUtils::CBuilder;
  my $cb = ExtUtils::CBuilder->new( quiet => 1 );
  my $dir = tempdir( CLEANUP => 1 );
  my ($fs, $src) = tempfile( DIR => $dir, SUFFIX => '.c' );
  syswrite($fs, <<MARKER); # write test source code
#include <tidyp.h>
int main() { tidyVersion(); return 0; }

MARKER
  close($fs);

  my $tdir = $ENV{TIDYP_DIR};
  my @candidates;
  push(@candidates, { L => "$tdir/lib", I => "$tdir/include/tidyp" }) if -d $tdir;
  push(@candidates, { L => '/usr/local/lib', I => '/usr/local/include/tidyp' });
  push(@candidates, { L => '/usr/lib', I => '/usr/include/tidyp' });
  push(@candidates, { L => '', I => "$Config{usrinc}/tidyp" });

  print "Gonna detect tidyp already installed on your system:\n";
  foreach my $i (@candidates) {
    my $lflags = $i->{L} ? '-L'.$self->quote_literal($i->{L}).' -ltidyp' : '-ltidyp';
    my $cflags = $i->{I} ? '-I'.$self->quote_literal($i->{I}) : '';
    print "- testing: $cflags $lflags ...\n";
    my ($obj, $exe);
    open(my $olderr, '>&', STDERR);
    open(STDERR, '>', File::Spec->devnull());
    $obj = eval { $cb->compile( source => $src, extra_compiler_flags => $cflags ) };
    $exe = eval { $cb->link_executable( objects => $obj, extra_linker_flags => $lflags ) } if $obj;
    open(STDERR, '>&', $olderr);
    next unless $exe;
    print "- TIDYP FOUND!\n";
    $self->notes('installed_tidyp', { lflags => $lflags, cflags => $cflags } );
    return 1;
  }
  print "- tidyp not found!\n";
  return 0;
}

1;

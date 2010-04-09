#!/usr/bin/perl

=head1 NAME

sort-photos - Sort photos from one directory into another.

Version 0.5

=head1 SYNOPSIS

Sorts all the photos from one directory into another directory based on the
date the photo was taken.

=cut


use warnings;
use strict;

use File::Path;
use File::Spec;
use Getopt::Long;
use Pod::Usage;
use POSIX ();
use Time::localtime;
use Term::ReadKey;
use File::Copy;
use Image::ExifTool ':Public';


my ($VOLUME, $DIRECTORIES, $SCRIPT) = File::Spec->splitpath($0);

my $source = "./tosort"; # source folder
my $dest   = "./sorted"; # destination folder

# get directory listing of source

# iterate over each file
    # is picture
	# get year, month and day photo was taken
	# create directory as $dest/$year/$month/$day
	# drop file in folder just created

=head1 USAGE

  sort-images.pl -h

  sort-images.pl -v

  sort-images.pl <options> -r <directory> <directory> ... <target-directory>

=head2 OPTIONS

=over 8

=item -h --help

Print a help message and exits.

=item --version

Print a breif message and exits.

=item -f --fake

Do everything except actually move or copy files.

=cut

#=item -s --sort
#
#Specifies how to sort the images.  This may be specified multiple times for
#sub-sorting.
#
#  sort option
#  ------------------------------
#  --sort image <image-property>
#  --sort file <file-property>

=item -q --quiet

Show less output.

=item -v --verbose

Show more output.

=item -r -R --recursive

Operate recursively (down directory tree).

=back

=cut


my $DEBUG = 1;
my $WARNINGS = 2;

# Verbosity of output.
#  0  Minimal
#  1  Normal
#  2  Verbose
my $verbosity = 2;

my $recursive = 0;

my $fake_mode = 0;

=head1 DESCRIPTION

Generates files needed to compile the dictionary and images into the Duet
project as well as binary files used to write various different tables.

=cut


ParseOptions();
ProcessFolder($source);


sub ParseOptions
{
    my ($option_show_help, $option_verbosity, $option_fake, $option_recursive) = 0;

    GetOptions
    (
        'help|version|h' => \$option_show_help,
        'verbose|v+'     => \$option_verbosity,
        'fake|f'         => \$option_fake,
        'recursive|R|r'  => \$option_recursive,
    );

    if ($option_show_help)
    {
        pod2usage
        (
          -exitval => 0,
          -verbose => 99,
          -sections => "NAME|SYNOPSIS|USAGE|USAGE/OPTIONS"
        ); # this will exit the script here.
    
        exit 0; # should not be reached.
    }

    if ($option_verbosity)
    {
        $verbosity = $option_verbosity;
    }

    if ($option_fake)
    {
        $fake_mode = $option_fake;
    }

    if ($option_recursive)
    {
        $recursive = $option_recursive;
    }
}


sub ProcessFolder
{
    my $path = shift;

    my @files = ListFiles($path);
    my $count = @files;

    if (!$count)
    {
        return;
    }

    ClearConsoleLine() if ($verbosity);
    print("$path : $count files") if ($verbosity);
    print("\n") if (1 < $verbosity);

    foreach my $file (@files)
    {
        my $base_filename = $path . '/' . $file;
        my $full_path = File::Spec->rel2abs($base_filename);
        my ($file_volume, $file_directories, $file_name) = File::Spec->splitpath($full_path);

        ClearConsoleLine() if ($verbosity);
        print("$file") if ($verbosity);

        if (-d $full_path)
        {
            # Is a directory, process it now.
            # exit function here.
            #ProcessFolder($full_path) if $recursive;
            next;
        }

        my $info = ImageInfo($full_path);
        my $date = $info->{'CreateDate'};

        if ($date)
        {
            $date =~ /
                (?<year>[0-9][0-9][0-9][0-9])
                [-: ]
                (?<month>[0-9][0-9])
                [-: ]
                (?<day>[0-9][0-9])
                [-: ]
                (?<hour>[0-9][0-9])
                [-: ]
                (?<minute>[0-9][0-9])
                [-: ]
                (?<second>[0-9][0-9])
                /x;

            my $target = $dest . '/' . $+{year} . '/' . $+{month} . '/' . $+{day} . '/' . $file_name;
            my $full_target = File::Spec->rel2abs($target);
            my $target_path = $dest . '/' . $+{year} . '/' . $+{month} . '/' . $+{day} . '/';
            my $full_target_path = File::Spec->rel2abs($target_path);
            mkpath($full_target_path);

            if (-e $full_target)
            {
                ClearConsoleLine() if ($verbosity);
                print("$base_filename : Exists") if ($verbosity);
                print("\n") if (1 < $verbosity);
            }
            else
            {
                ClearConsoleLine() if ($verbosity);
                print("$base_filename ") if ($verbosity);

                if ( copy($full_path, $full_target) )
                {
                    print("--> $target") if ($verbosity);
                }
                else
                {
                    print ": copy failed: $!" if ($verbosity);
                }

                print("\n") if (1 < $verbosity);

            }
        }
        else
        {
            ClearConsoleLine() if ($verbosity);
            print("$base_filename : unsupported file type or missing expected EXIF tags.") if ($verbosity);
            print("\n") if (1 < $verbosity);
        }

    }

    # ($a, $b, $c) = $image->Get('colorspace', 'magick', 'adjoin');
    # $width = $image->[3]->Get('columns');
    # user-time

}


=head2 ListFiles ( $path )

Lists the files and folders in $path.

Removes '.' and '..' from the list.

=over

=item $path

The path to get a file list from.

=item returns @list

Returns a list of files and folders in $path.

Returns an empty list on failure.

=back

=cut

sub ListFiles
{
    my $path = shift;

    if (!opendir(SOURCE_DIR, $path))
    {
        ClearConsoleLine();
        print STDERR "Failed to open $path: $!\n";
        return ();
    }
    my @list = readdir(SOURCE_DIR);
    close(SOURCE_DIR);
    
    @list = File::Spec->no_upwards(@list);

    return @list;
}


=head2 ClearConsoleLine ( $char )

Prints spaces for the width of the current console line except for the very
last character (in windows pringing the entire width of the line will
automatically move the carrot one line down)

Uses carrage return ("\r") in order to return to the start of the line.

=over

=item $char

Optional.  Defaults to space (' ').

If specified, this character will be used as the character to print the entire
length of the line.

=back

=cut

sub ClearConsoleLine
{
    my $char = shift // ' ';
    my ($console_width_chars, undef, undef, undef) = GetTerminalSize();
    print "\r";
    for (my $x = 0; $x < $console_width_chars - 1; $x++) {print $char}
    print "\r";
}


=head2 PadLeft ( $text, $length, $pad_with )

Pads the left of the specified string to the specified length.

=over

=item $text

the text to pad.

default: an empty string

=item $length

the length to pad the text to.

default: 0

=item $pad_with

the character to pad the string with.

default: space character

=item returns $padded

the padded string.

=back

=cut

sub PadLeft
{
    my $text = shift;
    my $pad_len = shift;
    my $pad_char = shift;
    
    if (!defined($text)) { $text = ""; }
    if (!defined($pad_len)) { $pad_len = 0; }
    if (!defined($pad_char)) { $pad_char = " "; }

    my $padding = $pad_char x ( $pad_len - length( $text ) );
    my $padded = $padding . $text;

    return $padded;
}


=head2 PadRight ( $text, $length, $pad_with )

Pads the right of the specified string to the specified length.

=over

=item $text

the text to pad.

default: an empty string

=item $length

the length to pad the text to.

default: 0

=item $pad_with

the character to pad the string with.

default: space character

=item returns $padded

the padded string.

=back

=cut

sub PadRight
{
    my $text = shift;
    my $pad_len = shift;
    my $pad_char = shift;
    
    if (!defined($text)) { $text = ""; }
    if (!defined($pad_len)) { $pad_len = 0; }
    if (!defined($pad_char)) { $pad_char = " "; }

    my $padding = $pad_char x ( $pad_len - length( $text ) );
    my $padded = $text . $padding;

    return $padded;
}


__END__

=head1 AUTHOR

Nathan Perry [nateperry333 at gmail dot com]

=head1 COPYRIGHT and LICENSE

Copyright 2010 Nathan Perry.

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

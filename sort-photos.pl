#!/usr/bin/perl


=head1 NAME

sort-photos - Sort photos from one directory into another.

Version 1.0.0

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
use Digest::MD5;


my ($VOLUME, $DIRECTORIES, $SCRIPT) = File::Spec->splitpath($0);


=head1 USAGE

Arguments starting with - are assumed to be single letter arguments.  Specifying "-abc" is equivalent to "-a -b -c"

  sort-images.pl [-R] <source> [<source> [...]] <target>

=head2 OPTIONS

=over 8

=item --help -h

Print a help message and exits.

=item --version

Print a brief message and exits.

=item --verbose -v

Show more output.

=item --recursive -r -R

Operate recursively (down directory tree).

=item --move -m

Instructs this script to use the move operation.  In addition, when duplicates
are found they will be deleted.

When omitted and by default, the copy operation is used and duplicates are left
untouched.

=item --fake

Do everything except actually move or copy files.  In addition, no files are
deleted.

=item --no-rename

Naming conflicts are reported but no files are copied or moved.

By default, when a naming conflict occurs, a number is appended to the target
path before the copy or move happens.

=item --

Stops processing command line options.  Further items are assumed to be
files or directories.  The final argument is assumed to be the target
directory.

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

=back

=cut


my $DEBUG = 1;
my $WARNINGS = 2;

# Verbosity of output.
#  0  Minimal
#  1  Normal
#  2  Verbose
my $verbosity = 1;

my $recursive = 0;

my $fake_mode = 0;

my $no_rename = 0;

# 0: Perform copy operation
# 1: Perform move operation
#    And duplicates are deleted
my $move_mode = 0;

my $operation = 'copy';
my $operation_pasttense = 'copied';

my @source_paths;
my $target_path;

=head1 DESCRIPTION

Generates files needed to compile the dictionary and images into the Duet
project as well as binary files used to write various different tables.

=cut


$|++ if ($verbosity); # causes print to output immediately.
ParseOptions();
foreach my $source (@source_paths)
{
    ProcessFolder($source);
}
ClearConsoleLine() if (1 == $verbosity);


sub ParseOptions
{
    while (@ARGV)
    {
        my $arg = shift(@ARGV);
        my $arg_lc = lc($arg);

        if ($arg_lc eq '--')
        {
            last;
        }
        elsif ($arg_lc =~ s/^-([^- ][^ ]*)$/$1/)
        {
            my @chars = split(//, $arg_lc);

            while(my $char = shift(@chars))
            {
                if ($char eq 'h')
                {
                    ShowUsage();
                    exit;
                }
                elsif ($char eq 'v') # verbose
                {
                    $verbosity++;
                }
                elsif ($char eq 'r') # recursive
                {
                    $recursive++;
                }
                elsif ($char eq 'R') # recursive
                {
                    $recursive++;
                }
                elsif ($char eq 'm') # move mode
                {
                    $move_mode++;
                }
                else
                {
                    print STDERR "Invalid option -$char\n";
                    exit;
                }
            }

        }
        elsif ($arg_lc =~ s/^--([^- ][^ ]+)$/$1/)
        {
            if ($arg_lc eq 'help')
            {
                ShowUsage();
                exit;
            }
            elsif ($arg_lc eq 'version')
            {
                ShowUsage();
                exit;
            }
            elsif ($arg_lc eq 'verbose')
            {
                $verbosity++;
            }
            elsif ($arg_lc eq 'recursive')
            {
                $recursive++;
            }
            elsif ($arg_lc eq 'fake')
            {
                $fake_mode++;
            }
            elsif ($arg_lc eq 'move')
            {
                $move_mode++;
            }
            elsif ($arg_lc eq 'no-rename')
            {
                $no_rename++;
            }
            else
            {
                print STDERR "Invalid option $arg\n";
                exit;
            }

        }
        else
        {
            push(@source_paths, $arg)
        }

    }

    while (@ARGV)
    {
        push(@source_paths, shift(@ARGV))
    }

    if (!@source_paths)
    {
        print STDERR "no source or target path specified\n";
        exit;
    }

    $target_path = pop(@source_paths);

    if (!@source_paths)
    {
        print STDERR "no source path(s) specified\n";
        exit;
    }

    my $not_exist = 0;
    foreach my $source (@source_paths)
    {
        if (!(-e $source))
        {
            print STDERR "$source does not exist or is unknown.\n";
            $not_exist++;
        }
    }

    if ($not_exist)
    {
        exit;
    }

    if ($move_mode)
    {
        $operation = 'move';
        $operation_pasttense = 'moved';
    }
}


sub ShowUsage
{
    pod2usage
    (
      -exitval => 0,
      -verbose => 99,
      -sections => "NAME|SYNOPSIS|USAGE|USAGE/OPTIONS"
    ); # this will exit the script here.
}


sub ProcessFolder
{
    my $path = shift;

    my $successful_count = 0;
    my $failed_count = 0;

    my @files = ListFiles($path);
    my $count = @files;
    my @folders;

    ClearConsoleLine() if ($verbosity);
    print("$path : $count files\n") if (1 < $verbosity);

    if (!$count)
    {
        return;
    }

    foreach my $pic_file (@files)
    {
        my $pic_rel = File::Spec->catfile($path, $pic_file);
        my $pic_full = File::Spec->rel2abs($pic_rel);

        ClearConsoleLine() if ($verbosity);
        print("$pic_file") if ($verbosity);

        if (-d $pic_full)
        {
            push(@folders, $pic_rel);
            next;
        }

        my $info = ImageInfo($pic_full);
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

            my $pic_target_path = File::Spec->catfile($target_path, $+{year}, $+{month}, $+{day});
            my $pic_target_full = File::Spec->rel2abs($pic_target_path);
            mkpath($pic_target_full) if !$fake_mode;
            my $target = File::Spec->catfile($pic_target_path, $pic_file);
            my $full_target = File::Spec->rel2abs($target);

            if (-e $full_target)
            {
                ClearConsoleLine() if ($verbosity);
                my $identical = AreIdentical($pic_full, $full_target);
                if ($identical)
                {
                    if ($move_mode)
                    {
                        unlink($pic_full) unless $fake_mode;
                        print "'$target' duplicate removed" if $verbosity;
                        print "[fake mode]" if $fake_mode;
                        print("\n") if (1 < $verbosity);
                        next;
                    }
                    else
                    {
                        print "'$target' [identical]" if $verbosity;
                        print "[fake mode]" if $fake_mode;
                        print("\n") if (1 < $verbosity);
                        next;
                    }
                }
                else
                #elsif ($no_rename)
                {
                    print "'$target' [name conflict]" if $verbosity;
                    print("\n") if (1 < $verbosity);
                    $failed_count += 1;
                    next;
                }
                #else
                #{
                #    my $number = 1;
                #    while (-e $full_target . $number)
                #    {
                #        $number++;
                #    }
                #
                #    $full_target = $full_target . $number;
                #    $target = $target . $number;
                #
                #    print "'$target' [renamed]" if $verbosity;
                #    print("\n") if (1 < $verbosity);
                #}
            }

            ClearConsoleLine() if ($verbosity);

            if ($fake_mode)
            {
                print("'$target' [fake mode]") if ($verbosity);
                $successful_count += 1;
            }
            else
            {
                my $operation_success = 0;
                if ($move_mode)
                {
                    $operation_success = move($pic_full, $full_target);
                }
                else
                {
                    $operation_success = copy($pic_full, $full_target);
                }

                if ( $operation_success )
                {
                    print("'$target' $operation_pasttense") if ($verbosity);
                    $successful_count += 1;
                }
                else
                {
                    print "'$target' $operation failed: $!" if ($verbosity);
                    $failed_count += 1;
                }
            }

            print("\n") if (1 < $verbosity);
        }
        else
        {
            ClearConsoleLine() if ($verbosity);
            print("$pic_rel could not process file") if ($verbosity);
            print("\n") if (1 < $verbosity);
            $failed_count += 1;
        }
    }

    if ($verbosity)
    {
        ClearConsoleLine();
        print("$path : $successful_count $operation_pasttense, $failed_count failed\n");
    }

    while (@folders)
    {
        my $folder = pop(@folders);
        ProcessFolder($folder) if $recursive;
    }

}


sub GetChecksum
{
    my $file = shift;

    open(FILE, $file) or die "Can't open '$file': $!";
    binmode(FILE);
    return Digest::MD5->new->addfile(*FILE)->hexdigest;
}


sub AreIdentical
{
    my $file1 = shift;
    my $file2 = shift;

    return (GetChecksum($file1) eq GetChecksum($file2));
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
last character (in windows printing the entire width of the line will
automatically move the carrot one line down)

Uses carriage return ("\r") in order to return to the start of the line.

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

#!/usr/bin/perl


=head1 NAME

sort-photos - Sort photos from one directory into another.

Version 1.2.0

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

=item -h

=item --help

Print a help message and exits.

=item --version

Print a brief message and exits.

=item -v

=item --verbose

Show more output.

=item -R

=item -r

=item --recursive

Operate recursively (down directory tree).

=item -m

=item --move

Instructs this script to use the move operation.  In addition, when duplicates
are found they will be deleted.

When omitted and by default, the copy operation is used and duplicates are left
untouched.

=item --fake

Do everything except actually move or copy files.  In addition, no files are
deleted.

=item --no-rename

Name conflicts are reported but no files are copied or moved.

By default, when a naming conflict occurs, a number is appended to the
destination file name before the copy or move happens.

=item --sort-unsupported

Sorts unsupported files (see below) into the root of the target folder.

=item --sort-unsupported-into <folder>

Sorts unsupported files (see below) into <folder>.

=item --

Stops processing command line options.  Further items are assumed to be
files or directories.  The final argument is assumed to be the destination
directory.

=back

=head2 DEFINITIONS

=over 8

=item unsupported file

When a source file has no EXIF metadata, an invalid date taken or is not an
image file.

=item duplicate

When a source file and destination file have the same file name, and the files
are identical.

=item name conflict

When a source file and destination file have the same file name, and the files
are not identical.

=back

=cut


my $DEBUG = 1;
my $WARNINGS = 2;

# Verbosity of output.
#  zero: Minimal or none
#   one: Normal
# other: Verbose
my $verbosity = 1;

#     zero: no recursive
# non-zero: search into sub-directories
my $recursive = 0;

#     zero: real mode, move and copy files
# non-zero: fake mode, no moves, copies or deletes
my $fake_mode = 0;

#     zero: rename file name conflicts
# non-zero: 
my $no_rename = 0;

#     zero: Perform copy operation
# non-zero: Perform move operation
#           and duplicates are deleted
my $move_mode = 0;

my $unsupported_sort = 0;
my $unsupported_target;

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
        # match -x, -xx... or -x-x... and trim initial dash
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
        # match --x... but not ---x... and remove initial two dashes.
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
            elsif ($arg_lc eq 'sort-unsupported')
            {
                $unsupported_sort++;
            }
            elsif ($arg_lc eq 'sort-unsupported-into')
            {
                $unsupported_sort++;

                my $folder = shift(@ARGV);
                if ($folder)
                {
                    $unsupported_target = $folder;
                }
                else
                {
                    print STDERR "ERROR: expected <folder> after '$arg'\n";
                    exit;
                }
            }
            else
            {
                print STDERR "Invalid option $arg\n";
                exit;
            }

        }
        ## match 3 or more dashes followed by any non-space characters
        #elsif ($arg_lc =~ s/^---([^ ]+)$/$1/)
        #{
        #}
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
    my $folder = shift;

    my $successful_count = 0;
    my $failed_count = 0;

    my @files = ListFiles($folder);
    @files = sort(@files);
    my $count = @files;
    my @folders;

    ClearConsoleLine() if ($verbosity);
    print("$folder : $count files\n") if (1 < $verbosity);

    if (!$count)
    {
        return;
    }

    foreach my $source_file (@files)
    {
        my $source_rel = File::Spec->catfile($folder, $source_file);

        ClearConsoleLine() if ($verbosity);
        print("$source_file") if ($verbosity);

        if (-d $source_rel)
        {
            push(@folders, $source_rel);
            next;
        }

        my $info = ImageInfo($source_rel);
        my $date = $info->{'DateTimeOriginal'};
        if(!$date  || $date eq ''){
            # fallback to CreateDate
            $date = $info->{'CreateDate'};
        }
        my ($year, $month, $day);

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

            $year  = $+{year};
            $month = $+{month};
            $day   = $+{day};

        }

        if (
          $year and (0 < $year) and
          $month and (0 < $month) and
          $day and (0 < $day))
        {
            my $destination_path = File::Spec->catfile($target_path, $+{year}, $+{month}, $+{day});
            my $destination_rel = File::Spec->catfile($destination_path, $source_file);

            mkpath($destination_path) if !$fake_mode;

            if (-e $destination_rel)
            {
                ClearConsoleLine() if ($verbosity);
                my $identical = AreIdentical($source_rel, $destination_rel);
                if ($identical)
                {
                    if ($move_mode)
                    {
                        unlink($source_rel) unless $fake_mode;
                        print "'$destination_rel' NOTICE: duplicate removed" if $verbosity;
                        print " fake" if $fake_mode;
                        print("\n") if (1 < $verbosity);
                        next;
                    }
                    else
                    {
                        print "'$destination_rel' NOTICE: duplicate file" if $verbosity;
                        print("\n") if (1 < $verbosity);
                        next;
                    }
                }
                elsif ($no_rename)
                {
                    print "'$destination_rel' ERROR: name conflict" if $verbosity;
                    print("\n") if (1 < $verbosity);
                    $failed_count += 1;
                    next;
                }
                else
                {
                    $destination_rel = RenameFile($destination_path, $source_file);
                    if (!$destination_rel)
                    {
                        $failed_count += 1;
                        next;
                    }
                }
            }

            ClearConsoleLine() if ($verbosity);

            if ($fake_mode)
            {
                print("'$destination_rel' [fake]") if ($verbosity);
                $successful_count += 1;
            }
            else
            {
                my $operation_success = 0;
                if ($move_mode)
                {
                    $operation_success = move($source_rel, $destination_rel);
                }
                else
                {
                    $operation_success = copy($source_rel, $destination_rel);
                }

                if ( $operation_success )
                {
                    print("'$destination_rel' $operation_pasttense") if ($verbosity);
                    $successful_count += 1;
                }
                else
                {
                    print "'$destination_rel' ERROR: $operation failed: $!" if ($verbosity);
                    $failed_count += 1;
                }
            }

            print("\n") if (1 < $verbosity);
        }

        if (0 or $unsupported_sort)
        {
            my $destination_path;

            if ($unsupported_target)
            {
                $destination_path = File::Spec->catfile($target_path, $unsupported_target);
            }
            else
            {
                $destination_path = $target_path;
            }

            my $destination_rel = File::Spec->catfile($destination_path, $source_file);

            mkpath($destination_path) if !$fake_mode;

        }
        else
        {
            ClearConsoleLine() if ($verbosity);
            print("'$source_rel' ERROR: unsupported file") if ($verbosity);
            print("\n") if (1 < $verbosity);
            $failed_count += 1;
        }
    }

    if ($verbosity)
    {
        ClearConsoleLine();
        print("$folder : $successful_count $operation_pasttense, $failed_count failed\n");
    }

    while (@folders)
    {
        my $folder = pop(@folders);
        ProcessFolder($folder) if $recursive;
    }

}


sub RenameFile
{
    my $destination_path = shift;
    my $source_file = shift;

    my $destination_rel;
    my $destination_full;

    my $source_file_mod = $source_file;
    $source_file_mod =~ /
        ^
        (?<file>.*)
        [.]
        (?<ext>jpg|jpeg|tif|tiff)
        $
        /x;

    my $file = $+{file};
    my $ext = $+{ext};

    if ($file and $ext)
    {
        print "'$destination_rel'" if $verbosity;

        my $number = 1;
        my $new_file = $file . '-' . $number . '.' . $ext;
        while (-e File::Spec->catfile($destination_path, $new_file))
        {
            $number++;
            $new_file = $file . '-' . $number . '.' . $ext;
        }

        $destination_rel = File::Spec->catfile($destination_path, $new_file);
        $destination_full = File::Spec->rel2abs($destination_rel);

        print " NOTICE: renamed to '$new_file'" if $verbosity;
        print("\n") if (1 < $verbosity);
    }
    else
    {
        print "'$destination_rel' ERROR: failed to parse file name " if $verbosity;
    }

    return $destination_rel;
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

=head1 CONTRIBUTORS

Maarten Stolte

=head1 COPYRIGHT and LICENSE

Copyright (C) 2010-2013 Nathan Perry.

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

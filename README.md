# sort-photos
Automatically exported from code.google.com/p/sort-photos

## Use

PERL script to sort photos into folders by date taken (EXIF property 'DateTimeOriginal' or 'CreateDate').

`target-folder/year/month/day/photos`

```
Name:
    sort-photos - Sort photos from one directory into another.

    Version 1.1.0

Usage:
    Sorts all the photos from one directory into another directory based on
    the date the photo was taken.

Usage:
    Arguments starting with - are assumed to be single letter arguments.
    Specifying "-abc" is equivalent to "-a -b -c"

      sort-images.pl [-R] <source> [<source> [...]] <target>

  Options:
    --help -h
            Print a help message and exits.

    --version
            Print a brief message and exits.

    --verbose -v
            Show more output.

    --recursive -r -R
            Operate recursively (down directory tree).

    --move -m
            Instructs this script to use the move operation. In addition,
            when duplicates are found they will be deleted.

            When omitted and by default, the copy operation is used and
            duplicates are left untouched.

    --fake  Do everything except actually move or copy files. In addition,
            no files are deleted.

    --no-rename
            Name conflicts are reported but no files are copied or moved.

            By default, when a naming conflict occurs, a number is appended
            to the destination file name before the copy or move happens.

    --      Stops processing command line options. Further items are assumed
            to be files or directories. The final argument is assumed to be
            the destination directory.

  Definitions:
    duplicate
        When a source file and destination file have the same file name, and
        the files are identical.

    name conflict
        When a source file and destination file have the same file name, and
        the files are not identical.
```

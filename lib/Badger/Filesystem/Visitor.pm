#========================================================================
#
# Badger::Filesystem::Visitor
#
# DESCRIPTION
#   Base class visitor object for traversing a filesystem.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
#========================================================================

package Badger::Filesystem::Visitor;

use Badger::Class
    version   => 0.01,
    debug     => 0,
    base      => 'Badger::Base',
    import    => 'class',
    utils     => 'params',
    constants => 'ARRAY CODE REGEX ON WILDCARD',
    config    => [
        'files|accept|class:FILES',
        'no_files|ignore|class:NO_FILES',
        'dirs|directories|class:DIRS',
        'no_dirs|no_directories|class:NO_DIRS',
        'in_dirs|in_directories|enter|class:IN_DIRS',
        'not_in_dirs|not_in_directories|leave|class:NOT_IN_DIRS',
        'accept_file',
        'reject_file',
        'accept_dir|accept_directory',
        'reject_dir|reject_directory',
        'enter_dir|enter_directory',
        'leave_dir|leave_directory',
    ],
    messages  => {
        no_node    => 'No node specified to %s',
        bad_filter => 'Invalid test in %s specification: %s',
    },
    alias     => {
        init            => \&init_visitor,
        collect_dir     => \&collect_dir,
        enter_dir       => \&enter_directory,
        visit_dir       => \&visit_directory,
        visit_dir_kids  => \&visit_directory_children,
    };

use Badger::Debug ':dump';
our @FILTERS     = qw( files dirs in_dirs no_files no_dirs not_in_dirs );
our $ALL         = 0;
our $FILES       = 1;
our $DIRS        = 1;
our $IN_DIRS     = 0;
our $NO_FILES    = 0;
our $NO_DIRS     = 0;
our $NOT_IN_DIRS = 0;


sub init_visitor {
    my ($self, $config) = @_;
    my $class = $self->class;
    my ($item, $long);

    $self->configure($config);
    
    $self->{ in_dirs } = 1
        if $config->{ recurse };
    
    $self->{ collect  } = [ ];
    $self->{ identify } = { };

    $self->init_filters;

    $self->debug("init_visitor() => ", $self->dump) if DEBUG;

    return $self;
}


sub init_filters {
    my $self = shift;
    my ($filter, $tests, $test, $type);
    
    foreach $filter (@FILTERS) {
        $tests = $self->{ $filter } || next;        # skip over false values
        $self->debug("filter: $filter => $tests\n") if DEBUG;
        $tests = $self->{ $filter } = [$tests] 
            unless ref $tests eq ARRAY;
        
        # NOTE: $test is aliasing list item so we can change it
        foreach $test (@$tests) {
            $self->debug("  - test: $test\n") if $DEBUG;
            last unless $test;                      # false test always fails
            
            if ($type = ref $test) {
                return $self->error_msg( bad_filter => $filter => $test )
                    unless $type eq CODE or $type eq REGEX;
                # OK
            }
            elsif ($test eq ON) {
                # OK
            }
            elsif ($test =~ WILDCARD) {
                # changing test affects list item via regex
                $test =~ s/\./<<DOT>>/g;     # . => <<DOT>>     (tmp)
                $test =~ s/\?/./g;           # ? => .
                $test =~ s/\*/.*/g;          # * => .*
                $test =~ s/<<DOT>>/\\./g;    # <<DOT>> => \.
                $test = qr/^$test$/;
                $self->debug("transmogrified wildcard into regex: $test\n") if $DEBUG;
            }
        }
        
        $self->debug(
            "initialised $filter tests: ", 
            $self->dump_data_inline($tests),
            "\n"
        ) if $DEBUG;
    }
}


sub visit {
    my $self = shift;
    my $node = shift || return $self->error_msg( no_node => 'visit' );
    $node->enter($self);
}


sub visit_path {
    my ($self, $path) = @_;
    # TODO: we have nothing going on here
    $self->debug("visiting path: $path\n") if $DEBUG;
}


sub visit_file {
    my ($self, $file) = @_;

    return $self->filter_file($file)
         ? $self->accept_file($file)
         : $self->reject_file($file);
}


sub visit_directory {
    my ($self, $dir) = @_;
    $self->debug("visiting directory: $dir\n") if $DEBUG;

    $self->filter_directory($dir)
         ? $self->accept_directory($dir) || return
         : $self->reject_directory($dir) || return;

    return $self->filter_entry($dir)
         ? $self->enter_directory($dir)
         : $self->leave_directory($dir);
}


sub filter {
    my ($self, $filter, $method, $item) = @_;
    my $tests = $self->{ $filter } || do {
        $self->debug("No filter defined for $filter") if DEBUG;
        return 0;
    };
    my ($test, $type);

    $self->debug("filter($filter, $method, $item)  tests: $tests\n") if $DEBUG;
    
    foreach $test (@$tests) {
        $self->debug("  - test: $test\n") if $DEBUG;
        if ($test eq ON) {
            return 1;
        }
        elsif ($type = ref $test) {
            if ($type eq CODE) {
#                $self->debug("calling code: ". $test->($item, $self));
                return 1 if $test->($item, $self);
            }
            elsif ($type eq REGEX) {
                return 1 if $item->$method =~ $test;
            }
            else {
                return $self->error_msg( bad_filter => $filter => $test );
            }
        }
        else {
            return 1 if $item->$method eq $test;
        }
    }
    $self->debug("  - ALL FAIL - ignore\n") if $DEBUG;
    return 0;
}


sub filter_file {
    my ($self, $file) = @_;
    return $self->filter( files    => name => $file )
      && ! $self->filter( no_files => name => $file );
}


sub filter_directory {
    my ($self, $dir) = @_;
    return $self->filter( dirs    => name => $dir )
      && ! $self->filter( no_dirs => name => $dir );
}


sub filter_entry {
    my ($self, $dir) = @_;
    return $self->filter( in_dirs     => name => $dir )
      && ! $self->filter( not_in_dirs => name => $dir );
}


sub accept_file {
    my ($self, $file) = @_;
    $self->debug("accept_file($file)") if DEBUG;
    $self->{ accept_file }->($self, $file)
        if $self->{ accept_file };
    return $self->collect($file);

#    return $self->filter( files    => name => @_ )
#      && ! $self->filter( no_files => name => @_ );
}


sub reject_file {
    my ($self, $file) = @_;
    $self->debug("reject_file($file)") if DEBUG;
    return $self->{ reject_file }
         ? $self->{ reject_file }->($self, $file)
         : 1;
}


sub accept_directory {
    my ($self, $dir) = @_;
    $self->debug("accept_dir($dir)") if DEBUG;
    $self->{ accept_dir }->($self, $dir) || return
        if $self->{ accept_dir };
    return $self->collect($dir);
}


sub reject_directory {
    my ($self, $dir) = @_;
    $self->debug("reject_directory($dir)") if DEBUG;
    return $self->{ reject_dir }
         ? $self->{ reject_dir }->($self, $dir)
         : 1;
}

sub enter_directory {
    my ($self, $dir) = @_;
    $self->debug("visiting directory children: $dir") if $DEBUG;
    $self->{ enter_dir }->($self, $dir) || return
        if $self->{ enter_dir };
    
    $_->accept($self)
        for $dir->children;
#        for $dir->children($self->{ all });
    return 1;
}


sub leave_directory {
    my ($self, $dir) = @_;
    $self->debug("leave_directory($dir)") if DEBUG;
    return $self->{ leave_dir }
         ? $self->{ leave_dir }->($self, $dir)
         : 1;
}


sub collect {
    my $self    = shift;
    my $collect = $self->{ collect };
    push(@$collect, @_) if @_;
    return wantarray
        ? @$collect
        :  $collect;
}


# identify() is not currently used

sub identify {
    my ($self, $params) = self_params(@_);
    my $identify = $self->{ identify };
    @$identify{ keys %$params } = values %$params
        if %$params;
    return wantarray
        ? %$identify
        :  $identify;
}


1;

__END__

=head1 NAME

Badger::Filesystem::Visitor - visitor for traversing filesystems

=head1 SYNOPSIS

    use Badger::Filesystem 'FS';
    
    my $controls = {
        files       => '*.pm',           # collect all *.pm files
        dirs        => 0,                # ignore dirs
        in_dirs     => 1,                # but do look in dirs for more files
        not_in_dirs => ['.svn', '.git'], # don't look in these dirs
    };
    
    my @files = FS
        ->dir('/path/to/dir')
        ->visit($controls)
        ->collect;

=head1 DESCRIPTION

The L<Badger::Filesystem::Visitor> module implements a base class visitor
object which can be used to traverse filesystems.  

The most common use of a visitor is to walk a filesystem and locate files and
directories matching (or not matching) a particular set of criteria (e.g. file
name, type, size, etc). The L<Badger::Filesystem::Visitor> module provides a
number of configuration options to assist in these common tasks. For more
complex operations, you can subclass the module to create your own custom
visitors.

The easiest way to create and use a visitor is to call the L<visit()> method
on any of the L<Badger::Filesystem> objects. In most cases, you'll want to
call it against a L<Badger::Filesystem::Directory> object, but there's nothing
to stop you from calling it against a L<Badger::Filesystem::File> object
(although your visitor won't have anywhere to visitor beyond that single file
so it doesn't serve any practical purpose).  If you call it against a 
top-level L<Badger::Filesystem> object then it will be applied to the root
directory of the filesystem.

    use Badger::Filesystem 'Dir';
    
    my $dir     = Dir('/path/to/search/dir');
    my $visitor = $dir->visit( files => 1, dirs => 0 );
    my $collect = $visitor->collect;

The L<visit()|Badger::Filesystem::Path/visit()> method will first create a
C<Badger::Filesystem::Visitor> object by delegating to the
L<Badger::Filesystem> L<visitor()|Badger::Filesystem/visitor()> method. This
configures the new visitor using any parameters passed as arguments, specified
either as a list or reference to a hash array of named parameters. If no
parameters are specified then the defaults are used.  The visitor's L<visit()>
method is then called, passing the L<Badger::Filesystem::Directory> object
as an argument.  And so begins the visitor's journey into the filesystem...

The configuration parameters are used to define what the visitor should 
collect on its travels.  Here are some examples.

    $dir->visit( 
        files => 1,                 # collect all files
        dirs  => 0,                 # ignore all dirs
    );

    $dir->visit( 
        files => '*.pm',            # collect all .pm files
        dirs  => 0,                 # ignore all dirs
    );

    $dir->visit(
        files   => '*.pm',          # as above, no dirs are collected
        dirs    => 0,               # but we do enter into them to 
        in_dirs => 1,               # find more files
    );

    $dir->visit( 
        files       => '*.pm',      # collect *.pm files
        dirs        => 0,           # don't collect dirs
        in_dirs     => 1,           # do recurse into them
        not_in_dirs => '.svn',      # but don't look in .svn dirs
    );
    
    $dir->visit(
        files   => 'foo'            # find all files named 'foo'
        dirs    => qr/ba[rz]/,      # and all dirs named 'bar' or 'baz'
        in_dirs => 1,               # recurse into subdirs
    );

You can also define subroutines to filter the files and/or directories that
you're interested in. The first argument passed to the subroutine is the
L<Badger::Filesystem::File> or L<Badger::Filesystem::Directory> object being
visited.  The second argument is a reference to the visitor object. 

In the following example, we collect files that are smaller than 420 bytes in
size, and directories that contain a F<metadata.yaml> file.

    $dir->visit(
        files   => sub { shift->size < 420 },
        dirs    => sub { shift->file('metadata.yaml')->exists }
        in_dirs => 1,
    );

You can also specify a reference to a list of items, each of which can be 
a simple flag (0/1), a name to match, regular expression or subroutine
reference.  Each will be tested in turn until the I<first> one matches.
If none match then the file or directory will be ignored.

    $dir->visit(
        files   => ['foo', qr/wiz/i, \&my_file_sub ],
        dirs    => [ qr/ba[rz]/, \&my_dir_sub ],
        in_dirs => 1,
    );

In addition to the inclusive matches show above, you can also tell the visitor
what to exclude. You can use any of the same pattern specifications as for the
inclusive options (0/1 flags, names, regexen, subroutines, or list refs
containing any of the above).

    $dir->visit( 
        no_files    => '*.bak',     
        no_dirs     => ['tmp', qr/backup/i],
        not_in_dirs => ['.svn', '.DS_Store'],
    );

When the visit is done, the L<collect()> method can be called to return
a list (in list context) or reference to a list (in scalar context) of the 
items that were collected.  The list will contain L<Badger::Filesystem::File>
and L<Badger::Filesystem::Directory> objects.

    my $collect = $visitor->collect;        # list ref in scalar context
    my @collect = $visitor->collect;        # list in list context

=head1 CONFIGURATION OPTIONS

NOTE: I'm planning the add the 'accept', 'ignore', 'enter', and 'leave'
aliases for 'files', 'no_files', 'in_dirs' and 'not_in_dirs'.  Can't think
of better names for 'dirs' and 'no_dirs' though...

=head2 files / accept (todo)

A pattern specifier indicating the files that you want to match.

=head2 no_files / ignore (todo)

A pattern specifier indicating the files that you don't want to match.

=head2 dirs / directories 

A pattern specifier indicating the directories that you want to match.

=head2 no_dirs / no_directories

A pattern specifier indicating the directories that you don't want to match.

=head2 in_dirs / in_directories / enter (todo)

A pattern specifier indicating the directories that you want to enter to 
search for further files and directories.

=head2 not_in_dirs / not_in_directories / leave (todo)

A pattern specifier indicating the directories that you don't want to enter to
search for further files and directories.

=head2 at_file

A reference to a subroutine that you want called whenever a file of interest
(i.e. one that is included by L<files> and not excluded by L<no_files>) is
visited.  The subroutine is passed a reference to the visitor object and
a reference to a L<Badger::Filesystem::File> object representing the file.

    $dir->visit(
        at_file => sub {
            my ($visitor, $file) = @_;
            print "visiting file: ", $file->name, "\n";
        }
    );

=head2 at_dir / at_directory

A reference to a subroutine that you want called whenever a directory of
interest (i.e. one that is included by L<dirs> and not excluded by
L<no_dirs>) is visited. The subroutine is passed a reference to the visitor
object and a reference to a L<Badger::Filesystem::Directory> object representing
the directory.

    $dir->visit(
        at_dir => sub {
            my ($visitor, $dir) = @_;
            print "visiting dir: ", $dir->name, "\n";
        }
    );

If the function returns a true value then the visitor will continue to 
visit any files or directories within it according to it's usual rules
(i.e. if the directory is listed in a L<not_in_dirs> rule then it won't
be entered).  If the function returns a false value then the directory
will be skipped.

=head1 METHODS

=head2 new(\%params)

Constructor method to create a new C<Badger::Filesystem::Visitor>.

=head1 TRAVERSAL METHODS

=head2 visit($node)

General purpose dispatch method to visit any node. This method calls the
L<accept()|Badger::Filesystem::Path/accept()> method on the C<$node>, passing
the visitor C<$self> reference as an argument. The C<$node> will then call
back to the correct method for the node type (e.g. L<visit_file()> or
L<visit_dir()>)

=head2 visit_path($path)

This method is called to visit base class L<Badger::Filesystem::Path>
objects. It doesn't do anything useful at present, but probably should.

=head2 visit_file($file)

This method is called to visit a L<Badger::Filesystem::File> object.

=head2 visit_directory($dir) / visit_dir($dir)

This method is called to visit a L<Badger::Filesystem::Directory> object.

=head2 visit_directory_children($dir) / visit_dir_kids($dir)

This method is called to visit the children of a
L<Badger::Filesystem::Directory> object.

=head1 SELECTION METHODS

=head2 accept_file($file)

This method applies any selection rules defined for the visitor to determine
if a file should be collected or not.  It returns a true value if it should,
or a false value if not.

=head2 accept_directory($dir) / accept_dir($dir)

This method applies any selection rules defined for the visitor to determine
if a directory should be collected or not. It returns a true value if it
should, or a false value if not.

=head2 enter_directory($dir) / enter_dir($dir)

This method applies any selection rules defined for the visitor to determine
if a directory should be entered or not. It returns a true value if it should,
or a false value if not.

=head2 filter($type,$method,$item)

This is a general purpose method which implements the selection algorithm 
for the above methods.  For example, the L<accept_file()> method is 
implemented as:

    return $self->filter( files    => name => $file )
      && ! $self->filter( no_files => name => $file );

The first argument provides the name of the configuration parameter which
defines the filter specification. The second argument is the name of the
file/directory method that returns the value that should be compared (in this
case, the file or directory name). The third argument is the file or directory
object itself.

=head1 COLLECTION METHODS

=head2 collect_file($file)

This method is called by the visitor when a file is accepted by the 
L<accept_file()> method.  If an L<at_file> handler is defined then it is
called, passing a reference to the visitor and the file being visited.  If
the handler returns a true value then the method goes on to call L<collect()>.
Otherwise it returns immediately.

If no L<at_file> handler is defined then the method delegates to L<collect()>.

=head2 collect_directory($dir) / collect_dir($dir)

This method is called by the visitor when a directory is accepted by the
L<accept_directory()> method. If an L<at_directory> handler is defined then it
is called, passing a reference to the visitor and the directory being visited
as arguments. If the handler returns a true value then the method goes on to
call L<collect()>. Otherwise it returns immediately and short-circuits any
further visits to files or directories contained within it.

If no L<at_directory> handler is defined then the method delegates to
L<collect()>.

=head2 collect(@items)

This method is used by the visitor to collect items of interest.  Any 
arguments passed are added to the internal C<collect> list.

    $visitor->collect($this, $that);

The list of collected items is returned in list context, or a reference to 
a list in scalar context.

    my $collect = $visitor->collect;
    my @collect = $visitor->collect;

=head2 identify(%items)

This method is similar to L<collect()> but is used to construct a lookup table
for identifying files and directories by name. In fact, it's currently not
currently used for anything, but may be one day RSN.

=head1 AUTHOR

Andy Wardley L<http://wardley.org/>

=head1 COPYRIGHT

Copyright (C) 2005-2009 Andy Wardley. All rights reserved.

=head1 SEE ALSO

L<Badger::Filesystem>

=cut

# Local Variables:
# mode: Perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
# TextMate: rocks my world

#========================================================================
#
# Badger::Filesystem::File
#
# DESCRIPTION
#   OO representation of a file in a filesystem.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
#========================================================================

package Badger::Filesystem::File;

use Badger::Class
    version     => 0.01,
    debug       => 0,
    base        => 'Badger::Filesystem::Path',
    constants   => 'ARRAY',
    constant    => {
        type    => 'File',
        is_file => 1,
    };

use Badger::Filesystem::Path ':fields';

sub init {
    my ($self, $config) = @_;
    my ($path, $vol, $dir, $name);
    my $fs = $self->filesystem;

    if ($config->{ path }) {
        $path = $self->{ path } = $fs->join_dir($config->{ path });
        @$self{@VDN_FIELDS} = $fs->split_path($path);
    }
    elsif ($self->{ name } = $config->{ name }) {
        @$self{@VD_FIELDS} = ($vol, $dir) = map { defined($_) ? $_ : '' } @$config{@VD_FIELDS};
        $self->{ path } = $fs->join_path($vol, $dir, $self->{ name });
    }
    else {
        $self->error_msg( missing => 'path or name' );
    }
    return $self;
}

sub directory {
    $_[0]->parent;
}

1;

#========================================================================
#
# Badger::Class::Methods
#
# DESCRIPTION
#   Class mixin module for adding methods to a class.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
#========================================================================

package Badger::Class::Methods;

use Badger::Class
    version   => 0.01,
    debug     => 0,
    base      => 'Badger::Base',
    import    => 'class BCLASS',
    constants => 'DELIMITER ARRAY HASH',
    utils     => 'is_object',
    exports   => {
        hooks => {
            init => \&initialiser,
            map { $_ => [\&generate, 1] }
            qw( accessors mutators get set slots hash )
        },
    },
    messages  => {
        no_target  => 'No target class specified to generate methods for',
        no_type    => 'No method type specified to generate',
        no_methods => 'No %s specified to generate',
        bad_method => 'Invalid %s method: %s',
        bad_type   => 'Invalid method generator specified: %s',
    };

# method aliases
*get = \&accessors;
*set = \&mutators;


sub generate {
    my $class   = shift;
    my $target  = shift
        || return $class->error_msg('no_target');
    my $type    = shift
        || return $class->error_msg('no_type');
    my $methods = shift
        || return $class->error_msg( no_methods => $type );
    my $code    = $class->can($type)
        || return $class->error_msg( bad_type => $type );

    $class->debug("generate($target, $type, $methods)") if DEBUG;
    
    $code->($class, $target, $methods);
}


sub accessors {
    my ($class, $target, $methods) = shift->args(@_);

    foreach (@$methods) {
        my $name = $_;              # new lexical var for closure
        $target->import_symbol(
            $name => sub {
                $_[0]->{ $name };
            }
        );
    }
}


sub mutators {
    my ($class, $target, $methods) = shift->args(@_);

    foreach (@$methods) {
        my $name = $_;              # new lexical var for closure
        $target->import_symbol(
            $name => sub {
                # You wouldn't ever want to write a real subroutine like this.
                # But that's OK, because we're here to do it for you.  You get
                # the efficiency without having to ever look at code like this:
                @_ == 2 
                    ? ($_[0]->{ $name } = $_[1])
                    :  $_[0]->{ $name };
            }
        );
    }
}


sub hash {
    my ($class, $target, $methods) = shift->args(@_);

    foreach (@$methods) {
        my $name = $_;              # new lexical var for closure
        $target->import_symbol(
            $name => sub {
                # return hash ref when called without args
                return $_[0]->{ $name } if @_ == 1;
                
                # return hash item when called with one non-ref arg
                return $_[0]->{ $name }->{ $_[1] } if @_ == 2 && ! ref $_[1];
                
                # add items to hash when called with hash ref or multiple args
                my $self  = shift;
                my $items = @_ == 1 && ref $_[0] eq HASH ? shift : { @_ };
                my $hash  = $self->{ $name };
                @$hash{ keys %$items } = values %$items;
                return $hash;
            }
        );
    }
}


sub initialiser {
    my ($class, $target, $methods) = shift->args(@_);

    $target->import_symbol(
        init => sub {
            my ($self, $config) = @_;
            $self->{ config } = $config;
            foreach my $name (@$methods) {
                $self->$name($config);
            }
            return $self;
        }
    );
}


sub slots {
    my ($class, $target, $methods) = shift->args(@_);
    my $index = 0;

    foreach my $method (@$methods) {
        my $i = $index++;           # new lexical var for closure
        $target->import_symbol(
            $method => sub {
                return @_ > 1
                    ? ($_[0]->[$i] = $_[1])
                    :  $_[0]->[$i];
            }
        );
    }
}


sub args {
    my $class   = shift;
    my $target  = shift;
    my $methods = @_ == 1 ? shift : [ @_ ];

    # update $target to a Badger::Class object if not already one
    $target  = class($target)
        unless is_object(BCLASS, $target);

    # split text string into list ref of method names
    $methods = [ split(DELIMITER, $methods) ] 
        unless ref $methods eq ARRAY;
    
    return ($class, $target, $methods);
}
        


1;

__END__

=head1 NAME

Badger::Class::Method - metaprogramming module for adding methods to a class

=head1 SYNOPSIS

    package My::Module;
    
    # using the module directly
    use Badger::Class::Methods
        accessors => 'foo bar',
        mutators  => 'wiz bang';
    
    # or via Badger::Class
    use Badger::Class
        accessors => 'foo bar',
        mutators  => 'wiz bang';

=head1 DESCRIPTION

This module can be used to generate methods for a class. It can be used
directly, or via the L<accessors|Badger::Class/accessors>, 
L<accessors|Badger::Class/accessors> and L<slots|Badger::Class/slots>
export hooks in L<Badger::Class>.

=head1 METHODS

=head2 generate($class,$type,$methods)

This method is a central dispatcher to other methods.

    Badger::Class::Methods->generate(
        accessors => 'foo bar',
    );

=head2 accessors($class,$methods) / get($class,$methods)

This method can be used to generate accessor (read-only) methods for a class
(L<Badger::Class> object) or package name. You can pass a list, reference to a
list, or a whitespace delimited string of method names as arguments.

    # these all do the same thing
    Badger::Class::Methods->accessors('My::Module', 'foo bar');
    Badger::Class::Methods->accessors('My::Module', 'foo', 'bar');
    Badger::Class::Methods->accessors('My::Module', ['foo', 'bar']);

A method will be generated in the target class for each that returns the
object member data of the same name. The code generated for each method is
equivalent to this:

    sub foo {
        $_[0]->{ foo };
    }

=head2 mutators($class,$methods) / set($class,$methods)

This method can be used to generate mutator (read/write) methods for a class
(L<Badger::Class> object) or package name. You can pass a list, reference to a
list, or a whitespace delimited string of method names as arguments.

    # these all do the same thing
    Badger::Class::Methods->mutators('My::Module', 'foo bar');
    Badger::Class::Methods->mutators('My::Module', 'foo', 'bar');
    Badger::Class::Methods->mutators('My::Module', ['foo', 'bar']);

A method will be generated in the target class for each that returns the
object member data of the same name. If an argument is passed then the 
member data is updated and the new value returned.

The code generated is equivalent to this:

    sub foo {
        @_ == 2 
            ? ($_[0]->{ foo } = $_[1])
            :  $_[0]->{ foo };
    }

Ugly isn't it?   But of course you wouldn't ever write it like that, being 
a conscientious Perl programmer concerned about the future readability and
maintainability of your code.  Instead you might write it something like
this:

    sub foo {
        my $self = shift;
        if (@_) {
            # an argument implies a set
            return ($self->{ foo } = shift);
        }
        else {
            # no argument implies a get
            return $self->{ foo };
        }
    }

Or perhaps like this:

    sub foo {
        my $self = shift;
        # update value if an argument was passed
        $self->{ foo } = shift if @_;
        return $self->{ foo };
    }

Or even like this (my personal favourite):

    sub foo {
        my $self = shift;
        return @_
            ? ($self->{ foo } = shift)
            :  $self->{ foo };
    }

Whichever way you do it is a waste of time, both for you and anyone who has to
read your code at a later. Seriously, give it up! Let us generate the methods
for you. We'll not only save you the effort of typing pages of code that
no-one will ever read (or want to read), but we'll also generate the most
efficient code for you. The kind that you wouldn't normally want to handle by
yourself.

So in summary, using this method will keep your code clean, your code 
efficient, and will free up the rest of the afternoon so you can go out 
skateboarding.  Tell your boss I said it was OK.

=head2 hash($class, $methods)

This method generates methods for accessing or updating items in a hash
reference stored in an object.  In the following example we create a 
C<users()> method for accessing the internal C<users> hash reference.

    package Your::Module;
    
    use base 'Badger::Base';
    use Badger::Class::Methods
        hash => 'users';
    
    sub init {
        my ($self, $config) = @_;
        $self->{ users } = $config->{ users } || { };
        return $self;
    }

The C<init()> method copies any C<users> passed as a configuration
parameter or creates an empty hash reference.

    my $object = Your::Module->new(
        users => {
            tom => 'tom@badgerpower.com',
        }
    );

When called without any arguments, the generated C<users()> method returns a
reference to the C<users> hash array.

    print $object->users->{ tom };  # tom@badgerpower.com

When called with a single non-reference argument, it returns the entry
in the hash corresponding to that key.

    print $object->users('tom');    # tom@badgerpower.com

When called with a single reference to a hash array, or a list of named 
parameters, the method will add the new items to the internal hash array.
A reference to the hash array is returned.

    $object->users({                        # single hash ref
        dick  => 'richard@badgerpower.com', 
        harry => 'harold@badgerpower.com',
    });
    
    $object->users(                         # list of amed parameters
        dick  => 'richard@badgerpower.com', 
        harry => 'harold@badgerpower.com',
    );

=head2 initialiser($class,$methods)

This method can be used to create a custom C<init()> method for your object
class. A list, reference to a list, or string of whitespace delimited method
names should be passed an argument(s). A method will be generated which 
calls each in turn, passing a reference to a hash array of configuration
parameters.

    use Badger::Class::Methods->initialiaser(
        'My::Module', 
        'init_foo init_bar'
    )

The above example will generate an C<init()> method in C<My::Module>
equivalent to:

    sub init {
        my ($self, $config) = @_;
        $self->{ config } = $config;
        $self->init_foo($config);
        $self->init_bar($config);
        return $self;
    }

It's up to you to implement the C<init_foo()> and C<init_bar()> methods,
or to inherit them from a base class or mixin.

=head2 slots($class,$methods)

This method can be used to define methods for list-based object classes.
A list, reference to a list, or string of whitespace delimited method
names should be passed an argument(s).  A method will be generated for
each item specified.  The first method will reference the first (0th) item
in the list, the second method will reference the second (1st), and so on.

    Badger::Class::Methods->slots('My::Module', 'foo bar');
    Badger::Class::Methods->slots('My::Module', 'foo', 'bar');
    Badger::Class::Methods->slots('My::Module', ['foo', 'bar']);

It is usually called indirectly via the L<slots|Badger::Class/slots>
export hook in L<Badger::Class>.

    package Badger::Example;
    
    use Badger::Class
        slots => 'size colour object';
    
    sub new {
        my ($class, @stuff) = @_;
        bless \@stuff, $class;
    }

The above example defines a simple list-based object class with three
slots: C<size>, C<colour> and C<object>.  You can use it like this:

    my $bus = Badger::Test::Slots->new(qw( big red bus ));
    
    print $bus->size;       # big
    print $bus->colour;     # red
    print $bus->object;     # bus

The methods generated are mutators.  That is, you can pass an argument
to update the slot value.

    $bus->size('large');

=head1 INTERNAL METHODS

=head2 args(@args)

This methods inspect the arguments and performs the necessary validation
for the L<accessors()>, L<mutators()> and L<slots()> methods.

=head1 AUTHOR

Andy Wardley L<http://wardley.org/>

=head1 COPYRIGHT

Copyright (C) 2008-2009 Andy Wardley.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:

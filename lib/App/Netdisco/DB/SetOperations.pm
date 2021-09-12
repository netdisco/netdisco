package App::Netdisco::DB::SetOperations;

use strict;
use warnings;

use parent 'DBIx::Class::Helper::ResultSet::SetOperations';

sub _set_operation {
   my ( $self, $operation, $other ) = @_;
 
   my @sql;
   my @params;
 
   my $as = $self->_resolved_attrs->{as};
 
   my @operands = ( $self, ref $other eq 'ARRAY' ? @$other : $other );
 
   for (@operands) {
      $self->throw_exception("ResultClass of ResultSets do not match!")
         unless $self->result_class eq $_->result_class;
 
      my $attrs = $_->_resolved_attrs;
 
      $self->throw_exception('ResultSets do not all have the same selected columns!')
         unless $self->_compare_arrays($as, $attrs->{as});
 
      my ($sql, @bind) = @{${$_->as_query}};
      # $sql =~ s/^\s*\((.*)\)\s*$/$1/;
      $sql = q<(> . $sql . q<)>;
 
      push @sql, $sql;
      push @params, @bind;
   }
 
   my $query = q<(> . join(" $operation ", @sql). q<)>;

   my $attrs = $self->_resolved_attrs;
   return $self->result_source->resultset->search(undef, {
      alias => $self->current_source_alias,
      from => [{
         $self->current_source_alias => \[ $query, @params ],
         -alias                      => $self->current_source_alias,
         -source_handle              => $self->result_source->handle,
      }],
      columns => $attrs->{as},
      result_class => $self->result_class,
   });
}

1;

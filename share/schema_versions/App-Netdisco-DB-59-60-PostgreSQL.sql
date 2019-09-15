BEGIN;

CREATE EXTENSION IF NOT EXISTS plperl;

CREATE OR REPLACE FUNCTION match(text, text) RETURNS bool LANGUAGE plperl AS $__$ ($_[0] =~ m/$_[1]/) ? true : false; $__$;

COMMIT;

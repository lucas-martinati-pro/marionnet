/*This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009, 2010  Luca Saiu

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. */


#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <libintl.h>

#include <caml/mlvalues.h>
/* If I don't #include caml/alloc.h then this module compiles fine, but then crashes
   at runtime. Funny, isn't it? */
#include <caml/alloc.h>
#include <caml/memory.h>

/* Some part of the gettext initialization should only be performed once: */
static bool was_gettext_initialized = false;

/* Initialize gettext, using the locale specified by the user with environment variables: */
void initialize_gettext_c(const char *text_domain,
                          const char *locales_directory){
  /* Set the locale if we have not initialized yet: */
  if(! was_gettext_initialized){
    if(setlocale (LC_ALL, "") == NULL) // "" means that we look at the environment
      printf("WARNING: setlocale() returned NULL. Inernationalization will not work.\n");
    was_gettext_initialized = true;
  } // outer if

  /* Now we're sure that gettext is initialized.  Bind the particular text domain the
     user requested: */
  bindtextdomain(text_domain, locales_directory);

  /* Notice that we don't call textdomain() any longer, as we don't use gettext() any longer:
     we only use dgettext(), where the text domain is an explicit parameter. */
  //textdomain(text_domain);
  //printf("[gettext was initialized: >%s<, >%s<]\n", text_domain, locales_directory); fflush(stdout);
}

/* Trivially convert the parameter representation and call another C function to do the work,
   paying attention not to violate the garbage collector constraints: */
CAMLprim value initialize_gettext_primitive(value text_domain, value locales_directory){
  /* The two parameters are GC roots: */
  CAMLparam2(text_domain, locales_directory);

  /* Convert from OCaml strings to C strings: */
#ifdef OCAML4_07_OR_LATER
  char *text_domain_as_a_c_string = Bytes_val(text_domain);
  char *locales_directory_as_a_c_string = Bytes_val(locales_directory);
#else
  const char *text_domain_as_a_c_string = String_val(text_domain);
  const char *locales_directory_as_a_c_string = String_val(locales_directory);
#endif

  /* Do the actual work: */
  initialize_gettext_c(text_domain_as_a_c_string,
                       locales_directory_as_a_c_string);

  /* Return. It's essential to use this macro, and not C's return statement: */
  CAMLreturn(Val_unit);
}

/* Trivially convert the parameter representation and call another C function to do the work,
   paying attention not to violate the garbage collector constraints: */
CAMLprim value dgettext_primitive(value text_domain_as_an_ocaml_string,
                                  value english_text_as_an_ocaml_string){
  /* The parameter is a GC root: */
  CAMLparam2(text_domain_as_an_ocaml_string,
             english_text_as_an_ocaml_string);

  /* The result will be another root: the documentation says to declare it here,
     and I've seen that it's initialized to zero, so it's ok if I don't set it.
     A GC can occur in the body, and it won't see any uninitialized object of
     type value: */
  CAMLlocal1(result_as_an_ocaml_string);

  /* Convert from OCaml strings to C strings: */
#ifdef OCAML4_07_OR_LATER
  char *text_domain_as_a_c_string = Bytes_val(text_domain_as_an_ocaml_string);
  char *english_text_as_a_c_string = Bytes_val(english_text_as_an_ocaml_string);
#else
  const char *text_domain_as_a_c_string = String_val(text_domain_as_an_ocaml_string);
  const char *english_text_as_a_c_string = String_val(english_text_as_an_ocaml_string);
#endif

  /* Do the actual work, obtaining a C string (which may be overwritten by the next
     gettext() call): */
  char *result_as_a_c_string = dgettext(text_domain_as_a_c_string,
                                        english_text_as_a_c_string);

  /* Convert from a C string to an OCaml string, using a temporary variable which
     is of course another GC root. The variable will refer a *copy* of the string,
     so the buffer at result_as_a_c_string can be safely overwritten later: */
  result_as_an_ocaml_string = caml_copy_string(result_as_a_c_string);

  /* printf("[gettext_primitive is about to return]\n"); fflush(stdout); */
  /* Return. It's essential to use this macro, and not C's return statement: */
  CAMLreturn(result_as_an_ocaml_string);
}

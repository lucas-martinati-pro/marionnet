/* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2010  Daniele Terreni

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


#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <assert.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/unixsupport.h>
#include <caml/threads.h>

#define WAITPID_NAME "waitpid"

typedef enum {
  WENOHANG,
  WEUNTRACED,
  WECONTINUE
} waitpid_flag;

typedef enum {
  WEUNCHANGED,
  WECONTINUED
} process_status_arity_0_constructors;

typedef enum {
  WEEXITED,
  WESIGNALED,
  WESTOPPED
} process_status_arity_1_constructors;

static int c_of_caml_waitpid_option(value ml_flag)
{
  switch(Int_val(ml_flag)){
    case WENOHANG:  return WNOHANG;
    case WEUNTRACED:  return WUNTRACED;
#ifdef WIFCONTINUED
    case WECONTINUE:  return WCONTINUED;
#else
    case WECONTINUE:  return 0;
#endif
  default: assert(0);
  }
}

CAMLprim value waitpid_c (value ml_flag_list, value ml_child_pid)
{
  int   options     = 0;
  pid_t child_pid   = 0;
  pid_t wpid        = 0;
  int   status      = 0;

  CAMLparam2(ml_flag_list, ml_child_pid);
  CAMLlocal3(flag, res, process_status);

  /* Retreiving the flag bit mask */
  while(ml_flag_list != Val_emptylist){
    flag = Field(ml_flag_list, 0);
    options = options | c_of_caml_waitpid_option(flag);
    ml_flag_list = Field(ml_flag_list, 1);
  }

  child_pid = Int_val(ml_child_pid);

  enter_blocking_section();
  wpid = waitpid(child_pid, &status, options);
  leave_blocking_section();

  if(wpid == -1){
    uerror(WAITPID_NAME, Nothing);
  }
  else {
    res = alloc_tuple(2);
    Store_field(res, 0, Val_int(wpid));

    if(wpid == 0){
    /* Waitpid launched with WNOHANG option: no state change 
       detected. Returning 0, WUNCHANGED */
      Store_field(res, 1, Val_int(WEUNCHANGED));
    }
    else{
      int tag_value;
      int code;

      /* State change detected */
#ifdef WIFCONTINUED
      if (WIFCONTINUED(status)) {
	Store_field(res, 1, Val_int(WECONTINUED));
	CAMLreturn(res);
      }
      else
#endif

      if (WIFEXITED(status)){
	tag_value = WEEXITED;
	code = WEXITSTATUS(status);
      }
      else if (WIFSIGNALED(status)) {
	tag_value = WESIGNALED;
	code = WTERMSIG(status);
      }
      else if (WIFSTOPPED(status)) {
	tag_value = WESTOPPED;
	code = WSTOPSIG(status);
      }
      else {
	uerror(WAITPID_NAME, Val_unit);
      }
      
      process_status = caml_alloc(1,tag_value);
      Store_field(process_status, 0, Val_int(code));
      Store_field(res, 1, process_status);
    }
  }

  CAMLreturn(res);
}

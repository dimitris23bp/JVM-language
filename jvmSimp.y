%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sglib.h"

/* Just for being able to show the line number were the error occurs.*/
extern FILE *yyout;
extern int yylineno;
int the_errors = 0;
extern int yylex();
int yyerror(const char *);

/* The file that contains all the functions */
#include "jvmSimp.h"

#define TYPEDESCRIPTOR(TYPE) ((TYPE == type_integer) ? "I" : "F")

%}
/* Output informative error messages (bison Option) */
%define parse.error verbose

/* Declaring the possible types of Symbols*/
%union{
  char *lexical;
  int intval;
  struct {
    ParType type;
    char *place;
    int num;
  } se;
}

/* Token declarations and their respective types */
%token <lexical> T_num
%token <lexical> T_real
%token '('
%token ')'
%token <lexical> T_id
%token T_start "start"
%token T_end "end"
%token T_print "print"
%token T_type_integer "int"
%token T_type_float "float"
%token T_inc "inc"
%token T_absolute "abs"
%token T_max "max"
%token T_min "min"

%type<se> expr
%type<intval> minmax
%type<intval> casting
%type<intval> operation

%%

program: "start" T_id {create_preample($2); symbolTable=NULL; }
			stmts "end"
			{fprintf(yyout,"return \n.end method\n\n");
  };

/* A simple (very) definition of a list of statements.*/
stmts:  '(' stmt ')' maybeStmts {/* nothing */}
  |  '(' error ')' stmts 
  ;

maybeStmts: /* Empty */
  | stmts 
  ;

stmt:  asmt	{/* nothing */}
	| printcmd {/* nothing */}
	;
 
printcmd: 
  "print" expr {
    if(typePrefix($2.type) != "error"){
      fprintf(yyout,"getstatic java/lang/System/out Ljava/io/PrintStream;\n");
      fprintf(yyout,"swap\n");
      fprintf(yyout,"invokevirtual java/io/PrintStream/println(%s)V\n", TYPEDESCRIPTOR($2.type));
    } else {
      printf("Variable %s NOT initialised, in line %d.\n", $2.place, yylineno);
      yyerror("Variable fault");
    }
  };

asmt: T_id expr {  
    if(lookup_type($1) == $2.type || !lookup_type($1)){
      addvar($1, $2.type);
      fprintf(yyout, "%sstore %d\n", typePrefix($2.type), lookup_position($1) );	
    } else {
      yyerror("Variable fault");
    }
  }; 

expr: T_num {
    $$.type = type_integer; 
    $$.place = malloc(strlen($1)+1);
    strcpy($$.place, $1); 
    fprintf(yyout,"sipush %s\n",$1);}
  | T_real {
    $$.type = type_real; 
    $$.place = malloc(strlen($1)+1);
    strcpy($$.place, $1); 
    fprintf(yyout,"ldc %s\n",$1);}
  | T_id { 
    $$.type = lookup_type($1);
    $$.place = malloc(strlen($1)+1);
    strcpy($$.place, $1); 

    fprintf(yyout, "%sload %d\n", typePrefix($$.type), lookup_position($1));
  }
  | expr expr operation {
    
    if(typePrefix($1.type) == "error"){
      printf("Variable %s NOT initialised, in line %d. \n", $1.place, yylineno);
      yyerror("Variable fault");
    }
    
    if(typePrefix($2.type) == "error"){
      printf("Variable %s NOT initialised, in line %d. ", $2.place, yylineno);
      yyerror("Variable fault");
    }

    $$.type = typeDefinition($1.type, $2.type); 

    if($3 == 0){
      fprintf(yyout,"%sadd \n",typePrefix($$.type));
    } else {
      fprintf(yyout,"%smul \n",typePrefix($$.type));
    }
  }
  | '(' T_id "inc" ')' {
    $$.type = lookup_type($2);
    fprintf(yyout, "%sload %d\n", typePrefix($$.type), lookup_position($2));
    fprintf(yyout, "%sinc %d 1\n", typePrefix($$.type), lookup_position($2));
  }
  | '(' "inc" T_id  ')'{
    $$.type = lookup_type($3);
    fprintf(yyout, "%sinc %d 1\n", typePrefix($$.type), lookup_position($3));
    fprintf(yyout, "%sload %d\n", typePrefix($$.type), lookup_position($3));
  }
  | '(' casting expr ')'{

    // If it is equals to 0, it is integer, otherwise it's real
    if($2 == 0){
      if($3.type == type_real){
        fprintf(yyout,"f2i\n");
      } else {
        printf("Warning: value is already int, in line %d\n", yylineno);
      }
      $$.type = type_integer;
    } else {
      if($3.type == type_integer){
        fprintf(yyout,"i2f\n");
      } else {
        printf("Warning: value is already real, in line %d\n", yylineno);
      }
      $$.type = type_real;
    }
  }
  | '(' expr ')' {
    $$.type = $2.type;
  }
  | expr "abs" {
    $$.type = $1.type;
    fprintf(yyout,"invokestatic java/lang/Math/abs(%s)%s\n", TYPEDESCRIPTOR($1.type), TYPEDESCRIPTOR($1.type));
  }
  | expr expr minmax {
    
    $$.type = typeDefinition($1.type, $2.type);

    if($$.type == type_error){
      if($3 == 0){
        fprintf(yyout, "invokestatic java/lang/Math/min(%s%s)%s\n", TYPEDESCRIPTOR($1.type), TYPEDESCRIPTOR($2.type), TYPEDESCRIPTOR($$.type)); 
      } else{
        fprintf(yyout, "invokestatic java/lang/Math/max(%s%s)%s\n", TYPEDESCRIPTOR($1.type), TYPEDESCRIPTOR($2.type), TYPEDESCRIPTOR($$.type)); 
      }

    }
  };

/*
 minmax has a type: int. (I use it as a boolean)
 When this value is equals to 0, it is a min
 Otherwise, it is a max
 That way, I don't have to specify each expression differently

  casting and operation works the same way
 */
 minmax: "min" {
    $$ = 0;
  }
  | "max" {
    $$ = 1; 
  };

casting: "int" {
    $$ = 0;
  }
  | "float" {
    $$ = 1; 
  };

operation: '+' {
  $$ = 0;
  }
  | '*' {
    $$ = 1;
  };
  
%%

/* The usual yyerror */
int yyerror (const char * msg)
{
  fprintf(stderr, "ERROR: %s. on line %d.\n", msg,yylineno);
  the_errors++;
}

/* Other error Functions*/
/* The lexer... */
#include "jvmSimpLex.c"

/* Main */
int main(int argc, char **argv ){

  ++argv, --argc;  /* skip over program name */
  if ( argc > 0 )
      yyin = fopen( argv[0], "r" );
  else
      yyin = stdin;
  if ( argc > 1)
      yyout = fopen( argv[1], "w");
  else
	    yyout = stdout;

  int result = yyparse();
  printf("Errors found %d.\n",the_errors);
  fclose(yyout);
  if (the_errors != 0 && yyout != stdout) {
    remove(argv[1]);
    printf("No Code Generated.\n");
  }

  //print_symbol_table(); /* uncomment for debugging. */

  return result;
}

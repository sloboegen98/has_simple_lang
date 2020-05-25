parser grammar HaskellParser;

options { tokenVocab=HaskellLexer; }

@parser::members {
    bool MultiWayIf = true;
    bool MagicHash  = true;
    bool FlexibleInstances = true;

    bool FunctionalDependencies = true;
    bool TypeFamilies = true;
    bool GADTs = true;
    bool StandaloneDeriving = true;
    bool DerivingVia = true;
    bool LambdaCase = true;
    bool EmptyCase  = true;
    bool RecursiveDo = true;
}

module :  semi* pragmas? semi* (module_content | body) EOF;

module_content
    :
    'module' modid exports? where_module
    ;

where_module
    :
    'where' module_body
    ;

module_body
    :
    open body close semi*
    ;

pragmas
    :
    pragma+
    ;

pragma
    :
    '{-#' 'LANGUAGE'  extension (',' extension)* '#-}' SEMI?
    ;

extension
    :
    CONID
    ;

body
    :
    (impdecls topdecls)
    | impdecls
    | topdecls
    ;

impdecls
    :
    (impdecl | NEWLINE | semi)+
    ;

exports
    :
    '(' (exprt (',' exprt)*)? ','? ')'
    ;

exprt
    :
    qvar
    | ( qtycon ( ('(' '..' ')') | ('(' (cname (',' cname)*)? ')') )? )
    | ( qtycls ( ('(' '..' ')') | ('(' (qvar (',' qvar)*)? ')') )? )
    | ( 'module' modid )
    ;

impdecl
    :
    'import' 'qualified'? modid ('as' modid)? impspec? semi+
    ;

impspec
    :
    ('(' (himport (',' himport)* ','?)? ')')
    | ( 'hiding' '(' (himport (',' himport)* ','?)? ')' )
    ;

himport
    :
    var
    | ( tycon ( ('(' '..' ')') | ('(' (cname (',' cname)*)? ')') )? )
    | ( tycls ( ('(' '..' ')') | ('(' sig_vars? ')') )? )
    ;

cname
    :
    var | con
    ;

// -------------------------------------------
// Fixity Declarations

fixity: 'infix' | 'infixl' | 'infixr';

ops : op (',' op)*;

// -------------------------------------------
// Top-Level Declarations
topdecls : (topdecl semi+| NEWLINE | semi)+;

topdecl
    :
    cl_decl
    | ty_decl
    // Check KindSignatures
    | standalone_kind_sig
    | inst_decl
    | {StandaloneDeriving}? standalone_deriving
    | ('default' '(' (type (',' type)*)? ')' )
    | ('foreign' fdecl)
    | ('{-#' 'DEPRECATED' deprecations? '#-}')
    | ('{-#' 'WARNING' warnings? '#-}')
    | ('{-#' 'RULES' rules? '#-}')
    | decl_no_th
    // -- Template Haskell Extension
    //  The $(..) form is one possible form of infixexp
    //  but we treat an arbitrary expression just as if
    //  it had a $(..) wrapped around it
    | infixexp
    ;

// Type classes
// 
cl_decl
    :
    'class' tycl_hdr fds? where_cls?
    ;

// Type declarations (toplevel)
// 
ty_decl
    :
    // ordinary type synonyms
    ('type' type '=' ktypedoc)
    // type family declaration
    | ('type' 'family' type opt_tyfam_kind_sig opt_injective_info? where_type_family?)
    // ordinary data type or newtype declaration
    | ('data' (typecontext '=>')? simpletype ('=' constrs)? derivings?)
    | ('newtype' (typecontext '=>')? simpletype '=' newconstr derivings?)
    // GADT declaration
    | ('data' capi_ctype? tycl_hdr opt_kind_sig? gadt_constrlist? derivings?)
    | ('newtype' capi_ctype? tycl_hdr opt_kind_sig?)
    // data family
    | ('data' 'family' type opt_datafam_kind_sig?)
    ;

// standalone kind signature

standalone_kind_sig
    :
    'type' sks_vars '::' ktypedoc
    ;

// See also: sig_vars
sks_vars
    :
    oqtycon (',' oqtycon)*
    ;

inst_decl
    :
    ('instance' overlap_pragma? inst_type where_inst?)
    | ('type' 'instance' ty_fam_inst_eqn)
    // 'constrs' in the end of this rules in GHC
    // This parser no use docs
    | ('data' 'instance' capi_ctype? tycl_hdr_inst derivings?)
    | ('newtype' 'instance' capi_ctype? tycl_hdr_inst derivings?)
    // For GADT
    | ('data' 'instance' capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    | ('newtype' 'instance' capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    ;

overlap_pragma
    :
      '{-#' 'OVERLAPPABLE' '#-}'
    | '{-#' 'OVERLAPPING' '#-}'
    | '{-#' 'OVERLAPS' '#-}'
    | '{-#' 'INCOHERENT' '#-}'
    ;


deriv_strategy_no_via
    :
      'stock'
    | 'anyclass'
    | 'newtype'
    ;

deriv_strategy_via
    :
    'via' ktype
    ;

deriv_standalone_strategy
    :
    'stock'
    | 'anyclass'
    | 'newtype'
    | deriv_strategy_via
    ;

// Injective type families

opt_injective_info
    :
    '|' injectivity_cond
    ;

injectivity_cond
    :
    // but in GHC new tyvarid rule
    tyvarid
    | (tyvarid '->' inj_varids)
    ;

inj_varids
    :
    tyvarid+
    ;

// Closed type families

where_type_family
    :
    'where' ty_fam_inst_eqn_list
    ;

ty_fam_inst_eqn_list
    :
    (open ty_fam_inst_eqns? close)
    | ('{' '..' '}')
    | (open '..' close)
    ;

ty_fam_inst_eqns
    :
    ty_fam_inst_eqn (semi ty_fam_inst_eqn)* semi?
    ;

ty_fam_inst_eqn
    :
    'forall' tv_bndrs '.' type '=' ktype
    | type '=' ktype
    ;

//  Associated type family declarations

//  * They have a different syntax than on the toplevel (no family special
//    identifier).

//  * They also need to be separate from instances; otherwise, data family
//    declarations without a kind signature cause parsing conflicts with empty
//    data declarations.

at_decl_cls
    :
    ('data' 'family'? type opt_datafam_kind_sig?)
    | ('type' 'family'? type opt_at_kind_inj_sig?)
    | ('type' 'instance'? ty_fam_inst_eqn)
    ;

// Associated type instances
at_decl_inst
    :
    // type instance declarations, with optional 'instance' keyword
    ('type' 'instance'? ty_fam_inst_eqn)
    // data/newtype instance declaration, with optional 'instance' keyword
    | ('data' 'instance'? capi_ctype? tycl_hdr_inst constrs derivings?)
    | ('newtype' 'instance'? capi_ctype? tycl_hdr_inst constrs derivings?)
    // GADT instance declaration, with optional 'instance' keyword
    | ('data' 'instance'? capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    | ('newtype' 'instance'? capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    ;

// Family result/return kind signatures

opt_kind_sig
    :
    '::' kind
    ;

opt_datafam_kind_sig
    :
    '::' kind
    ;

opt_tyfam_kind_sig
    :
    ('::' kind)
    | ('=' tv_bndr)
    ;

opt_at_kind_inj_sig
    :
    ('::' kind)
    | ('=' tv_bndr '|' injectivity_cond)
    ;

tycl_hdr
    :
    (tycl_context '=>' type)
    | type
    ;

tycl_hdr_inst
    :
    ('forall' tv_bndrs '.' tycl_context '=>' type)
    | ('forall' tv_bndr '.' type) 
    | (tycl_context '=>' type)
    | type
    ;

capi_ctype
    :
    ('{-#' 'CTYPE' STRING STRING '#-}')
    | ('{-#' 'CTYPE' STRING '#-}')
    ;

// -------------------------------------------
// Stand-alone deriving

standalone_deriving
    :
    'deriving' deriv_standalone_strategy? 'instance' overlap_pragma? inst_type
    ;

// -------------------------------------------

// Role annotations
// TODO

// -------------------------------------------

// Pattern synonyms
// TODO

// -------------------------------------------
// Nested declaration

// Declaration in class bodies

decl_cls
    :
    at_decl_cls
    | decl
    // | 'default' infixexp '::' sigtypedoc
    ;

decls_cls
    :
    (decl_cls semi+)* decl_cls semi*
    ;

decllist_cls
    :
    open decls_cls? close
    ;

// Class body
// 
where_cls
    :
    'where' decllist_cls
    ;

// Declarations in instance bodies
//
decl_inst
    :
    at_decl_inst
    | decl
    ;

decls_inst
    :
    decl_inst (semi+ decl_inst)* semi*
    ;

decllist_inst
    :
    open decls_inst? close
    ;

// Instance body
// 
where_inst
    :
    'where' decllist_inst
    ;

// Declarations in binding groups other than classes and instances
// 
decls
    :
    (decl semi+)* decl semi*
    ;

decllist
    :
    open decls? close
    ;

// Binding groups other than those of class and instance declarations
// 
binds
    :
    decllist
    | (open dbinds? close)
    ;

wherebinds
    :
    'where' binds
    ;


// -------------------------------------------
// Transformation Rules

rules
    :
    pragma_rule (semi pragma_rule)* semi?
    ;

pragma_rule
    :
    pstring rule_activation? rule_foralls? infixexp '=' exp
    ;

rule_activation_marker
    :
    '~' | varsym
    ;

rule_activation
    :
    ('[' integer ']')
    | ('[' rule_activation_marker integer ']')
    | ('[' rule_activation_marker ']')
    ;

rule_foralls
    :
    ('forall' rule_vars? '.' ('forall' rule_vars? '.')?)
    ;

rule_vars
    :
    rule_var+
    ;

rule_var
    :
    varid
    | ('(' varid '::' ctype ')')
    ;

// -------------------------------------------
// Warnings and deprecations (c.f. rules)

warnings
    :
    pragma_warning (semi pragma_warning)* semi?
    ;

pragma_warning
    :
    namelist strings
    ;

deprecations
    :
    pragma_deprecation (semi pragma_deprecation)* semi?
    ;

pragma_deprecation
    :
    namelist strings
    ;

strings
    :
    pstring
    | ('[' stringlist? ']')
    ;

stringlist
    :
    pstring (',' pstring)*
    ;

// -------------------------------------------

// Annotations
// TODO

// -------------------------------------------
// Foreign import and export declarations

fdecl
    :
    ('import' callconv safety? fspec)
    | ('export' callconv fspec)
    ;

callconv
    :
    'ccall' | 'stdcall' | 'cplusplus' | 'javascript'
    ;

safety : 'unsafe' | 'safe' | 'interruptible'; 

fspec
    :
    pstring? var '::' sigtypedoc
    ; 

// -------------------------------------------
// Type signatures

opt_sig : '::' sigtype;

opt_tyconsig : '::' gtycon;

sigtype
    :
    ctype
    ;

sigtypedoc
    :
    ctypedoc
    ;

sig_vars
    :
    var (',' var)*
    ;

// -------------------------------------------
// Types

unpackedness
    :
      ('{-#' 'UNPACK'   '#-}')
    | ('{-#' 'NOUNPACK' '#-}')
    ;

forall_vis_flag
    :
    '.'
    | '->'
    ;

// A ktype/ktypedoc is a ctype/ctypedoc, possibly with a kind annotation
ktype
    :
    ctype
    | (ctype '::' kind)
    ;

ktypedoc
    :
    ctypedoc
    | ctypedoc '::' kind
    ;

// A ctype is a for-all type
ctype
    :
    'forall' tv_bndrs forall_vis_flag ctype
    | btype '=>' ctype
    | var '::' type // not sure about this rule
    | type
    ;

ctypedoc
    :
    'forall' tv_bndrs forall_vis_flag ctypedoc
    | tycl_context '=>' ctypedoc
    | var '::' type
    | typedoc
    ;

// In GHC this rule is context
tycl_context
    :
    btype
    ;

// constr_context rule

// {- Note [GADT decl discards annotations]
// ~~~~~~~~~~~~~~~~~~~~~
// The type production for

//     btype `->`         ctypedoc
//     btype docprev `->` ctypedoc

// add the AnnRarrow annotation twice, in different places.

// This is because if the type is processed as usual, it belongs on the annotations
// for the type as a whole.

// But if the type is passed to mkGadtDecl, it discards the top level SrcSpan, and
// the top-level annotation will be disconnected. Hence for this specific case it
// is connected to the first type too.
// -}

type
    :
    btype
    | btype '->' ctype
    ;

typedoc
    :
    btype
    | btype '->' ctypedoc
    ;

btype
    :
    tyapps
    ;

tyapps
    :
    tyapp+
    ;

tyapp
    :
    atype
    | ('@' atype)
    | qtyconop
    | tyvarop
    | ('\'' qconop)
    | ('\'' varop)
    | unpackedness
    ;

atype
    :
    gtycon
    | tyvar
    | '*'
    | ('{' fielddecls '}')
    | ('(' ')')
    | ('(' ktype (',' ktype)* ')')
    | ('[' ktype ']')
    | ('(' ktype ')')
    | ('[' ktype (',' ktype)* ']')
    | quasiquote
    | splice_untyped
    | ('\'' qcon_nowiredlist)
    | ('\'' '(' ktype (',' ktype)*)
    | ('\'' '[' ']')
    | ('\'' '[' ktype (',' ktype)* ']')
    | ('\'' var)
    | integer
    | STRING
    | '_'
    ;

inst_type
    :
    sigtype
    ;

deriv_types
    :
    ktypedoc (',' ktypedoc)*
    ;

tv_bndrs
    :
    tv_bndr+
    ;

tv_bndr
    :
    tyvar
    | ('(' tyvar '::' kind ')')
    ;

fds
    :
    '|' fds1
    ;

fds1
    :
    fd (',' fd)*
    ;

fd
    :
    varids0? '->' varids0?
    ;

varids0
    :
    tyvar+
    ;


// -------------------------------------------
// Kinds

kind
    :
    ctype
    ;

// {- Note [Promotion]
//    ~~~~~~~~~~~~~~~~

// - Syntax of promoted qualified names
// We write 'Nat.Zero instead of Nat.'Zero when dealing with qualified
// names. Moreover ticks are only allowed in types, not in kinds, for a
// few reasons:
//   1. we don't need quotes since we cannot define names in kinds
//   2. if one day we merge types and kinds, tick would mean look in DataName
//   3. we don't have a kind namespace anyway

// - Name resolution
// When the user write Zero instead of 'Zero in types, we parse it a
// HsTyVar ("Zero", TcClsName) instead of HsTyVar ("Zero", DataName). We
// deal with this in the renamer. If a HsTyVar ("Zero", TcClsName) is not
// bounded in the type level, then we look for it in the term level (we
// change its namespace to DataName, see Note [Demotion] in GHC.Types.Names.OccName).
// And both become a HsTyVar ("Zero", DataName) after the renamer.

// -}

// -------------------------------------------
// Datatype declarations

gadt_constrlist
    :
    'where' open gadt_constrs? semi* close
    ;

gadt_constrs
    :
    gadt_constr_with_doc (semi gadt_constr_with_doc)*
    ;

// We allow the following forms:
//      C :: Eq a => a -> T a
//      C :: forall a. Eq a => !a -> T a
//      D { x,y :: a } :: T a
//      forall a. Eq a => D { x,y :: a } :: T a

gadt_constr_with_doc
    :
    gadt_constr
    ;

gadt_constr
    :
    con_list '::' sigtypedoc
    ;


// {- Note [Difference in parsing GADT and data constructors]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// GADT constructors have simpler syntax than usual data constructors:
// in GADTs, types cannot occur to the left of '::', so they cannot be mixed
// with constructor names (see Note [Parsing data constructors is hard]).

// Due to simplified syntax, GADT constructor names (left-hand side of '::')
// use simpler grammar production than usual data constructor names. As a
// consequence, GADT constructor names are restricted (names like '(*)' are
// allowed in usual data constructors, but not in GADTs).
// -}

// NOT AS IN GHC
constrs
    :
    constr ('|' constr)*
    ;

// {- Note [Constr variations of non-terminals]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// In record declarations we assume that 'ctype' used to parse the type will not
// consume the trailing docprev:

//   data R = R { field :: Int -- ^ comment on the field }

// In 'R' we expect the comment to apply to the entire field, not to 'Int'. The
// same issue is detailed in Note [ctype and ctypedoc].

// So, we do not want 'ctype'  to consume 'docprev', therefore
//     we do not want 'btype'  to consume 'docprev', therefore
//     we do not want 'tyapps' to consume 'docprev'.

// At the same time, when parsing a 'constr', we do want to consume 'docprev':

//   data T = C Int  -- ^ comment on Int
//              Bool -- ^ comment on Bool

// So, we do want 'constr_stuff' to consume 'docprev'.

// The problem arises because the clauses in 'constr' have the following
// structure:

//   (a)  context '=>' constr_stuff   (e.g.  data T a = Ord a => C a)
//   (b)               constr_stuff   (e.g.  data T a =          C a)

// and to avoid a reduce/reduce conflict, 'context' and 'constr_stuff' must be
// compatible. And for 'context' to be compatible with 'constr_stuff', it must
// consume 'docprev'.

// So, we want 'context'  to consume 'docprev', therefore
//     we want 'btype'    to consume 'docprev', therefore
//     we want 'tyapps'   to consume 'docprev'.

// Our requirements end up conflicting: for parsing record types, we want 'tyapps'
// to leave 'docprev' alone, but for parsing constructors, we want it to consume
// 'docprev'.

// As the result, we maintain two parallel hierarchies of non-terminals that
// either consume 'docprev' or not:

//   tyapps      constr_tyapps
//   btype       constr_btype
//   context     constr_context
//   ...

// They must be kept identical except for their treatment of 'docprev'.

// -}

constr
    :
    (con ('!'? atype)*)
    | ((btype | ('!' atype)) conop (btype | ('!' atype)))
    | (con '{' fielddecls? '}')
    ;

fielddecls
    :
    fielddecl (',' fielddecl)*
    ;

fielddecl
    :
    sig_vars '::' ctype
    ;

// A list of one or more deriving clauses at the end of a datatype
derivings
    :
    deriving+
    ;

// The outer Located is just to allow the caller to
// know the rightmost extremity of the 'deriving' clause
deriving
    :
    ('deriving' deriv_clause_types)
    | ('deriving' deriv_strategy_no_via deriv_clause_types)
    | ('deriving' deriv_clause_types {DerivingVia}? deriv_strategy_via)
    ;

deriv_clause_types
    :
    qtycon
    | '(' ')'
    | '(' deriv_types ')'
    ;

// -------------------------------------------
// Value definitions (CHECK!!!)

// {- Note [Declaration/signature overlap]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// There's an awkward overlap with a type signature.  Consider
//         f :: Int -> Int = ...rhs...
//    Then we can't tell whether it's a type signature or a value
//    definition with a result signature until we see the '='.
//    So we have to inline enough to postpone reductions until we know.
// -}

// {-
//   ATTENTION: Dirty Hackery Ahead! If the second alternative of vars is var
//   instead of qvar, we get another shift/reduce-conflict. Consider the
//   following programs:

//      { (^^) :: Int->Int ; }          Type signature; only var allowed

//      { (^^) :: Int->Int = ... ; }    Value defn with result signature;
//                                      qvar allowed (because of instance decls)

//   We can't tell whether to reduce var to qvar until after we've read the signatures.
// -}

decl_no_th
    :
    sigdecl
    | (infixexp opt_sig? rhs)
    // | pattern_synonym_decl
    // | docdecl
    | semi+
    ;

decl 
    :
    decl_no_th

    // Why do we only allow naked declaration splices in top-level
    // declarations and not here? Short answer: because readFail009
    // fails terribly with a panic in cvBindsAndSigs otherwise.
    | splice_exp
    | semi+
    ;

rhs
    :
    ('=' exp wherebinds?)
    | (gdrhs wherebinds?);

gdrhs
    :
    gdrh+
    ;

gdrh
    :
    '|' guards '=' exp
    ;

sigdecl
    : 
    (infixexp '::' sigtypedoc)
    | (var ',' sig_vars '::' sigtypedoc)
    | (fixity integer? ops)
    // | (pattern_synonym_sig)
    // |(semi+)
    ;

// -------------------------------------------
// Expressions

th_quasiquote
    :
    '[' varid '|'
    ;

th_qquasiquote
    :
    '[' qvarid '|'
    ;

quasiquote
    :
    th_quasiquote
    | th_qquasiquote
    ;

exp
    :
    (infixexp '::' sigtype)
    | infixexp
    ;

// infixexp
//     :
//     (lexp qop infixexp)
//     | ('-' infixexp)
//     | lexp
//     ;

infixexp
    :
    exp10 (qop exp10p)*
    ;

exp10p
    :
    exp10
    ;

exp10
    :
    '-'? fexp
    ;

fexp
    :
    aexp+ ('@' atype)?
    ;

aexp
    :
    (qvar '@' aexp)
    | ('~' aexp)
    | ('!' aexp)
    | ('\\' apat+ '->' exp)
    | ('let' decllist 'in' exp)
    | (LCASE alts)
    | ('if' exp semi? 'then' exp semi? 'else' exp)
    | ('if' ifgdpats)
    | ('case' exp 'of' alts)
    | ('do' stmtlist)
    | ('mdo' stmtlist)
    | aexp1
    ;

aexp1
    :
    aexp2 ('{' fbinds? '}')*
    ;

aexp2
    :
    qvar
    | qcon
    | varid
    | literal
    | pstring
    | integer
    | pfloat
    | ('(' texp ')')
    | ('(' tup_exprs ')')
    // | ('(#' texp '#)')
    // | ('(#' tup_exprs '#)')
    | ('[' list ']')
    | '_'
    // Template Haskell
    | splice_untyped
    | splice_typed
    | '[|' exp '|]'
    | '[||' exp '||]'
    | '[t|' ktype '|]'
    | '[p|' infixexp '|]'
    | '[d|' cvtopbody '|]'
    | quasiquote
    ;

splice_exp
    :
    splice_typed
    | splice_untyped
    ;

splice_untyped
    :
    '$' aexp
    ;

splice_typed
    :
    '$$' aexp
    ;

cvtopbody
    :
    open cvtopdecls0? close
    ;

cvtopdecls0
    :
    topdecls semi*
    ;

// -------------------------------------------

// Tuple expressions
// TODO

texp
    :
    exp
    | (infixexp qop)
    | (qopm infixexp)
    | (exp '->' texp)
    ;

tup_exprs
    :
    (texp commas_tup_tail)
    | (texp bars)
    | (commas tup_tail?)
    | (bars texp bars?)
    ;

commas_tup_tail
    :
    commas tup_tail?
    ;

tup_tail
    :
    texp commas_tup_tail
    | texp
    ;

// -------------------------------------------

// List expressions
// TODO

list
    :
    texp
    | lexps
    | texp '..'
    | texp ',' exp '..'
    | texp '..' exp
    | texp ',' exp '..' exp
    | texp '|' flattenedpquals
    ;

lexps
    :
    texp ',' texp (',' texp)*
    ;


// -------------------------------------------

// List Comprehensions
// TODO

flattenedpquals
    :
    pquals
    ;

pquals
    :
    squals ('|' squals)*
    ;

squals
    :
    // transformqual (',' transformqual)*
    // | transformqual (',' qual)*
    // | qual (',' transformqual)*
    | qual (',' qual)*
    ;

// -------------------------------------------
// Guards (Different from GHC)

guards
    :
    guard (',' guard)*
    ;

guard
    :
    pat '<-' infixexp
    | 'let' decllist
    | infixexp
    ;

// -------------------------------------------
// Case alternatives

alts
    :
    (open (alt semi*)+ close)
    | ({EmptyCase}? open close)
    ;

alt : pat alt_rhs ;

alt_rhs
    :
    ralt wherebinds?
    ;

ralt
    :
    ('->' exp)
    | gdpats
    ;


gdpats
    :
    gdpat+
    ;

// In ghc parser on GitLab second rule is 'gdpats close'
// Unclearly, is there possible errors with this implemmentation
ifgdpats
    :
    '{' gdpats '}'
    | gdpats
    ;

gdpat
    :
    '|' guards '->' exp
    ;

pat
    :
    (lpat qconop pat)
    | lpat
    ;

lpat
    :
    apat
    | ('-' (integer | pfloat))
    | (gcon apat+)
    ;

apat
    :
    (var ('@' apat)?)
    | gcon
    | (qcon '{' (fpat (',' fpat)*)? '}')
    | literal
    | '_'
    | ('(' pat ')')
    | ('(' pat ',' pat (',' pat)* ')')
    | ('[' pat (',' pat)* ']')
    | ('~'apat)
    ;

fpat
    :
    qvar '=' pat
    ;

// -------------------------------------------
// Statement sequences

stmtlist
    :
    open stmts? close
    ;

stmts
    :
    stmt (semi+ stmt)* semi*
    ;

stmt
    : qual
    | ({RecursiveDo}? 'rec' stmtlist)
    | semi+
    ;

qual
    :
    (pat '<-' exp)
    | ('let' decllist)
    | exp
    ;

// -------------------------------------------
// Record Field Update/Construction

fbinds
    :
    (fbind (',' fbind)*)
    | ('..')
    ;

// In GHC 'texp', not 'exp'

// 1) RHS is a 'texp', allowing view patterns (#6038)
// and, incidentally, sections.  Eg
// f (R { x = show -> s }) = ...
// 
// 2) In the punning case, use a place-holder
// The renamer fills in the final value
fbind
    :
    (qvar '=' exp)
    | qvar
    ;

// -------------------------------------------
// Implicit Parameter Bindings

dbinds
    :
    dbind (semi+ dbind) semi*
    ;

dbind
    :
    varid '=' exp
    ;

// -------------------------------------------

// Warnings and deprecations
// TODO

namelist
    :
    name_var (',' name_var)*
    ;

name_var
    :
    var | con
    ;

// -------------------------------------------
// Data constructors
// There are two different productions here as lifted list constructors
// are parsed differently.

qcon_nowiredlist : gen_qcon | sysdcon_nolist;

// qcon   : qconid  | ( '(' gconsym ')');
qcon  : gen_qcon | sysdcon;

gen_qcon : qconid | ( '(' qconsym ')' ); 

con    : conid   | ( '(' consym ')' ) | sysdcon;

con_list : con (',' con)*;

sysdcon_nolist
    :
    ('(' ')')
    | ('(' commas ')')
    | ('(#' '#)')
    | ('(#' commas '#)')
    ;

sysdcon
    :
    sysdcon_nolist
    | ('[' ']')
    ;

conop  : consym  | ('`' conid '`')	 ;

qconop : gconsym | ('`' qconid '`')	 ;


// -------------------------------------------
// Type constructors (CHECK!!!)

gtycon
    :
    qtycon
    | ( '(' ')' )
    | ( '[' ']' )
    | ( '(' '->' ')' )
    | ( '(' ',' '{' ',' '}' ')' )
    ;

oqtycon
    :
    qtycon
    | ('(' qtyconsym ')')
    ;

// {- Note [Type constructors in export list]
// ~~~~~~~~~~~~~~~~~~~~~
// Mixing type constructors and data constructors in export lists introduces
// ambiguity in grammar: e.g. (*) may be both a type constructor and a function.

// -XExplicitNamespaces allows to disambiguate by explicitly prefixing type
// constructors with 'type' keyword.

// This ambiguity causes reduce/reduce conflicts in parser, which are always
// resolved in favour of data constructors. To get rid of conflicts we demand
// that ambiguous type constructors (those, which are formed by the same
// productions as variable constructors) are always prefixed with 'type' keyword.
// Unambiguous type constructors may occur both with or without 'type' keyword.

// Note that in the parser we still parse data constructors as type
// constructors. As such, they still end up in the type constructor namespace
// until after renaming when we resolve the proper namespace for each exported
// child.
// -}

qtyconop: qtyconsym | ('`' qtycon '`');

qtycon : (modid '.')? tycon;

tycon : conid;

qtyconsym:qconsym | qvarsym | tyconsym;

tyconsym: consym | varsym | ':' | '-' | '.';

// -------------------------------------------
// Operators

op     : varop   | conop           ;

varop  : varsym  | ('`' varid '`') ;

qop    : qvarop  | qconop		   ;

qopm   : qvaropm | qconop | hole_op;

hole_op: '`' '_' '`';

qvarop : qvarsym | ('`' qvarid '`');

qvaropm: qvarsym_no_minus | ('`' qvarid '`');

// -------------------------------------------
// Type variables

tyvar : varid;

tyvarop: '`' tyvarid '`';

// Expand this rule later
// In GHC:
// tyvarid : VARID | special_id | 'unsafe'
//         | 'safe' | 'interruptible';

tyvarid : varid;

// -------------------------------------------
// Variables

var	   : varid   | ( '(' varsym ')' );

qvar   : qvarid  | ( '(' qvarsym ')');

// We've inlined qvarsym here so that the decision about
// whether it's a qvar or a var can be postponed until
// *after* we see the close paren
qvarid : (modid '.')? varid;

// Note that 'role' and 'family' get lexed separately regardless of
// the use of extensions. However, because they are listed here,
// this is OK and they can be used as normal varids.
varid : (VARID | special_id) ({MagicHash}? '#'*);

qvarsym: (modid '.')? varsym;

qvarsym_no_minus
    : varsym_no_minus
    | qvarsym
    ;

varsym : varsym_no_minus | '-';

varsym_no_minus : ascSymbol+;

// These special_ids are treated as keywords in various places,
// but as ordinary ids elsewhere.   'special_id' collects all these
// except 'unsafe', 'interruptible', 'forall', 'family', 'role', 'stock', and
// 'anyclass', whose treatment differs depending on context
special_id
    : 'as'
    | 'qualified'
    | 'hiding'
    | 'export'
    | 'stdcall'
    | 'ccall'
    | 'capi'
    | 'javascript'
    | 'stock'
    | 'anyclass'
    | 'via'
    ;

// -------------------------------------------
// Data constructors

qconid : (modid '.')? conid;

conid : CONID ({MagicHash}? '#'*);

qconsym: (modid '.')? consym;

consym : ':' ascSymbol*;

// -------------------------------------------
// Literals

literal : integer | pfloat | pchar | pstring;

// -------------------------------------------
// Layout

open : VOCURLY | OCURLY;
close : VCCURLY | CCURLY;
semi : ';' | SEMI;

// -------------------------------------------
// Miscellaneous (mostly renamings)

modid : (conid '.')* conid;

commas: ','+;

bars : '|'+;

// -------------------------------------------

typecontext
    :
    cls
    | ( '(' cls (',' cls)* ')' )
    ;

cls
    :
    (conid varid)
    // Flexible Context and MultiParamTypeClasses
    | (conid multiparams)
    | ( qtycls '(' tyvar (atype (',' atype)*) ')' )
    ;

multiparams
    :
    multiparam+
    ;

multiparam
    :
    qvarid
    | qconid
    ;

simpletype
    :
    tycon tyvar*
    ;

newconstr
    :
    (con atype)
    | (con '{' var '::' type '}')
    ;

funlhs
    :
    (var apat+)
    | (pat varop pat)
    | ( '(' funlhs ')' apat+)
    ;

gcon
    :
    ('(' ')')
    | ('[' ']')
    | ('(' (',')+ ')')
    | qcon
    ;



gconsym: ':'  	 | qconsym			 ;





special : '(' | ')' | ',' | ';' | '[' | ']' | '`' | '{' | '}';

symbol: ascSymbol;
ascSymbol: '!' | '#' | '$' | '%' | '&' | '*' | '+'
        | '.' | '/' | '<' | '=' | '>' | '?' | '@'
        | '\\' | '^' | '|' | '~' | ':' ;


tycls : conid;

qtycls : (modid '.')? tycls;


integer
    :
    DECIMAL
    | OCTAL
    | HEXADECIMAL
    ;


pfloat : FLOAT;
pchar  : CHAR;
pstring: STRING;
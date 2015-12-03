#lang racket/base
(require (for-syntax racket/base
                     syntax/quote
                     syntax/parse
                     racket/syntax
                     racket/generic
                     racket/format
                     racket/list
                     racket/match
                     (prefix-in remix: remix/stx0)
                     remix/stx/singleton-struct0
                     (for-syntax racket/base
                                 racket/syntax
                                 syntax/parse
                                 racket/generic
                                 (prefix-in remix: remix/stx0)))
         racket/unsafe/ops
         racket/performance-hint
         (prefix-in remix: remix/stx0))

(begin-for-syntax
  (define-generics static-interface
    (static-interface-members static-interface))

  (module interface-member racket/base
    (require syntax/parse)
    (define-syntax-class interface-member
      (pattern x:id)
      (pattern x:keyword))
    (provide interface-member))
  (require (submod "." interface-member)
           (for-syntax
            (submod "." interface-member)))

  (define-syntax (phase1:static-interface stx)
    (syntax-parse stx
      #:literals (remix:#%brackets)
      [(_si (remix:#%brackets
             lhs:interface-member rhs:id
             (~optional
              (~seq #:is rhs-dt:id)
              #:defaults ([rhs-dt #'#f])))
            ...
            (~optional
             (~seq #:extensions
                   extension ...)
             #:defaults ([[extension 1] '()])))
       (with-syntax* ([int-name (or (syntax-local-name) 'static-interface)]
                      [(def-rhs ...)
                       (for/list ([lhs (in-list
                                        (map syntax->datum
                                             (syntax->list #'(lhs ...))))])
                         (format-id #f "~a-~a-for-def" #'int-name
                                    (if (keyword? lhs) (keyword->string lhs)
                                        lhs)))]
                      [(full-def-rhs ...)
                       (for/list ([def-rhs (in-list (syntax->list #'(def-rhs ...)))]
                                  [rhs-dt (in-list (syntax->list #'(rhs-dt ...)))])
                         (if (syntax-e rhs-dt)
                             (list def-rhs '#:is rhs-dt)
                             (list def-rhs)))])
         (syntax/loc stx
           (let ()
             (define int-id->orig
               (make-immutable-hasheq
                (list (cons 'lhs (cons #'rhs #'rhs-dt))
                      ...)))
             (define available-ids
               (sort (hash-keys int-id->orig)
                     string<=?
                     #:key ~a))
             (define (get-rhs stx x)
               (define xv (syntax->datum x))
               (hash-ref int-id->orig
                         xv
                         (λ ()
                           (raise-syntax-error
                            'int-name
                            (format "Unknown component ~v, expected one of ~v"
                                    xv
                                    available-ids)
                            stx
                            x))))
             (define (get-rhs-id stx x)
               (car (get-rhs stx x)))
             (define (get-rhs-is stx x)
               (define r (cdr (get-rhs stx x)))
               (if (syntax-e r)
                   r
                   #f))
             (define (get-rhs-def stx x-stx)
               (define xd (get-rhs-is stx x-stx))
               (with-syntax* ([xb (get-rhs-id stx x-stx)]
                              [x-def
                               (if xd xd #'remix:stx)]
                              [x-def-v
                               (if xd #'xb #'(make-rename-transformer #'xb))])
                 (quasisyntax/loc stx
                   (remix:def (remix:#%brackets x-def #,x-stx) x-def-v))))
             (singleton-struct
              #:methods gen:static-interface
              [(define (static-interface-members _)
                 available-ids)]
              #:methods remix:gen:dot-transformer
              [(define (dot-transform _ stx)
                 (syntax-parse stx
                   [(_dot me:id x:interface-member)
                    (get-rhs-id stx #'x)]
                   [(_dot me:id x:interface-member . more:expr)
                    (quasisyntax/loc stx
                      (remix:block
                       #,(get-rhs-def stx #'x)
                       (remix:#%dot x . more)))]))]
              #:methods remix:gen:app-dot-transformer
              [(define (app-dot-transform _ stx)
                 (syntax-parse stx
                   [(_app (_dot me:id x:interface-member) . body:expr)
                    (quasisyntax/loc stx
                      (#,(get-rhs-id stx #'x) . body))]
                   [(_app (_dot me:id x:interface-member . more:expr) . body:expr)
                    (quasisyntax/loc stx
                      (remix:block
                       #,(get-rhs-def stx #'x)
                       (remix:#%app (remix:#%dot x . more) . body)))]))]
              #:methods remix:gen:def-transformer
              [(define (def-transform _ stx)
                 (syntax-parse stx
                   #:literals (remix:#%brackets)
                   [(def (remix:#%brackets me:id i:id) . body:expr)
                    (with-syntax ([real-i (generate-temporary #'i)])
                      (syntax/loc stx
                        (begin
                          (remix:def real-i . body)
                          (remix:def (remix:#%brackets remix:stx def-rhs)
                                     (λ (stx)
                                       (syntax-parse stx
                                         [_:id
                                          (syntax/loc stx
                                            (rhs real-i))]
                                         [(_ . blah:expr)
                                          (syntax/loc stx
                                            (rhs real-i . blah))])))
                          ...
                          (remix:def (remix:#%brackets remix:stx i)
                                     (phase1:static-interface
                                      (remix:#%brackets lhs . full-def-rhs)
                                      ...
                                      #:extensions
                                      ;; NB I don't pass on other
                                      ;; extensions... I don't think
                                      ;; it can possibly make sense,
                                      ;; because I don't know what
                                      ;; they might be.
                                      #:property prop:procedure
                                      (λ (_ stx)
                                        (syntax-parse stx
                                          [_:id
                                           (syntax/loc stx
                                             real-i)]
                                          [(_ . blah:expr)
                                           (syntax/loc stx
                                             (real-i . blah))])))))))]))]
              extension ...))))])))

(define-syntax (define-phase0-def->phase1-macro stx)
  (syntax-parse stx
    [(_ base:id)
     (with-syntax ([phase0:base (format-id #'base "phase0:~a" #'base)]
                   [phase1:base (format-id #'base "phase1:~a" #'base)])
       (syntax/loc stx
         (define-syntax phase0:base
           (singleton-struct
            #:property prop:procedure
            (λ (_ stx)
              (raise-syntax-error 'base "Illegal outside def" stx))
            #:methods remix:gen:def-transformer
            [(define (def-transform _ stx)
               (syntax-parse stx
                 #:literals (remix:#%brackets)
                 [(def (remix:#%brackets me:id i:id) . body:expr)
                  (syntax/loc stx
                    (remix:def (remix:#%brackets remix:stx i)
                               (phase1:base . body)))]))]))))]))

(define-phase0-def->phase1-macro static-interface)

(provide (rename-out [phase0:static-interface static-interface])
         (for-syntax (rename-out [phase1:static-interface static-interface])
                     gen:static-interface
                     static-interface?
                     static-interface-members))

(begin-for-syntax
  ;; XXX fill this in for parents, etc
  (define-generics layout
    (layout-planner layout)
    ;; xxx the accessors seem to not be around anyways, so instead,
    ;; this should just be a mapping produced by the planner.
    (layout-field->acc layout))
  (begin-for-syntax
    (define-generics layout-planner
      (layout-planner-mutable? layout-planner)))
  (define-syntax layout-immutable
    (singleton-struct
     #:methods gen:layout-planner
     [(define (layout-planner-mutable? lp) #f)]))
  (define-syntax layout-mutable
    (singleton-struct
     #:methods gen:layout-planner
     [(define (layout-planner-mutable? lp) #t)]))

  (define-syntax-class field
    #:attributes (name dt)
    #:literals (remix:#%brackets)
    (pattern name:id
             #:attr dt #f)
    (pattern (remix:#%brackets dt name:id)
             #:declare dt (static remix:def-transformer? "def transformer"))))

(define-syntax phase0:layout
  (singleton-struct
   #:property prop:procedure
   (λ (_ stx)
     (raise-syntax-error 'layout "Illegal outside def" stx))
   #:methods remix:gen:def-transformer
   [(define (def-transform _ stx)
      (syntax-parse stx
        #:literals (remix:#%brackets)
        [(def (remix:#%brackets me:id name:id)
           (~optional (~and (~seq #:parent (~var parent (static layout? "layout")))
                            (~bind [parent-va (attribute parent.value)]))
                      #:defaults ([parent-va #f]))
           F:field ...)
         (define parent-v (attribute parent-va))
         (define the-planner
           (or (and parent-v (layout-planner parent-v))
               ;; xxx allow the default planner to be customized and
               ;; ensure it is equal to the parent's
               #'layout-immutable))
         (define parent-f->acc
           (or (and parent-v (layout-field->acc parent-v))
               (hasheq)))
         (define f->acc
           (for/fold ([base parent-f->acc])
                     ([the-f (in-list (syntax->datum #'(F.name ...)))]
                      [the-dt (in-list (attribute F.dt))]
                      [the-idx (in-naturals (hash-count parent-f->acc))])
             (when (hash-has-key? base the-f)
               (raise-syntax-error 'layout
                                   (format "duplicate field ~a in layout"
                                           the-f)
                                   stx
                                   the-f))
             (define the-name-f (format-id #f "~a-~a" #'name the-f))
             (hash-set base the-f (vector the-name-f the-dt the-idx))))
         (with-syntax* ([name-alloc (format-id #f "~a-alloc" #'name)]
                        [name-set (format-id #f "~a-set" #'name)]
                        [((all-f all-name-f all-f-si-rhs all-f-idx) ...)
                         (for/list ([(the-f v) (in-hash f->acc)])
                           (match-define (vector the-name-f the-dt the-f-idx) v)
                           (list the-f the-name-f
                                 (if the-dt
                                     (list the-name-f '#:is the-dt)
                                     (list the-name-f))
                                 the-f-idx))]
                        [stx-the-planner the-planner]
                        [stx-f->acc f->acc])
           (syntax/loc stx
             (begin
               (begin-for-syntax
                 (define f->acc stx-f->acc)
                 (define available-fields
                   (sort (hash-keys f->acc)
                         string<=?
                         #:key symbol->string))
                 (define ordered-fields
                   (sort (hash-keys f->acc)
                         <=
                         #:key (λ (x)
                                 (vector-ref (hash-ref f->acc x) 2))))
                 (define-syntax-class name-arg
                   #:attributes (lhs rhs)
                   #:literals (remix:#%brackets)
                   (pattern (remix:#%brackets lhs:id rhs:expr)
                            #:do [(define lhs-v (syntax->datum #'lhs))]
                            #:fail-unless
                            (hash-has-key? f->acc lhs-v)
                            (format "invalid field given: ~a, valid fields are: ~a"
                                    lhs-v
                                    available-fields)))
                 (define-syntax-class name-args
                   #:attributes (f->rhs)
                   (pattern (a:name-arg (... ...))
                            #:do [(define first-dupe
                                    (check-duplicates
                                     (syntax->datum #'(a.lhs (... ...)))))]
                            #:fail-when first-dupe
                            (format "field occurs twice: ~a" first-dupe)
                            #:attr f->rhs
                            (for/hasheq ([l (syntax->list #'(a.lhs (... ...)))]
                                         [r (syntax->list #'(a.rhs (... ...)))])
                              (values (syntax->datum l) r)))))
               (define-syntax (name-alloc stx)
                 (syntax-parse stx
                   [(_ . args:name-args)
                    (with-syntax ([(f-val (... ...))
                                   (for/list ([this-f (in-list ordered-fields)])
                                     (hash-ref (attribute args.f->rhs)
                                               this-f
                                               (λ ()
                                                 (raise-syntax-error
                                                  'name-alloc
                                                  (format "missing initializer for ~a"
                                                          this-f)
                                                  stx))))])
                      (syntax/loc stx
                        ;; xxx push this in representation planner
                        (vector-immutable f-val (... ...))))]))
               (define-syntax (name-set stx)
                 (syntax-parse stx
                   [(_ base:expr . args:name-args)
                    (with-syntax* ([base-id (generate-temporary #'base)]
                                   [(f-val (... ...))
                                    (for/list ([this-f (in-list ordered-fields)])
                                      (define this-name-f
                                        (vector-ref
                                         (hash-ref f->acc this-f)
                                         0))
                                      (hash-ref (attribute args.f->rhs)
                                                this-f
                                                (λ ()
                                                  (quasisyntax/loc stx
                                                    (#,this-name-f base-id)))))])
                      (syntax/loc stx
                        (let ([base-id base])
                          ;; xxx push this in representation planner
                          (vector-immutable f-val (... ...)))))]))
               (begin-encourage-inline
                 ;; xxx push this in representation planner
                 (define (all-name-f v) (unsafe-vector*-ref v all-f-idx))
                 ...)
               (define-syntax name
                 (phase1:static-interface
                  (remix:#%brackets #:alloc name-alloc)
                  ;; xxx perhaps allow planner to not have this
                  (remix:#%brackets #:set name-set)
                  (remix:#%brackets #:= name-set)
                  ;; xxx add set! if planner says so
                  (remix:#%brackets all-f . all-f-si-rhs)
                  ...
                  #:extensions
                  #:methods gen:layout
                  [(define (layout-planner _)
                     #'stx-the-planner)
                   (define (layout-field->acc _)
                     f->acc)])))))]))]))

(provide (rename-out [phase0:layout layout])
         (for-meta 2
                   gen:layout-planner
                   layout-planner?
                   layout-planner-mutable?)
         (for-syntax gen:layout
                     layout?
                     layout-immutable
                     layout-mutable))

;; xxx (dynamic-)interface
;; xxx data
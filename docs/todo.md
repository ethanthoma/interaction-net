# TODO list

## runtime

Reduction is memory-bandwidth bound; profile before optimizing. Build with
`-define:PROFILE=true` for a per-rule interaction breakdown. Baseline numbers
and the measured hot path live in [perf-baseline.md](./perf-baseline.md).

Measured priorities (rec.inio / stress.inio): the hot rules are annihilate
(~26-32%) and operate (~21-25%) and call/def-expansion is only ~10-12%.

- inline numbers into the Port to drop the nums arena (operate/cond/void touch
  it on ~40% of interactions) which is blocked on the 32-bit Port width, needs a
  wider Port/Pair
- kill the 64-byte `Slot` cache-line padding (arena.odin) which needs per-worker
  packed arena segments to stay false-sharing free
- make the global interaction counter per-worker (runtime.odin `interact`) to
  stop cache-line ping-pong across workers

Open design work:

- gamma-operation and gamma-switch both use apply, the interaction between
  switch and operation is undefined and now panics. Decide the real semantics.
  - idk if the apply operation makes sense. It feels semantically correct for
    constructions of lists but DUP can emulate this builtin, ig this is why we
    use it in apply?
  - HVM paper says CON-SWI is problematic. Should explore why
  - the OPE-CON is commution in HVM. Here we use apply like we do with SWI
  - the apply interaction generates DUP nodes which makes them unsafe for high
    order functions?
- copying from book (our list of definitions) into the program is too taxing as
  we have to adjust every address
  - reuse per-worker scratch maps instead of make/delete per call() first
  - reserve a contiguous arena range per def so remap becomes base + i
  - numbers can just be buffer copied once packed/inlined
- annihilate for gamma should probably be its own rule called destruction as it
  is used for function application and deconstructing constructions
  - look into polarity
    - can probably think about polarity-based optimizations?
    - is polarity able to be deduced or has to be explictly encoded?
- we should try remove excess branches, OPE node for example. The address is the
  same length across all nodes so we shouldnt need to switch on it
- explore simd for math ops? some bucket system
- lazy evaluations
  - amb node w/ ref?
  - ivy has opt in and opt out
  - go from interaction on input to interaction on output
  - HVM1 had explict primary nodes and wires instead of named vars
    - maybe slotmap or some other ds can help with wires
    - tree construction from root to redex is log(n)
    - tree structure mem layout?
  - multi-primary ports
    - pointers/indexs into node buffer or a diff buffer
    - how to make concurrently safe?
    - can help with async and lazy evals, not sure
- switch from lafont IC to SIC
  - gamma to zeta (easy)
  - refactor examples
  - explore code/decoder breakdown of @refs
    - can polarity be used to inform us of anything about a project?
  - switch to SIC style of naming (project/code/decoder/agents/etc)

## frontend

- all files can probably be moved into their module for better separation
- tests exist only for the first three stages, not the final stage (generation)
- tokenizer is pretty well made, multicharacter tokens are a little iffy
  - maybe a trie-based parser could work?
  - there are simd approaches to string parsing, should look into it
- semantic checking (the checker) is per definition, this can easily be made
  parallel
- error context is shared via the Error_Context struct defined in main
  - this should moved and probably have a better API for each stage of
    compilation
  - maybe returned from the stages to the frontend?
- each stage has its own error printing that does the same thing, should be
  moved up

## IO

- we should implement this lol
- HVM normalizes and checks if the result is some sort of IO OP
  - wonder if certain part of the num address space could be used for IO mapping
    - num address space isnt exposed in the IR...
  - HVM way has to wait for the IO to complete, there needs to be a lazy way for
    IO
    - special IO node? seems sucky
    - probably something to do with AMB nodes or some sort of multi-primary port
      agent?

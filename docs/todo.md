# TODO list 

## runtime

- numbers use indices into a number buffer. We need to duplicate them for 
erasure, commution, and map
- deleted nodes leave buffer holes, we fill those holes when we run out of 
buffer capacity via a linear scan which is fine when the hole is within the 
first 10_000 or so. We should probably have a free list or some tree structure 
for deleted nodes past 10_000 or so indices.
- this a multithreaded paradigm without any multithreading...
    - copy HVM data structures
- gamma-operation and gamma-switch both use apply, the interaction between 
switch and operation is undefined (what should the semantic meaning be?)
    - idk if the apply operation makes sense. It feels semantically correct for 
    constructions of lists but DUP can emulate this builtin, ig this is why we 
    use it in apply?
    - HVM paper says CON-SWI is problematic. Should explore why
    - the OPE-CON is commution in HVM. Here we use apply like we do with SWI
    - the apply interaction generates DUP nodes which makes them unsafe for 
    high order functions?
- empty nodes are represented by maybe(pair), this is bad as maybe adds 4 extra 
bytes, messing up the ideal 8 byte alignment for our vectors, swap it to a 
special address space (nullptr)
- copying from book (our list of definitions) into the program is too taxing as 
we have to adjust every address
    - numbers can just be buffer copied
    - addresses have to be updated for the nums and operations buffer. I feel 
    there must be a way to use simd for this
- annihilate for gamma should probably be its own rule called destruction as it 
is used for function application and deconstructing constructions
- we should try remove excess branches, OPE node for example. The address is the 
same length across all nodes so we shouldnt need to switch on it
- explore simd for math ops? some bucket system
- lazy evaluations
    - amb node w/ ref?
    - ivy has opt in and opt out
    - go from interaction on input to interaction on output

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
    - wonder if certain part of the num address space could be used for IO 
    mapping
        - num address space isnt exposed in the IR...
    - HVM way has to wait for the IO to complete, there needs to be a lazy way 
    for IO
        - special IO node? seems sucky

---
title: "Practical Dependent Types in Haskell: Type-Safe Neural Networks (Part 1)"
categories: Haskell, Ramblings
series: Practical Dependent Types in Haskell
tags: functional programming, dependent types, numerical, haskell, singletons, types, linear algebra, artificial neural networks, machine learning
create-time: 2016/02/25 11:47:50
date: 2016/05/25 11:46:21
identifier: dependent-haskell-1
slug: practical-dependent-types-in-haskell-1
---

It seems these days like programming with dependent types in Haskell (and its
advantages) is moving slowly but steadily to the mainstream of Haskell
programming.  In the current state of Haskell education, dependent types are
often considered topics for "advanced" Haskell users.  However, I can foresee a
day where the ease of use of modern Haskell libraries relying on dependent
types forces programming with dependent types to be an integral part of normal
intermediate (or even beginner) Haskell education.

There are [more][weirich] and [more][andres] and [more][hiromi] and
[more][jozefg] great resources and tutorials and introductions to integrating
dependent types into your Haskell every day.  The point of this series is to
show more some practical examples of using dependent types in guiding your
programming, and to also walk through the "why" and high-level philosophy of
the way you structure your Haskell programs.  It'll also hopefully instill an
intuition of a dependently typed work flow of "exploring" how dependent types
can help your current programs.  The intended audience of this post is for
intermediate Haskell programmers in general, with no required knowledge of
dependently typed programming.  I should also point out that I'm no expert ---
I'm still in the process of learning this all, myself :)

[weirich]: https://www.youtube.com/watch?v=rhWMhTjQzsU
[andres]: http://www.well-typed.com/blog/2015/11/implementing-a-minimal-version-of-haskell-servant/
[hiromi]: https://www.schoolofhaskell.com/user/konn/prove-your-haskell-for-great-safety
[jozefg]: http://jozefg.bitbucket.org/posts/2014-08-25-dep-types-part-1.html

The first project in this series will build up to a type-safe **[artificial
neural network][ann]** implementation with back-propagation training.

[ann]: https://en.wikipedia.org/wiki/Artificial_neural_network

#### Setup

This post is written on *[stack][]* snapshot *[lts-5.17][]*, but uses an unreleased
version of *hmatrix*, *[hmatrix-0.18 (commit 42a88fb)][hmatrix head]*.  I
[maintain my own documentation][hmatrix head docs] for reference.  You can add
this:


~~~yaml
packages:
- location:
    git: git@github.com:albertoruiz/hmatrix.git
    commit: 42a88fbcb6bd1d2c4dc18fae5e962bd34fb316a1
  subdirs:
    - packages/base
~~~

to the `packages` field of your directory or global *stack.yaml* and *stack*
will know what version of *hmatrix* to use when you use `stack runghc` or
`stack ghc`, etc. to build your files.

[hmatrix head]: https://github.com/albertoruiz/hmatrix/tree/42a88fbcb6bd1d2c4dc18fae5e962bd34fb316a1
[hmatrix head docs]: http://mstksg.github.io/hmatrix/
[stack]: http://www.haskellstack.org
[lts-5.17]: https://www.stackage.org/lts-5.17

Neural Networks
---------------

[Artificial neural networks][ann] have been somewhat of a hot topic in
computing recently.  Implementations of training algorithms (like
back-propagation) are tricky to implement correctly --- despite being simple,
there are many locations where accidental bugs might pop up when multiplying
the wrong matrices, for example.

[ann]: https://en.wikipedia.org/wiki/Artificial_neural_network

Though some might recognize that complicated matrix and vector arithmetic is a
common application of phantom type-based dependent types, it's not necessarily
always easy to gauge before-the-fact what would or would not be a good
candidate for adding dependent types to.  Often times, it can even be
considered premature to start off with "as powerful types as you can".  So
let's walk through programming things with as "dumb" types as possible, and see
where types can help.

We'll be following a process called "type-driven development" --- start with
general and non-descriptive types, write the implementation and recognize
partial functions and red flags, and slowly refine and add more and more
powerful types to fix the problems.

### Background

![Feed-forward ANN architecture](/img/entries/dependent-haskell-1/ffneural.png "Feed-forward ANN architecture")

Here's a quick run through on background for ANN's --- but remember, this isn't
an article on ANN's, so we are going to be glossing over some of the details.

We're going to be implementing a *feed-forward neural network* with
back-propagation training.  These networks are layers of "nodes", each
connected to the each of the nodes of the previous layer.  Input goes to the
first layer, which feeds information to the next year, which feeds it to the
next, etc., until the final layer, where we read it off as the "answer" that
the network is giving us.  Layers between the input and output layers are
called *hidden* layers.  Every node "outputs" a weighted sum of all of the
outputs of the *previous* layer, plus an always-on "bias" term (so that its
result can be non-zero even when all of its inputs are zero). Symbolically, it
looks like:

$$
y_j = b_j + \sum_i^m w_{ij} x_i
$$

Or, if we treat the output of a layer and the list of list of weights as a
matrix, we can write it a little cleaner:

$$
\mathbf{y} = \mathbf{b} + W \mathbf{x}
$$

The result, the $n$-vector of nodes $\mathbf{y}$, is computed from the
$n$-vector of biases $\mathbf{b}$ and the $n \times m$ weight matrix $W$
multiplied with the $m$-vector input, $\mathbf{x}$.

To "scale" the result (and to give the system the magical powers of
nonlinearity), we actually apply an "activation function" to the output before
passing it down to the next step.  We'll be using the popular [logistic
function][], $f(x) = 1 / (1 + e^{-x})$.

[logistic function]: https://en.wikipedia.org/wiki/Logistic_function

*Training* a network involves picking the right set of weights to get the
network to answer the question you want.

Vanilla Types
-------------

We can store a network by storing the matrix of of weights and biases between
each layer:

~~~haskell
!!!dependent-haskell/NetworkUntyped.hs "data Weights"
~~~

Now, a `Weights` linking an *m*-node layer to an *n*-node layer has an
*n*-dimensional bias vector (one component for each output) and an *n*-by-*m*
node weight matrix (one column for each output, one row for each input).

(We're using the `Matrix` type from the awesome *[hmatrix][]* library for
performant linear algebra, implemented using blas/lapack under the hood)

[hmatrix]: http://hackage.haskell.org/package/hmatrix

A feed-forward neural network is then just a linked list of these weights:

~~~haskell
!!!dependent-haskell/NetworkUntyped.hs "data Network"
~~~

Note that we're using [GADT][] syntax here, which just lets us define `Network`
(with a kind signature, `*`) by providing the type of its *constructors*, `O`
and `(:&~)`.  It'd be equivalent to the following normal data declaration:

[GADT]: https://en.wikibooks.org/wiki/Haskell/GADT

~~~haskell
data Network = O Weights
             | Weights :&~ Network
~~~

A network with one input layer, two inner layers, and one output
layer would look like:

~~~haskell
ih :&~ hh :&~ O ho
~~~

The first component is the weights from the input to first inner layer, the
second is the weights between the two hidden layers, and the last is the
weights between the last hidden layer and the output layer.

<!-- TODO: graphs using diagrams? -->

We can write simple procedures, like generating random networks:

~~~haskell
!!!dependent-haskell/NetworkUntyped.hs "randomWeights ::" "randomNet ::"
~~~

(We're using the `MonadRandom` typeclass from the *[MonadRandom][]* library,
which uses the mechanisms in *[System.Random][]* and gives us a generic way of
working with monads where we can get random values with `getRandom`, etc.)

[MonadRandom]: http://hackage.haskell.org/package/MonadRandom
[System.Random]: http://hackage.haskell.org/package/random-1.1/docs/System-Random.html

([`randomVector`][] and [`uniformSample`][] are from the *[hmatrix][]* library,
generating random vectors and matrices from a random `Int` seed.  We manipulate
them here to generate them with numbers between -1 and 1)

[`randomVector`]: http://hackage.haskell.org/package/hmatrix-0.17.0.1/docs/Numeric-LinearAlgebra.html#v:randomVector
[`uniformSample`]: http://hackage.haskell.org/package/hmatrix-0.17.0.1/docs/Numeric-LinearAlgebra.html#v:uniformSample

And now we can write a function to "run" our network on a given input vector,
following the matrix equation we wrote earlier:

~~~haskell
!!!dependent-haskell/NetworkUntyped.hs "logistic ::" "runLayer ::" "runNet ::"
~~~

(`#>` is matrix-vector multiplication)

<!-- TODO: examples of running -->

If you're a non-Haskell programmer, this might all seem perfectly fine and
normal, and you probably have only a slightly elevated heart rate.  If you are
a Haskell programmer, you are most likely already having heart attacks. Let's
imagine all of the bad things that could happen:

*   How do we know that we didn't accidentally mix up the dimensions for our
    implementation of `randomWeights`?  We could have switched parameters and
    be none the wiser.

*   How do we even know that each subsequent matrix in the network is
    "compatible"?   We want the outputs of one matrix to line up with the
    inputs of the next, but there's no way to know.  It's possible to build a
    bad network, and things will just explode at runtime.

*   How do we know the size of vector the network expects?  What stops you from
    sending in a bad vector at run-time?  We might do runtime-checks, but the
    compiler won't help us.

*   How do we verify that we have implemented `runLayer` and `runNet` in a way
    that they won't suddenly fail at runtime?  We write `l #> v`, but how do we
    know that it's even correct...what if we forgot to multiply something, or
    used something in the wrong places?  We can it prove ourselves, but the
    compiler won't help us.


### Back-propagation

Now, let's try implementing back-propagation!  It's a textbook gradient descent
algorithm.  There are [many explanations][backprop] on the internet; the basic
idea is that you try to minimize the squared error of what the neural network
outputs for a given input vs. the actual expected output.  You find the
direction of change that minimizes the error (by finding the derivative), and
move that direction.  The implementation of backpropagation is found in many
sources online and in literature, so let's see the implementation in Haskell:

[backprop]: https://en.wikipedia.org/wiki/Backpropagation

~~~haskell
!!!dependent-haskell/NetworkUntyped.hs "train ::"
~~~

The algorithm computes the *updated* network by recursively updating the
layers, backwards up from the output layer.  At every step, it returns the
updated layer/network, as well as a bundle of derivatives (`dWs`) for the next layer up
to use to calculate its descent direction.

At the output layer, all it needs to calculate the direction of descent is just
`o - targ`, the target.  At the inner layers, it has to use the `dWs` bundle it
receives from the lower layers to figure it out.  `dWs` essentially "bubbles
up" from the output layer up to the input layer calculations.

Writing this is a bit of a struggle.  I actually implemented this incorrectly
several times before writing it as you see here.  The type system doesn't help
you like it normally does in Haskell, and you can't really use parametricity to
help you write your code like normal Haskell.  Everything is monomorphic, and
everything multiplies with everything else.  You don't have any hits about what
to multiply with what at any point in time.  It's like all of the bad things
mentioned before, but amplified.

In short, you're leaving yourself open to many potential bugs...and the
compiler doesn't help you write your code at all!  This is the nightmare of
every Haskell programmer.  There must be a better way![^better]

[^better]: This sentence is the story of my Haskell life.

#### Putting it to the test

Pretty much the only way you can verify this code is to test it out on example
cases.  In the [source file][NetworkUntyped], I have [`main`][mainUntyped] test out the
backprop, training a network on a 2D function that was "on" for two small
circles and "off" everywhere else (A nice cute non-linearly-separable
function to test our network on).  We basically train the network to be able to
recognize the two-circle pattern.  I implemented a simple printing function and
tested the trained network on a grid:

!!![NetworkUntyped]:dependent-haskell/NetworkUntyped.hs
!!![mainUntyped]:dependent-haskell/NetworkUntyped.hs "main ::"

~~~bash
$ stack install hmatrix MonadRandom
$ stack ghc -- -O2 ./NetworkUntyped.hs
$ ./NetworkUntyped
# Training network...
#
#
#            .=########=
#          .##############.
#          ################
#          ################
#          .##############-
#            .###########
#                 ...             ...
#                             -##########.
#                           -##############.
#                           ################
#                           ################
#                            =############=
#                              .#######=.
#
#
~~~

Not too bad!  The network learned to recognize the circles.  But, I was
basically forced to resort to unit testing to ensure my code was correct.
Let's see if we can do better.

### The Call of Types

Before we go on to the "typed" version of our program, let's take a step back
and look at some big checks you might want to ask yourself after you write code
in Haskell.

1.  Are any of my functions either partial or implemented using partial
    functions?
2.  How could I have written things that are *incorrect*, and yet still
    type check?  Where does the compiler *not* help me by restricting my
    choices?

Both of these questions usually yield some truth about the code you write and
the things you should worry about.  As a Haskeller, they should always be at
the back of your mind!

Looking back at our untyped implementation, we notice some things:

1.  Literally every single function we wrote is partial.  Like,
    actually.[^literally] If we had passed in the incorrectly sized
    matrix/vector, or stored mismatched vectors in our network, everything
    would fall apart.
2.  There are billions of ways we could have implemented our functions where
    they would still typechecked.  We could multiply mismatched matrices, or
    forget to multiply a matrix, etc.

[^literally]: Okay, maybe not *literally* every one.  But, pretty much every
one.

With Static Size-Indexed Types
------------------------------

### Networks

Gauging our potential problems, it seems like the first major class of bugs we
can address is improperly sized and incompatible matrices.  If the compiler
always made sure we used compatible matrices, we can avoid bugs at
compile-time, and we also can get a friendly helper when we write programs (by
knowing what works with what, and what we need were, and helping us organize
our logic)

Let's write a `Weights` type that tells you the size of its output and the
input it expects.  Let's have, say, a `Weights 10 5` be a set of weights that
takes you from a layer of 10 nodes to a layer of 5 nodes.  `w :: Weights 4 6`
would take you from a layer of 4 nodes to a layer of 6 nodes:

~~~haskell
!!!dependent-haskell/NetworkTyped.hs "data Weights"
~~~

The type constructor `Weights` has the kind `Weights :: Nat -> Nat -> *` --- it
takes two types of kind `Nat` (from the *[GHC.TypeLits][]* module, which the
integer type literals give us with *[DataKinds][]* enabled) and returns a `*`
--- a "normal type".

[DataKinds]: https://www.schoolofhaskell.com/user/konn/prove-your-haskell-for-great-safety/dependent-types-in-haskell#type-level-naturals
[GHC.TypeLits]: http://hackage.haskell.org/package/base-4.8.2.0/docs/GHC-TypeLits.html

We're using the *[Numeric.LinearAlgebra.Static][]* module from *[hmatrix][]*, which
offers matrix and vector types with their size in their types: an `R 5` is a
vector of Doubles with 5 elements, and a `L 3 6` is a 3x6 vector of Doubles.

[Numeric.LinearAlgebra.Static]: http://mstksg.github.io/hmatrix/Numeric-LinearAlgebra-Static.html

These types are called "dependent" types because the type itself *depends* on
its value.  If an `R n` contains a 5-element vector, its type is `R 5`.

The *Static* module in *hmatrix* relies on the [`KnownNat`][] mechanism that GHC
offers.  Almost all operations in the library require a `KnownNat` constraint
on the type-level Nats --- for example, you can take the dot product of two
vectors with `dot :: KnownNat n => R n -> R n -> Double`.  It lets the library
use the information in the `n` at runtime as an `Integer`.  (More on this
later!)

[`KnownNat`]: http://hackage.haskell.org/package/base-4.8.2.0/docs/GHC-TypeLits.html#t:KnownNat

Moving on, our network type for this post will be something like `Network 10
'[7,5,3] 2`: Take 10 inputs, return 2 outputs --- and internally, have hidden
layers of size 7, 5, and 3. (The `'[7,5,3]` is a type-level list of Nats; the
optional `'` apostrophe is just for our own benefit to distinguish it from a
value-level list of integers.)

~~~haskell
!!!dependent-haskell/NetworkTyped.hs "data Network"
~~~

We use GADT syntax here again.  The *kind signature* of the type constructor
means that the `Network` type constructor takes three inputs: a `Nat`
(type-level numeral, like `10` or `5`), list of `Nat`s, and another `Nat` (the
input, hidden layers, and output sizes).  Let's go over the two constructors.

*   The `O` constructor takes a `Weights i o` and returns a `Network i '[] o`.
    That is, if your network is just weights from `i` inputs to `o` outputs,
    your network itself just takes `i` inputs and returns `o` outputs, with no
    hidden layers.

*   The `(:&~)` constructor takes a `Network h hs o` -- a network with `h`
    inputs and `o` outputs -- and "conses" an extra input layer in front.  If
    you give it a `Weights i h`, its outputs fit perfectly into the inputs of
    the subnetwork, and you get a `Network i (h ': hs) o`.  (`(':)`, or `(:)`,
    is the same as normal `(:)`, but is for type-level lists.  The apostrophe
    is optional here too, but it's just nice to be able to visually distinguish
    the two)

    We add a `KnownNat` constraint on the `h`, so that whenever you pattern
    match on `w :&~ net`, you automatically get a `KnownNat` constraint for the
    input size of `net` that the *hmatrix* library can use.

We can still construct them the same way:

~~~haskell
-- given:
ih :: Weights 10 7
hh :: Weights  7 4
ho :: Weights  4 2

-- we have:
              O ho :: Network  4 '[] 2
       hh :&~ O ho :: Network  7 '[4] 2
ih :&~ hh :&~ O ho :: Network 10 '[7,4] 2
~~~

Note that the shape of the constructors requires all of the weight vectors to
"fit together".  `ih :&~ O ho` would be a type error (feeding a 7-output layer
to a 4-input layer).  Also, if we ever pattern match on `:&~`, we know that the
resulting matrices and vectors are compatible!

One neat thing is that this approach is also self-documenting.  I don't need to
specify what the dimensions are in the docs and trust the users to read it and
obey it. The types tell them!  And if they don't listen, they get a compiler
error!  (You should, of course, still provide reasonable documentation.  But,
in this case, the compiler actually enforces your documentation's statements!)

Generating random weights and networks is even nicer now:

~~~haskell
!!!dependent-haskell/NetworkTyped.hs "randomWeights ::"
~~~

Notice that the *Static* versions of [`randomVector`][randomVector static] and
[`uniformSample`][uniformSample static] don't actually require the size of the
vector/matrix you want as an input -- they just use *type inference* to figure
out what size you want!  This is the same process that [`read`][] uses to figure
out what type of thing you want to return. You would use `randomVector s
Uniform :: R 10`, and type inference would give you a 10-element vector the
same way `read "hello" :: Int` would give you an `Int`.

[randomVector static]: http://mstksg.github.io/hmatrix/Numeric-LinearAlgebra-Static.html#v:randomVector
[uniformSample static]: http://mstksg.github.io/hmatrix/Numeric-LinearAlgebra-Static.html#v:uniformSample
[`read`]: http://hackage.haskell.org/package/base-4.8.2.0/docs/Prelude.html#v:read

It's important to note that it's much harder to implement this incorrectly.
Before, you could give the matrix the wrong dimensions (maybe you flipped the
parameters?), or gave the wrong parameter to the vector generator.

But here, you are guaranteed/forced to return the correctly sized vectors and
matrices.  In fact, you *don't even have to worry* about it --- it's handled
automatically by the magic of type inference[^hindley]!  I consider this a very big
victory.  One of the whole points of types is to give you less to "worry
about", as a programmer. Here, we completely eliminate an *entire dimension* of
programmer concern.

[^hindley]: Thank you based Hindley-Milner.

#### Benefits to the user

Not only is this style nicer for you as the implementer, it's also very
beneficial for the *user* of the function.  Consider looking at the two
competing type signatures side-by-side:

~~~haskell
randomWeights :: Int -> Int -> m Weights
randomWeights ::               m (Weights i o)
~~~

If you want to *use* this function, you have to look up some things from the
documentation:

1.  What do the two arguments represent?
2.  What *order* is the function expecting these two arguments?
3.  What will be the dimension of the result?

These are three things you *need* to look up in the documentation.  There's
simply no way around it.

But, here, all of these questions are answered *immediately*, just from the
type (which you can get from GHC, or from ghci).  You don't need to worry about
arguments.  You don't need to worry about what order the function is expecting
the arguments to be in.  And you already know *exactly* what the dimensions of
the result is, right in the type.

I often implement many of my functions in this style, even if the rest of my
program isn't intended to be dependently typed (I can just convert the type to
a "dumb" type as soon as I get the result).  All of these benefits come even
when the caller doesn't *care* at all about dependently typed programming ---
it's just a better style of defining functions/offering an API!

### Singletons and Induction

The code for the updated `randomNet` takes a bit of background to understand,
so let's take a quick detour through the concepts of singletons, dependent
pattern matching, and induction on dependent data types.

Let's say we want to implement an algorithm that can create any `Network i hs
o`, so that we can construct a `Network 4 '[3,2] 1` or something.  In true
Haskell fashion, we want do this recursively ("inductively").   After all, we
know how to make a `Network i '[] o` (just `O <$> randomWieights`), and we know
how to create a `Network i (h ': hs) o` if we had a `Network h hs o` (just use
`(:&~)` with `randomWeights`).  Now all we have to do is just "pattern match"
on the type-level list, and...

Oh wait.  We can't pattern match on types like that in Haskell.  This is due to
one of Haskell's fundamental design decisions: types are **erased** at runtime.
We need to have a way to "access" the type (at run-time) as a *value*, so we
can pattern match on it and do things with it.

In Haskell, the popular way to deal with this is by using *singletons* ---
(parameterized) types which only have valid constructor.  The
*[typelits-witnesses][]* library offers a handy singleton for just this job. If
you have a type level list of nats, you get a `KnownNats ns` constraint. This
lets you create a `NatList`:

[typelits-witnesses]: http://hackage.haskell.org/package/typelits-witnesses-0.2.2.0

~~~haskell
data NatList :: [Nat] -> * where
    ØNL   :: NatList '[]
    (:<#) :: (KnownNat n, KnownNats ns)
          => !(Proxy n) -> !(NatList ns) -> NatList (n ': ns)

infixr 5 :<#
~~~

Basically, the *only* value of type `NatList '[1,2,3]` is `p1 :<# p2 :<# p3 :<#
ØNL`, where `p1 :: Proxy 1`, `p2 :: Proxy 2`, and `p3 :: Proxy 3`.  (Remember,
`data Proxy a = Proxy`; `Proxy` is like `()` but with an extra phantom type
parameter).

We use singletons like this by *pattern matching* on the polymorphic type (a `NatList ns`)
and consequentially learning about the type parameter `ns`.  If we match on the
`ØNL` constructor, we (and by we, I mean GHC) knows we have a `NatList '[]`, and
we match on the `:<#` constructor, we know we have `NatList (n ': ns)`

This is called *dependent pattern matching* --- the constructor we match on
yields information about the type of the value.

We can spontaneously generate a `NatList` for any type-level Nat list with
`natList :: KnownNats ns => NatList ns`:

~~~haskell
ghci> natList :: NatList '[1,2,3]
Proxy :<# Proxy :<# Proxy :<# ØNL
-- ^         ^         ^
-- `-- :: Pro|xy 1     |
--           `-- :: Pro|xy 2
--                     `-- :: Proxy 3
~~~

Essentially, the `KnownNats ns` typeclass constraint lets us turn `ns` into the
`NatList ns` that we can pattern match on.  (In a sense, `KnownNats ns =>` is
really equivalent to `NatList ns ->`)  Now that we have an actual
value-level *structure* (the list of `Proxy`s), we can now morally "pattern
match" on `hs`, the type --- if it's empty, we'll get the `ØNL` constructor
when we use `natList`, otherwise we'll get the `(:<#)` constructor, etc.

~~~haskell
!!!dependent-haskell/NetworkTyped.hs "randomNet ::"
~~~

(Note that we need `ScopedTypeVariables` and explicit `forall` so that
can say `NatList hs` in the body of the declaration.)

The reason why `NatList` and `:<#` works for this is that its constructors
*come with "proofs"* that the head's type has a `KnownNat` constraint and the
tail's type has a `KnownNats` one.  It's a part of the GADT declaration.  If
you ever pattern match on `p :<# ns`, you get a `KnownNat n` constraint (that
`randomWeights` uses) for the `p :: Proxy n`, and also a `KnownNats ns`
constraint (that the recursive call to `randomNet` uses).

This is a common pattern in dependent Haskell: "building up" a value-level
singleton *structure* from a type that we want (either explicitly given as an
argument, or provided through a typeclass like `KnownNats`) and then
inductively piggybacking on that structure's constructors to build the thing
you *really* want (called "elimination").  Here, we use `KnownNats hs` to build
our `NatList hs` structure, and use/"eliminate" that structure to create our
`Network i hs o`.

Along the way, the singletons and the typeclasses and the types play an
intricate dance.  `randomWeights` needed a `KnownNat` constraint.  Where did it
*come* from?

#### On Typeclasses

`natList` uses the `KnownNat n` to construct the `NatList ns` (because any time
you use `(:<#)`, you have/need a `KnownNat` instance in scope).  Then, when you
pattern match on the `(:<#)` in `randomNet`, you "release" the `KnownNat n`
that was stuffed in there by `natList`.

People say that pattern matching on `(:<#)` gives you a "context" in that
case-statement-branch where `KnownNat n` is in scope and satisfied.  But
sometimes it helps to think of it in the way we just did --- the instance
*itself* is actually a "thing" that gets passed around through GADT
constructors/deconstructors.  The `KnownNat` *instance* gets put *into* `:<#`
by `natList`, and is then taken *out* in the pattern match so that
`randomWeights` can use it.  (When we match on `_ :<# _`, we really are saying
that we don't care about the "normal" contents --- we just want the typeclass
instances that the constructor is hiding!)

At a high-level, you can see that this is really no different than just having
a plain old `Integer` that you "put in" to the constructor (as an extra field),
and which you then take out if you pattern match on it.  Really, every time you
see `KnownNat n => ..`, you can think of it as an `Integer -> ..` (because all
the typeclass is is a way to get an `Integer` out of it with `natVal`). `(:<#)`
requiring a `KnownNat n =>` put into it is really the same as requiring an
`Integer` in it, which the act of pattern-matching can then take out.  A
`NatList ns` is no different at run-time than an `[Integer]`, and `KnownNats
ns =>` is no different than `[Integer] ->`.

The difference is that GHC and the compiler can now *track* these at
compile-time to give you *checks* on how your Nat's act together on the type
level, allowing it to catch mismatches with compile-time checks instead of
run-time checks.

### Running with it

So now, you can use `randomNet :: IO (Network 5 '[4,3] 2)` to get a random
network of the desired dimensions! (`IO` is an instance of `MonadRandom`)

Can we just pause right here to just appreciate how awesome it is that we can
generate random networks of whatever size we want by *just requesting something
by its type*?  Our implementation is also *guaranteed* to have the right sized
matrices --- no worrying about using the right size parameters for the right
matrix in the right order.  GHC does it for you automatically!  And, for the
person who *uses* `randomNet`, they don't have to bungle around with figuring
out what function argument indicates what, and in what order, and they don't
have to play a guessing game about the shape of the returned matrix.

The code for *running* the nets is actually literally identical from before:

~~~haskell
!!!dependent-haskell/NetworkTyped.hs "runLayer ::" "runNet ::"
~~~

But now, we get the assurance that the matrices and vectors all fit each-other,
at compile-time.  GHC basically writes our code for us.  The operations all
demand vectors and matrices that "fit together", so you can only ever multiply
a matrix by a properly sized vector.

~~~haskell
(+)  :: KnownNat n
     => R n -> R n -> R n
(#>) :: (KnownNat n, KnownNat m)
     => L n m -> R m -> R n

logistic :: KnownNat n
         => R n -> R n
~~~

The source code is the same from before, so there isn't any extra overhead in
annotation.  The correctness proofs and guarantees basically come without any
extra work --- they're free!

Our back-prop algorithm is ported pretty nicely too:

~~~haskell
!!!dependent-haskell/NetworkTyped.hs "train ::"
~~~

It's pretty much again almost an exact copy-and-paste, but now with GHC
checking to make sure everything fits together in our implementation.

One thing that's hard for me to convey here without walking through the
implementation step-by-step is how much the types *help you* in writing this
code.

Before starting writing a back-prop implementation without the help of types,
I'd probably be a bit concerned.  I mentioned earlier that writing the untyped
version was no fun at all.  But, with the types, writing the implementation
became a *joy* again.  And, you have the help of *hole driven development*,
too.

If you need, say, an `R n`, there might be only one way get it!  And if you
have something that you need to combine with something you don't know about,
you can use typed holes (`_`) and GHC will give you a list of all the values
you have in scope that can fit there.  Your programs basically write
themselves!

The more you can restrict the implementations of your functions with your
types, the more of a joy programming in Haskell is.  Things fit together and
fall together before your eyes...and the best part is that if they're wrong,
the compiler will nudge you gently into the correct direction.

The most stressful part of programming happens when you have to tenuously hold
a complex and fragile network of ideas and constraints in your brain, and any
slight distraction or break in focus causes everything to crash down in your
mind.  Over time, people have begun to believe that this is "normal" in
programming. Don't believe this lie --- it's *not*!  A good programming
experience involves maintaining as *little* in your head as possible, and
letting the compiler handle remembering/checking the rest.

#### The final test

You can download the [typed network][NetworkTyped] source code and run it
yourself.  Again, the [`main`][mainTyped] method is written identically to that
of the other file and tests the identical function.

!!![NetworkTyped]:dependent-haskell/NetworkTyped.hs
!!![mainTyped]:dependent-haskell/NetworkTyped.hs "main ::"

~~~bash
$ stack install hmatrix MonadRandom typelits-witnesses
$ stack ghc -- -O2 ./NetworkTyped.hs
$ ./NetworkTyped
# Training network...
#
#
#             -#########-
#           -#############=
#          -###############-
#          =###############=
#           ##############=.
#            .##########=.
#                               .==#=-
#                            -###########-
#                           =##############.
#                          .###############=
#                           =##############-
#                            =############-
#                              -######=-.
#
#
~~~


Finding Something to Depend on
------------------------------

We wrote out an initial "non-typed" implementation and recognized a lot red flags
that you might already be trained to recognize if you have been programming
Haskell for a while: *partial functions* and *multiple potential
implementations*.

We followed our well-tuned Haskell guts, listened to our hearts, and introduced
extra power in our types to remove all partial functions and eliminate *most*
potential implementations (though not all, yet --- there are more gains to be
made from pulling in more parametric polymorphism).

Though we might have been able to find the bugs we avoided "eventually", we
were able to remove entire *dimensions* of programmer concern and also leverage
parametric polymorphism to help write our programs for us.  We found joy again
in programming.

In the process, however, we encountered some unexpected resistance from Haskell
(the language).  We couldn't directly pattern match on our types, so we ended
up playing games with singletons and GADT constructors to pass instances.

In practice, using types as powerful and descriptive as these begin to require
a whole new set of tools once you get past the simplest use cases here.  For
example, our `Network` types so far required you to specify their size in the
program itself (`Network 2 '[16, 8] 1` in the example source code, for
instance).  But what if we wanted to generate a network that has
runtime-determined size (For example, getting the size from user input)?  What
if we wanted to load a pre-trained network whose size we don't know?  How can
we manipulate our networks in a "dynamic" and generic way that still gives us
all of the benefits of type-safe programming?

What we're looking at here is a world where *types* can depend on run-time
values ... and values can depend on types.  A world where types can be returned
from functions and where types become as much of a manipulatable citizen of as
values are.

The art of working with types like this is *dependently typed programming*.
We're going to feel a bit of push back from Haskell at first, but after we hit
our stride and tame the tools we need, we're going to open up a whole new world
of potential!

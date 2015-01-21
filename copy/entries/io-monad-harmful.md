IO Monad Considered Harmful
===========================

Categories
:   Haskell
Tags
:   haskell
:   functional programming
:   monads
:   io
CreateTime
:   2015/01/20 22:08:11
PostDate
:   Never
Identifier
:   io-monad-harmful

In the tradition of "considered harmful" posts, this post's title is
intentionally misleading and designed to incite controversy --- or at least
grab your attention :D

I don't mean that this "IO Monad" is something to be avoid.  What I
mean is that the phrase "IO Monad"...it's got to go.  It has its usages, but
99.9% of times it is used, it is used improperly.  So let's go ahead with
stopping this nonsense once and for all, okay?

So I'll say it here:

**The phrase "IO monad" considered harmful.  Please do not use
it.**[^never][^sometimes]

In most circumstances, the *IO type* is the more helpful and more correct
answer.

[^never]: In any case, ever, for any circumstance or reason.
[^sometimes]: Just kidding.  Only a sith deals in absolutes.

Let's say someone comes to you and asks you the question:

> How does Haskell do things like print a string?

**Definitely not with the IO monad.**

This is literally one of the simplest question a new person to Haskell can
ask.  There are many incorrect answers you could give, but "the IO Monad" is
one of the most incorrect answers possible.

For one, one of the most beautiful things about Haskell is that IO actions are
all [first-class normal data objects][fcs], like lists or integers or
booleans.

[fcs]: http://blog.jle.im/entry/first-class-statements

The answer to this is that you use something of an `IO` type.

You use the *IO type*.

~~~haskell
ghci> :t putStrLn "hello world"
putStrLn "hello world" :: IO ()
~~~

There is nothing that has to do with monads at all in printing a string.  The
idea that `putStrLn "hello world"` is monadic is as absurd as saying that
`[1,2,3]` is monadic.

Saying that the answer is the "IO monad" implies that the monad part is
something important.  **It's not.**

**IO in Haskell has nothing to do with monads.**

You could take away monads and even the entire monadic interface from Haskell
and Haskell could *still* do IO *with the same IO type*.

The ability for Haskell to work with IO comes from the fact that we have a
data type that represents IO actions, in the same way that `Bool` represents a
boolean or `Integer` represents an integer.

Saying "the IO monad" is literally the most misleading thing you could
possibly say.  IO in Haskell has nothing to do with monads.

How did this idea become so prevalent and pervasive?  I cannot say!  But
somehow, somewhere, this idea happened, and it is persistent now.  Please do
not add anything to this misconception and further propagate this dangerous
myth.

Saying "IO monad" is very misleading and awful pedagogy because when someone
new to Haskell reads that you print strings or do IO actions using "the IO
monad", the natural question is: "What is a monad?"

Not only is that question completely *irrelevant* to doing IO at all, it's
also a question that has [historically lead to much confusion][mtf].  I
consider it one of the worst "sidequests" you could embark on in learning
Haskell.  Seeking an intuitive grasp of what a monad is is not only worthless
for learning practical haskell (at the start), but one that can lead to many
false answers, confusing and contradictory answers, and just a lot of headache
in general.  Before I even ever heard about Haskell, I heard about the
infamous "IO monad".  I read, "monads are a crazy hard-to-understand subject,
but once you understand it, Haskell becomes amazing."  Haskell is haskell and
is useful before you ever introduce Monad into the picture...and a quote like
that implies that understanding monads is important to understanding haskell
or IO.

[mtf]: https://byorgey.wordpress.com/2009/01/12/abstraction-intuition-and-the-monad-tutorial-fallacy/

It just simply *isn't*.  If you want to "understand Monads" (whatever that
means), then go ahead; try.  But please don't think that it'll help you **even
a single bit** in understanding IO in haskell.

Saying "IO Monad" implies that understanding monads is some prerequisite to
understanding IO, or at the very least that IO in haskell is inherently tied
to monads.  **Both are untrue**.

Furthermore, imagine someone new to Haskell asked you, "Can I store a sequence
of numbers?"

One good answer would be, "Yes, with a list!", or the list type.

One bad answer would be, "Yes, with the List Monad!"

Now someone who wants to be able to do something simple like `[1, 2, 3]` will
think that something like `[1, 2, 3]` in Haskell is inherently tied to monads
in some way.

But having a list like `[1,2,3]` has nothing to do with monads.  Calling every
list "the list monad", or calling every situation where a list would be useful
a situation where "you want the List moand" is misleading, false, and just
leads to more confusion.

I need to find all even numbers from one to one hundred.

Right: Use a list and `filter even` over a list from one to one
hundred.

Wrong: Use the list monad and `filter even` over a list from one to one
hundred.

Why would you ever do that?

What good does it do?

What good has it ever done anyone?

Really, why?

Why do people say the IO monad?

Why did people start saying that in the first place?

Why doesn't this world many any sense?

Please, please, stop saying "the IO monad".

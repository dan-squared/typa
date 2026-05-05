# How Typa Works

This guide explains Typa from two angles:

- what the app is doing behind the scenes
- what all of that means for a real person using it day to day

The first half is more structural and product-oriented.
The second half is written for non-technical readers and focuses on what users feel, see, and improve.

## 1. The Big Picture

Typa is not just a timer with random words.

It is a local typing trainer with two main modes:

- `Learning`
  This is the adaptive mode. It studies how you type and changes future lessons based on your weaknesses.
- `Test`
  This is the fixed-measurement mode. It lets you run controlled sessions for common words, code words, numbers, or custom text.

Typa is currently tuned for QWERTY and keeps all progress locally on the device.

## 2. What Happens The First Time A User Opens Typa

When a new user opens Typa for the first time, the app does not yet know:

- which keys are easy for them
- which keys are slow
- which transitions break down
- whether they tend to rush, hesitate, or overcorrect

So the app starts with a simpler learning state.

In practice, this means:

1. The user enters the app and lands in the main typing experience.
2. If they begin in `Learning` mode, Typa generates a lesson using a manageable active set of keys.
3. As they type, Typa records speed, accuracy, misses, corrections, and key-to-key timing.
4. When the session ends, the app saves the result and updates the learning profile.
5. The next lesson is generated using the new profile, not from scratch.

The entire product loop is:

1. generate a lesson
2. observe the user
3. save the session
4. update the profile
5. generate a better lesson

## 3. What Typa Tracks During Practice

Typa tracks more than a final WPM number.

During a session, it records:

- accepted inputs
- rejected inputs
- corrected inputs
- cursor position changes
- expected key versus typed key
- timing between accepted keys
- transition trouble between adjacent letters
- correction hotspots after mistakes

This matters because typing improvement is rarely just “type faster.”

A user can have:

- good average speed but poor transitions
- good speed on familiar words but poor recovery after mistakes
- strong common letters but weak punctuation or certain finger patterns

Typa tries to capture those differences and use them to shape future practice.

## 4. How Learning Mode Progresses Over Time

Learning mode is the part that makes Typa feel personal.

It maintains a lesson state that includes:

- the active alphabet
- the current focus key, if one exists
- any forced keys that still need reinforcement
- the target pace the system is aiming toward

Over time, Typa tries to do four things at once:

1. keep practice readable enough to sustain momentum
2. expose weak keys often enough to improve them
3. avoid expanding too fast when the user is unstable
4. unlock broader practice when the user is ready

In simple terms:

- if the user is handling the current key set well, the app can broaden practice
- if the user is struggling on specific keys, the app can slow down expansion and reinforce those keys first
- if a specific letter or letter pair keeps causing trouble, Typa can keep steering lessons toward it

That is the core idea of progress in Typa.

Progress is not only “my highest WPM increased.”
Progress is also:

- I can type a wider range of keys cleanly
- I recover from mistakes faster
- I miss fewer transitions
- my weaker letters are becoming more stable
- my speed is rising without accuracy collapsing

## 5. How Typa Decides Whether You Are Improving

Typa looks at several signs together.

### Session-level signs

- WPM
- accuracy
- total errors
- duration
- completed text

### Key-level signs

- hits and misses for each key
- average time for each key
- confidence estimates for each key
- whether a key is stable enough to stop forcing

### Transition-level signs

- which letter pairs slow the user down
- which pairs are repeatedly missed
- where corrections happen most often

### Pattern-level signs

- whether the active alphabet can safely grow
- whether the user is improving consistently or only in bursts
- whether the user is reaching goals and maintaining streaks

This is why Typa’s idea of progress is more trustworthy than a single-speed spike.

## 6. What The User Sees As Evidence Of Progress

Typa exposes progress in a few ways:

- session results after a run
- learning milestones such as goal reached or new best speed
- profile charts over time
- weakest-key summaries
- key detail views
- transition insights
- daily goal and streak history

A user knows they are improving when several things start moving together:

- average WPM trends upward
- accuracy stays steady or rises
- weak keys stop dominating lessons
- lessons feel broader and less repetitive
- fewer mistakes happen on the same letters and transitions

## 7. Why Lessons Sometimes Change In Character

Typa is always balancing two goals:

- make practice natural enough to feel usable
- make practice targeted enough to improve weaknesses

That means lesson texture may change based on:

- current weak keys
- the selected target speed
- the active alphabet size
- whether the app is prioritizing real words
- whether the user needs reinforcement before unlocking more variety

So if a session feels easier, narrower, stranger, or more repetitive than a previous one, that is usually not random.
It is the engine trying to solve a training problem.

## 8. The Role Of Real Words And Pseudo-Words

Typa prefers real words when possible, especially when the active alphabet can support enough readable words.

Pseudo-words exist as a fallback when the engine needs:

- a narrow set of letters
- more repetition of specific patterns
- more coverage than the real-word pool can provide cleanly

Pseudo-words should support the lesson, not dominate it.

That is why shorter pseudo-words generally feel better:

- they reduce cognitive friction
- they keep the lesson moving
- they behave more like drills than fake vocabulary puzzles

## 9. What Each Major Setting Does

This section explains the main settings in product terms.

### Session Mode

- `Learning`
  The app adapts based on performance and decides what to practice next.
- `Test`
  The app does not adapt the source during the session. It behaves more like a controlled benchmark.

### Test Length

- `Time`
  Practice ends when the timer runs out.
- `Words`
  Practice ends after a chosen word count.
- `Continuous`
  Practice behaves more like an open run without a fixed word cap.

### Word Source

- `Common Words`
  Best for general typing practice.
- `Code Words`
  Better for developer-style vocabulary and shorter technical words.
- `Numbers`
  Good for number entry and digit stability.
- `Custom Words`
  Uses the user’s own text source.

### Daily Goal

This is not a speed goal.
It is a time commitment goal.

It helps the user build consistency rather than chase a single fast session.

### Error Mode

- `Off`
  Freer typing flow.
- `Letter Strict`
  More corrective pressure at the character level.
- `Word Strict`
  More rigid typing behavior across whole words.

Stricter modes can be useful for deliberate drills, but they can also make sessions feel harsher.

### Minimum Accuracy

This protects the quality of saved results.

If a user types too sloppily, the run can be treated as less meaningful.
That encourages cleaner practice rather than pure speed-chasing.

### Target Speed

This tells the learning engine what pace it is training toward.

It does not mean “the app thinks you can do this everywhere right now.”
It means “this is the pace the lesson logic is using as a training reference.”

### Lesson Length

This controls how long a learning lesson feels.

Shorter lessons:

- feel faster
- reduce fatigue
- give more frequent feedback loops

Longer lessons:

- provide more data
- increase endurance pressure
- make a single session feel more substantial

### Repeat Each Word

This increases repetition inside the lesson.

More repetition can help early reinforcement.
Too much repetition can make practice feel stale.

### Unlock Order

- `Keyboard Order`
  Expands with a stronger positional logic.
- `Frequency First`
  Expands based more on language usefulness.

The difference is mostly about how the learning path grows, not whether the app tracks mistakes.

### How Fast To Add New Keys

This controls how aggressively the active alphabet expands.

Low values:

- slower expansion
- more stability
- better for careful progression

High values:

- faster expansion
- more variety
- greater chance of overwhelming weaker users

### Fix Weak Keys Before Adding More

When enabled, Typa is more conservative.

It tries to repair weakness before broadening the lesson pool.

This is often better for real learning quality, especially for newer users.

### Use More Real Words When Possible

This pushes the engine toward readable practice.

It usually improves comfort and engagement.
Turning it off can make lessons more drill-like and artificial.

### Capital Letters And Punctuation

These control how demanding the text looks.

Higher values:

- add realism
- increase visual complexity
- increase cognitive load

Lower values:

- keep practice cleaner
- reduce noise for learning core keys

### Sound Pack And Error Sound

These change feedback feel, not skill logic.

They affect pacing, rhythm, and satisfaction.
Some users type more calmly with sound off, while others benefit from tactile-style audio confirmation.

### Font Size, Line Height, Letter Spacing, Visibility

These shape readability.

If the text is hard to scan, typing quality often drops even if the engine is good.
These settings matter more than they first appear.

### Live Stats

This controls how much the app exposes performance during a run.

Some users perform better with constant feedback.
Others improve more when they stop monitoring the numbers every second.

## 10. Non-Technical Explanation For Real Users

This section explains Typa as if we were describing it to a normal user, not a developer.

### What Typa Is Trying To Do For You

Typa is trying to give you practice that is:

- not too easy
- not too random
- not too overwhelming
- focused on the places where you actually need help

Instead of treating every session like a fresh start, it remembers how you type and uses that memory to shape the next session.

### What Improvement Looks Like In Real Life

If Typa is working well for you, improvement usually feels like this:

1. At first, the lessons feel narrow and controlled.
2. After a while, the text starts feeling easier to read and complete.
3. You stop getting stuck on the same keys over and over.
4. The app broadens what it asks from you.
5. Your speed rises more naturally because you are fighting the text less.

So improvement is not just “I hit one high score.”
It is “the app needs to rescue me less often.”

### Why A User Might Feel Stuck

A user can feel stuck even if progress is happening.

That usually happens when:

- they focus only on peak WPM
- the app is still repairing weak keys
- they are practicing inconsistently
- the lesson settings are too difficult
- the text style is visually tiring

In those cases, the right question is not only “am I faster?”
It is also:

- am I cleaner?
- am I more stable?
- am I making fewer repeat mistakes?

### How To Use Typa Well As A User

For most people, the healthiest approach is:

1. Use `Learning` mode regularly.
2. Keep the daily goal realistic.
3. Do not set the target speed unrealistically high.
4. Let the app reinforce weak keys instead of constantly forcing variety.
5. Use `Test` mode to measure yourself occasionally, not every minute.

### How Settings Change The Feel Of Practice

If a user wants calmer practice:

- shorter lessons
- more real words
- lower capitals and punctuation
- sound off or softer sound
- live stats off if the numbers are distracting

If a user wants more challenge:

- slightly longer lessons
- more punctuation
- stricter error handling
- a higher target speed
- more aggressive key expansion

### What A Good Long-Term User Experience Should Feel Like

Over weeks, a good Typa experience should feel like:

- less friction
- more confidence
- wider coverage
- fewer repeated pain points
- more trustworthy progress trends

The app should start feeling less like a word generator and more like a coach that keeps adjusting the drill to the user’s real skill.

## 11. Summary

Typa works best when users understand three things:

1. `Learning` mode is for improvement, not just score chasing.
2. Progress means cleaner and broader skill, not just one fast run.
3. Settings change the training experience in meaningful ways, especially lesson length, target speed, real-word preference, and weak-key recovery.

If Typa feels focused, readable, and progressively more stable over time, the system is doing its job.

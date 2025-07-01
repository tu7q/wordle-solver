Wordle Solver:
    - based on 3b1b video on wordle


Calculate the entropy for each word. (O(n^2) ???) Display top 10 words (sorting ig)


Entropy
Generate possible Patterns or maybe just loop over all possible words??? (looping is n^2 no?)

Things that need to happen
1. Filtering word list for letters
2. Filtering word list for letters in a position
3. Filtering word list for letters not in a position
4. Filtering word list excluding certain letters

Idea:
1. Word list for each letter with flags. (Each index of this list correspond to actual word list)

Strat:
Compute all patterns for every pair of words. (Actual + Guess)
List of possible words (indices)
Compute entropy of possible words.
Suggest word with max entropy (sorted idk)
User reports actual guess + pattern
Filter words to have actual pattern.

# Dependencies
1. https://github.com/rockorager/libvaxis
2. https://github.com/Hejsil/zig-clap


-> Words as integers(bit strings)? && operator,  
With each WordleResult as a byte (2 bits per thing -> 2 * 5 = 10 bits so 2 bytes when considering padding)
And 14,000 possible words -> 196000000 entries in the matrix
which is 392 megabytes. (Which is reasonable. unlike python taking 20+ GB for some reason)

 
# 
E[Information] = -sum(p*log2(p))
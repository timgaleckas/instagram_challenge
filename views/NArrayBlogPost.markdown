Recently Instagram put forward a challenge: [Instagram Engineering Challenge: The Unshredder](http://instagram-engineering.tumblr.com/post/12651721845/instagram-engineering-challenge-the-unshredder).

There are some solutions out there already:

- [Quickly Solving the “Instagram Engineering Challenge: The Unshredder”](http://martin.ankerl.com/2011/11/15/solving-the-instagram-challenge-quickly/) 
- [Explorations in Go: solving the Instagram engineering challenge](http://blog.carbonfive.com/2011/11/17/explorations-in-go-solving-the-instagram-engineering-challenge/)

And that's just in the first page of Google hits.

Here at [Centro](http://www.centro.net/), the team all challenged each
other and shared our solutions.

I solved the problem and was pretty proud of myself until one of the
wiseguys here threw this image at my code: [Shredded Mona Lisa](https://github.com/timgaleckas/instagram_challenge/raw/master/inputs/mona_lisa_shredded.png)

Of course, [my original code](https://github.com/timgaleckas/instagram_challenge/commit/d186032d71f29bb2568dad00d6e656a6962d0f82) fell over and took 21 seconds to to un-shred an image
that large. It became a point of pride to see how fast I could get it
running.

I tried:

 - [Caching](https://github.com/timgaleckas/instagram_challenge/commit/180eececcf2f422694554a6244acd489af5c8750)
for a speed up to 18 seconds.
 - [Unrolling loops and skipping pixels](https://github.com/timgaleckas/instagram_challenge/commit/780931fa6acd5239c66350420a20292cbb039388)
to get me to 3 seconds but it cost me some resolution and had the
potential to fail if it checked the wrong pixels (if I started at
the second pixel instead of the first it failed).
 - [Switching to NArray](https://github.com/timgaleckas/instagram_challenge/commit/66c78aa072a3d33d3fc7805720df1805809c1269)
gave me comparable speed (5 seconds) without sacrificing any of the
resolution.
 - And [reducing the scope of the check](https://github.com/timgaleckas/instagram_challenge/commit/18fe2e13df723371cad313c27a7608cb9e9be54b)
reduced the time back to the blazing fast sub 3 second time without
sacrificing vertical resolution.

If you take a careful look at the code and do the math, you'll see that
switching to NArray allowed me to go from only checking 100 pixels for
each column to checking the full 1549 pixels while staying within one
second of the time of the other run.

Seems pretty powerful. That's why I'd like to give you a little
explanation of how we're using NArray in this case and hopefully give
you an incredibly powerful tool in your ruby tool box.

The loop we're trying to optimize is:

    def percentage_pixels_that_are_edgelike(other_column)
      @percentage_by_other_column ||= {}
      return @percentage_by_other_column[other_column] if @percentage_by_other_column[other_column]
      # this line is doing all the work
      @percentage_by_other_column[other_column] = (0...pixels.size).select{|index|pixel_is_edgelike?(index, other_column)}.size.to_f / pixels.size
    end

    def pixel_is_edgelike?(index, other_column)
      (self[index+1] && (self[index]-other_column[index]).intensity > (self[index]-self[index+1]).intensity) ||
      (self[index-1] && (self[index]-other_column[index]).intensity > (self[index]-self[index-1]).intensity)
    end

We know that creating that inner block that many times is inefficient
and we know that using select{}.size is inefficient. That's why my first
attempt at optimization was just to unroll the iteration into a simple
loop.

What [NArray](http://narray.rubyforge.org/) allows us to do, on the other
hand, is remove both iteration and math over arrays of data from ruby and
push it down to a native extension.

So what used to be:

    def add_arrays( array_1, array_2 )
      new_array = []
      array_1.each_index{ |index| new_array[index] = array_1[index] - array_2[index] }
      new_array
    end

Turns into:

    #we don't even need a method for this but,
    def add_narrays( narray_1, narray_2 )
      narray_1 - narray_2
    end

And the fact that NArray handles math between multidimensional arrays just
as easily allows us to do stuff like this:

    [
      [ 1, 3, 3 ],
      [ 2, 1, 3 ],
      [ 2, 2, 1 ]
    ] +
    [
      [ 0, 1, 2 ],
      [ 3, 4, 5 ],
      [ 6, 7, 8 ]
    ]
    ->
    [
      [ 1, 4, 5 ],
      [ 3, 5, 8 ],
      [ 8, 9, 4 ]
    ]

and even cooler:

    [
      [ 1, 3, 3 ],
      [ 2, 1, 3 ],
      [ 2, 2, 1 ]
    ] * 2
    ->
    [
      [ 2, 6, 6 ],
      [ 4, 2, 6 ],
      [ 4, 4, 2 ]
    ]

So instead of using RMagick's Pixel class and defining a custom :+
operator, we convert the array of pixels to a multidimensional array
of color values:

    NArray.to_na(pixels.map{|p|[p.red.to_f,p.green.to_f,p.blue.to_f]})

Which allows us to find the absolute difference between pixel columns
by:

    (pixel_array1 - pixel_array2).abs

And we multiply these pixel arrays by the function to convert to
intensity:

    a = pixel_differences * [0.299,0.587,0.114]
    a[0,true] + a[1,true] + a[2,true]

That multiplies each red value by 0.299, each green value by 0.587, each
blue value by 0.114, and then adds them together to get the intensity.

So that's all fine and good for values that run horizontally across the
array, but our formula needs to compare pixels to the top and the bottom
of the current pixel.

Given the pixel map:

    c1 | c2
    -------
    a0 | b0
    a1 | b1
    a2 | b2
    a3 | b3
    a4 | b4

The formula to check that a2 is closer to the pixel above or below it
than to the pixel next to it is: ( (a2 - b2) > (a2 - a1) ) || ( (a2 - b2) > (a2 - a3) )

To set up the data to allow us to use only operations across rows, we
add shifted copies of the first array to our dataset like so:

    c1 | c2 | c1_u | c1_d
    ---------------------
    a1 | b1 | a2   | a0
    a2 | b2 | a3   | a1
    a3 | b3 | a4   | a2

( Notice the removal of the top and bottom row from c1 )

So the formula for any given index i, becomes:
( ( c1[i] - c2[i] ) > ( c1[i] - c1_u[i] ) ) ||
( ( c1[i] - c2[i] ) > ( c1[i] - c1_d[i] ) )

The actual NArray code looks like this:

    def _pptae(other_column)
      s = @pixels
      o = other_column.pixels
      s1 = s[0..2,1..-2]
      column_difference = intensity_transform((s1 - o[0..2,1..-2]).abs)
      difference_up     = intensity_transform((s1 - s[0..2,0..-3]).abs)
      difference_down   = intensity_transform((s1 - s[0..2,2..-1]).abs)
      ((column_difference > difference_down).or( column_difference > difference_up )).where.total.to_f / s[0,true].total
    end

Notice the 'where' method and the 'total' method.

'where' returns an array of the indices for which the predicate is
true and 'total' is the same as the ruby array's size method ( but
faster )

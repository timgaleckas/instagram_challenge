require 'rubygems'
require 'narray'
require 'rmagick'
include Magick

class PixelColumn

  attr_reader :pixels, :label

  def initialize(pixels, label)
    @pixels = NArray.to_na(pixels.map{|p|[p.red.to_f,p.green.to_f,p.blue.to_f]})
    @label = label
  end

  def percentage_pixels_that_are_edgelike(other_column)
    @percentage_by_other_column ||= {}
    @percentage_by_other_column[other_column] = compute_percentage_pixels_that_are_edgelike(other_column)
  end

  private

  # given the pixels ( | is the edge we're working with )
  #
  #     a |
  #     b | d
  #     c |
  #
  # we want to know that b is closer (in color) to a or c than it is to d
  def compute_percentage_pixels_that_are_edgelike(other_column)
    s = @pixels
    o = other_column.pixels
    s1 = s[0..2,1..-2]
    column_difference = intensity_transform((s1 - o[0..2,1..-2]).abs)
    difference_up     = intensity_transform((s1 - s[0..2,0..-3]).abs)
    difference_down   = intensity_transform((s1 - s[0..2,2..-1]).abs)
    ((column_difference > difference_down).or( column_difference > difference_up )).where.total.to_f / s[0,true].total
  end

  def intensity_transform(narray)
    #http://www.imagemagick.org/RMagick/doc/struct.html#Pixel
    #The intensity is computed as 0.299*R+0.587*G+0.114*B.
    a = narray * [0.299,0.587,0.114]
    a[0,true] + a[1,true] + a[2,true]
  end
end

class Image

  def get_pixel_column(column_number)
    @pixel_columns ||= Array.new(columns)
    @pixel_columns[column_number] ||= PixelColumn.new(get_pixels(column_number, 0, 1, rows ), column_number)
  end

  def each_column_pair(limit=(columns/2))
    limit = columns/2 if limit > columns/2
    (0...limit).each{|i| yield(get_pixel_column(i), get_pixel_column(i+1))}
  end

end

class StripeSet

  class Stripe
    attr_accessor :left_stripe, :left_confidence, :right_stripe, :right_confidence
    attr_reader :image, :left_edge, :right_edge, :index
    def initialize(stripe_set, size, index)
      @stripe_set, @size, @index = stripe_set, size, index
    end

    def left_index;  @left_index  ||= @index * @size;                                                         end
    def left_edge;   @left_edge   ||= @stripe_set.image.get_pixel_column( left_index );                       end
    def right_index; @right_index ||= ( @index * @size ) + ( @size - 1 );                                     end
    def right_edge;  @right_edge  ||= @stripe_set.image.get_pixel_column( right_index );                      end
    def image;       @image       ||= @stripe_set.image.excerpt(@index*@size,0,@size,@stripe_set.image.rows); end

  end

  attr_reader :image, :stripes

  def initialize(image)
    @image = image
    @stripes = (0...image.columns/stripe_size).map{|index| Stripe.new(self,stripe_size,index)}
  end

  def restriped_image
    return @restriped_image if @restriped_image
    image_list = ImageList.new()
    ordered_stripes.each do |s|
      image_list << s.image
    end
    @restriped_image = image_list
  end

  private

  def stripe_size
    return @stripe_size if @stripe_size
    possible_breaks = []
    image.each_column_pair do |a,b|
      percentage = a.percentage_pixels_that_are_edgelike(b)
      possible_breaks[ b.label ] = percentage
    end
    possible_breaks = NArray.to_na(possible_breaks)
    possible_breaks = (possible_breaks > (possible_breaks.max - possible_breaks.stddev )).where
    possible_widths = (possible_breaks[1..-1] - possible_breaks[0..-2])
    size_to_occurences = possible_widths.to_a.inject({}) do |hash,item|
      if item > 1
        hash[item] ||= 0
        hash[item] += 1
      end
      hash
    end
    @stripe_size = size_to_occurences.sort_by{|a,b|-b}[0][0]
  end

  def ordered_stripes
    return @ordered_stripes if @ordered_stripes
    unused_stripes = @stripes.dup
    @ordered_stripes = [unused_stripes.delete_at(0)]
    while unused_stripes.size > 0
      guesses = []
      unused_stripes.each do |s|
        guesses << [ @ordered_stripes[0].left_edge.percentage_pixels_that_are_edgelike(s.right_edge), s, :left  ]
        guesses << [ @ordered_stripes[-1].right_edge.percentage_pixels_that_are_edgelike(s.left_edge),  s, :right ]
      end
      guess = guesses.sort_by{|g|g[0]}.first
      @ordered_stripes.insert( guess[2]==:left ? 0 : -1, guess[1] )
      unused_stripes.delete(guess[1])
    end
    @ordered_stripes
  end

end

Dir.glob('inputs/*shredded.png').each do |i|
  puts i
  image_set = StripeSet.new(Image.read(i)[0]).restriped_image.append(false)
  image_set.display
end

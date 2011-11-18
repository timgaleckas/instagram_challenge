require 'rubygems'
require 'rmagick'
include Magick

MAGIC_NUMBERS = { :outlier_percent     => 0.05 }

class PixelColumn

  attr_reader :pixels, :label

  def initialize(pixels, label)
    @pixels, @label = pixels, label
  end

  def [](*args); pixels[*args]; end

  def percentage_pixels_that_are_edgelike(other_column)
    (0...pixels.size).select{|index|pixel_is_edgelike?(index, other_column)}.size.to_f / pixels.size
  end

  def pixel_is_edgelike?(index, other_column)
    (self[index+1] && (self[index]-other_column[index]).intensity > (self[index]-self[index+1]).intensity) ||
    (self[index-1] && (self[index]-other_column[index]).intensity > (self[index]-self[index-1]).intensity)
  end

end

class Image

  def get_pixel_column(column_number)
    @pixel_columns ||= Array.new(columns)
    @pixel_columns[column_number] ||= PixelColumn.new(get_pixels(column_number, 0, 1, rows ), column_number)
  end

  def each_column_pair
    (0...(columns-2)).each{|i| yield(get_pixel_column(i), get_pixel_column(i+1))}
  end

end

class Pixel
  def -( p ); Pixel.new((red - p.red).abs, (green - p.green).abs, (blue - p.blue).abs); end
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

    def self.edges_match?(left_edge, right_edge)
      left_edge.percentage_pixels_that_are_edgelike(right_edge)
    end

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
      possible_breaks << [[a.label,b.label],a.percentage_pixels_that_are_edgelike(b)]
    end
    top_percent_outliers = possible_breaks.sort_by{|a|a[1]}[-(possible_breaks.size*(MAGIC_NUMBERS[:outlier_percent]))..-1]
    @stripe_size = top_percent_outliers.sort_by{|a|a[0][1]}.map{|a|a[0][1]}.inject([0]){|a,b|a<<(b-a[0]);a[0]=b;a}.select{|a|a>1}.inject({}){|a,b|a[b]||=0;a[b]+=1;a}.sort_by{|a,b|b}.reverse.first.first
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

pics = %w(TokyoPanoramaShredded.png big_sean_shredded.png lenna_shredded.png mona_lisa_shredded.png windowlicker_shredded.png)
pics.each{ |i| StripeSet.new(Image.read("inputs/#{i}")[0]).restriped_image.append(false).display }
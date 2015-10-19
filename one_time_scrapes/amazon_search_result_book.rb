# An implementation of a Search Result item representing a book
#
# This is implemented using a bunch of getter methods that search through the html list item.
# It would be nice to implement some sort of general try/catch block but I'm not exactly sure
# how to do so, and I don't think a simple .send() will work.
class AmazonSearchResultBook

  def initialize(result_node)
    @result_node = result_node

    # Private values representing internal html structure
    @container = nil
    @col_right = nil

    # values provided by getters
    @asin = nil
    @title = nil
    @link = nil
    @cover_art = nil
    @publication_date = nil
    @author = nil
    @num_reviews = nil
    @rating = nil
    @kindle_price = nil
    @paperback_price = nil
  end

  def asin
    if @asin.nil?
      @asin = @result_node.attribute_value('data-asin')
    end

    @asin
  end

  def title
    if @title.nil?
      @title = @result_node.link(:class, 's-access-detail-page').title
    end

    @title
  end

  def link
    if @link.nil?
      @link = @result_node.link(:class, 's-access-detail-page').href
    end

    @link
  end

  # This is a smaller thumbnail image from the search results
  def cover_art
    if @cover_art.nil?
      @cover_art = container.img(:class, 's-access-image').src
    end

    @cover_art
  end

  def publication_date
    if @publication_date.nil?
      @publication_date = col_right.span(:class, 'a-size-small').text
    end

    @publication_date
  end

  def author
    if @author.nil?
      # The author name is in the second span
      @author = col_right.div(:class, 'a-spacing-none').spans[1].text
    end

    @author
  end

  def rating
    if @rating.nil?
      get_rating_and_reviews
    end

    @rating
  end

  def num_reviews
    if @num_reviews.nil?
      get_rating_and_reviews
    end

    @num_reviews
  end

  def kindle_price
    if @kindle_price.nil?
      get_prices
    end

    @kindle_price
  end

  def paperback_price
    if @paperback_price.nil?
      get_prices
    end

    @paperback_price
  end

  private

  # outermost search result
  def container
    if @container.nil?
      @container = @result_node.div(:class, 'a-fixed-left-grid-inner')
    end

    @container
  end

  # Set of divs where publication date, author name are held
  def col_right
    if @col_right.nil?
      @col_right = container.div(:class, 'a-col-right')
    end

    @col_right
  end

  def get_rating_and_reviews
    begin
      rating_span = col_right.i(:class, 'a-icon-star').span
      rating_verbose = rating_span.inner_html
      if ! rating_verbose.nil?
        matches = /(\d(.\d)?) out of 5 stars/.match(rating_verbose)
        if ! matches.nil?
          @rating = matches[1].to_f
        end
      end

      @num_reviews = col_right.div(:class, 'a-span-last').link(:class, 'a-link-normal').inner_html || 0

    rescue Watir::Exception::UnknownObjectException
      @rating = 0.0
      @num_reviews = 0
    end
  end


  # We have to iterate through a set of divs
  def get_prices

    pricing_column = col_right.div(:class, 'a-span7').divs(:class, 'a-row')
    num_rows = pricing_column.size
    i = 0

    while i < num_rows do
      begin

        column_title = pricing_column[i].h3.inner_html ## "Kindle Edition"
        if column_title == 'Kindle Edition'
          @kindle_price = pricing_column[i + 1].span(:class, 's-price').inner_html
        end

        if column_title == 'Paperback'
          @paperback_price = pricing_column[i + 1].span(:class, 's-price').inner_html
        end

      rescue Watir::Exception::UnknownObjectException
        # Just do nothing -- we'll advance and try again
      end

      i += 1
    end
  end

end

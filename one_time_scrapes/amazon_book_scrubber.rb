require './amazon_search_result_book.rb'
require 'csv'

# This is a generic implementation of a book scrubber - Child classes can be used to control the search arguments
# and column definition and to modify the implementation as needed.
class AmazonBookScrubber

  AmazonAdvancedSearchUrl = 'http://www.amazon.com/Advanced-Search-Books/b/ref=sv_b_0?ie=UTF8&node=241582011'

  # The children of this class should define these
  AdvancedSearchArguments = { }
  ColumnDefinition = [ ]

  def initialize(browser)
    @should_run_headless = false
    @browser = browser
    @next_page_link = ''

    @kindle_only = true
    @max = 0
    @results_found = 0

    @filename = nil
  end

  # The main loop - Runs the search and advances through the pages, writing to a CSV file
  # after each page.
  def run

    raise 'No filename specified, cannot write CSV file!' if @filename.nil?

    # Open the Advanced Search page and run the search
    run_advanced_search

    # Start writing our CSV File
    CSV.open(@filename, 'wb') do |csv|
      # Header
      csv << get_column_definition

      # Grab that first page of results
      results = get_search_results

      # Find out if we have more.  If we do, we'll advance through the pages below
      has_more_results = more_results_available

      # Keep advancing
      while has_more_results != false

        # Write out the CSV
        if results.count > 0
          results.each do |asin, row_hash|
            csv << row_hash.values
          end

          results = {}
        end

        if(@max > 0 && @results_found >= @max)
          break
        end

        advance_to_next_page_results
        results.merge!(get_search_results)
        has_more_results = more_results_available
      end

      if results.count > 0
        results.each do |asin, row_hash|
          csv << row_hash.values
        end
      end

    end
  end

  # Set the Max number of records to pull -- Primarily for testing
  def max=(max)
    @max = max.to_i
  end

  # Filename must be defined
  def filename=(filename)
    @filename = filename
  end

  # Getter method to grab the search arguments from the constant defined in the child class
  def get_advanced_search_arguments
    self.class::AdvancedSearchArguments
  end

  # Getter method to grab the column definition from the constant defined in the child class
  def get_column_definition
    self.class::ColumnDefinition
  end

  private

  # Navigates to the Advanced Search URL & enters the search criteria
  #
  # This probably could be refactored into a "Search Page", which would return
  # a "Results Page" though they'd likely be very lightweight since we only
  # care about the individual results which are passed into a SearchResultBook.
  def run_advanced_search
    # Connect to the Advanced Search URL
    @browser.goto AmazonAdvancedSearchUrl

    # Submit the search criteria
    @browser.text_field(:name, 'field-publisher').wait_until_present

    # Enter search criteria based on what's defined
    get_advanced_search_arguments.each do |field, argument|
      @browser.text_field(:name, field).set(argument)
    end

    # Submit the search
    @browser.button(:name, 'Adv-Srch-Books-Submit').click
  end

  # Get the results of the advanced search
  def get_search_results
    results = {}

    # Should have results
    @browser.ul(:id, 's-results-list-atf').wait_until_present

    # Iterate through results, write each record
    @browser.ul(:id, 's-results-list-atf').lis.each do |li|

      # This is just a wrapper -- All values are lazy-loaded through the getters
      result = AmazonSearchResultBook.new(li)

      begin
        puts "Title: #{result.title} by #{result.author} - ASIN: #{result.asin}"
        row = {}

        get_column_definition.each do |col|
          if result.respond_to?(col)
            row.store(col.to_sym, result.send(col))
          else
            row.store(col.to_sym, '')
          end
        end

        results.store(row[:asin], row)
        @results_found += 1

      rescue Watir::Exception::UnknownObjectException
        puts 'Error adding book!'
      end

      if(@max > 0 && @results_found >= @max)
        break
      end

    end

    results
  end

  # Figure out if we can get more results based on whether the "next page" button exists
  def more_results_available
    begin
      next_page_link = @browser.link(:id, 'pagnNextLink').href
      if ! next_page_link.nil? && next_page_link.length > 0
        @next_page_link = next_page_link
        return true
      else
        return false
      end

    rescue Watir::Exception::UnknownObjectException
      return false
    end
  end

  # Advance to the next results page
  def advance_to_next_page_results
    if(! @next_page_link.nil? && @next_page_link.length > 0)
      @browser.goto(@next_page_link)
    end
  end

end

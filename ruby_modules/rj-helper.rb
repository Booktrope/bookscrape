require 'rjmetrics_client'
require 'json'
require 'pp'
module Booktrope
	class RJHelper
	
		attr_accessor :table_name
		attr_accessor :keys
		attr_accessor :is_sandbox
		attr_accessor :data		
		attr_accessor :rj_client
		
		MAX_OBJECTS = 100
		APPLE_SALES_TABLE       = "apple_sales_data"
		APPLE_STATS_TABLE       = "apple_stats_data" 
		AMAZON_SALES_TABLE      = "amazon_sales_data"
		AMAZON_STATS_TABLE      = "amazon_stats_data"
		NOOK_SALES_TABLE        = "nook_sales_data"
		NOOK_STATS_TABLE        = "nook_stats_data"
		LSI_SALES_TABLE         = "lsi_sales_data"
		CREATESPACE_SALES_TABLE = "createspace_sales_data"
		GOOGLE_PLAY_STATS_TABLE = "google_play_stats_data"
		GOOGLE_PLAY_SALES_TABLE = "google_play_sales_data"
		TEAM_REVENUE_ALLOCATION_TABLE = "team_revenue_allocation_table"
		
		def initialize(table_name, keys, is_sandbox = false)
		
			raise ArgumentError, "table_name is required" if table_name.empty?
			raise ArgumentError, "keys must be an array of keys" if !keys.kind_of?(Array) || keys.count < 1
			
			constants = Booktrope::Constants.instance
			
			@table_name = table_name
			@keys = keys
			@data = Array.new
			@is_sandbox = is_sandbox
			@rj_client = RJMetricsClient.new(constants[:rjmetrics_client_id], constants[:rjmetrics_api_key])
		end
		
		def add_object!(object)
			object["keys"] = @keys
			@data.push object		
			
			if @data.count >= MAX_OBJECTS
				pushData 
			end
		end
		
		def pushData
			response = @rj_client.pushData @table_name, self.data, ((@is_sandbox) ? RJMetrics::Client::SANDBOX_BASE : RJMetrics::Client::API_BASE)

			if ParseHelper.initialized?
				log_entry = Parse::Object.new("RJMetricsLogEntry")
				log_entry["base"] = (@is_sandbox) ? RJMetrics::Client::SANDBOX_BASE : RJMetrics::Client::API_BASE
				log_entry["rjTable"] = @table_name
				log_entry["keys"] = @keys.to_json
				log_entry["data"] = @data.to_json
				log_entry["rawResponse"] = response.to_s			
				
				if response.first && response.first["code"]
					results = JSON.parse(response.first)				
					log_entry["code"] = results["code"]
					log_entry["message"] = results["message"]				
				else
					log_entry["code"] = 999
					log_entry["Unexpected Results: Check the raw response"]
				end
				log_entry.save
			end
			
			@data = Array.new		 
			response
		end

	end
end
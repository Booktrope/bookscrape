require 'trollop'

basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, '..', 'booktrope-modules')

	        
$opts = Trollop::options do

   banner <<-EOS

   Usage:
            ruby pushTeamRevAlloc.rb --testRJMetrics --dontSaveToParse --dontSaveToRJMetrics
   EOS
   
   opt :testRJMetrics, "Use RJMetrics test sandbox. This option will save to the sandbox.", :short => 't'
   opt :dontSaveToParse, "Prevents the collected data from being saved to parse.", :short => 'x'
   opt :dontSaveToRJMetrics, "Turns of RJMetrics entirely. Data wont be saved to either the sandbox or live.", :short => 'r'
   
   version "1.0.0 2014 Justin Jeffress"

end	        

log = Bt_logging.create_logging('Foo')

$BT_CONSTANTS = Booktrope::Constants.instance
is_test_rj = ($opts.testRJMetrics) ? true : false
$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::TEAM_REVENUE_ALLOCATION_TABLE, ["parse_id", "createdAt"], is_test_rj

BT_CONSTANTS = Booktrope::Constants.instance

Booktrope::ParseHelper.init :application_id => $BT_CONSTANTS[:parse_application_id],
							       :api_key        => $BT_CONSTANTS[:parse_api_key]

$batch = Parse::Batch.new
$batch.max_requests = 50

def syncParseTeamRevenueAlloc(skip)

	team_rev_alloc_list = Parse::Query.new("TeamRevenueAllocation").tap do | q |
		q.count = 1
		q.eq "sentToRjMetrics", false 
		q.limit = 100
		q.skip = skip
	end.get
	
	
	data = Array.new
	team_rev_alloc_list["results"].each do | team_rev_alloc |
	
	
		team_rev_alloc_hash = Hash.new

		team_rev_alloc_hash["parse_id"] = team_rev_alloc.parse_object_id
		
		team_rev_alloc_hash["teamtropeId"]         = team_rev_alloc["teamtropeId"]
		team_rev_alloc_hash["effectiveDate"]       = team_rev_alloc["effectiveDate"]
		team_rev_alloc_hash["authorId"]            = team_rev_alloc["authorId"]
		team_rev_alloc_hash["authorPct"]           = team_rev_alloc["authorPct"]
		team_rev_alloc_hash["managerId"]           = team_rev_alloc["managerId"]
		team_rev_alloc_hash["managerPct"]          = team_rev_alloc["managerPct"]
		team_rev_alloc_hash["projectManagerId"]    = team_rev_alloc["projectManagerId"]
		team_rev_alloc_hash["projectManagerPct"]   = team_rev_alloc["projectManagerPct"]
		team_rev_alloc_hash["editorId"]            = team_rev_alloc["editorId"]
		team_rev_alloc_hash["editorPct"]           = team_rev_alloc["editorPct"]
		team_rev_alloc_hash["proofreaderId"]       = team_rev_alloc["proofreaderId"]
		team_rev_alloc_hash["proofreaderPct"]      = team_rev_alloc["proofreaderPct"]
		team_rev_alloc_hash["designerId"]          = team_rev_alloc["designerId"]
		team_rev_alloc_hash["designerPct"]         = team_rev_alloc["designerPct"]
		team_rev_alloc_hash["otherId"]             = team_rev_alloc["otherId"]
		team_rev_alloc_hash["otherPct"]            = team_rev_alloc["otherPct"]
		team_rev_alloc_hash["other2Id"]            = team_rev_alloc["other2Id"]
		team_rev_alloc_hash["other2Pct"]           = team_rev_alloc["other2Pct"]
		team_rev_alloc_hash["other3Id"]            = team_rev_alloc["other3Id"]
		team_rev_alloc_hash["other3Pct"]           = team_rev_alloc["other3Pct"]		

		team_rev_alloc_hash["createdAt"]           = team_rev_alloc["createdAt"]
		team_rev_alloc_hash["updatedAt"]           = team_rev_alloc["updatedAt"]
		
		team_rev_alloc["sentToRjMetrics"] = true
		
		$batch.update_object_run_when_full!(team_rev_alloc) if !$opts.dontSaveToParse
		$rjClient.add_object! team_rev_alloc_hash
	end
	syncParseTeamRevenueAlloc(skip + 100) if team_rev_alloc_list["results"].count == 100
end

skip = 0
syncParseTeamRevenueAlloc skip


if $batch.requests.length > 0
	$batch.requests
	$batch.run!
	$batch.requests.clear
end



$rjClient.pushData if $rjClient.data.count > 0
#!/usr/bin/env ruby

require 'aws-sdk'
require 'date'
require 'json'
require 'logger'

SQS_KEY_ID = ENV['SQS_KEY_ID'] 
SQS_ACCESS_KEY = ENV['SQS_ACCESS_KEY']
SNS_KEY_ID = ENV['SNS_KEY_ID']
SNS_ACCESS_KEY = ENV['SNS_ACCESS_KEY']
REGION = ENV['AWS_REGION']
platform = 'ios-prod'

sqs = Aws::SQS::Client.new(region: REGION, credentials: Aws::Credentials.new(SQS_KEY_ID, SQS_ACCESS_KEY))
sns = Aws::SNS::Client.new(region: REGION, credentials: Aws::Credentials.new(SNS_KEY_ID, SNS_ACCESS_KEY))
########## Set up logger
# How to configure: http://ruby-doc.org/stdlib-2.1.0/libdoc/logger/rdoc/Logger.html
logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG
logger.info "Starting up mailman"
########## BEGIN: Configure SQS
queue_list = []
sqs.list_queues.queue_urls.each{|queue| 
    queue_list << queue
}
if queue_list.length == 0
    queue_url = sqs.create_queue(queue_name: "Messages").queue_url
else
    queue_list.each {|urls| 
        if urls.include? "Messages"
            queue_url = urls
        end
    }
end
########## END: Configure SQS
########## BEGIN: Configure SNS
# Get list of platforms
valid_platform = ''
begin
    sns.list_platform_applications.platform_applications.each {|app|
        enabled = app.attributes["Enabled"]
        expire_ts = Time.parse(app.attributes["AppleCertificateExpirationDate"]).to_i
        if expire_ts > Time.now.to_i and enabled == "true"
            if app.platform_application_arn.include? platform
                valid_platform = app.platform_application_arn
            end
        end
    }
rescue Aws::SNS::Errors::ServiceError
    puts Aws::SNS::Errors::ServiceError
end
########## END: Configure SNS

while true
	logger.debug "Checking for messages..."	
	# Get work from Messages queue
	sqs.receive_message({queue_url: queue_url}).messages.each {|message|
	    logger.info "Processed message received"
	    logger.debug "Message received from queue: #{message}"		
	    from_queue = JSON.parse(message.body)
	    apspayload = {
	        :aps => {
	            :alert => {
	                'loc-key' => 'NEW_MESSAGE_RECEIVED'
	            },
	            :sound => "default"
	        },
	        :recipientid => from_queue['recipientid'],
	        :fromid => from_queue['fromid'],
	        :fromname => from_queue['fromname']
	    }.to_json
	    messagepayload = {
	        :APNS => apspayload,
	        :APNS_SANDBOX => apspayload
	    }
	    if from_queue["devices"] != nil
	    	from_queue["devices"].each {|device|
	    		if device["platform"] == "ios"
	    			pushtoken = device["token"]
	    			logger.debug "Sending to #{pushtoken}"
	    			#### BEGIN: Get and cleanup endpoints
					# Get list of endpoints
					valid_endpoints = []
					invalid_endpoints = []
					valid_tokens = []
					endpoint_arn = ''
					begin
					    sns.list_endpoints_by_platform_application({platform_application_arn: valid_platform}).endpoints.each{|endpoint|
					        enabled = endpoint.attributes["Enabled"]
					        token = endpoint.attributes["Token"]
					        if enabled == "true"
					            if token == pushtoken
					                endpoint_arn = endpoint.endpoint_arn
					            end
					            valid_endpoints << endpoint.endpoint_arn
					        else
					            invalid_endpoints << endpoint.endpoint_arn
					        end
					    }
					rescue Aws::SNS::Errors::ServiceError
					    puts Aws::SNS::Errors::ServiceError
					end

					# Clean up invalid endpoints
					invalid_endpoints.each{|endpoint|
					    sns.delete_endpoint({endpoint_arn: endpoint})
					}
					if endpoint_arn == ''
					    logger.info "ARN doesnt exist so creating it..."
					    endpoint_arn = sns.create_platform_endpoint({token: pushtoken, platform_application_arn: valid_platform}).endpoint_arn
					end
					logger.debug "ARN Used: #{endpoint_arn}"	
					push_message_id = sns.publish({
						message_structure: 'json',
						message: messagepayload.to_json.to_s,
						target_arn: endpoint_arn
						}).message_id
					logger.info "Sent message to #{endpoint_arn} (ID=#{push_message_id})"
	    			#### END: Get Endpoint
	    		end
	    	}
	    end
	    
	    # Delete message
	    sqs.delete_message({queue_url: queue_url, receipt_handle: message.receipt_handle})
	}

	# Go to sleep
	sleep 5
end

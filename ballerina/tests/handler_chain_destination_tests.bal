// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/io;
import ballerina/log;
import ballerina/messaging;
import ballerina/test;

@ProcessorConfig {
    id: "simple-processor"
}
isolated function processMessage(MessageContext ctx) {
    log:printInfo("Processing message in simple processor", msgId = ctx.getId());
}

@DestinationConfig {
    id: "destination-1"
}
isolated function executeDestination1(MessageContext ctx) returns string => "destination-1-executed";

isolated int destination2Attempts = 0;

@DestinationConfig {
    id: "destination-2",
    retryConfig: {
        maxRetries: 2,
        retryInterval: 2
    }
}
isolated function executeDestination2(MessageContext ctx) returns string|error {
    lock {
        destination2Attempts += 1;
        if destination2Attempts <= 2 {
            return error("Failed to process in destination 2");
        }
        return string `destination-2-executed-in-attempt-${destination2Attempts}`;
    }
}

isolated boolean enabledDestination3and4 = false;

@DestinationConfig {
    id: "destination-3"
}
isolated function executeDestination3(MessageContext ctx) returns string|error {
    lock {
        return enabledDestination3and4 ? "destination-3-executed" : error("Destination 3 is disabled");
    }
}

isolated int destination4Attempts = 0;

@DestinationConfig {
    id: "destination-4",
    retryConfig: {
        maxRetries: 3,
        retryInterval: 1
    }
}
isolated function executeDestination4(MessageContext ctx) returns string|error {
    lock {
        destination4Attempts += 1;
    }
    lock {
        if !enabledDestination3and4 {
            return error("Failed to process in destination 4");
        }
    }
    lock {
        if destination4Attempts <= 5 {
            return error("Failed to process in destination 4");
        }
        return string `destination-4-executed-in-attempt-${destination4Attempts}`;
    }
}

final messaging:Store failureStoreForMultiDestinations = new messaging:InMemoryMessageStore();

HandlerChain chainWithMultipleDestinations = check new (
    name = "chainWithMultipleDestinations",
    processors = [processMessage],
    destinations = [
        executeDestination1,
        executeDestination2,
        executeDestination3,
        executeDestination4
    ],
    failureStore = failureStoreForMultiDestinations
);

@test:Config {
    groups: ["handler-chain-destination-tests"]
}
function testHandlerChainWithMultipleDestinationsExecution() returns error? {
    ExecutionSuccess|ExecutionError result = chainWithMultipleDestinations.execute("test-message");
    if result is ExecutionSuccess {
        test:assertFail("Expected an error due to the destination 3 and 4 being disabled, but got a successful result");
    }

    Message message = result.detail().message;
    test:assertEquals(message.content, "test-message");
    test:assertEquals(message.metadata.destinationsToSkip, ["destination-1", "destination-2"]);
    test:assertEquals(message.errorMsg, "Failed to execute destinations: destination-3, destination-4");

    map<ErrorInfo>? destinationErrors = message.destinationErrors;
    if destinationErrors is () {
        test:assertFail("Expected destination errors to be present, but found none");
    }
    test:assertEquals(destinationErrors.length(), 2);
    test:assertTrue(destinationErrors.hasKey("destination-3"));
    test:assertTrue(destinationErrors.hasKey("destination-4"));

    ErrorInfo destination3Error = destinationErrors.get("destination-3");
    test:assertEquals(destination3Error.message, "Destination 3 is disabled");

    ErrorInfo destination4Error = destinationErrors.get("destination-4");
    test:assertEquals(destination4Error.message, "Failed to execute destination after retries");
    io:println(destination4Error);
    ErrorInfo? destination4Cause = destination4Error.cause;
    if destination4Cause is () {
        test:assertFail("Expected cause for destination 4 error to be present, but found none");
    }
    test:assertEquals(destination4Cause.message, "Failed to process in destination 4");

    map<anydata>? destinationResults = message.destinationResults;
    if destinationResults is () {
        test:assertFail("Expected destination results to be present, but found none");
    }
    test:assertEquals(destinationResults.length(), 2);
    test:assertTrue(destinationResults.hasKey("destination-1"));
    test:assertTrue(destinationResults.hasKey("destination-2"));
    test:assertEquals(destinationResults.get("destination-1"), "destination-1-executed");
    test:assertEquals(destinationResults.get("destination-2"), "destination-2-executed-in-attempt-3");
}

@test:Config {
    groups: ["handler-chain-destination-tests"],
    dependsOn: [testHandlerChainWithMultipleDestinationsExecution]
}
function testHandlerChainWithMultipleDestinationsReplay() returns error? {
    messaging:Message|error? failedMessage = failureStoreForMultiDestinations->retrieve();
    if failedMessage is error? {
        test:assertFail("Failed message should be present in the failure store, but it was not found");
    }

    lock {
        enabledDestination3and4 = true;
    }

    Message payload = check failedMessage.payload.toJson().fromJsonWithType();
    ExecutionSuccess|ExecutionError result = chainWithMultipleDestinations.replay(payload);
    if result is ExecutionError {
        test:assertFail("Expected a successful replay, but got an error: " + result.message());
    }
    map<anydata> destinationResults = result.destinationResults;
    test:assertEquals(destinationResults.length(), 2);
    test:assertFalse(destinationResults.hasKey("destination-1"));
    test:assertFalse(destinationResults.hasKey("destination-2"));
    test:assertTrue(destinationResults.hasKey("destination-3"));
    test:assertTrue(destinationResults.hasKey("destination-4"));
    test:assertEquals(destinationResults.get("destination-3"), "destination-3-executed");
    test:assertEquals(destinationResults.get("destination-4"), "destination-4-executed-in-attempt-6");
}

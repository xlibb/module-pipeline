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

import ballerina/lang.runtime;
import ballerina/log;
import ballerina/messaging;
import ballerina/uuid;

# Represents the listener configurations to replay message processing in a handler chain.
public type ReplayListenerConfiguration record {|
    *ServiceRetryConfiguration;
    # The interval in seconds to poll for messages to replay
    decimal pollingInterval = 1;
    # The store to be used for storing messages that could not be processed even after retries
    messaging:Store deadLetterStore;
    # Optional store to be used for replaying messages in the handler chain. If not provided, 
    # the handler chain's failure store will be used.
    messaging:Store replayStore?;
|};

# Represents a handler chain that processes messages through a series of processors and destinations.
# A handler chain can be defined with a sequence of processors and a set of destinations. The destinations
# are executed in parallel after all processors have been executed. If any processor or destination fails,
# the message can be stored in a store for later processing or for error handling. Additionally,
# the handler chain supports pausing the execution of a message, allowing it to be resumed later with the same state.
public isolated class HandlerChain {

    private string name;
    final readonly & Processor[] processors;
    final readonly & Destination[] destinations;
    private final messaging:Store failureStore;

    # Creates a new handler chain.
    #
    # + name - The name of the handler chain
    # + processors - The processors to be used in the handler chain, which can be a single processor or an array of processors
    # + destinations - The destinations to be used in the handler chain, which can be a single destination or an array of destinations
    # + failureStore - The store to be used for storing messages on failure
    # + replayConfig - Optional configuration for replaying messages in the handler chain
    public isolated function init(string name, Processor|Processor[] processors, Destination|Destination[] destinations,
            messaging:Store failureStore, ReplayListenerConfiguration? replayListenerConfig = ()) returns Error? {
        if (processors is Processor[] && processors.length() == 0) ||
            (destinations is Destination[] && destinations.length() == 0) {
            return error Error("Handler chain must have at least one processor and one destination");
        }
        self.name = name.clone();
        self.processors = processors is Processor[] ? processors.cloneReadOnly() : [processors];
        self.destinations = destinations is Destination[] ? destinations.cloneReadOnly() : [destinations];
        self.failureStore = failureStore;
        if replayListenerConfig is ReplayListenerConfiguration {
            check startReplayListener(self, replayListenerConfig);
        }
    }

    # Get the name of the handler chain.
    #
    # + return - Returns the name of the handler chain
    public isolated function getName() returns string {
        lock {
            return self.name;
        }
    }

    # Get the failure store of the handler chain.
    #
    # + return - Returns the failure store of the handler chain
    public isolated function getFailureStore() returns messaging:Store {
        lock {
            return self.failureStore;
        }
    }

    # Replay the execution of a failed message in the handler chain. Failed messages in replay will
    # not be stored automatically.
    #
    # + message - The message to be replayed, which should contain the ID and the relevant state of the failed message
    # + return - Returns an error if the message could not be processed, otherwise returns the execution result
    public isolated function replay(Message message) returns ExecutionSuccess|ExecutionError {
        MessageContext msgContext = new (message);
        log:printDebug("message replay started", msgId = msgContext.getId(), handlerchain = self.getName());
        msgContext.cleanMessageForReplay();
        ExecutionSuccess|ExecutionError result = self.executeInternal(msgContext);
        return result;
    }

    # Dispatch a message to the handler chain for processing with the defined processors and destinations.
    #
    # + content - The message content to be processed
    # + return - Returns the execution result or an error if the processing failed
    public isolated function execute(anydata content) returns ExecutionSuccess|ExecutionError {
        string id = uuid:createType1AsString();
        MessageContext msgContext = new (id = id, handlerChainName = self.getName(), content = content);
        log:printDebug("handler chain execution started", msgId = id, handlerchain = self.getName());
        ExecutionSuccess|ExecutionError result = self.executeInternal(msgContext);
        if result is ExecutionError {
            self.storeFailedMessage(result, msgContext);
        }
        return result;
    }

    isolated function storeFailedMessage(ExecutionError executionError, MessageContext msgContext) {
        messaging:Store store = self.getFailureStore();
        error? storeResult = store->store({...executionError.detail().message});
        if storeResult is error {
            log:printError("failed to store the failed message in the store", storeResult,
                    msgId = msgContext.getId(), handlerchain = self.getName());
        }
        log:printDebug("failed message stored in the store", msgId = msgContext.getId(), handlerchain = self.getName());
    }

    isolated function executeInternal(MessageContext msgContext) returns ExecutionSuccess|ExecutionError {
        MessageContext msgCtxSnapshot = msgContext.clone();
        SourceExecutionResult? executeProcessorsResult = check executeProcessors(self.processors,
                msgContext, msgCtxSnapshot);
        if executeProcessorsResult is SourceExecutionResult {
            return {...executeProcessorsResult};
        }

        map<future<anydata|error>> destinationFutures = startExecuteDestinations(self.destinations,
                msgContext, msgCtxSnapshot);

        [map<anydata>, map<error>] destinationResults = waitForDestinationsToComplete(destinationFutures, msgCtxSnapshot);

        if destinationResults[1].length() > 0 {
            return reportDestinationFailure(destinationResults[1], destinationResults[0], msgCtxSnapshot);
        }
        return {message: {...msgContext.toRecord()}, destinationResults: destinationResults[0]};
    }
}

isolated function getProcessorId(Processor processor) returns string {
    string? id = (typeof processor).@ProcessorConfig?.id;
    if id is string {
        return id;
    }
    id = (typeof processor).@FilterConfig?.id;
    if id is string {
        return id;
    }
    id = (typeof processor).@TransformerConfig?.id;
    if id is () {
        panic error Error("Processor ID is not defined");
    }
    return id;
};

isolated function getDestinationId(Destination destination) returns string {
    string? id = (typeof destination).@DestinationConfig?.id;
    if id is () {
        panic error Error("Destination ID is not defined");
    }
    return id;
};

isolated function executeProcessors(Processor[] processors, MessageContext msgContext,
        MessageContext msgCtxSnapshot) returns SourceExecutionResult|ExecutionError? {
    string id = msgContext.getId();
    foreach Processor processor in processors {
        string processorName = getProcessorId(processor);
        SourceExecutionResult|error? result = executeProcessor(processor, msgContext);
        if result is error {
            log:printDebug("processor execution failed", result, processor = processorName, msgId = id,
                    handlerchain = msgContext.getHandlerChainName());
            string errorMsg = string `Failed to execute processor: ${processorName} - ${result.message()}`;
            msgCtxSnapshot.setError(result, errorMsg);
            return error ExecutionError(errorMsg, result, message = {...msgCtxSnapshot.toRecord()});
        } else if result is SourceExecutionResult {
            return {...result};
        }
    }
    return;
}

isolated function executeProcessor(Processor processor, MessageContext msgContext)
        returns SourceExecutionResult|error? {
    string processorName = getProcessorId(processor);
    string id = msgContext.getId();

    if processor is GenericProcessor {
        _ = check trap processor(msgContext);
        log:printDebug("processor executed successfully", processor = processorName, msgId = id,
                handlerchain = msgContext.getHandlerChainName());
    } else if processor is Filter {
        boolean filterResult = check trap processor(msgContext);
        if !filterResult {
            log:printDebug("processor filter returned false, skipping further processing",
                    processorName = processorName, msgId = msgContext.getId(),
                    handlerchain = msgContext.getHandlerChainName());
            return {message: {...msgContext.toRecord()}};
        }
        log:printDebug("processor filter executed successfully", processor = processorName,
                msgId = msgContext.getId(), handlerchain = msgContext.getHandlerChainName());
    } else {
        anydata transformedContent = check trap processor(msgContext);
        msgContext.setContent(transformedContent);
        log:printDebug("processor transformer executed successfully", processor = processorName,
                msgId = msgContext.getId(), handlerchain = msgContext.getHandlerChainName());
    }
    return;
}

isolated function startExecuteDestinations(Destination[] destinations, MessageContext msgContext,
        MessageContext msgCtxSnapshot) returns map<future<anydata|error>> {
    map<future<anydata|error>> destinationExecutions = {};
    foreach Destination destination in destinations {
        string destinationName = getDestinationId(destination);
        if msgContext.isDestinationSkipped(destinationName) {
            log:printDebug("destination is requested to be skipped", destination = destinationName,
                    msgId = msgContext.getId(), handlerchain = msgContext.getHandlerChainName());
        } else {
            Destination retirableDestination = getRetriableDestination(destination);
            future<anydata|error> destinationExecution = start retirableDestination(msgContext.clone());
            destinationExecutions[destinationName] = destinationExecution;
        }
    }
    return destinationExecutions;
}

isolated function waitForDestinationsToComplete(map<future<anydata|error>> destinationFutures,
        MessageContext msgCtxSnapshot) returns [map<anydata>, map<error>] {
    map<error> failedDestinations = {};
    map<anydata> successfulDestinations = {};

    foreach var [destinationName, destinationFuture] in destinationFutures.entries() {
        anydata|error result = wait destinationFuture;
        if result is anydata {
            msgCtxSnapshot.skipDestination(destinationName);
            log:printDebug("destination executed successfully", destination = destinationName,
                    msgId = msgCtxSnapshot.getId(), handlerchain = msgCtxSnapshot.getHandlerChainName());
            successfulDestinations[destinationName] = result;
            continue;
        } else {
            failedDestinations[destinationName] = result;
            log:printDebug("destination execution failed", result, destination = destinationName,
                    msgId = msgCtxSnapshot.getId(), handlerchain = msgCtxSnapshot.getHandlerChainName());
        }
    }
    return [successfulDestinations, failedDestinations];
}

isolated function reportDestinationFailure(map<error> failedDestinations, map<anydata> successfulDestinations,
        MessageContext msgContext) returns ExecutionError {
    string errorMsg;
    if failedDestinations.length() == 1 {
        string destinationName = failedDestinations.keys()[0];
        error failedDestination = failedDestinations.get(destinationName);
        errorMsg = string `Failed to execute destination: ${destinationName} - ${failedDestination.message()}`;
        msgContext.setError(failedDestination, errorMsg);
    } else {
        errorMsg = "Failed to execute destinations: ";
        foreach var [handlerName, err] in failedDestinations.entries() {
            msgContext.addDestinationError(handlerName, err);
            errorMsg += handlerName + ", ";
        }
        if errorMsg.length() > 0 {
            errorMsg = errorMsg.substring(0, errorMsg.length() - 2);
        }
        msgContext.setErrorMessage(errorMsg.trim());
    }
    msgContext.setDestinationResults(successfulDestinations);
    return error ExecutionError(errorMsg, message = {...msgContext.toRecord()});
}

isolated function getRetriableDestination(Destination targetDestination) returns Destination {
    DestinationConfiguration? config = (typeof targetDestination).@DestinationConfig;
    if config is () {
        panic error Error("Function does not have a destination configuration");
    }
    RetryDestinationConfig? retryConfig = config.retryConfig;
    if retryConfig is () {
        return targetDestination;
    }
    return getRetriableDestinationFunction(retryConfig.cloneReadOnly(), targetDestination);
}

isolated function getRetriableDestinationFunction(readonly & RetryDestinationConfig retryConfig,
        Destination targetDestination) returns Destination => isolated function(MessageContext msgCtx) returns anydata|error {
    anydata|error result = targetDestination(msgCtx);
    if result is anydata {
        return result;
    }
    log:printDebug("destination execution failed, retrying", result, destination = getDestinationId(targetDestination),
            msgId = msgCtx.getId(), handlerchain = msgCtx.getHandlerChainName());

    error lastError = result;
    foreach int attempt in 1 ... retryConfig.maxRetries {
        anydata|error retryResult = targetDestination(msgCtx);
        if retryResult is anydata {
            return retryResult;
        }
        if attempt < retryConfig.maxRetries {
            log:printDebug("destination execution failed on retry attempt", retryAttempt = attempt,
                    destination = getDestinationId(targetDestination), msgId = msgCtx.getId(),
                    handlerchain = msgCtx.getHandlerChainName());
            runtime:sleep(retryConfig.retryInterval);
        }
        lastError = retryResult;
    }
    return error("Failed to execute destination after retries", lastError);
};

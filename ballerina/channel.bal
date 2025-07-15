import ballerina/messaging;
import ballerina/log;
import ballerina/uuid;

# Represents the listener configurations to resume message processing in a channel.
#
# + pollingInterval - The interval in seconds to poll for messages to resume
# + deadLetterStore - The store to be used for storing messages that could not be processed even after retries
# + store - The store to be used for resuming messages in the channel
public type ResumeListenerConfiguration record {|
    *ServiceRetryConfiguration;
    decimal pollingInterval = 1;
    messaging:Store deadLetterStore;
    messaging:Store store?;
|};

# Represents a channel that processes messages through a series of processors and destinations.
# A channel can be defined with a sequence of processors and a set of destinations. The destinations
# are executed in parallel after all processors have been executed. If any processor or destination fails,
# the message can be stored in a store for later processing or for error handling. Additionally,
# the channel supports pausing the execution of a message, allowing it to be resumed later with the same state.
public isolated class Channel {

    private string name;
    final readonly & Processor[] processors;
    final readonly & (Destination|Destination[])[] destinations;
    private final messaging:Store store;

    # Creates a new channel.
    #
    # + name - The name of the channel
    # + processors - The processors to be used in the channel, which can be a single processor or an array of processors
    # + destinations - The destinations to be used in the channel, which can be a single destination or an array of destinations
    # + store - The store to be used for storing messages, especially in case of errors or pauses
    # + resumeConfig - Optional configuration for resuming messages in the channel, which includes the store to be used for resuming messages
    public isolated function init(string name, Processor|Processor[] processors, Destination|Destination[] destinations, messaging:Store store, ResumeListenerConfiguration? resumeListenerConfig = ()) returns error? {
        self.name = name.clone();
        if processors is Processor[] {
            self.processors = processors.cloneReadOnly();
        } else {
            self.processors = [processors];
        }
        if destinations is Destination {
            self.destinations = [destinations];
        } else {
            self.destinations = destinations.cloneReadOnly();
        }
        self.store = store;
        if resumeListenerConfig is ResumeListenerConfiguration {
            check startResumeListener(self, resumeListenerConfig);
        }
    }

    # Get the name of the channel.
    #
    # + return - Returns the name of the channel
    public isolated function getName() returns string {
        lock {
            return self.name;
        }
    }

    # Get the store of the channel.
    #
    # + return - Returns the store of the channel
    public isolated function getStore() returns messaging:Store {
        lock {
            return self.store;
        }
    }

    # Resume the execution of a failed/paused message in the channel.
    #
    # + message - The message to be resumed, which should contain the ID and the relevant state of the failed/paused message
    # + return - Returns an error if the message could not be processed, otherwise returns the execution result
    public isolated function resume(Message message) returns ExecutionResult|ExecutionError {
        MessageContext msgContext = new (getProcessorPipeline(self.processors), message);
        log:printDebug("channel execution continued", msgId = msgContext.getId());
        msgContext.cleanErrorInfoForReplay();
        ExecutionResult|ExecutionError result = self.executeInternal(msgContext);
        return result;
    }

    # Dispatch a message to the channel for processing with the defined processors and destinations.
    #
    # + content - The message content to be processed
    # + return - Returns the execution result or an error if the processing failed
    public isolated function execute(anydata content) returns ExecutionResult|ExecutionError {
        string id = uuid:createType1AsString();
        MessageContext msgContext = new (getProcessorPipeline(self.processors), id = id, content = content);
        log:printDebug("channel execution started", msgId = id);
        ExecutionResult|ExecutionError result = self.executeInternal(msgContext);
        if result is ExecutionError {
            self.storeFailedMessage(result, msgContext);
        }
        return result;
    }

    isolated function storeFailedMessage(ExecutionError executionError, MessageContext msgContext) {
        messaging:Store store = self.getStore();
        error? storeResult = store->store(executionError.detail().message);
        if storeResult is error {
            log:printError("failed to store the failed message in the store", msgId = msgContext.getId(), channel = self.getName(), 'error = storeResult);
        }
        log:printDebug("failed message stored in the store", msgId = msgContext.getId(), channel = self.getName());
    }

    isolated function executeInternal(MessageContext msgContext) returns ExecutionResult|ExecutionError {
        string id = msgContext.getId();
        // Take a copy of the message context to avoid modifying the original message.
        MessageContext msgCtxSnapshot = msgContext.clone();
        // First execute all processors
        foreach Processor processor in self.processors {
            string processorName = getProcessorId(processor);
            if msgContext.isProcessorSkipped(processorName) {
                log:printDebug("processor is skipped since it is already executed", processorName = processorName, msgId = id);
                continue;
            }
            SourceExecutionResult|error? result = self.executeProcessor(processor, msgContext);
            if result is error {
                string errorMsg;
                if result is SuspensionError {
                    // If the processor execution is suspended
                    log:printDebug("processor execution suspended", processorName = processorName, msgId = id);
                    errorMsg = string `Processor execution suspended: ${processorName} - ${result.message()}`;
                } else {
                    // If the processor execution failed, add to dead letter store and return error.
                    log:printDebug("processor execution failed", processorName = processorName, msgId = id, 'error = result);
                    errorMsg = string `Failed to execute processor: ${processorName} - ${result.message()}`;
                }
                msgCtxSnapshot.setError(result, errorMsg);
                return error ExecutionError(errorMsg, result, message = {...msgCtxSnapshot.toRecord()});
            } else if result is SourceExecutionResult {
                // If the processor execution is returned with a result, stop further processing.
                return {...result};
            }
            // Update the message context snapshot with the latest message context.
            msgCtxSnapshot = msgContext.clone();
            msgCtxSnapshot.setLastProcessorId(processorName);
        }

        map<future<any|error>> destinationExecutions = {};
        map<error> failedDestinations = {};
        map<any> successfulDestinations = {};

        foreach Destination|Destination[] destination in self.destinations {
            if destination is Destination {
                string destinationName = getDestinationId(destination);
                if msgContext.isDestinationSkipped(destinationName) {
                    log:printDebug("destination is requested to be skipped", destinationName = destinationName, msgId = msgContext.getId());
                } else {
                    future<any|error> destinationExecution = start destination(msgContext.clone());
                    destinationExecutions[destinationName] = destinationExecution;
                }
            } else {
                foreach Destination dest in destination {
                    string destinationName = getDestinationId(dest);
                    if msgContext.isDestinationSkipped(destinationName) {
                        log:printDebug("destination is requested to be skipped", destinationName = destinationName, msgId = msgContext.getId());
                    } else {
                        any|error destResult = dest(msgContext.clone());
                        if destResult is any {
                            // If the destination execution was successful, continue.
                            msgCtxSnapshot.skipDestination(destinationName);
                            log:printDebug("destination executed successfully", destinationName = destinationName, msgId = msgCtxSnapshot.getId());
                            successfulDestinations[destinationName] = destResult;
                            continue;
                        } else {
                            // If there was an error, collect the error.
                            failedDestinations[destinationName] = destResult;
                            log:printDebug("destination execution failed", destinationName = destinationName, msgId = msgCtxSnapshot.getId(), 'error = destResult);
                            break;
                        }
                    }
                }
            }
        }

        foreach var [destinationName, destinationExecution] in destinationExecutions.entries() {
            any|error result = wait destinationExecution;
            if result is any {
                // If the destination execution was successful, continue.
                msgCtxSnapshot.skipDestination(destinationName);
                log:printDebug("destination executed successfully", destinationName = destinationName, msgId = msgCtxSnapshot.getId());
                successfulDestinations[destinationName] = result;
                continue;
            } else {
                // If there was an error, collect the error.
                failedDestinations[destinationName] = result;
                log:printDebug("destination execution failed", destinationName = destinationName, msgId = msgCtxSnapshot.getId(), 'error = result);
            }
        }
        if failedDestinations.length() > 0 {
            return self.reportDestinationFailure(failedDestinations, msgCtxSnapshot);
        }
        return {message: {...msgContext.toRecord()}, destinationResults: successfulDestinations};
    }

    isolated function executeProcessor(Processor processor, MessageContext msgContext) returns SourceExecutionResult|error? {
        string processorName = getProcessorId(processor);
        string id = msgContext.getId();

        if processor is GenericProcessor {
            _ = check processor(msgContext);
            log:printDebug("processor executed successfully", processorName = processorName, msgId = id);
        } else if processor is Filter {
            boolean filterResult = check processor(msgContext);
            if !filterResult {
                log:printDebug("processor filter returned false, skipping further processing", processorName = processorName, msgId = msgContext.getId());
                return {message: {...msgContext.toRecord()}};
            }
            log:printDebug("processor filter executed successfully", processorName = processorName, msgId = msgContext.getId());
        } else {
            anydata transformedContent = check processor(msgContext);
            msgContext.setContent(transformedContent);
            log:printDebug("processor transformer executed successfully", processorName = processorName, msgId = msgContext.getId());
        }
        return;
    }

    isolated function reportDestinationFailure(map<error> failedDestinations, MessageContext msgContext) returns ExecutionError {
        string errorMsg;
        if failedDestinations.length() == 1 {
            string destinationName = failedDestinations.keys()[0];
            error failedDestination = failedDestinations.get(destinationName);
            errorMsg = string `Failed to execute destination: ${destinationName} - ${failedDestination.message()}`;
            msgContext.setError(failedDestination, errorMsg);
        } else {
            errorMsg = "Failed to execute destinations: ";
            foreach var [handlerName, err] in failedDestinations.entries() {
                msgContext.addError(handlerName, err);
                errorMsg += handlerName + ", ";
            }
            if errorMsg.length() > 0 {
                errorMsg = errorMsg.substring(0, errorMsg.length() - 2);
            }
            msgContext.setErrorMessage(errorMsg.trim());
        }
        return error ExecutionError(errorMsg, message = {...msgContext.toRecord()});
    }
}

isolated function getProcessorPipeline(Processor[] processors) returns string[] {
    return from Processor processor in processors
        select getProcessorId(processor);
};

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

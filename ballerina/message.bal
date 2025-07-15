# Message type represents a message with content, error information, metadata, and properties.
#
# + id - Unique identifier for the message
# + content - The actual content of the message, which can be of any data type
# + isSuspended - Indicates whether the message is suspended. Default is `false`
# + lastProcessorId - Optional identifier of the last processor that handled the message
# + errorMsg - Optional error message if an error occurred during processing
# + errorStackTrace - Optional stack trace of the error if available
# + errorDetails - A map containing additional details about the error, which can include any data type
# + destinationErrors - A map of errors associated with specific destinations, where the key is the destination name and the value is an `ErrorInfo` record
# + metadata - Metadata associated with the message, such as processors to skip
# + properties - A map of additional properties associated with the message
public type Message record {|
    readonly string id;
    anydata content;
    boolean isSuspended = false;
    string lastProcessorId?;
    string errorMsg?;
    string[] errorStackTrace?;
    map<anydata> errorDetails?;
    map<ErrorInfo> destinationErrors?;
    MessageMetadata metadata = {};
    map<anydata> properties = {};
|};

# Error information type.
#
# + message - A descriptive error message
# + stackTrace - An array of strings representing the stack trace of the error
# + detail - A map containing additional details about the error, which can include any data type
public type ErrorInfo record {|
    string message;
    string[] stackTrace;
    map<anydata> detail;
|};

# Message metadata.
#
# + destinationsToSkip - An array of destination names that should be skipped when processing the message
public type MessageMetadata record {|
    string[] destinationsToSkip = [];
|};

# Source execution result.
#
# + message - The message that was processed.
public type SourceExecutionResult record {|
    Message message;
|};

# Channel execution result.
#
# + message - The message that was processed
# + destinationResults - A map of destination names to their respective results
public type ExecutionResult record {|
    Message message;
    map<any> destinationResults = {};
|};
